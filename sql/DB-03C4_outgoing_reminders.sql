-- DB-03C4 v0.1: outgoing actions, confirmed effects, reminders and no-response loss
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02, DB-03A, DB-03B, DB-03C1 v0.3,
--   DB-03C2 v0.1 and DB-03C3 v0.1 applied.
--
-- CREATES 5 SECURITY DEFINER FUNCTIONS
--   sozdat_ishodyashchee_deystvie(jsonb)        -> qbit_test_bot
--   zabrat_ishodyashchee_deystvie(jsonb)        -> qbit_test_bot
--   zafiksirovat_rezultat_ishodyashchego(jsonb)-> qbit_test_bot
--   podgotovit_napominanie(jsonb)               -> qbit_test_bot
--   zafiksirovat_poteryu_bez_otveta(jsonb)      -> qbit_test_bot
--
-- RELIABILITY MODEL
--   * logical outgoing message/action is persisted before external API;
--   * stable klyuch_povtora prevents a second logical action;
--   * claim/reclaim uses lease + monotonic fencing number;
--   * neizvestno is terminal for blind retry: dependent effects are NOT applied;
--   * confirmed delivery fact is persisted even if dialog changed in-flight;
--   * only still-current podtverzhdeno applies stage/goal/close/t0 effects;
--   * t0 is set only by a confirmed main bot message that actually requires reply;
--   * reminders never move t0;
--   * reminder2 confirmation creates durable loss-check at actual_send + trusted delay;
--   * net_otveta is allowed only after confirmed reminder2 and no newer client input.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * Probe rows are rolled back to SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03C4 migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03c4$
DECLARE
    v_required_table text;
    v_required_fn text;
    v_new_fn text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03C4 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03C4 must run from trusted postgres session. session_user=%',
            session_user;
    END IF;

    IF NOT pg_catalog.pg_has_role(session_user, 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION
            'session_user % cannot SET ROLE qbit_test_owner',
            session_user;
    END IF;

    FOREACH v_required_table IN ARRAY ARRAY[
        'polzovateli',
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'ishodyashchie_deystviya',
        'napominaniya',
        'sobytiya_dialogov',
        'sobytiya_etapov',
        'celevye_sobytiya',
        'operator_telegram_temy',
        'sobytiya_zerkala_operatora'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_test.%I', v_required_table)
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required table qbit_test.% is missing',
                v_required_table;
        END IF;
    END LOOP;

    FOREACH v_required_fn IN ARRAY ARRAY[
        'zaregistrirovat_vhod_klienta',
        'zabrat_zadanie_obrabotki',
        'zavershit_zadanie_obrabotki'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_test'
               AND p.proname = v_required_fn
        ) THEN
            RAISE EXCEPTION
                'Required prior function qbit_test.% is missing',
                v_required_fn;
        END IF;
    END LOOP;

    FOREACH v_new_fn IN ARRAY ARRAY[
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_test'
               AND p.proname = v_new_fn
        ) THEN
            RAISE EXCEPTION
                'DB-03C4 function qbit_test.% already exists; stop instead of overwriting',
                v_new_fn;
        END IF;
    END LOOP;

    IF pg_catalog.to_regclass('qbit_test.uq_ishod_klyuch_povtora') IS NULL
       OR pg_catalog.to_regclass('qbit_test.uq_napominaniya_dialog_pok_tip') IS NULL
       OR pg_catalog.to_regclass('qbit_test.uq_zerkalo_klyuch') IS NULL THEN
        RAISE EXCEPTION
            'Required outgoing/reminder/mirror unique indexes are missing';
    END IF;
END
$db03c4$;

SET LOCAL ROLE qbit_test_owner;

-- ===========================================================================
-- 1. CREATE LOGICAL OUTGOING ACTION BEFORE EXTERNAL API
-- ===========================================================================

CREATE FUNCTION qbit_test.sozdat_ishodyashchee_deystvie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    deystvie_id uuid,
    dialog_id uuid,
    soobshchenie_id uuid,
    status_deystviya text,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_key text;
    v_kind text;
    v_source text;
    v_dialog_id uuid;
    v_expected_version bigint;
    v_initiative boolean;
    v_channel text;
    v_account text;
    v_external_dialog text;
    v_reply_external text;
    v_text_raw text;
    v_text_safe text;
    v_wait boolean;
    v_finish_type text;
    v_reason text;
    v_payload jsonb;
    v_effects jsonb;
    v_next_stage text;
    v_close_result text;
    v_goal_code text;
    v_rem1 integer;
    v_rem2 integer;
    v_rem_window integer;
    v_loss_after integer;

    v_dialog record;
    v_identity record;
    v_existing record;
    v_existing_message record;
    v_message_id uuid;
    v_action_id uuid;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_key := NULLIF(btrim(p_dannye->>'klyuch_povtora'), '');
    v_kind := COALESCE(NULLIF(btrim(p_dannye->>'vid_deystviya'), ''), 'soobshchenie');
    v_source := COALESCE(NULLIF(btrim(p_dannye->>'istochnik'), ''), 'bot');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_expected_version := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_initiative := COALESCE((p_dannye->>'iniciativnoe')::boolean, false);
    v_channel := NULLIF(btrim(p_dannye->>'kanal'), '');
    v_account := NULLIF(btrim(p_dannye->>'akkaunt_kanala_id'), '');
    v_external_dialog := NULLIF(btrim(p_dannye->>'vneshniy_dialog_id'), '');
    v_reply_external := NULLIF(btrim(p_dannye->>'vneshnee_otvet_na_id'), '');
    v_text_raw := p_dannye->>'tekst_ishodnyy';
    v_text_safe := p_dannye->>'tekst_obezlichennyy';
    v_wait := COALESCE((p_dannye->>'ozhidaetsya_otvet')::boolean, false);
    v_finish_type := NULLIF(btrim(p_dannye->>'tip_zaversheniya'), '');
    v_reason := p_dannye->>'prichina_resheniya';
    v_payload := COALESCE(p_dannye->'payload', '{}'::jsonb);
    v_effects := COALESCE(p_dannye->'effekty_posle_podtverzhdeniya', '{}'::jsonb);
    v_next_stage := NULLIF(btrim(v_effects->>'novyy_etap'), '');
    v_close_result := NULLIF(btrim(v_effects->>'zavershit_rezultat'), '');
    v_goal_code := NULLIF(btrim(v_effects->>'kod_celi'), '');
    v_rem1 := NULLIF(v_effects->>'napominanie_1_sekund', '')::integer;
    v_rem2 := NULLIF(v_effects->>'napominanie_2_sekund', '')::integer;
    v_rem_window := NULLIF(v_effects->>'okno_napominaniya_sekund', '')::integer;
    v_loss_after := NULLIF(v_effects->>'poterya_posle_sekund', '')::integer;

    IF v_operaciya IS NULL
       OR v_key IS NULL
       OR v_dialog_id IS NULL
       OR v_expected_version IS NULL
       OR v_expected_version < 1
       OR v_kind NOT IN ('soobshchenie', 'crm', 'uvedomlenie', 'otchet')
       OR v_source NOT IN ('bot', 'sistema')
       OR jsonb_typeof(v_payload) <> 'object'
       OR jsonb_typeof(v_effects) <> 'object'
       OR (
            v_close_result IS NOT NULL
            AND v_close_result NOT IN (
                'zayavka_prinyata',
                'konsultaciya_zavershena',
                'otkaz',
                'tehnicheski_prervan'
            )
       )
       OR (
            v_wait
            AND (
                v_kind <> 'soobshchenie'
                OR v_rem1 IS NULL
                OR v_rem2 IS NULL
                OR v_rem_window IS NULL
                OR v_loss_after IS NULL
                OR v_rem1 < 60
                OR v_rem2 <= v_rem1
                OR v_rem_window < 60
                OR v_loss_after < 3600
            )
       )
       OR (v_wait AND v_close_result IS NOT NULL)
       OR (v_kind = 'soobshchenie' AND (
            v_channel IS NULL
            OR v_account IS NULL
            OR v_external_dialog IS NULL
            OR v_text_raw IS NULL
       )) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректный outgoing request/effects. Waiting требует trusted reminder/loss intervals.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::uuid, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('db03c4_out' || pg_catalog.chr(31) || v_key, 7)
    );

    SELECT a.*
      INTO v_existing
      FROM qbit_test.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora = v_key;

    IF FOUND THEN
        IF v_existing.soobshchenie_id IS NOT NULL THEN
            SELECT m.*
              INTO v_existing_message
              FROM qbit_test.soobshcheniya AS m
             WHERE m.id = v_existing.soobshchenie_id;
        END IF;

        IF v_existing.dialog_id IS DISTINCT FROM v_dialog_id
           OR v_existing.vid_deystviya IS DISTINCT FROM v_kind
           OR v_existing.istochnik IS DISTINCT FROM v_source
           OR v_existing.versiya_dialoga IS DISTINCT FROM v_expected_version
           OR v_existing.kanal IS DISTINCT FROM v_channel
           OR v_existing.akkaunt_kanala_id IS DISTINCT FROM v_account
           OR v_existing.vneshniy_dialog_id IS DISTINCT FROM v_external_dialog
           OR v_existing.vneshnee_otvet_na_id IS DISTINCT FROM v_reply_external
           OR (
                v_kind = 'soobshchenie'
                AND (
                    v_existing_message.tekst_ishodnyy IS DISTINCT FROM v_text_raw
                    OR v_existing_message.tekst_obezlichennyy IS DISTINCT FROM v_text_safe
                    OR v_existing_message.ozhidaetsya_otvet IS DISTINCT FROM v_wait
                    OR v_existing_message.tip_zaversheniya IS DISTINCT FROM v_finish_type
                    OR v_existing_message.prichina_resheniya IS DISTINCT FROM v_reason
                )
           )
           OR v_existing.payload IS DISTINCT FROM (
                v_payload
                || jsonb_build_object(
                    'iniciativnoe', v_initiative,
                    'effekty_posle_podtverzhdeniya', v_effects
                )
           ) THEN
            RETURN QUERY SELECT
                v_operaciya, 'konflikt'::text, 'klyuch_povtora_conflict'::text,
                'Stable outgoing key уже связан с другим логическим действием/содержимым.'::text,
                NULL::timestamptz,
                v_existing.id, v_existing.dialog_id, v_existing.soobshchenie_id,
                v_existing.status, v_existing.versiya_dialoga;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Логическое исходящее действие уже существует.'::text,
            v_existing.povtor_posle,
            v_existing.id, v_existing.dialog_id, v_existing.soobshchenie_id,
            v_existing.status, v_existing.versiya_dialoga;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_nayden'::text,
            'Диалог не найден.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::uuid, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    IF v_dialog.versiya_dialoga IS DISTINCT FROM v_expected_version THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Диалог изменился до создания outgoing action.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::uuid, NULL::text,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.vladelec <> 'bot'
       OR v_dialog.status IN ('peredan_cheloveku', 'zavershen')
       OR v_identity.logicheski_zablokirovan
       OR (v_initiative AND v_identity.zapret_iniciativnyh_soobshcheniy) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'otpravka_ne_razreshena'::text,
            'Текущее состояние dialog/identity не разрешает эту bot-отправку.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::uuid, NULL::text,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_kind = 'soobshchenie' THEN
        INSERT INTO qbit_test.soobshcheniya AS new_message (
            dialog_id,
            napravlenie,
            avtor,
            vid,
            tekst_ishodnyy,
            tekst_obezlichennyy,
            vremya_priema,
            status_otpravki,
            ozhidaetsya_otvet,
            tip_zaversheniya,
            prichina_resheniya,
            trassirovka_id
        )
        VALUES (
            v_dialog_id,
            'ishodyashchee',
            CASE WHEN v_source = 'bot' THEN 'bot' ELSE 'sistema' END,
            'text',
            v_text_raw,
            v_text_safe,
            clock_timestamp(),
            'zaplanirovano',
            v_wait,
            v_finish_type,
            v_reason,
            v_operaciya
        )
        RETURNING new_message.id
        INTO v_message_id;
    END IF;

    INSERT INTO qbit_test.ishodyashchie_deystviya AS new_action (
        dialog_id,
        soobshchenie_id,
        vid_deystviya,
        istochnik,
        klyuch_povtora,
        kanal,
        akkaunt_kanala_id,
        vneshniy_dialog_id,
        vneshnee_otvet_na_id,
        payload,
        status,
        sleduyushchiy_zapusk,
        versiya_dialoga
    )
    VALUES (
        v_dialog_id,
        v_message_id,
        v_kind,
        v_source,
        v_key,
        v_channel,
        v_account,
        v_external_dialog,
        v_reply_external,
        v_payload
        || jsonb_build_object(
            'iniciativnoe', v_initiative,
            'effekty_posle_podtverzhdeniya', v_effects
        ),
        'zaplanirovano',
        clock_timestamp(),
        v_expected_version
    )
    RETURNING new_action.id
    INTO v_action_id;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Логическое outgoing intent сохранено до внешнего API.'::text,
        NULL::timestamptz,
        v_action_id, v_dialog_id, v_message_id, 'zaplanirovano'::text,
        v_expected_version;
END
$fn$;

COMMENT ON FUNCTION qbit_test.sozdat_ishodyashchee_deystvie(jsonb) IS
'DB-03C4: сохраняет stable logical outgoing action до внешнего API; проверяет bot owner/version/block и opt-out только для initiative; waiting effects применяются только после confirmed send.';

-- ===========================================================================
-- 2. CLAIM OUTGOING ACTION WITH LEASE/FENCING
-- ===========================================================================

CREATE FUNCTION qbit_test.zabrat_ishodyashchee_deystvie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    deystvie_id uuid,
    dialog_id uuid,
    soobshchenie_id uuid,
    vid_deystviya text,
    kanal text,
    akkaunt_kanala_id text,
    vneshniy_dialog_id text,
    vneshnee_otvet_na_id text,
    payload jsonb,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga bigint,
    byl_perehvachen boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_worker text;
    v_lease_seconds integer;
    v_now timestamptz;
    v_candidate record;
    v_claimed record;
    v_initiative boolean;
    v_cleanup_reason text;
    v_reclaim boolean;
    v_iteration integer;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund', '')::integer;

    IF v_operaciya IS NULL
       OR v_worker IS NULL
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation, worker и trusted lease 10..3600.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::jsonb,
            NULL::integer, NULL::text, NULL::timestamptz, NULL::bigint,
            NULL::bigint, false;
        RETURN;
    END IF;

    FOR v_iteration IN 1..50 LOOP
        v_now := clock_timestamp();

        SELECT
            a.id,
            a.dialog_id,
            a.soobshchenie_id,
            a.vid_deystviya,
            a.kanal,
            a.akkaunt_kanala_id,
            a.vneshniy_dialog_id,
            a.vneshnee_otvet_na_id,
            a.payload,
            a.status,
            a.popytki,
            a.vladelec_arendy,
            a.arenda_do,
            a.nomer_vladeniya,
            a.versiya_dialoga,
            d.versiya_dialoga AS current_dialog_version,
            d.vladelec AS dialog_owner,
            d.status AS dialog_status,
            i.logicheski_zablokirovan,
            i.zapret_iniciativnyh_soobshcheniy
          INTO v_candidate
          FROM qbit_test.ishodyashchie_deystviya AS a
          JOIN qbit_test.dialogi AS d
            ON d.id = a.dialog_id
          JOIN qbit_test.identifikatory_kanalov AS i
            ON i.id = d.identifikator_kanala_id
         WHERE (
                (
                    a.status IN ('zaplanirovano', 'povtor')
                    AND a.sleduyushchiy_zapusk <= v_now
                )
                OR
                (
                    a.status = 'v_rabote'
                    AND a.arenda_do <= v_now
                )
         )
         ORDER BY
            CASE WHEN a.status = 'v_rabote' THEN 0 ELSE 1 END,
            CASE
                WHEN a.status = 'v_rabote' THEN a.arenda_do
                ELSE a.sleduyushchiy_zapusk
            END,
            a.vremya_sozdaniya,
            a.id
         FOR UPDATE OF a, d SKIP LOCKED
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                v_operaciya, 'net_deystviya'::text, NULL::text,
                'Готового outgoing action сейчас нет.'::text,
                NULL::timestamptz,
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::jsonb,
                NULL::integer, NULL::text, NULL::timestamptz, NULL::bigint,
                NULL::bigint, false;
            RETURN;
        END IF;

        v_initiative := COALESCE((v_candidate.payload->>'iniciativnoe')::boolean, false);

        v_cleanup_reason := CASE
            WHEN v_candidate.versiya_dialoga
                 IS DISTINCT FROM v_candidate.current_dialog_version
            THEN 'stale_dialog_version'
            WHEN v_candidate.logicheski_zablokirovan
            THEN 'logicheski_zablokirovan'
            WHEN v_candidate.dialog_owner <> 'bot'
            THEN 'vladelec_ne_bot'
            WHEN v_candidate.dialog_status IN ('peredan_cheloveku', 'zavershen')
            THEN 'dialog_ne_aktiven'
            WHEN v_initiative AND v_candidate.zapret_iniciativnyh_soobshcheniy
            THEN 'zapret_iniciativy'
            ELSE NULL
        END;

        IF v_cleanup_reason IS NOT NULL THEN
            UPDATE qbit_test.ishodyashchie_deystviya AS a_cancel
               SET status = 'otmeneno',
                   vladelec_arendy = NULL,
                   arenda_do = NULL,
                   kod_oshibki = v_cleanup_reason,
                   opisanie_oshibki = 'DB-03C4 claim cleanup: действие больше не разрешено состоянием dialog/identity.',
                   vremya_obnovleniya = clock_timestamp()
             WHERE a_cancel.id = v_candidate.id;

            IF v_candidate.soobshchenie_id IS NOT NULL THEN
                UPDATE qbit_test.soobshcheniya AS m_cancel
                   SET status_otpravki = 'otmeneno'
                 WHERE m_cancel.id = v_candidate.soobshchenie_id
                   AND m_cancel.status_otpravki IN ('zaplanirovano', 'povtor', 'v_rabote');
            END IF;

            CONTINUE;
        END IF;

        v_reclaim := (
            v_candidate.status = 'v_rabote'
            AND v_candidate.arenda_do <= v_now
        );

        UPDATE qbit_test.ishodyashchie_deystviya AS a_claim
           SET status = 'v_rabote',
               popytki = a_claim.popytki + 1,
               vladelec_arendy = v_worker,
               arenda_do = v_now + make_interval(secs => v_lease_seconds),
               nomer_vladeniya = a_claim.nomer_vladeniya + 1,
               vremya_zaprosa = v_now,
               povtor_posle = NULL,
               kod_oshibki = NULL,
               opisanie_oshibki = NULL,
               vremya_obnovleniya = clock_timestamp()
         WHERE a_claim.id = v_candidate.id
         RETURNING
            a_claim.id,
            a_claim.dialog_id,
            a_claim.soobshchenie_id,
            a_claim.vid_deystviya,
            a_claim.kanal,
            a_claim.akkaunt_kanala_id,
            a_claim.vneshniy_dialog_id,
            a_claim.vneshnee_otvet_na_id,
            a_claim.payload,
            a_claim.popytki,
            a_claim.vladelec_arendy,
            a_claim.arenda_do,
            a_claim.nomer_vladeniya,
            a_claim.versiya_dialoga
          INTO v_claimed;

        IF v_claimed.soobshchenie_id IS NOT NULL THEN
            UPDATE qbit_test.soobshcheniya AS m_claim
               SET status_otpravki = 'v_rabote'
             WHERE m_claim.id = v_claimed.soobshchenie_id;
        END IF;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            CASE WHEN v_reclaim
                THEN 'Истёкшая аренда outgoing action перехвачена новым fencing number.'
                ELSE 'Outgoing action выдан worker.'
            END::text,
            NULL::timestamptz,
            v_claimed.id, v_claimed.dialog_id, v_claimed.soobshchenie_id,
            v_claimed.vid_deystviya, v_claimed.kanal, v_claimed.akkaunt_kanala_id,
            v_claimed.vneshniy_dialog_id, v_claimed.vneshnee_otvet_na_id,
            v_claimed.payload, v_claimed.popytki, v_claimed.vladelec_arendy,
            v_claimed.arenda_do, v_claimed.nomer_vladeniya,
            v_claimed.versiya_dialoga, v_reclaim;
        RETURN;
    END LOOP;

    RETURN QUERY SELECT
        v_operaciya, 'povtor'::text, 'ochistka_limit'::text,
        'Очищено 50 устаревших outgoing actions; безопасно повторить claim.'::text,
        clock_timestamp() + interval '1 second',
        NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::text, NULL::jsonb,
        NULL::integer, NULL::text, NULL::timestamptz, NULL::bigint,
        NULL::bigint, false;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zabrat_ishodyashchee_deystvie(jsonb) IS
'DB-03C4: claim/reclaim outgoing actions через SKIP LOCKED, lease/fencing и final recheck dialog version/owner/block/initiative opt-out; neizvestno не claimится.';

-- ===========================================================================
-- 3. RECORD EXTERNAL RESULT; ONLY CONFIRMED APPLIES DEPENDENT EFFECTS
-- ===========================================================================

CREATE FUNCTION qbit_test.zafiksirovat_rezultat_ishodyashchego(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    deystvie_id uuid,
    dialog_id uuid,
    soobshchenie_id uuid,
    status_deystviya text,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint,
    t0 timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_action_id uuid;
    v_worker text;
    v_ownership bigint;
    v_status text;
    v_external_id text;
    v_request_time timestamptz;
    v_confirm_time timestamptz;
    v_retry_at timestamptz;
    v_error_code text;
    v_error_description text;
    v_now timestamptz;

    v_action record;
    v_dialog record;
    v_identity record;
    v_message record;
    v_effects jsonb;
    v_initiative boolean;
    v_next_stage text;
    v_close_result text;
    v_goal_code text;
    v_rem1 integer;
    v_rem2 integer;
    v_rem_window integer;
    v_loss_after integer;
    v_new_generation bigint;
    v_new_dialog_version bigint;
    v_topic_chat text;
    v_topic_thread text;
    v_reminder_id uuid;
    v_reminder_type text;
    v_effects_allowed boolean := false;
    v_effects_suppressed boolean := false;
    v_return_t0 timestamptz;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_action_id := NULLIF(p_dannye->>'deystvie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_status := NULLIF(btrim(p_dannye->>'status'), '');
    v_external_id := NULLIF(btrim(p_dannye->>'vneshniy_id'), '');
    v_request_time := NULLIF(p_dannye->>'vremya_zaprosa', '')::timestamptz;
    v_confirm_time := NULLIF(p_dannye->>'vremya_podtverzhdeniya', '')::timestamptz;
    v_retry_at := NULLIF(p_dannye->>'povtor_posle', '')::timestamptz;
    v_error_code := NULLIF(btrim(p_dannye->>'kod_oshibki'), '');
    v_error_description := NULLIF(btrim(p_dannye->>'opisanie_oshibki'), '');
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_action_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_status NOT IN ('podtverzhdeno', 'povtor', 'neizvestno', 'oshibka')
       OR (v_status = 'podtverzhdeno' AND v_confirm_time IS NULL)
       OR (v_status = 'povtor' AND (
            v_retry_at IS NULL
            OR v_retry_at <= v_now
            OR v_error_code IS NULL
       ))
       OR (v_status IN ('neizvestno', 'oshibka') AND v_error_code IS NULL) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректный внешний результат. confirmed требует time; retry требует future+error; unknown/error требуют code.'::text,
            NULL::timestamptz,
            v_action_id, NULL::uuid, NULL::uuid, NULL::text,
            NULL::bigint, NULL::bigint, NULL::timestamptz;
        RETURN;
    END IF;

    SELECT a.*
      INTO v_action
      FROM qbit_test.ishodyashchie_deystviya AS a
     WHERE a.id = v_action_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'deystvie_ne_naydeno'::text,
            'Outgoing action не найден.'::text, NULL::timestamptz,
            v_action_id, NULL::uuid, NULL::uuid, NULL::text,
            NULL::bigint, NULL::bigint, NULL::timestamptz;
        RETURN;
    END IF;

    IF v_status = 'podtverzhdeno'
       AND v_action.vid_deystviya = 'soobshchenie'
       AND v_external_id IS NULL THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'net_vneshnego_id'::text,
            'Confirmed message требует подтверждённый внешний message ID.'::text,
            NULL::timestamptz,
            v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
            v_action.status, v_action.versiya_dialoga, NULL::bigint, NULL::timestamptz;
        RETURN;
    END IF;

    IF v_action.status <> 'v_rabote'
       OR v_action.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_action.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker/fencing больше не владеет outgoing action.'::text,
            NULL::timestamptz,
            v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
            v_action.status, v_action.versiya_dialoga, NULL::bigint, NULL::timestamptz;
        RETURN;
    END IF;

    IF v_action.arenda_do IS NULL
       OR v_action.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая outgoing lease не может записывать результат.'::text,
            NULL::timestamptz,
            v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
            v_action.status, v_action.versiya_dialoga, NULL::bigint, NULL::timestamptz;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_action.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    v_initiative := COALESCE((v_action.payload->>'iniciativnoe')::boolean, false);

    v_effects_allowed := (
        v_action.versiya_dialoga IS NOT DISTINCT FROM v_dialog.versiya_dialoga
        AND v_dialog.vladelec = 'bot'
        AND v_dialog.status NOT IN ('peredan_cheloveku', 'zavershen')
        AND NOT v_identity.logicheski_zablokirovan
        AND NOT (
            v_initiative
            AND v_identity.zapret_iniciativnyh_soobshcheniy
        )
    );
    v_effects_suppressed := NOT v_effects_allowed;

    -- A retry is a future external call, so stale/forbidden state cancels it.
    -- confirmed/unknown/error are facts about an API attempt that already happened
    -- and must still be persisted even if dialog state changed meanwhile.
    IF v_status = 'povtor' AND NOT v_effects_allowed THEN
        UPDATE qbit_test.ishodyashchie_deystviya AS a_cancel
           SET status = 'otmeneno',
               vladelec_arendy = NULL,
               arenda_do = NULL,
               kod_oshibki = 'stale_ili_zapreshcheno',
               opisanie_oshibki = 'Retry suppressed because dialog/identity changed after external attempt.',
               vremya_obnovleniya = clock_timestamp()
         WHERE a_cancel.id = v_action_id;

        IF v_action.soobshchenie_id IS NOT NULL THEN
            UPDATE qbit_test.soobshcheniya AS m_cancel
               SET status_otpravki = 'otmeneno'
             WHERE m_cancel.id = v_action.soobshchenie_id;
        END IF;

        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_ili_zapreshcheno'::text,
            'Retry не планируется: dialog/identity уже изменился.'::text,
            NULL::timestamptz,
            v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
            'otmeneno'::text, v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya, v_dialog.t0;
        RETURN;
    END IF;

    UPDATE qbit_test.ishodyashchie_deystviya AS a_done
       SET status = v_status,
           vladelec_arendy = NULL,
           arenda_do = NULL,
           vneshniy_id = CASE
               WHEN v_status = 'podtverzhdeno' THEN v_external_id
               ELSE a_done.vneshniy_id
           END,
           vremya_zaprosa = COALESCE(v_request_time, a_done.vremya_zaprosa),
           vremya_podtverzhdeniya = CASE
               WHEN v_status = 'podtverzhdeno' THEN v_confirm_time
               ELSE NULL
           END,
           povtor_posle = CASE
               WHEN v_status = 'povtor' THEN v_retry_at
               ELSE NULL
           END,
           sleduyushchiy_zapusk = CASE
               WHEN v_status = 'povtor' THEN v_retry_at
               ELSE a_done.sleduyushchiy_zapusk
           END,
           kod_oshibki = CASE
               WHEN v_status IN ('povtor', 'neizvestno', 'oshibka') THEN v_error_code
               ELSE NULL
           END,
           opisanie_oshibki = CASE
               WHEN v_status IN ('povtor', 'neizvestno', 'oshibka') THEN v_error_description
               ELSE NULL
           END,
           vremya_obnovleniya = clock_timestamp()
     WHERE a_done.id = v_action_id;

    IF v_action.soobshchenie_id IS NOT NULL THEN
        UPDATE qbit_test.soobshcheniya AS m_done
           SET status_otpravki = v_status,
               vneshnee_soobshchenie_id = CASE
                   WHEN v_status = 'podtverzhdeno' THEN v_external_id
                   ELSE m_done.vneshnee_soobshchenie_id
               END,
               vremya_otpravki = CASE
                   WHEN v_status = 'podtverzhdeno' THEN v_confirm_time
                   ELSE m_done.vremya_otpravki
               END
         WHERE m_done.id = v_action.soobshchenie_id;
    END IF;

    -- Retry/unknown/error never apply business effects.
    IF v_status <> 'podtverzhdeno' THEN
        IF (v_action.payload ? 'napominanie_id') THEN
            v_reminder_id := NULLIF(v_action.payload->>'napominanie_id', '')::uuid;

            UPDATE qbit_test.napominaniya AS n_result
               SET status = CASE
                   WHEN v_status = 'povtor' THEN 'v_rabote'
                   WHEN v_status = 'neizvestno' THEN 'neizvestno'
                   ELSE 'oshibka'
               END,
               prichina = CASE
                   WHEN v_status = 'povtor' THEN 'vremennaya_oshibka_otpravki'
                   WHEN v_status = 'neizvestno' THEN 'rezultat_otpravki_neizvesten'
                   ELSE 'postoyannaya_oshibka_otpravki'
               END,
               vremya_obnovleniya = clock_timestamp()
             WHERE n_result.id = v_reminder_id;
        END IF;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            CASE
                WHEN v_status = 'povtor' THEN 'Retry сохранён; зависимые эффекты не применены.'
                WHEN v_status = 'neizvestno' THEN 'Результат неизвестен; blind retry запрещён, зависимые эффекты не применены.'
                ELSE 'Постоянная ошибка сохранена; зависимые эффекты не применены.'
            END::text,
            CASE WHEN v_status = 'povtor' THEN v_retry_at ELSE NULL END,
            v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
            v_status, v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya, v_dialog.t0;
        RETURN;
    END IF;

    IF v_action.soobshchenie_id IS NOT NULL THEN
        SELECT m.*
          INTO v_message
          FROM qbit_test.soobshcheniya AS m
         WHERE m.id = v_action.soobshchenie_id
         FOR UPDATE;
    END IF;

    -- Confirmed reminder: the external send fact is stored even if an input
    -- crossed in flight. Such stale confirmation does NOT create further loss chain.
    IF (v_action.payload ? 'napominanie_id') THEN
        v_reminder_id := NULLIF(v_action.payload->>'napominanie_id', '')::uuid;

        SELECT n.tip
          INTO v_reminder_type
          FROM qbit_test.napominaniya AS n
         WHERE n.id = v_reminder_id
           AND n.dialog_id = v_action.dialog_id
         FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Confirmed reminder action % points to missing reminder %',
                v_action_id,
                v_reminder_id;
        END IF;

        UPDATE qbit_test.napominaniya AS n_confirm
           SET status = 'podtverzhdeno',
               vremya_fakticheskoy_otpravki = v_confirm_time,
               prichina = CASE
                   WHEN v_effects_allowed THEN n_confirm.prichina
                   ELSE 'podtverzhdeno_posle_izmeneniya_dialoga'
               END,
               vremya_obnovleniya = clock_timestamp()
         WHERE n_confirm.id = v_reminder_id;

        IF v_effects_allowed
           AND v_reminder_type = 'napominanie_2' THEN
            v_loss_after := NULLIF(v_action.payload->>'poterya_posle_sekund', '')::integer;

            IF v_loss_after IS NULL OR v_loss_after < 3600 THEN
                RAISE EXCEPTION
                    'Confirmed reminder2 action % lacks trusted loss delay',
                    v_action_id;
            END IF;

            INSERT INTO qbit_test.napominaniya (
                dialog_id,
                tip,
                t0,
                soobshchenie_osnovanie_id,
                pokolenie_ozhidaniya,
                srok,
                aktualno_do,
                status,
                prichina
            )
            VALUES (
                v_action.dialog_id,
                'proverka_poteri',
                v_dialog.t0,
                v_action.soobshchenie_id,
                v_dialog.pokolenie_ozhidaniya,
                v_confirm_time + make_interval(secs => v_loss_after),
                v_confirm_time + make_interval(secs => v_loss_after + 86400),
                'zaplanirovano',
                'posle_podtverzhdennogo_napominaniya_2'
            )
            ON CONFLICT (dialog_id, pokolenie_ozhidaniya, tip)
            DO NOTHING;
        END IF;

        v_new_dialog_version := v_dialog.versiya_dialoga;
        v_new_generation := v_dialog.pokolenie_ozhidaniya;

    ELSE
        -- Main confirmed message: apply only narrow allowlisted effects.
        v_effects := COALESCE(
            v_action.payload->'effekty_posle_podtverzhdeniya',
            '{}'::jsonb
        );
        v_next_stage := NULLIF(btrim(v_effects->>'novyy_etap'), '');
        v_close_result := NULLIF(btrim(v_effects->>'zavershit_rezultat'), '');
        v_goal_code := NULLIF(btrim(v_effects->>'kod_celi'), '');
        v_rem1 := NULLIF(v_effects->>'napominanie_1_sekund', '')::integer;
        v_rem2 := NULLIF(v_effects->>'napominanie_2_sekund', '')::integer;
        v_rem_window := NULLIF(v_effects->>'okno_napominaniya_sekund', '')::integer;
        v_loss_after := NULLIF(v_effects->>'poterya_posle_sekund', '')::integer;

        IF v_effects_allowed THEN
            IF v_next_stage IS NOT NULL
               AND v_next_stage IS DISTINCT FROM v_dialog.etap THEN
            INSERT INTO qbit_test.sobytiya_etapov (
                dialog_id,
                staryy_etap,
                novyy_etap,
                vremya_sobytiya,
                prichina,
                istochnik,
                soobshchenie_dokazatelstvo_id
            )
            VALUES (
                v_dialog.id,
                v_dialog.etap,
                v_next_stage,
                v_confirm_time,
                'confirmed_outgoing_effect',
                'bot',
                v_action.soobshchenie_id
            );
            END IF;

            IF v_goal_code IS NOT NULL THEN
            INSERT INTO qbit_test.celevye_sobytiya (
                polzovatel_id,
                dialog_id,
                kod_celi,
                vremya_sobytiya,
                istochnik,
                podtverzhdenie_id,
                dokazatelnye_soobshcheniya,
                podtverzhdeno
            )
            VALUES (
                v_dialog.polzovatel_id,
                v_dialog.id,
                v_goal_code,
                v_confirm_time,
                'confirmed_outgoing',
                v_action.id,
                ARRAY[v_action.soobshchenie_id]::uuid[],
                true
            );
            END IF;

            IF v_message.ozhidaetsya_otvet THEN
            IF v_rem1 IS NULL
               OR v_rem2 IS NULL
               OR v_rem_window IS NULL
               OR v_loss_after IS NULL THEN
                RAISE EXCEPTION
                    'Confirmed waiting action % lacks reminder policy',
                    v_action_id;
            END IF;

            v_new_generation := v_dialog.pokolenie_ozhidaniya + 1;

            UPDATE qbit_test.dialogi AS d_wait
               SET etap = COALESCE(v_next_stage, d_wait.etap),
                   status = 'ozhidaet_otveta',
                   poslednee_ishodyashchee_id = v_action.soobshchenie_id,
                   ozhidaetsya_otvet = true,
                   t0 = v_confirm_time,
                   pokolenie_ozhidaniya = v_new_generation,
                   vremya_obnovleniya = clock_timestamp()
             WHERE d_wait.id = v_dialog.id;

            INSERT INTO qbit_test.napominaniya (
                dialog_id,
                tip,
                t0,
                soobshchenie_osnovanie_id,
                pokolenie_ozhidaniya,
                srok,
                aktualno_do,
                status
            )
            VALUES
            (
                v_dialog.id,
                'napominanie_1',
                v_confirm_time,
                v_action.soobshchenie_id,
                v_new_generation,
                v_confirm_time + make_interval(secs => v_rem1),
                v_confirm_time + make_interval(secs => v_rem1 + v_rem_window),
                'zaplanirovano'
            ),
            (
                v_dialog.id,
                'napominanie_2',
                v_confirm_time,
                v_action.soobshchenie_id,
                v_new_generation,
                v_confirm_time + make_interval(secs => v_rem2),
                v_confirm_time + make_interval(secs => v_rem2 + v_rem_window),
                'zaplanirovano'
            )
            ON CONFLICT (dialog_id, pokolenie_ozhidaniya, tip)
            DO NOTHING;

        ELSIF v_close_result IS NOT NULL THEN
            v_new_generation := v_dialog.pokolenie_ozhidaniya + 1;

            UPDATE qbit_test.dialogi AS d_close
               SET etap = COALESCE(v_next_stage, d_close.etap),
                   status = 'zavershen',
                   rezultat = v_close_result,
                   prichina_zaversheniya = COALESCE(v_message.prichina_resheniya, 'confirmed_outgoing'),
                   vremya_zaversheniya = v_confirm_time,
                   poslednee_ishodyashchee_id = v_action.soobshchenie_id,
                   ozhidaetsya_otvet = false,
                   t0 = NULL,
                   pokolenie_ozhidaniya = v_new_generation,
                   versiya_dialoga = d_close.versiya_dialoga + 1,
                   vremya_obnovleniya = clock_timestamp()
             WHERE d_close.id = v_dialog.id
             RETURNING d_close.versiya_dialoga
             INTO v_new_dialog_version;

            UPDATE qbit_test.napominaniya AS n_close
               SET status = 'otmeneno',
                   prichina = 'dialog_zavershen',
                   vremya_obnovleniya = clock_timestamp()
             WHERE n_close.dialog_id = v_dialog.id
               AND n_close.status IN ('zaplanirovano', 'v_rabote');

            INSERT INTO qbit_test.sobytiya_dialogov (
                dialog_id,
                polzovatel_id,
                tip_sobytiya,
                vremya_sobytiya,
                prichina,
                rezultat,
                istochnik,
                trassirovka_id
            )
            VALUES (
                v_dialog.id,
                v_dialog.polzovatel_id,
                'zavershenie',
                v_confirm_time,
                COALESCE(v_message.prichina_resheniya, 'confirmed_outgoing'),
                v_close_result,
                'bot',
                v_operaciya
            );
        ELSE
            UPDATE qbit_test.dialogi AS d_plain
               SET etap = COALESCE(v_next_stage, d_plain.etap),
                   poslednee_ishodyashchee_id = v_action.soobshchenie_id,
                   vremya_obnovleniya = clock_timestamp()
             WHERE d_plain.id = v_dialog.id;

            v_new_generation := v_dialog.pokolenie_ozhidaniya;
            END IF;
        ELSE
            -- The API send is real, but state-dependent effects are stale.
            v_new_dialog_version := v_dialog.versiya_dialoga;
            v_new_generation := v_dialog.pokolenie_ozhidaniya;
        END IF;

        IF v_new_dialog_version IS NULL THEN
            SELECT d.versiya_dialoga
              INTO v_new_dialog_version
              FROM qbit_test.dialogi AS d
             WHERE d.id = v_dialog.id;
        END IF;

    END IF;

    -- Every actually confirmed client-facing bot/system message is mirrored,
    -- including reminders. The mirror event records whether business effects
    -- were still current when confirmation was persisted.
    IF v_action.soobshchenie_id IS NOT NULL THEN
        SELECT t.sluzhebnyy_chat_id, t.message_thread_id
          INTO v_topic_chat, v_topic_thread
          FROM qbit_test.operator_telegram_temy AS t
         WHERE t.dialog_id = v_dialog.id;

        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
            dialog_id,
            soobshchenie_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            prioritet,
            cel_chat_id,
            cel_thread_id,
            tekst,
            payload,
            status
        )
        VALUES (
            v_dialog.id,
            v_action.soobshchenie_id,
            'otvet_bota',
            'bot_confirmed:' || v_action.soobshchenie_id::text,
            10,
            v_topic_chat,
            v_topic_thread,
            COALESCE(v_message.tekst_ishodnyy, ''),
            jsonb_build_object(
                'deystvie_id', v_action.id,
                'vneshniy_id', v_external_id,
                'effekty_primeneny', v_effects_allowed,
                'napominanie', (v_action.payload ? 'napominanie_id')
            ),
            'zaplanirovano'
        )
        ON CONFLICT (klyuch_idempotentnosti)
        DO NOTHING;
    END IF;

    IF v_new_dialog_version IS NULL THEN
        v_new_dialog_version := v_dialog.versiya_dialoga;
    END IF;

    IF v_new_generation IS NULL THEN
        v_new_generation := v_dialog.pokolenie_ozhidaniya;
    END IF;

    SELECT d.t0
      INTO v_return_t0
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_action.dialog_id;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        CASE
            WHEN v_effects_suppressed
            THEN 'Внешний confirmed-факт сохранён, но устаревшие зависимые эффекты подавлены.'
            ELSE 'Подтверждённый внешний результат сохранён; разрешённые зависимые эффекты применены атомарно.'
        END::text,
        NULL::timestamptz,
        v_action_id, v_action.dialog_id, v_action.soobshchenie_id,
        'podtverzhdeno'::text, v_new_dialog_version,
        v_new_generation,
        v_return_t0;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zafiksirovat_rezultat_ishodyashchego(jsonb) IS
'DB-03C4: fenced external result; retry/unknown/error never apply dependent business effects; only confirmed may set message status, stage/goal/close/t0/reminders and confirmed bot mirror. Reminder confirmations never move t0.';

-- ===========================================================================
-- 4. FINAL REMINDER CHECK + CREATE OUTGOING REMINDER ACTION
-- ===========================================================================

CREATE FUNCTION qbit_test.podgotovit_napominanie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    napominanie_id uuid,
    deystvie_id uuid,
    soobshchenie_id uuid,
    reshenie text,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_reminder_id uuid;
    v_expected_generation bigint;
    v_text text;
    v_text_safe text;
    v_now timestamptz;
    v_loss_after integer;

    v_reminder record;
    v_dialog record;
    v_identity record;
    v_basis record;
    v_next_rem2 timestamptz;
    v_existing_action record;
    v_message_id uuid;
    v_action_id uuid;
    v_key text;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_reminder_id := NULLIF(p_dannye->>'napominanie_id', '')::uuid;
    v_expected_generation := NULLIF(p_dannye->>'pokolenie_ozhidaniya', '')::bigint;
    v_text := p_dannye->>'tekst_ishodnyy';
    v_text_safe := p_dannye->>'tekst_obezlichennyy';
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_proverki', '')::timestamptz,
        clock_timestamp()
    );
    v_loss_after := COALESCE(
        NULLIF(p_dannye->>'poterya_posle_sekund', '')::integer,
        86400
    );

    IF v_operaciya IS NULL
       OR v_reminder_id IS NULL
       OR v_expected_generation IS NULL
       OR v_expected_generation < 0
       OR v_text IS NULL
       OR v_loss_after < 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны reminder/generation/text и trusted loss delay.'::text,
            NULL::timestamptz,
            v_reminder_id, NULL::uuid, NULL::uuid, 'otmenit'::text,
            v_expected_generation;
        RETURN;
    END IF;

    SELECT n.*
      INTO v_reminder
      FROM qbit_test.napominaniya AS n
     WHERE n.id = v_reminder_id
     FOR UPDATE;

    IF NOT FOUND
       OR v_reminder.tip NOT IN ('napominanie_1', 'napominanie_2') THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'napominanie_ne_naydeno'::text,
            'Reminder1/2 не найден.'::text,
            NULL::timestamptz,
            v_reminder_id, NULL::uuid, NULL::uuid, 'otmenit'::text,
            v_expected_generation;
        RETURN;
    END IF;

    IF v_reminder.pokolenie_ozhidaniya IS DISTINCT FROM v_expected_generation THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_generation'::text,
            'Поколение ожидания уже изменилось.'::text,
            NULL::timestamptz,
            v_reminder_id, v_reminder.ishodyashchee_deystvie_id,
            NULL::uuid, 'otmenit'::text, v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_reminder.status <> 'zaplanirovano' THEN
        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Reminder уже был обработан или находится в обработке.'::text,
            NULL::timestamptz,
            v_reminder_id, v_reminder.ishodyashchee_deystvie_id,
            NULL::uuid,
            CASE
                WHEN v_reminder.status = 'podtverzhdeno' THEN 'uzhe_otpravleno'
                ELSE 'otmenit'
            END::text,
            v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_reminder.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    SELECT m.*
      INTO v_basis
      FROM qbit_test.soobshcheniya AS m
     WHERE m.id = v_reminder.soobshchenie_osnovanie_id;

    IF v_now < v_reminder.srok THEN
        RETURN QUERY SELECT
            v_operaciya, 'povtor'::text, 'eshche_rano'::text,
            'Срок reminder ещё не наступил.'::text,
            v_reminder.srok,
            v_reminder_id, NULL::uuid, NULL::uuid, 'povtorit_pozzhe'::text,
            v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_now > v_reminder.aktualno_do THEN
        UPDATE qbit_test.napominaniya AS n_skip
           SET status = 'propushcheno',
               prichina = 'okno_isteklo',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_skip.id = v_reminder_id;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            'Окно reminder истекло; отправка пропущена.'::text,
            NULL::timestamptz,
            v_reminder_id, NULL::uuid, NULL::uuid, 'propustit'::text,
            v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_reminder.tip = 'napominanie_1' THEN
        SELECT n2.srok
          INTO v_next_rem2
          FROM qbit_test.napominaniya AS n2
         WHERE n2.dialog_id = v_reminder.dialog_id
           AND n2.pokolenie_ozhidaniya = v_reminder.pokolenie_ozhidaniya
           AND n2.tip = 'napominanie_2';

        IF v_next_rem2 IS NOT NULL
           AND v_now >= v_next_rem2 THEN
            UPDATE qbit_test.napominaniya AS n_skip2
               SET status = 'propushcheno',
                   prichina = 'uzhe_nastupil_srok_napominaniya_2',
                   vremya_obnovleniya = clock_timestamp()
             WHERE n_skip2.id = v_reminder_id;

            RETURN QUERY SELECT
                v_operaciya, 'uspeshno'::text, NULL::text,
                'Reminder1 не отправляется вплотную к уже наступившему reminder2.'::text,
                NULL::timestamptz,
                v_reminder_id, NULL::uuid, NULL::uuid, 'propustit'::text,
                v_reminder.pokolenie_ozhidaniya;
            RETURN;
        END IF;
    END IF;

    IF v_dialog.vladelec <> 'bot'
       OR v_dialog.status <> 'ozhidaet_otveta'
       OR NOT v_dialog.ozhidaetsya_otvet
       OR v_dialog.t0 IS DISTINCT FROM v_reminder.t0
       OR v_dialog.pokolenie_ozhidaniya IS DISTINCT FROM v_reminder.pokolenie_ozhidaniya
       OR v_identity.logicheski_zablokirovan
       OR v_identity.zapret_iniciativnyh_soobshcheniy
       OR v_basis.status_otpravki <> 'podtverzhdeno'
       OR EXISTS (
            SELECT 1
              FROM qbit_test.soobshcheniya AS m_in
             WHERE m_in.dialog_id = v_dialog.id
               AND m_in.napravlenie = 'vhodyashchee'
               AND m_in.avtor = 'klient'
               AND m_in.vremya_priema > v_reminder.t0
       ) THEN
        UPDATE qbit_test.napominaniya AS n_cancel
           SET status = 'otmeneno',
               prichina = 'finalnaya_proverka_ne_proydena',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_cancel.id = v_reminder_id;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            'Final reminder recheck запретил отправку.'::text,
            NULL::timestamptz,
            v_reminder_id, NULL::uuid, NULL::uuid, 'otmenit'::text,
            v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    v_key := 'napominanie:' || v_reminder_id::text;

    SELECT a.*
      INTO v_existing_action
      FROM qbit_test.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora = v_key;

    IF FOUND THEN
        UPDATE qbit_test.napominaniya AS n_link
           SET ishodyashchee_deystvie_id = v_existing_action.id,
               status = CASE
                   WHEN v_existing_action.status = 'podtverzhdeno' THEN 'podtverzhdeno'
                   WHEN v_existing_action.status = 'neizvestno' THEN 'neizvestno'
                   WHEN v_existing_action.status = 'oshibka' THEN 'oshibka'
                   ELSE 'v_rabote'
               END,
               vremya_obnovleniya = clock_timestamp()
         WHERE n_link.id = v_reminder_id;

        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Stable reminder action уже существует.'::text,
            v_existing_action.povtor_posle,
            v_reminder_id, v_existing_action.id, v_existing_action.soobshchenie_id,
            'otpravit'::text, v_reminder.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    INSERT INTO qbit_test.soobshcheniya AS new_message (
        dialog_id,
        napravlenie,
        avtor,
        vid,
        tekst_ishodnyy,
        tekst_obezlichennyy,
        vremya_priema,
        status_otpravki,
        ozhidaetsya_otvet,
        tip_zaversheniya,
        prichina_resheniya,
        trassirovka_id
    )
    VALUES (
        v_dialog.id,
        'ishodyashchee',
        'bot',
        'text',
        v_text,
        v_text_safe,
        v_now,
        'zaplanirovano',
        false,
        NULL,
        'napominanie',
        v_operaciya
    )
    RETURNING new_message.id
    INTO v_message_id;

    INSERT INTO qbit_test.ishodyashchie_deystviya AS new_action (
        dialog_id,
        soobshchenie_id,
        vid_deystviya,
        istochnik,
        klyuch_povtora,
        kanal,
        akkaunt_kanala_id,
        vneshniy_dialog_id,
        payload,
        status,
        sleduyushchiy_zapusk,
        versiya_dialoga
    )
    VALUES (
        v_dialog.id,
        v_message_id,
        'soobshchenie',
        'sistema',
        v_key,
        v_identity.kanal,
        v_identity.akkaunt_kanala_id,
        v_identity.vneshniy_dialog_id,
        jsonb_build_object(
            'iniciativnoe', true,
            'napominanie_id', v_reminder_id,
            'tip_napominaniya', v_reminder.tip,
            'poterya_posle_sekund', v_loss_after
        ),
        'zaplanirovano',
        v_now,
        v_dialog.versiya_dialoga
    )
    RETURNING new_action.id
    INTO v_action_id;

    UPDATE qbit_test.napominaniya AS n_work
       SET status = 'v_rabote',
           ishodyashchee_deystvie_id = v_action_id,
           vremya_obnovleniya = clock_timestamp()
     WHERE n_work.id = v_reminder_id;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Reminder прошёл final recheck; outgoing action создан.'::text,
        NULL::timestamptz,
        v_reminder_id, v_action_id, v_message_id, 'otpravit'::text,
        v_reminder.pokolenie_ozhidaniya;
END
$fn$;

COMMENT ON FUNCTION qbit_test.podgotovit_napominanie(jsonb) IS
'DB-03C4: final reminder recheck под locks; проверяет generation/t0/owner/block/opt-out/new input/window, skip reminder1 near reminder2, затем создаёт initiative outgoing action.';

-- ===========================================================================
-- 5. LOSS CHECK AFTER CONFIRMED REMINDER2
-- ===========================================================================

CREATE FUNCTION qbit_test.zafiksirovat_poteryu_bez_otveta(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    napominanie_id uuid,
    dialog_id uuid,
    status_dialoga text,
    rezultat_dialoga text,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_loss_id uuid;
    v_now timestamptz;
    v_loss record;
    v_dialog record;
    v_identity record;
    v_rem2 record;
    v_new_version bigint;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_loss_id := NULLIF(p_dannye->>'napominanie_id', '')::uuid;
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_proverki', '')::timestamptz,
        clock_timestamp()
    );

    IF v_operaciya IS NULL OR v_loss_id IS NULL THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужен loss-check reminder id.'::text, NULL::timestamptz,
            v_loss_id, NULL::uuid, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT n.*
      INTO v_loss
      FROM qbit_test.napominaniya AS n
     WHERE n.id = v_loss_id
       AND n.tip = 'proverka_poteri'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'proverka_poteri_ne_naydena'::text,
            'Loss-check reminder не найден.'::text, NULL::timestamptz,
            v_loss_id, NULL::uuid, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_loss.status <> 'zaplanirovano' THEN
        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Loss-check уже обработан.'::text, NULL::timestamptz,
            v_loss_id, v_loss.dialog_id, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_now < v_loss.srok THEN
        RETURN QUERY SELECT
            v_operaciya, 'povtor'::text, 'eshche_rano'::text,
            'Срок loss-check ещё не наступил.'::text, v_loss.srok,
            v_loss_id, v_loss.dialog_id, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_loss.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    SELECT n2.*
      INTO v_rem2
      FROM qbit_test.napominaniya AS n2
     WHERE n2.dialog_id = v_loss.dialog_id
       AND n2.pokolenie_ozhidaniya = v_loss.pokolenie_ozhidaniya
       AND n2.tip = 'napominanie_2';

    IF NOT FOUND
       OR v_rem2.status <> 'podtverzhdeno'
       OR v_rem2.vremya_fakticheskoy_otpravki IS NULL THEN
        UPDATE qbit_test.napominaniya AS n_bad
           SET status = 'otmeneno',
               prichina = 'net_podtverzhdennogo_napominaniya_2',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_bad.id = v_loss_id;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            'Loss запрещён: reminder2 не имеет подтверждённой отправки.'::text,
            NULL::timestamptz,
            v_loss_id, v_loss.dialog_id, v_dialog.status, v_dialog.rezultat,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.status <> 'ozhidaet_otveta'
       OR NOT v_dialog.ozhidaetsya_otvet
       OR v_dialog.pokolenie_ozhidaniya IS DISTINCT FROM v_loss.pokolenie_ozhidaniya
       OR v_dialog.t0 IS DISTINCT FROM v_loss.t0
       OR v_dialog.vladelec <> 'bot'
       OR v_identity.logicheski_zablokirovan
       OR v_identity.zapret_iniciativnyh_soobshcheniy
       OR EXISTS (
            SELECT 1
              FROM qbit_test.soobshcheniya AS m_in
             WHERE m_in.dialog_id = v_dialog.id
               AND m_in.napravlenie = 'vhodyashchee'
               AND m_in.avtor = 'klient'
               AND m_in.vremya_priema > v_loss.t0
       ) THEN
        UPDATE qbit_test.napominaniya AS n_cancel
           SET status = 'otmeneno',
               prichina = 'dialog_bolshe_ne_zhdet',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_cancel.id = v_loss_id;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            'Loss-check отменён: ожидание больше не актуально.'::text,
            NULL::timestamptz,
            v_loss_id, v_loss.dialog_id, v_dialog.status, v_dialog.rezultat,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    UPDATE qbit_test.dialogi AS d_loss
       SET status = 'zavershen',
           rezultat = 'net_otveta',
           prichina_zaversheniya = 'posle_podtverzhdennogo_napominaniya_2',
           vremya_zaversheniya = v_now,
           ozhidaetsya_otvet = false,
           t0 = NULL,
           pokolenie_ozhidaniya = d_loss.pokolenie_ozhidaniya + 1,
           versiya_dialoga = d_loss.versiya_dialoga + 1,
           vremya_obnovleniya = clock_timestamp()
     WHERE d_loss.id = v_dialog.id
     RETURNING d_loss.versiya_dialoga
     INTO v_new_version;

    UPDATE qbit_test.napominaniya AS n_loss
       SET status = CASE
           WHEN n_loss.id = v_loss_id THEN 'podtverzhdeno'
           WHEN n_loss.status IN ('zaplanirovano', 'v_rabote') THEN 'otmeneno'
           ELSE n_loss.status
       END,
       prichina = CASE
           WHEN n_loss.id = v_loss_id THEN 'net_otveta_zafiksirovan'
           WHEN n_loss.status IN ('zaplanirovano', 'v_rabote') THEN 'dialog_zavershen'
           ELSE n_loss.prichina
       END,
       vremya_obnovleniya = clock_timestamp()
     WHERE n_loss.dialog_id = v_dialog.id
       AND n_loss.pokolenie_ozhidaniya = v_loss.pokolenie_ozhidaniya;

    UPDATE qbit_test.polzovateli AS p_loss
       SET tekushchaya_metka = 'poteryannyy',
           vremya_obnovleniya = clock_timestamp()
     WHERE p_loss.id = v_dialog.polzovatel_id;

    INSERT INTO qbit_test.sobytiya_dialogov (
        dialog_id,
        polzovatel_id,
        tip_sobytiya,
        vremya_sobytiya,
        prichina,
        rezultat,
        istochnik,
        trassirovka_id
    )
    VALUES (
        v_dialog.id,
        v_dialog.polzovatel_id,
        'poterya',
        v_now,
        'posle_podtverzhdennogo_napominaniya_2',
        'net_otveta',
        'reminder_loss_check',
        v_operaciya
    );

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Диалог закрыт как net_otveta после подтверждённого reminder2 и отсутствия нового входа.'::text,
        NULL::timestamptz,
        v_loss_id, v_dialog.id, 'zavershen'::text, 'net_otveta'::text,
        v_new_version;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zafiksirovat_poteryu_bez_otveta(jsonb) IS
'DB-03C4: закрывает net_otveta только по durable loss-check после confirmed reminder2 и trusted delay, при том же generation/t0 и отсутствии более нового client input; иначе отменяет loss-check.';

-- ===========================================================================
-- 6. PRIVILEGES
-- ===========================================================================

REVOKE ALL ON FUNCTION qbit_test.sozdat_ishodyashchee_deystvie(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zabrat_ishodyashchee_deystvie(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zafiksirovat_rezultat_ishodyashchego(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.podgotovit_napominanie(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zafiksirovat_poteryu_bez_otveta(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_test.sozdat_ishodyashchee_deystvie(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.zabrat_ishodyashchee_deystvie(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.zafiksirovat_rezultat_ishodyashchego(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.podgotovit_napominanie(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.zafiksirovat_poteryu_bez_otveta(jsonb) TO qbit_test_bot;

-- ===========================================================================
-- 7. STATIC SECURITY ASSERTIONS
-- ===========================================================================

DO $db03c4$
DECLARE
    v_fn record;
BEGIN
    FOR v_fn IN
        SELECT p.oid, p.proname, p.prosecdef, p.proconfig, r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
          JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta'
           )
    LOOP
        IF NOT v_fn.prosecdef
           OR v_fn.owner_name IS DISTINCT FROM 'qbit_test_owner'
           OR NOT (
                COALESCE(v_fn.proconfig, ARRAY[]::text[])
                @> ARRAY['search_path=pg_catalog, qbit_test']::text[]
           ) THEN
            RAISE EXCEPTION
                'Unsafe DB-03C4 function metadata: %, owner=%, config=%',
                v_fn.proname, v_fn.owner_name, v_fn.proconfig;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM pg_catalog.aclexplode(
                    COALESCE(
                        (SELECT p2.proacl FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=v_fn.oid),
                        pg_catalog.acldefault(
                            'f',
                            (SELECT p2.proowner FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=v_fn.oid)
                        )
                    )
              ) AS a
             WHERE a.grantee = 0
               AND a.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'PUBLIC unexpectedly has EXECUTE on %', v_fn.proname;
        END IF;

        IF NOT pg_catalog.has_function_privilege(
            'qbit_test_bot', v_fn.oid, 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'qbit_test_bot lacks EXECUTE on %', v_fn.proname;
        END IF;

        IF pg_catalog.has_function_privilege(
            'qbit_test_sluzhebnyy', v_fn.oid, 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'qbit_test_sluzhebnyy unexpectedly has client outgoing EXECUTE on %', v_fn.proname;
        END IF;
    END LOOP;

    IF (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_test'
           AND p.proname IN (
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta'
           )
    ) <> 5 THEN
        RAISE EXCEPTION 'DB-03C4 expected exactly 5 functions';
    END IF;
END
$db03c4$;

-- ===========================================================================
-- 8. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03c4_probe;

DO $db03c4$
DECLARE
    rin record;
    create1 record;
    create_dup record;
    claim1 record;
    unknown1 record;
    create_stale record;
    claim_stale record;
    rin2 record;
    confirm_stale record;
    create2 record;
    claim2 record;
    retry2 record;
    claim2b record;
    confirm2 record;
    rem1 uuid;
    rem2 uuid;
    prep1 record;
    claim_rem1 record;
    confirm_rem1 record;
    prep2 record;
    claim_rem2 record;
    confirm_rem2 record;
    loss_id uuid;
    loss_early record;
    loss_ok record;
    create_close record;
    claim_close record;
    confirm_close record;
    v_t0 timestamptz;
    v_generation bigint;
BEGIN
    SELECT *
      INTO rin
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c4_ingress',
            'klyuch_idempotentnosti', 'db03c4_in_idem',
            'hash_soderzhaniya', 'db03c4_in_hash',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c4_client_bot',
            'vneshnee_sobytie_id', 'db03c4_event_1',
            'vneshniy_polzovatel_id', 'db03c4_user',
            'vneshniy_dialog_id', 'db03c4_chat',
            'vneshnee_soobshchenie_id', 'db03c4_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Хочу консультацию',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03c4_probe',
            'versiya_prompta', 'db03c4_probe',
            'sluzhebnyy_chat_id', 'db03c4_service_group'
        )
      );

    IF rin.rezultat <> 'uspeshno' OR rin.versiya_dialoga <> 1 THEN
        RAISE EXCEPTION 'DB-03C4 ingress setup failed: %', row_to_json(rin);
    END IF;

    -- Unknown result must never apply waiting/t0/reminders.
    SELECT *
      INTO create1
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id', 'db03c4_create_unknown',
            'klyuch_povtora', 'db03c4_out_unknown',
            'vid_deystviya', 'soobshchenie',
            'istochnik', 'bot',
            'dialog_id', rin.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'iniciativnoe', false,
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c4_client_bot',
            'vneshniy_dialog_id', 'db03c4_chat',
            'tekst_ishodnyy', 'Ответ неизвестного результата',
            'tekst_obezlichennyy', 'Ответ неизвестного результата',
            'ozhidaetsya_otvet', true,
            'effekty_posle_podtverzhdeniya', jsonb_build_object(
                'napominanie_1_sekund', 10800,
                'napominanie_2_sekund', 43200,
                'okno_napominaniya_sekund', 3600,
                'poterya_posle_sekund', 86400
            )
        )
      );

    SELECT *
      INTO create_dup
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id', 'db03c4_create_unknown_dup',
            'klyuch_povtora', 'db03c4_out_unknown',
            'vid_deystviya', 'soobshchenie',
            'istochnik', 'bot',
            'dialog_id', rin.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'iniciativnoe', false,
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c4_client_bot',
            'vneshniy_dialog_id', 'db03c4_chat',
            'tekst_ishodnyy', 'Ответ неизвестного результата',
            'tekst_obezlichennyy', 'Ответ неизвестного результата',
            'ozhidaetsya_otvet', true,
            'effekty_posle_podtverzhdeniya', jsonb_build_object(
                'napominanie_1_sekund', 10800,
                'napominanie_2_sekund', 43200,
                'okno_napominaniya_sekund', 3600,
                'poterya_posle_sekund', 86400
            )
        )
      );

    IF create1.rezultat <> 'uspeshno'
       OR create_dup.rezultat <> 'dublikat'
       OR create_dup.deystvie_id IS DISTINCT FROM create1.deystvie_id THEN
        RAISE EXCEPTION 'DB-03C4 outgoing stable-key idempotency failed';
    END IF;

    SELECT *
      INTO claim1
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_unknown',
            'worker_id','out_worker_1',
            'arenda_sekund',120
        )
      );

    SELECT *
      INTO unknown1
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_unknown_result',
            'deystvie_id',claim1.deystvie_id,
            'worker_id','out_worker_1',
            'nomer_vladeniya',claim1.nomer_vladeniya,
            'status','neizvestno',
            'kod_oshibki','transport_ambiguous',
            'opisanie_oshibki','probe unknown'
        )
      );

    IF unknown1.rezultat <> 'uspeshno'
       OR unknown1.status_deystviya <> 'neizvestno'
       OR EXISTS (
            SELECT 1 FROM qbit_test.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND (d.ozhidaetsya_otvet OR d.t0 IS NOT NULL)
       )
       OR EXISTS (
            SELECT 1 FROM qbit_test.napominaniya AS n
             WHERE n.dialog_id=rin.dialog_id
       ) THEN
        RAISE EXCEPTION 'DB-03C4 unknown result applied dependent effects: %', row_to_json(unknown1);
    END IF;

    -- If the external API already sent while a new client input crossed in flight,
    -- confirmed delivery is stored but stale t0/reminder effects are suppressed.
    SELECT *
      INTO create_stale
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_create_stale_confirm',
            'klyuch_povtora','db03c4_out_stale_confirm',
            'dialog_id',rin.dialog_id,
            'ozhidaemaya_versiya_dialoga',1,
            'kanal','telegram',
            'akkaunt_kanala_id','db03c4_client_bot',
            'vneshniy_dialog_id','db03c4_chat',
            'tekst_ishodnyy','Сообщение ушло одновременно с новым входом',
            'tekst_obezlichennyy','Сообщение ушло одновременно с новым входом',
            'ozhidaetsya_otvet',true,
            'effekty_posle_podtverzhdeniya',jsonb_build_object(
                'napominanie_1_sekund',10800,
                'napominanie_2_sekund',43200,
                'okno_napominaniya_sekund',3600,
                'poterya_posle_sekund',86400
            )
        )
      );

    SELECT *
      INTO claim_stale
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_stale_confirm',
            'worker_id','out_worker_stale',
            'arenda_sekund',120
        )
      );

    SELECT *
      INTO rin2
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03c4_ingress_cross',
            'klyuch_idempotentnosti','db03c4_in_cross',
            'hash_soderzhaniya','db03c4_in_cross_hash',
            'kanal','telegram',
            'akkaunt_kanala_id','db03c4_client_bot',
            'vneshnee_sobytie_id','db03c4_event_cross',
            'vneshniy_polzovatel_id','db03c4_user',
            'vneshniy_dialog_id','db03c4_chat',
            'vneshnee_soobshchenie_id','db03c4_msg_cross',
            'tip_sobytiya','message',
            'tip_soobshcheniya','text',
            'tekst_ishodnyy','Новый вход пересёкся с отправкой',
            'vremya_priema',clock_timestamp(),
            'versiya_workflow','db03c4_probe',
            'versiya_prompta','db03c4_probe',
            'sluzhebnyy_chat_id','db03c4_service_group'
        )
      );

    SELECT *
      INTO confirm_stale
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_confirm_stale_after_input',
            'deystvie_id',claim_stale.deystvie_id,
            'worker_id','out_worker_stale',
            'nomer_vladeniya',claim_stale.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03c4_ext_stale_real_send',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF rin2.versiya_dialoga <> 2
       OR confirm_stale.rezultat <> 'uspeshno'
       OR confirm_stale.status_deystviya <> 'podtverzhdeno'
       OR EXISTS (
            SELECT 1 FROM qbit_test.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND (d.ozhidaetsya_otvet OR d.t0 IS NOT NULL)
       )
       OR EXISTS (
            SELECT 1 FROM qbit_test.napominaniya AS n
             WHERE n.dialog_id=rin.dialog_id
       )
       OR NOT EXISTS (
            SELECT 1 FROM qbit_test.soobshcheniya AS m
             WHERE m.id=create_stale.soobshchenie_id
               AND m.status_otpravki='podtverzhdeno'
               AND m.vneshnee_soobshchenie_id='db03c4_ext_stale_real_send'
       ) THEN
        RAISE EXCEPTION
            'DB-03C4 in-flight confirmed send was not recorded/suppressed correctly: input=%, result=%',
            row_to_json(rin2), row_to_json(confirm_stale);
    END IF;

    -- Continue all normal confirmed-flow probes on current dialog version 2.
    -- Confirmed main message: retry once, then confirm and create t0/reminders.
    SELECT *
      INTO create2
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id', 'db03c4_create_wait',
            'klyuch_povtora', 'db03c4_out_wait',
            'vid_deystviya', 'soobshchenie',
            'istochnik', 'bot',
            'dialog_id', rin.dialog_id,
            'ozhidaemaya_versiya_dialoga', 2,
            'iniciativnoe', false,
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c4_client_bot',
            'vneshniy_dialog_id', 'db03c4_chat',
            'tekst_ishodnyy', 'Какой размер окна вам нужен?',
            'tekst_obezlichennyy', 'Какой размер окна вам нужен?',
            'ozhidaetsya_otvet', true,
            'effekty_posle_podtverzhdeniya', jsonb_build_object(
                'novyy_etap','utochnenie_parametrov',
                'napominanie_1_sekund',10800,
                'napominanie_2_sekund',43200,
                'okno_napominaniya_sekund',3600,
                'poterya_posle_sekund',86400
            )
        )
      );

    SELECT *
      INTO claim2
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_wait_1',
            'worker_id','out_worker_2',
            'arenda_sekund',120
        )
      );

    SELECT *
      INTO retry2
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_retry_wait',
            'deystvie_id',claim2.deystvie_id,
            'worker_id','out_worker_2',
            'nomer_vladeniya',claim2.nomer_vladeniya,
            'status','povtor',
            'povtor_posle',clock_timestamp()+interval '10 minutes',
            'kod_oshibki','temporary_probe'
        )
      );

    IF retry2.rezultat <> 'uspeshno'
       OR retry2.status_deystviya <> 'povtor' THEN
        RAISE EXCEPTION 'DB-03C4 retry result failed: %', row_to_json(retry2);
    END IF;

    UPDATE qbit_test.ishodyashchie_deystviya AS a_probe
       SET sleduyushchiy_zapusk=clock_timestamp()-interval '1 second',
           povtor_posle=clock_timestamp()-interval '1 second'
     WHERE a_probe.id=create2.deystvie_id;

    SELECT *
      INTO claim2b
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_wait_2',
            'worker_id','out_worker_3',
            'arenda_sekund',120
        )
      );

    SELECT *
      INTO confirm2
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_confirm_wait',
            'deystvie_id',claim2b.deystvie_id,
            'worker_id','out_worker_3',
            'nomer_vladeniya',claim2b.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03c4_external_main',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    SELECT d.t0,d.pokolenie_ozhidaniya
      INTO v_t0,v_generation
      FROM qbit_test.dialogi AS d
     WHERE d.id=rin.dialog_id;

    SELECT n.id INTO rem1
      FROM qbit_test.napominaniya AS n
     WHERE n.dialog_id=rin.dialog_id
       AND n.pokolenie_ozhidaniya=v_generation
       AND n.tip='napominanie_1';

    SELECT n.id INTO rem2
      FROM qbit_test.napominaniya AS n
     WHERE n.dialog_id=rin.dialog_id
       AND n.pokolenie_ozhidaniya=v_generation
       AND n.tip='napominanie_2';

    IF confirm2.rezultat <> 'uspeshno'
       OR v_t0 IS NULL
       OR v_generation <> 1
       OR rem1 IS NULL
       OR rem2 IS NULL
       OR NOT EXISTS (
            SELECT 1 FROM qbit_test.sobytiya_zerkala_operatora AS z
             WHERE z.soobshchenie_id=create2.soobshchenie_id
               AND z.tip_sobytiya='otvet_bota'
       ) THEN
        RAISE EXCEPTION 'DB-03C4 confirmed main/t0/reminders/mirror failed: %',row_to_json(confirm2);
    END IF;

    -- Reminder1 confirmed: t0 must stay unchanged.
    UPDATE qbit_test.napominaniya AS n_probe
       SET srok=clock_timestamp()-interval '1 second',
           aktualno_do=clock_timestamp()+interval '1 hour'
     WHERE n_probe.id=rem1;

    SELECT * INTO prep1
      FROM qbit_test.podgotovit_napominanie(
        jsonb_build_object(
            'operaciya_id','db03c4_prepare_rem1',
            'napominanie_id',rem1,
            'pokolenie_ozhidaniya',v_generation,
            'tekst_ishodnyy','Напоминаем о вопросе.',
            'tekst_obezlichennyy','Напоминаем о вопросе.',
            'poterya_posle_sekund',86400
        )
      );

    SELECT * INTO claim_rem1
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_rem1',
            'worker_id','out_worker_r1',
            'arenda_sekund',120
        )
      );

    SELECT * INTO confirm_rem1
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_confirm_rem1',
            'deystvie_id',claim_rem1.deystvie_id,
            'worker_id','out_worker_r1',
            'nomer_vladeniya',claim_rem1.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03c4_ext_rem1',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF prep1.reshenie <> 'otpravit'
       OR confirm_rem1.rezultat <> 'uspeshno'
       OR EXISTS (
            SELECT 1 FROM qbit_test.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND d.t0 IS DISTINCT FROM v_t0
       )
       OR NOT EXISTS (
            SELECT 1 FROM qbit_test.sobytiya_zerkala_operatora AS z
             WHERE z.soobshchenie_id=prep1.soobshchenie_id
               AND z.tip_sobytiya='otvet_bota'
       ) THEN
        RAISE EXCEPTION 'DB-03C4 reminder1 moved t0 or failed';
    END IF;

    -- Reminder2 confirmed creates durable loss-check based on actual send time.
    UPDATE qbit_test.napominaniya AS n_probe2
       SET srok=clock_timestamp()-interval '1 second',
           aktualno_do=clock_timestamp()+interval '1 hour'
     WHERE n_probe2.id=rem2;

    SELECT * INTO prep2
      FROM qbit_test.podgotovit_napominanie(
        jsonb_build_object(
            'operaciya_id','db03c4_prepare_rem2',
            'napominanie_id',rem2,
            'pokolenie_ozhidaniya',v_generation,
            'tekst_ishodnyy','Второе напоминание.',
            'tekst_obezlichennyy','Второе напоминание.',
            'poterya_posle_sekund',86400
        )
      );

    SELECT * INTO claim_rem2
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_rem2',
            'worker_id','out_worker_r2',
            'arenda_sekund',120
        )
      );

    SELECT * INTO confirm_rem2
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_confirm_rem2',
            'deystvie_id',claim_rem2.deystvie_id,
            'worker_id','out_worker_r2',
            'nomer_vladeniya',claim_rem2.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03c4_ext_rem2',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    SELECT n.id INTO loss_id
      FROM qbit_test.napominaniya AS n
     WHERE n.dialog_id=rin.dialog_id
       AND n.pokolenie_ozhidaniya=v_generation
       AND n.tip='proverka_poteri';

    IF prep2.reshenie <> 'otpravit'
       OR confirm_rem2.rezultat <> 'uspeshno'
       OR loss_id IS NULL THEN
        RAISE EXCEPTION 'DB-03C4 reminder2/loss-check creation failed';
    END IF;

    SELECT * INTO loss_early
      FROM qbit_test.zafiksirovat_poteryu_bez_otveta(
        jsonb_build_object(
            'operaciya_id','db03c4_loss_early',
            'napominanie_id',loss_id,
            'vremya_proverki',clock_timestamp()
        )
      );

    IF loss_early.rezultat <> 'povtor'
       OR loss_early.kod_oshibki <> 'eshche_rano' THEN
        RAISE EXCEPTION 'DB-03C4 early loss was not postponed: %',row_to_json(loss_early);
    END IF;

    UPDATE qbit_test.napominaniya AS n_lossprobe
       SET srok=clock_timestamp()-interval '1 second'
     WHERE n_lossprobe.id=loss_id;

    SELECT * INTO loss_ok
      FROM qbit_test.zafiksirovat_poteryu_bez_otveta(
        jsonb_build_object(
            'operaciya_id','db03c4_loss_ok',
            'napominanie_id',loss_id,
            'vremya_proverki',clock_timestamp()
        )
      );

    IF loss_ok.rezultat <> 'uspeshno'
       OR loss_ok.rezultat_dialoga <> 'net_otveta'
       OR loss_ok.status_dialoga <> 'zavershen' THEN
        RAISE EXCEPTION 'DB-03C4 loss close failed: %',row_to_json(loss_ok);
    END IF;

    -- New dialog after loss: confirmed non-waiting close path.
    SELECT *
      INTO rin
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03c4_ingress_return',
            'klyuch_idempotentnosti','db03c4_in_return',
            'hash_soderzhaniya','db03c4_in_return_hash',
            'kanal','telegram',
            'akkaunt_kanala_id','db03c4_client_bot',
            'vneshnee_sobytie_id','db03c4_event_return',
            'vneshniy_polzovatel_id','db03c4_user',
            'vneshniy_dialog_id','db03c4_chat',
            'vneshnee_soobshchenie_id','db03c4_msg_return',
            'tip_sobytiya','message',
            'tip_soobshcheniya','text',
            'tekst_ishodnyy','Спасибо, вопрос решён',
            'vremya_priema',clock_timestamp(),
            'versiya_workflow','db03c4_probe',
            'versiya_prompta','db03c4_probe',
            'sluzhebnyy_chat_id','db03c4_service_group'
        )
      );

    SELECT * INTO create_close
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_create_close',
            'klyuch_povtora','db03c4_out_close',
            'dialog_id',rin.dialog_id,
            'ozhidaemaya_versiya_dialoga',rin.versiya_dialoga,
            'kanal','telegram',
            'akkaunt_kanala_id','db03c4_client_bot',
            'vneshniy_dialog_id','db03c4_chat',
            'tekst_ishodnyy','Рады помочь.',
            'tekst_obezlichennyy','Рады помочь.',
            'ozhidaetsya_otvet',false,
            'tip_zaversheniya','konsultaciya_zavershena',
            'prichina_resheniya','spravochnyy_otvet_zavershen',
            'effekty_posle_podtverzhdeniya',jsonb_build_object(
                'zavershit_rezultat','konsultaciya_zavershena'
            )
        )
      );

    SELECT * INTO claim_close
      FROM qbit_test.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03c4_claim_close',
            'worker_id','out_worker_close',
            'arenda_sekund',120
        )
      );

    SELECT * INTO confirm_close
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03c4_confirm_close',
            'deystvie_id',claim_close.deystvie_id,
            'worker_id','out_worker_close',
            'nomer_vladeniya',claim_close.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03c4_ext_close',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF confirm_close.rezultat <> 'uspeshno'
       OR NOT EXISTS (
            SELECT 1 FROM qbit_test.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND d.status='zavershen'
               AND d.rezultat='konsultaciya_zavershena'
               AND NOT d.ozhidaetsya_otvet
               AND d.t0 IS NULL
       ) THEN
        RAISE EXCEPTION 'DB-03C4 confirmed close path failed: %',row_to_json(confirm_close);
    END IF;
END
$db03c4$;

ROLLBACK TO SAVEPOINT db03c4_probe;
RELEASE SAVEPOINT db03c4_probe;

-- ===========================================================================
-- 9. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03c4$
DECLARE
    v_role text;
    v_table record;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id='db03c4_client_bot'
            OR i.vneshniy_polzovatel_id='db03c4_user'
    ) THEN
        RAISE EXCEPTION 'DB-03C4 probe rows remain after rollback';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_admin'
    ]
    LOOP
        FOR v_table IN
            SELECT c.oid,c.relname
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
             WHERE n.nspname='qbit_test'
               AND c.relkind='r'
        LOOP
            IF pg_catalog.has_table_privilege(v_role,v_table.oid,'SELECT')
            OR pg_catalog.has_table_privilege(v_role,v_table.oid,'INSERT')
            OR pg_catalog.has_table_privilege(v_role,v_table.oid,'UPDATE')
            OR pg_catalog.has_table_privilege(v_role,v_table.oid,'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % unexpectedly has direct DML on qbit_test.%',
                    v_role,v_table.relname;
            END IF;
        END LOOP;
    END LOOP;
END
$db03c4$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 10. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03c4_status','applied',
    'database',current_database(),
    'schema','qbit_test',
    'functions_ok',
    (
        SELECT count(*)=5
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_test'
           AND p.proname IN (
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta'
           )
           AND p.prosecdef=true
    ),
    'bot_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_test.sozdat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_test.zabrat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_test.zafiksirovat_rezultat_ishodyashchego(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_test.podgotovit_napominanie(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_test.zafiksirovat_poteryu_bez_otveta(jsonb)','EXECUTE'
    ),
    'service_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_test.sozdat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    ),
    'outgoing_unique_key_ok',
    pg_catalog.to_regclass('qbit_test.uq_ishod_klyuch_povtora') IS NOT NULL,
    'reminder_unique_generation_ok',
    pg_catalog.to_regclass('qbit_test.uq_napominaniya_dialog_pok_tip') IS NOT NULL,
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id='db03c4_client_bot'
            OR i.vneshniy_polzovatel_id='db03c4_user'
    ),
    'runtime_direct_dml',false,
    'result',
    'DB-03C4 SQL APPLIED: outgoing intent/lease/in-flight-confirmed fact/confirmed-vs-unknown effects/t0/reminders/loss-check verified; probe data removed; production untouched.'
) AS db03c4_result;
