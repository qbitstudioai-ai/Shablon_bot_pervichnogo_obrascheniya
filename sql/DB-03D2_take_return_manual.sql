-- DB-03D2 v0.1: operator Take/Return, manual outgoing and private alert
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- TARGET: qbit_bot_pervichnogo_obrascheniya ONLY, self-hosted PostgreSQL 17.6
--
-- REQUIRES: DB-03D1 applied.
--
-- CREATES 4 SECURITY DEFINER FUNCTIONS
--   zabrat_dialog_operatorom(jsonb)      -> qbit_test_sluzhebnyy
--   vernut_dialog_botu(jsonb)            -> qbit_test_sluzhebnyy
--   sozdat_ruchnoe_ishodyashchee(jsonb)  -> qbit_test_sluzhebnyy
--   sozdat_lichnoe_uvedomlenie(jsonb)    -> qbit_test_bot
--
-- CONTROLLED UPGRADES, SAME SIGNATURE/RETURN TYPE
--   zabrat_ishodyashchee_deystvie(jsonb)
--   zafiksirovat_rezultat_ishodyashchego(jsonb)
--
-- SAFETY
--   * Take is atomic first-commit-wins on dialog row + expected version.
--   * Take cancels waiting/reminders/internal jobs and only not-yet-claimed
--     bot/system outgoing actions. v_rabote external attempts are preserved
--     so a later confirmed fact is not lost.
--   * Manual action is created only by current manager in confirmed topic.
--   * Existing bot C4 create API remains bot/system-only.
--   * Client bot worker can claim manager action only while exact manager
--     still owns the same dialog version.
--   * Return never creates a client outgoing action.
--   * Private alert takes manager UUID, never arbitrary chat_id.
--   * Production schema qbit is untouched.
--   * Probe is rolled back to SAVEPOINT before COMMIT.

BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='180s';
SET LOCAL search_path=pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03d2$
DECLARE
    v_name text;
    v_oid oid;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION 'DB-03D2 requires PostgreSQL 17+';
    END IF;

    IF session_user <> 'postgres'
       OR NOT pg_catalog.pg_has_role(session_user,'qbit_test_owner','SET') THEN
        RAISE EXCEPTION
            'DB-03D2 requires trusted postgres session with SET qbit_test_owner';
    END IF;

    FOREACH v_name IN ARRAY ARRAY[
        'zaregistrirovat_sluzhebnoe_sobytie',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego'
    ]
    LOOP
        SELECT p.oid
          INTO v_oid
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname=v_name
           AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb';

        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'Required function qbit_bot_pervichnogo_obrascheniya.%(jsonb) missing',v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY ARRAY[
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
               AND p.proname=v_name
        ) THEN
            RAISE EXCEPTION
                'DB-03D2 function qbit_bot_pervichnogo_obrascheniya.% already exists; stop instead of overwriting',
                v_name;
        END IF;
    END LOOP;

    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)',
        'EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(jsonb)',
        'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Unexpected C4 privileges before DB-03D2';
    END IF;
END
$db03d2$;

SET LOCAL ROLE qbit_test_owner;

-- ===========================================================================
-- 1. UPGRADE C4 CLAIM TO SUPPORT TRUSTED MANAGER ACTIONS
-- ===========================================================================

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
            a.istochnik,
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
            d.tekushchiy_menedzher_id AS current_manager_id,
            d.status AS dialog_status,
            i.logicheski_zablokirovan,
            i.zapret_iniciativnyh_soobshcheniy
          INTO v_candidate
          FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
          JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
            ON d.id = a.dialog_id
          JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
            WHEN v_candidate.istochnik = 'menedzher'
             AND (
                    v_candidate.dialog_owner <> 'chelovek'
                    OR v_candidate.dialog_status <> 'peredan_cheloveku'
                    OR v_candidate.current_manager_id::text
                       IS DISTINCT FROM NULLIF(v_candidate.payload->>'menedzher_id','')
             )
            THEN 'menedzher_bolshe_ne_vladelec'
            WHEN v_candidate.istochnik <> 'menedzher'
             AND v_candidate.logicheski_zablokirovan
            THEN 'logicheski_zablokirovan'
            WHEN v_candidate.istochnik <> 'menedzher'
             AND v_candidate.dialog_owner <> 'bot'
            THEN 'vladelec_ne_bot'
            WHEN v_candidate.istochnik <> 'menedzher'
             AND v_candidate.dialog_status IN ('peredan_cheloveku', 'zavershen')
            THEN 'dialog_ne_aktiven'
            WHEN v_candidate.istochnik <> 'menedzher'
             AND v_initiative
             AND v_candidate.zapret_iniciativnyh_soobshcheniy
            THEN 'zapret_iniciativy'
            ELSE NULL
        END;

        IF v_cleanup_reason IS NOT NULL THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a_cancel
               SET status = 'otmeneno',
                   vladelec_arendy = NULL,
                   arenda_do = NULL,
                   kod_oshibki = v_cleanup_reason,
                   opisanie_oshibki = 'DB-03C4 claim cleanup: действие больше не разрешено состоянием dialog/identity.',
                   vremya_obnovleniya = clock_timestamp()
             WHERE a_cancel.id = v_candidate.id;

            IF v_candidate.soobshchenie_id IS NOT NULL THEN
                UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_cancel
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

        UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a_claim
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
            UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_claim
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

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb) IS
'DB-03D2 upgrade: claim/reclaim через SKIP LOCKED + lease/fencing; bot/system требуют bot-owner/block/opt-out checks, manager-source требует human owner + exact current manager from trusted payload; neizvestno не claimится.';


-- ===========================================================================
-- 2. UPGRADE C4 RESULT TO SUPPORT TRUSTED MANAGER ACTIONS
-- ===========================================================================

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id = v_action.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    v_initiative := COALESCE((v_action.payload->>'iniciativnoe')::boolean, false);

    v_effects_allowed := CASE
        WHEN v_action.istochnik = 'menedzher' THEN (
            v_action.versiya_dialoga IS NOT DISTINCT FROM v_dialog.versiya_dialoga
            AND v_dialog.vladelec = 'chelovek'
            AND v_dialog.status = 'peredan_cheloveku'
            AND v_dialog.tekushchiy_menedzher_id::text
                IS NOT DISTINCT FROM NULLIF(v_action.payload->>'menedzher_id','')
        )
        ELSE (
            v_action.versiya_dialoga IS NOT DISTINCT FROM v_dialog.versiya_dialoga
            AND v_dialog.vladelec = 'bot'
            AND v_dialog.status NOT IN ('peredan_cheloveku', 'zavershen')
            AND NOT v_identity.logicheski_zablokirovan
            AND NOT (
                v_initiative
                AND v_identity.zapret_iniciativnyh_soobshcheniy
            )
        )
    END;
    v_effects_suppressed := NOT v_effects_allowed;

    -- A retry is a future external call, so stale/forbidden state cancels it.
    -- confirmed/unknown/error are facts about an API attempt that already happened
    -- and must still be persisted even if dialog state changed meanwhile.
    IF v_status = 'povtor' AND NOT v_effects_allowed THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a_cancel
           SET status = 'otmeneno',
               vladelec_arendy = NULL,
               arenda_do = NULL,
               kod_oshibki = 'stale_ili_zapreshcheno',
               opisanie_oshibki = 'Retry suppressed because dialog/identity/owner changed after external attempt.',
               vremya_obnovleniya = clock_timestamp()
         WHERE a_cancel.id = v_action_id;

        IF v_action.soobshchenie_id IS NOT NULL THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_cancel
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a_done
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
        UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_done
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

            UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_result
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
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
         WHERE m.id = v_action.soobshchenie_id
         FOR UPDATE;
    END IF;

    -- Confirmed reminder: the external send fact is stored even if an input
    -- crossed in flight. Such stale confirmation does NOT create further loss chain.
    IF (v_action.payload ? 'napominanie_id') THEN
        v_reminder_id := NULLIF(v_action.payload->>'napominanie_id', '')::uuid;

        SELECT n.tip
          INTO v_reminder_type
          FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
         WHERE n.id = v_reminder_id
           AND n.dialog_id = v_action.dialog_id
         FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Confirmed reminder action % points to missing reminder %',
                v_action_id,
                v_reminder_id;
        END IF;

        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_confirm
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

            INSERT INTO qbit_bot_pervichnogo_obrascheniya.napominaniya (
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
            INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov (
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
            INSERT INTO qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya (
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

            UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_wait
               SET etap = COALESCE(v_next_stage, d_wait.etap),
                   status = 'ozhidaet_otveta',
                   poslednee_ishodyashchee_id = v_action.soobshchenie_id,
                   ozhidaetsya_otvet = true,
                   t0 = v_confirm_time,
                   pokolenie_ozhidaniya = v_new_generation,
                   vremya_obnovleniya = clock_timestamp()
             WHERE d_wait.id = v_dialog.id;

            INSERT INTO qbit_bot_pervichnogo_obrascheniya.napominaniya (
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

            UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_close
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

            UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_close
               SET status = 'otmeneno',
                   prichina = 'dialog_zavershen',
                   vremya_obnovleniya = clock_timestamp()
             WHERE n_close.dialog_id = v_dialog.id
               AND n_close.status IN ('zaplanirovano', 'v_rabote');

            INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
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
            UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_plain
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
              FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
             WHERE d.id = v_dialog.id;
        END IF;

    END IF;

    -- Every actually confirmed client-facing bot/system message is mirrored,
    -- including reminders. The mirror event records whether business effects
    -- were still current when confirmation was persisted.
    IF v_action.soobshchenie_id IS NOT NULL
       AND v_action.istochnik <> 'menedzher' THEN
        SELECT t.sluzhebnyy_chat_id, t.message_thread_id
          INTO v_topic_chat, v_topic_thread
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
         WHERE t.dialog_id = v_dialog.id;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
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

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(jsonb) IS
'DB-03D2 upgrade: fenced result для bot/system/manager actions; confirmed external fact сохраняется при in-flight state change; manager retry требует текущего human owner/current manager/version; manager message не зеркалируется обратно как otvet_bota.';


-- ===========================================================================
-- 3. ATOMIC TAKE
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(p_dannye jsonb)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    menedzher_id uuid,
    vladelec text,
    status_dialoga text,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_event_id uuid;
    v_dialog_id uuid;
    v_user text;
    v_expected bigint;
    v_event record;
    v_manager record;
    v_dialog record;
    v_new_version bigint;
    v_new_generation bigint;
    v_existing_take record;
BEGIN
    v_operation:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_event_id:=NULLIF(p_dannye->>'sobytie_id','')::uuid;
    v_dialog_id:=NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_user:=NULLIF(btrim(p_dannye->>'telegram_user_id'),'');
    v_expected:=NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga','')::bigint;

    IF v_operation IS NULL OR v_event_id IS NULL OR v_dialog_id IS NULL
       OR v_user IS NULL OR v_expected IS NULL OR v_expected<1 THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/service event/dialog/manager Telegram ID/expected version.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT e.* INTO v_event
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
     WHERE e.id=v_event_id AND e.istochnik='telegram_service'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'sluzhebnoe_sobytie_ne_naydeno'::text,
            'Take требует предварительно зарегистрированный service event.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF v_event.tip_sobytiya<>'callback_take' THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nevernyy_tip_sluzhebnogo_sobytiya'::text,
            'Для Take нужен зарегистрированный callback_take.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT z.* INTO v_existing_take
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS z
     WHERE z.klyuch_idempotentnosti='zabran_service:'||v_event_id::text;

    IF FOUND THEN
        SELECT d.* INTO v_dialog
          FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
         WHERE d.id=v_existing_take.dialog_id;

        RETURN QUERY SELECT
            v_operation,'dublikat'::text,NULL::text,
            'Этот callback Take уже применён.'::text,NULL::timestamptz,
            v_existing_take.dialog_id,
            NULLIF(v_existing_take.payload->>'menedzher_id','')::uuid,
            v_dialog.vladelec,v_dialog.status,v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    SELECT m.* INTO v_manager
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.telegram_user_id=v_user
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неизвестен.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF NOT v_manager.aktiven OR NOT v_manager.mozhet_zabirat THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неактивен или не имеет права Take.'::text,
            NULL::timestamptz,v_dialog_id,v_manager.id,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'dialog_ne_nayden'::text,
            'Dialog не найден.'::text,NULL::timestamptz,
            v_dialog_id,v_manager.id,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operation,'konflikt'::text,'stale_dialog_version'::text,
            'Dialog изменился до Take.'::text,NULL::timestamptz,
            v_dialog.id,v_manager.id,v_dialog.vladelec,v_dialog.status,
            v_dialog.versiya_dialoga,v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_dialog.status='zavershen' THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'dialog_zavershen'::text,
            'Завершённый dialog нельзя забрать.'::text,NULL::timestamptz,
            v_dialog.id,v_manager.id,v_dialog.vladelec,v_dialog.status,
            v_dialog.versiya_dialoga,v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_dialog.vladelec='chelovek' THEN
        RETURN QUERY SELECT
            v_operation,
            CASE WHEN v_dialog.tekushchiy_menedzher_id=v_manager.id THEN 'dublikat' ELSE 'konflikt' END::text,
            CASE WHEN v_dialog.tekushchiy_menedzher_id=v_manager.id THEN NULL ELSE 'dialog_uzhe_zanyat' END::text,
            CASE WHEN v_dialog.tekushchiy_menedzher_id=v_manager.id
                THEN 'Dialog уже принадлежит этому менеджеру.'
                ELSE 'Dialog уже забрал другой менеджер.'
            END::text,
            NULL::timestamptz,v_dialog.id,v_manager.id,v_dialog.vladelec,
            v_dialog.status,v_dialog.versiya_dialoga,v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    -- Internal processing can be safely canceled. External actions already v_rabote
    -- are NOT erased: their later confirmed/unknown/error fact must still persist.
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS j
       SET status='otmeneno',
           vladelec_arendy=NULL,
           arenda_do=NULL,
           kod_oshibki='operator_take',
           opisanie_oshibki='Dialog передан человеку.',
           vremya_obnovleniya=clock_timestamp()
     WHERE j.dialog_id=v_dialog.id
       AND j.status IN ('ozhidaet','povtor','v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
       SET status='otmeneno',
           prichina='operator_take',
           vremya_obnovleniya=clock_timestamp()
     WHERE n.dialog_id=v_dialog.id
       AND n.status IN ('zaplanirovano','v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
       SET status_otpravki='otmeneno'
     WHERE m.id IN (
        SELECT a.soobshchenie_id
          FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
         WHERE a.dialog_id=v_dialog.id
           AND a.istochnik IN ('bot','sistema')
           AND a.status IN ('zaplanirovano','povtor')
           AND a.soobshchenie_id IS NOT NULL
     );

    UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
       SET status='otmeneno',
           vladelec_arendy=NULL,
           arenda_do=NULL,
           kod_oshibki='operator_take',
           opisanie_oshibki='Не начатая bot/system отправка отменена после Take.',
           vremya_obnovleniya=clock_timestamp()
     WHERE a.dialog_id=v_dialog.id
       AND a.istochnik IN ('bot','sistema')
       AND a.status IN ('zaplanirovano','povtor');

    v_new_version:=v_dialog.versiya_dialoga+1;
    v_new_generation:=v_dialog.pokolenie_ozhidaniya+1;

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
       SET status='peredan_cheloveku',
           vladelec='chelovek',
           tekushchiy_menedzher_id=v_manager.id,
           ozhidaetsya_otvet=false,
           t0=NULL,
           pokolenie_ozhidaniya=v_new_generation,
           versiya_dialoga=v_new_version,
           vremya_obnovleniya=clock_timestamp()
     WHERE d.id=v_dialog.id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        dialog_id,polzovatel_id,tip_sobytiya,vremya_sobytiya,
        prichina,istochnik,trassirovka_id
    ) VALUES (
        v_dialog.id,v_dialog.polzovatel_id,'zabran_operatorom',clock_timestamp(),
        'telegram_take','sluzhebnyy_telegram',v_event_id::text
    );

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
        dialog_id,tip_sobytiya,klyuch_idempotentnosti,prioritet,
        cel_chat_id,cel_thread_id,cel_menedzher_id,tekst,payload,status
    )
    SELECT
        v_dialog.id,'zabran','zabran_service:'||v_event_id::text,95,
        t.sluzhebnyy_chat_id,t.message_thread_id,v_manager.id,
        'Диалог забран менеджером.',
        jsonb_build_object(
            'menedzher_id',v_manager.id,
            'telegram_user_id',v_manager.telegram_user_id,
            'versiya_dialoga',v_new_version
        ),
        'zaplanirovano'
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id=v_dialog.id
    ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
        dialog_id,tip_sobytiya,klyuch_idempotentnosti,prioritet,
        cel_chat_id,cel_thread_id,payload,status
    )
    SELECT
        v_dialog.id,'obnovit_kartochku',
        'kartochka:'||v_dialog.id::text||':owner:'||v_new_version::text,90,
        t.sluzhebnyy_chat_id,t.message_thread_id,
        jsonb_build_object('vladelec','chelovek','menedzher_id',v_manager.id,'versiya_dialoga',v_new_version),
        'zaplanirovano'
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id=v_dialog.id
    ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
       SET status='obrabotano'
     WHERE e.id=v_event_id;

    RETURN QUERY SELECT
        v_operation,'uspeshno'::text,NULL::text,
        'Take применён атомарно; bot wait/reminders/internal jobs и не начатые bot actions отменены.'::text,
        NULL::timestamptz,v_dialog.id,v_manager.id,'chelovek'::text,
        'peredan_cheloveku'::text,v_new_version,v_new_generation;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb) IS
'DB-03D2: atomic first-commit-wins bot->human Take by allowed manager and expected dialog version; cancels bot wait/reminders/internal jobs and only not-yet-claimed bot/system outgoing actions, preserving in-flight external facts.';

-- ===========================================================================
-- 4. EXPLICIT RETURN, NO AUTO CLIENT MESSAGE
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(p_dannye jsonb)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    menedzher_id uuid,
    vladelec text,
    status_dialoga text,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_event_id uuid;
    v_dialog_id uuid;
    v_user text;
    v_expected bigint;
    v_event record;
    v_manager record;
    v_dialog record;
    v_new_version bigint;
    v_new_generation bigint;
    v_existing_return record;
BEGIN
    v_operation:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_event_id:=NULLIF(p_dannye->>'sobytie_id','')::uuid;
    v_dialog_id:=NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_user:=NULLIF(btrim(p_dannye->>'telegram_user_id'),'');
    v_expected:=NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga','')::bigint;

    IF v_operation IS NULL OR v_event_id IS NULL OR v_dialog_id IS NULL
       OR v_user IS NULL OR v_expected IS NULL OR v_expected<1 THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/service event/dialog/manager Telegram ID/expected version.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT e.* INTO v_event
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
     WHERE e.id=v_event_id AND e.istochnik='telegram_service'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'sluzhebnoe_sobytie_ne_naydeno'::text,
            'Return требует зарегистрированный service event.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF v_event.tip_sobytiya<>'callback_return' THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nevernyy_tip_sluzhebnogo_sobytiya'::text,
            'Для Return нужен зарегистрированный callback_return.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT z.* INTO v_existing_return
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS z
     WHERE z.klyuch_idempotentnosti='vozvrashchen_service:'||v_event_id::text;

    IF FOUND THEN
        SELECT d.* INTO v_dialog FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
         WHERE d.id=v_existing_return.dialog_id;
        RETURN QUERY SELECT
            v_operation,'dublikat'::text,NULL::text,
            'Этот callback Return уже применён.'::text,NULL::timestamptz,
            v_existing_return.dialog_id,
            NULLIF(v_existing_return.payload->>'menedzher_id','')::uuid,
            v_dialog.vladelec,v_dialog.status,v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    SELECT m.* INTO v_manager
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.telegram_user_id=v_user
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неизвестен.'::text,
            NULL::timestamptz,v_dialog_id,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF NOT v_manager.aktiven OR NOT v_manager.mozhet_vozvrashchat THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неактивен или не имеет права Return.'::text,
            NULL::timestamptz,v_dialog_id,v_manager.id,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'dialog_ne_nayden'::text,
            'Dialog не найден.'::text,NULL::timestamptz,
            v_dialog_id,v_manager.id,NULL::text,NULL::text,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    IF v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operation,'konflikt'::text,'stale_dialog_version'::text,
            'Dialog изменился до Return.'::text,NULL::timestamptz,
            v_dialog.id,v_manager.id,v_dialog.vladelec,v_dialog.status,
            v_dialog.versiya_dialoga,v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_dialog.vladelec<>'chelovek'
       OR v_dialog.status<>'peredan_cheloveku'
       OR v_dialog.tekushchiy_menedzher_id IS DISTINCT FROM v_manager.id THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'ne_tekushchiy_menedzher'::text,
            'Return разрешён только текущему менеджеру dialog.'::text,
            NULL::timestamptz,v_dialog.id,v_manager.id,v_dialog.vladelec,
            v_dialog.status,v_dialog.versiya_dialoga,v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    v_new_version:=v_dialog.versiya_dialoga+1;
    v_new_generation:=v_dialog.pokolenie_ozhidaniya+1;

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
       SET status='aktivnyy',
           vladelec='bot',
           tekushchiy_menedzher_id=NULL,
           ozhidaetsya_otvet=false,
           t0=NULL,
           pokolenie_ozhidaniya=v_new_generation,
           versiya_dialoga=v_new_version,
           vremya_obnovleniya=clock_timestamp()
     WHERE d.id=v_dialog.id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        dialog_id,polzovatel_id,tip_sobytiya,vremya_sobytiya,
        prichina,istochnik,trassirovka_id
    ) VALUES (
        v_dialog.id,v_dialog.polzovatel_id,'vozvrashchen_botu',clock_timestamp(),
        'telegram_return','sluzhebnyy_telegram',v_event_id::text
    );

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
        dialog_id,tip_sobytiya,klyuch_idempotentnosti,prioritet,
        cel_chat_id,cel_thread_id,cel_menedzher_id,tekst,payload,status
    )
    SELECT
        v_dialog.id,'vozvrashchen','vozvrashchen_service:'||v_event_id::text,95,
        t.sluzhebnyy_chat_id,t.message_thread_id,v_manager.id,
        'Диалог возвращён боту.',
        jsonb_build_object(
            'menedzher_id',v_manager.id,
            'telegram_user_id',v_manager.telegram_user_id,
            'versiya_dialoga',v_new_version
        ),
        'zaplanirovano'
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id=v_dialog.id
    ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
        dialog_id,tip_sobytiya,klyuch_idempotentnosti,prioritet,
        cel_chat_id,cel_thread_id,payload,status
    )
    SELECT
        v_dialog.id,'obnovit_kartochku',
        'kartochka:'||v_dialog.id::text||':owner:'||v_new_version::text,90,
        t.sluzhebnyy_chat_id,t.message_thread_id,
        jsonb_build_object('vladelec','bot','versiya_dialoga',v_new_version),
        'zaplanirovano'
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id=v_dialog.id
    ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
       SET status='obrabotano'
     WHERE e.id=v_event_id;

    RETURN QUERY SELECT
        v_operation,'uspeshno'::text,NULL::text,
        'Dialog возвращён боту без создания клиентского исходящего действия.'::text,
        NULL::timestamptz,v_dialog.id,v_manager.id,'bot'::text,'aktivnyy'::text,
        v_new_version,v_new_generation;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(jsonb) IS
'DB-03D2: explicit current-manager human->bot Return by expected version; increments version/generation, clears wait/manager and creates only operator events, never an automatic client message.';

-- ===========================================================================
-- 5. CURRENT MANAGER CREATES ORDINARY MANAGER OUTGOING INTENT
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(p_dannye jsonb)
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
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_event_id uuid;
    v_user text;
    v_service_chat text;
    v_service_thread text;
    v_text text;
    v_text_safe text;
    v_expected bigint;
    v_event record;
    v_manager record;
    v_topic record;
    v_dialog record;
    v_identity record;
    v_existing record;
    v_existing_message record;
    v_message_id uuid;
    v_action_id uuid;
    v_key text;
BEGIN
    v_operation:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_event_id:=NULLIF(p_dannye->>'sobytie_id','')::uuid;
    v_user:=NULLIF(btrim(p_dannye->>'telegram_user_id'),'');
    v_service_chat:=NULLIF(btrim(p_dannye->>'sluzhebnyy_chat_id'),'');
    v_service_thread:=NULLIF(btrim(p_dannye->>'message_thread_id'),'');
    v_text:=p_dannye->>'tekst';
    v_text_safe:=COALESCE(p_dannye->>'tekst_obezlichennyy',v_text);
    v_expected:=NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga','')::bigint;
    v_key:='manager_service:'||COALESCE(v_event_id::text,'');

    IF v_operation IS NULL OR v_event_id IS NULL OR v_user IS NULL
       OR v_service_chat IS NULL OR v_service_thread IS NULL
       OR v_text IS NULL OR btrim(v_text)=''
       OR v_expected IS NULL OR v_expected<1 THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/service event/manager/service chat/thread/text/expected version.'::text,
            NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    SELECT e.* INTO v_event
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
     WHERE e.id=v_event_id AND e.istochnik='telegram_service'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'sluzhebnoe_sobytie_ne_naydeno'::text,
            'Manual outgoing требует durable service event.'::text,
            NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    IF v_event.tip_sobytiya<>'operator_message' THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nevernyy_tip_sluzhebnogo_sobytiya'::text,
            'Для ручного исходящего нужен зарегистрированный operator_message.'::text,
            NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    SELECT a.* INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora=v_key
     FOR UPDATE;

    IF FOUND THEN
        SELECT m.* INTO v_existing_message
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
         WHERE m.id=v_existing.soobshchenie_id;

        IF v_existing.istochnik<>'menedzher'
           OR v_existing_message.tekst_ishodnyy IS DISTINCT FROM v_text
           OR v_existing.payload->>'telegram_user_id' IS DISTINCT FROM v_user
           OR v_existing.payload->>'sluzhebnyy_chat_id' IS DISTINCT FROM v_service_chat
           OR v_existing.payload->>'message_thread_id' IS DISTINCT FROM v_service_thread THEN
            RETURN QUERY SELECT
                v_operation,'konflikt'::text,'service_event_reused'::text,
                'Тот же service event уже связан с другим manual outgoing содержимым.'::text,
                NULL::timestamptz,v_existing.id,v_existing.dialog_id,
                v_existing.soobshchenie_id,v_existing.status,v_existing.versiya_dialoga;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation,'dublikat'::text,NULL::text,
            'Manual outgoing intent уже существует.'::text,NULL::timestamptz,
            v_existing.id,v_existing.dialog_id,v_existing.soobshchenie_id,
            v_existing.status,v_existing.versiya_dialoga;
        RETURN;
    END IF;

    SELECT m.* INTO v_manager
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.telegram_user_id=v_user
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неизвестен.'::text,NULL::timestamptz,
            NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    IF NOT v_manager.aktiven THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'menedzher_ne_razreshen'::text,
            'Manager неактивен.'::text,NULL::timestamptz,
            NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    SELECT t.* INTO v_topic
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.sluzhebnyy_chat_id=v_service_chat
       AND t.message_thread_id=v_service_thread
       AND t.status='gotova'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'tema_ne_naydena'::text,
            'Service chat/thread не соответствует confirmed operator topic.'::text,
            NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::bigint;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_topic.dialog_id
     FOR UPDATE;

    IF v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operation,'konflikt'::text,'stale_dialog_version'::text,
            'Dialog изменился до manual outgoing.'::text,NULL::timestamptz,
            NULL::uuid,v_dialog.id,NULL::uuid,NULL::text,v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.vladelec<>'chelovek'
       OR v_dialog.status<>'peredan_cheloveku'
       OR v_dialog.tekushchiy_menedzher_id IS DISTINCT FROM v_manager.id THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'ne_tekushchiy_menedzher'::text,
            'Только текущий manager human-owned dialog может писать клиенту.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog.id,NULL::uuid,NULL::text,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    SELECT i.* INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id=v_dialog.identifikator_kanala_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dialog % has missing channel identity',v_dialog.id;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS new_message (
        dialog_id,napravlenie,avtor,vid,tekst_ishodnyy,tekst_obezlichennyy,
        vremya_priema,status_otpravki,ozhidaetsya_otvet,trassirovka_id
    ) VALUES (
        v_dialog.id,'ishodyashchee','menedzher','text',v_text,v_text_safe,
        clock_timestamp(),'zaplanirovano',false,v_event_id::text
    )
    RETURNING new_message.id INTO v_message_id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS new_action (
        dialog_id,soobshchenie_id,vid_deystviya,istochnik,klyuch_povtora,
        kanal,akkaunt_kanala_id,vneshniy_dialog_id,payload,status,
        sleduyushchiy_zapusk,versiya_dialoga
    ) VALUES (
        v_dialog.id,v_message_id,'soobshchenie','menedzher',v_key,
        v_identity.kanal,v_identity.akkaunt_kanala_id,v_identity.vneshniy_dialog_id,
        jsonb_build_object(
            'menedzher_id',v_manager.id,
            'telegram_user_id',v_manager.telegram_user_id,
            'service_event_id',v_event_id,
            'sluzhebnyy_chat_id',v_service_chat,
            'message_thread_id',v_service_thread,
            'iniciativnoe',false,
            'effekty_posle_podtverzhdeniya',jsonb_build_object()
        ),
        'zaplanirovano',clock_timestamp(),v_dialog.versiya_dialoga
    )
    RETURNING new_action.id INTO v_action_id;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
       SET status='obrabotano'
     WHERE e.id=v_event_id;

    RETURN QUERY SELECT
        v_operation,'uspeshno'::text,NULL::text,
        'Manual manager message сохранено как ordinary outgoing intent до client Telegram API.'::text,
        NULL::timestamptz,v_action_id,v_dialog.id,v_message_id,
        'zaplanirovano'::text,v_dialog.versiya_dialoga;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(jsonb) IS
'DB-03D2: service message in confirmed topic resolves dialog, validates exact current manager + version, then creates manager-authored logical message and ordinary outgoing action with trusted client channel derived from DB; idempotent by service event.';

-- ===========================================================================
-- 6. BOT CREATES PRIVATE ALERT EVENT, NEVER ACCEPTS CHAT_ID
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(p_dannye jsonb)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    sobytie_zerkala_id uuid,
    dialog_id uuid,
    menedzher_id uuid,
    status_sobytiya text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_key text;
    v_dialog_id uuid;
    v_manager_id uuid;
    v_reason text;
    v_text text;
    v_dialog record;
    v_manager record;
    v_existing record;
    v_event_id uuid;
BEGIN
    v_operation:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_key:=NULLIF(btrim(p_dannye->>'klyuch_povtora'),'');
    v_dialog_id:=NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_manager_id:=NULLIF(p_dannye->>'menedzher_id','')::uuid;
    v_reason:=NULLIF(btrim(p_dannye->>'prichina'),'');
    v_text:=COALESCE(NULLIF(p_dannye->>'tekst',''),'Требуется внимание менеджера.');

    IF v_operation IS NULL OR v_key IS NULL OR v_dialog_id IS NULL
       OR v_manager_id IS NULL OR v_reason IS NULL THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/stable key/dialog/manager/reason; chat_id не принимается.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,v_manager_id,NULL::text;
        RETURN;
    END IF;

    SELECT z.* INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS z
     WHERE z.klyuch_idempotentnosti='private:'||v_key
     FOR UPDATE;

    IF FOUND THEN
        IF v_existing.dialog_id IS DISTINCT FROM v_dialog_id
           OR v_existing.cel_menedzher_id IS DISTINCT FROM v_manager_id
           OR v_existing.payload->>'prichina' IS DISTINCT FROM v_reason
           OR v_existing.tekst IS DISTINCT FROM v_text THEN
            RETURN QUERY SELECT
                v_operation,'konflikt'::text,'private_key_reused'::text,
                'Stable private-alert key уже связан с другим содержимым.'::text,
                NULL::timestamptz,v_existing.id,v_existing.dialog_id,
                v_existing.cel_menedzher_id,v_existing.status;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation,'dublikat'::text,NULL::text,
            'Private alert уже создан.'::text,NULL::timestamptz,
            v_existing.id,v_existing.dialog_id,v_existing.cel_menedzher_id,
            v_existing.status;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_dialog_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'dialog_ne_aktiven'::text,
            'Dialog для private alert не найден.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,v_manager_id,NULL::text;
        RETURN;
    END IF;

    IF v_dialog.status='zavershen' THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'dialog_ne_aktiven'::text,
            'Private alert не создаётся для завершённого dialog.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,v_manager_id,NULL::text;
        RETURN;
    END IF;

    SELECT m.* INTO v_manager
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.id=v_manager_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'lichnoe_uvedomlenie_ne_razresheno'::text,
            'Manager для private alert не найден.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,v_manager_id,NULL::text;
        RETURN;
    END IF;

    IF NOT v_manager.aktiven
       OR NOT v_manager.lichnye_uvedomleniya
       OR NOT v_manager.private_chat_podtverzhden
       OR v_manager.private_chat_id IS NULL THEN
        RETURN QUERY SELECT
            v_operation,'otkaz'::text,'lichnoe_uvedomlenie_ne_razresheno'::text,
            'Manager/private chat/notification setting не разрешает private alert.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,v_manager_id,NULL::text;
        RETURN;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS new_event (
        dialog_id,tip_sobytiya,klyuch_idempotentnosti,prioritet,
        cel_menedzher_id,tekst,payload,status
    ) VALUES (
        v_dialog_id,'lichnoe_uvedomlenie','private:'||v_key,100,
        v_manager_id,v_text,
        jsonb_build_object(
            'prichina',v_reason,
            'menedzher_id',v_manager_id,
            'versiya_dialoga',v_dialog.versiya_dialoga
        ),
        'zaplanirovano'
    )
    RETURNING new_event.id INTO v_event_id;

    RETURN QUERY SELECT
        v_operation,'uspeshno'::text,NULL::text,
        'Private alert intent создан без передачи произвольного chat_id.'::text,
        NULL::timestamptz,v_event_id,v_dialog_id,v_manager_id,'zaplanirovano'::text;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb) IS
'DB-03D2: bot creates stable private notification event only for active manager with confirmed private chat and notifications enabled; input never accepts target chat_id, D1 claim resolves it from manager table.';

-- ===========================================================================
-- 7. PRIVILEGES + SECURITY ASSERTIONS
-- ===========================================================================

REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb) TO qbit_test_bot;

DO $db03d2$
DECLARE
    v_fn record;
BEGIN
    FOR v_fn IN
        SELECT p.oid,p.proname,p.prosecdef,p.proconfig,r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
          JOIN pg_catalog.pg_roles AS r ON r.oid=p.proowner
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego'
           )
    LOOP
        IF NOT v_fn.prosecdef
           OR v_fn.owner_name<>'qbit_test_owner'
           OR NOT (
                COALESCE(v_fn.proconfig,ARRAY[]::text[])
                @> ARRAY['search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya']::text[]
           ) THEN
            RAISE EXCEPTION
                'Unsafe DB-03D2 function metadata: %, owner=%, config=%',
                v_fn.proname,v_fn.owner_name,v_fn.proconfig;
        END IF;

        IF EXISTS (
            SELECT 1 FROM pg_catalog.aclexplode(
                COALESCE(
                    (SELECT p2.proacl FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=v_fn.oid),
                    pg_catalog.acldefault(
                        'f',(SELECT p2.proowner FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=v_fn.oid)
                    )
                )
            ) AS a
             WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
        ) THEN
            RAISE EXCEPTION 'PUBLIC unexpectedly has EXECUTE on %',v_fn.proname;
        END IF;
    END LOOP;

    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb)','EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(jsonb)','EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(jsonb)','EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb)','EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Required DB-03D2 EXECUTE grant missing';
    END IF;

    IF pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb)','EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb)','EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Cross-role DB-03D2 privilege unexpectedly granted';
    END IF;
END
$db03d2$;

-- ===========================================================================
-- 8. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03d2_probe;

DO $db03d2$
DECLARE
    rin record;
    topic_claim record;
    topic_ok record;

    wait_create record;
    wait_claim record;
    wait_confirm record;
    pending_bot record;

    take_event1 record;
    take_event2 record;
    take1 record;
    take2 record;

    manual_event1 record;
    manual_event2 record;
    manual1 record;
    manual_dup record;
    manual_foreign record;
    manager_claim record;
    manager_confirm record;

    return_event_bad record;
    return_event_ok record;
    return_bad record;
    return_ok record;

    private_new record;
    private_dup record;
    private_claim record;
    private_done record;

    v_manager1 uuid;
    v_manager2 uuid;
    v_version_before_take bigint;
    v_generation_before_take bigint;
    v_version_human bigint;
    v_generation_human bigint;
    v_actions_before_return bigint;
    v_actions_after_return bigint;
BEGIN
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m (
        telegram_user_id,private_chat_id,private_chat_podtverzhden,
        vremya_podtverzhdeniya,otobrazhaemoe_imya,aktiven,
        mozhet_zabirat,mozhet_vozvrashchat,lichnye_uvedomleniya,prioritet_naznacheniya
    ) VALUES (
        'db03d2_manager_1','db03d2_private_1',true,clock_timestamp(),
        'Менеджер D2-1',true,true,true,true,10
    ) RETURNING m.id INTO v_manager1;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m (
        telegram_user_id,private_chat_id,private_chat_podtverzhden,
        vremya_podtverzhdeniya,otobrazhaemoe_imya,aktiven,
        mozhet_zabirat,mozhet_vozvrashchat,lichnye_uvedomleniya,prioritet_naznacheniya
    ) VALUES (
        'db03d2_manager_2','db03d2_private_2',true,clock_timestamp(),
        'Менеджер D2-2',true,true,true,true,20
    ) RETURNING m.id INTO v_manager2;

    SELECT * INTO rin
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03d2_client_ingress',
            'klyuch_idempotentnosti','db03d2_client_idem',
            'hash_soderzhaniya','db03d2_client_hash',
            'kanal','telegram',
            'akkaunt_kanala_id','db03d2_client_bot',
            'vneshnee_sobytie_id','db03d2_client_event',
            'vneshniy_polzovatel_id','db03d2_client_user',
            'vneshniy_dialog_id','db03d2_client_chat',
            'vneshnee_soobshchenie_id','db03d2_client_msg',
            'tip_sobytiya','message',
            'tip_soobshcheniya','text',
            'tekst_ishodnyy','Хочу поговорить с менеджером',
            'vremya_priema',clock_timestamp(),
            'versiya_workflow','db03d2_probe',
            'versiya_prompta','db03d2_probe',
            'sluzhebnyy_chat_id','db03d2_service_group',
            'bezopasnaya_podpis_klienta','Клиент D2'
        )
      );

    SELECT * INTO topic_claim
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_sozdanie_operator_temy(
        jsonb_build_object(
            'operaciya_id','db03d2_topic_create',
            'worker_id','db03d2_topic_worker',
            'dialog_id',rin.dialog_id,
            'arenda_sekund',120
        )
      );

    SELECT * INTO topic_ok
      FROM qbit_bot_pervichnogo_obrascheniya.podtverdit_operator_temu(
        jsonb_build_object(
            'operaciya_sozdaniya_id',topic_claim.operaciya_sozdaniya_id,
            'dialog_id',rin.dialog_id,
            'worker_id','db03d2_topic_worker',
            'nomer_vladeniya',topic_claim.nomer_vladeniya,
            'message_thread_id','db03d2_thread'
        )
      );

    IF topic_claim.rezultat<>'uspeshno' OR topic_ok.rezultat<>'uspeshno' THEN
        RAISE EXCEPTION 'DB-03D2 setup topic failed: claim=%, confirm=%',
            row_to_json(topic_claim),row_to_json(topic_ok);
    END IF;

    -- Confirm one waiting bot response so Take must cancel wait/reminders.
    SELECT * INTO wait_create
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03d2_wait_create',
            'klyuch_povtora','db03d2_wait_action',
            'dialog_id',rin.dialog_id,
            'ozhidaemaya_versiya_dialoga',rin.versiya_dialoga,
            'kanal','telegram',
            'akkaunt_kanala_id','db03d2_client_bot',
            'vneshniy_dialog_id','db03d2_client_chat',
            'tekst_ishodnyy','Подскажите детали',
            'tekst_obezlichennyy','Подскажите детали',
            'ozhidaetsya_otvet',true,
            'effekty_posle_podtverzhdeniya',jsonb_build_object(
                'napominanie_1_sekund',10800,
                'napominanie_2_sekund',43200,
                'okno_napominaniya_sekund',3600,
                'poterya_posle_sekund',86400
            )
        )
      );

    SELECT * INTO wait_claim
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03d2_wait_claim',
            'worker_id','db03d2_client_worker',
            'arenda_sekund',120
        )
      );

    SELECT * INTO wait_confirm
      FROM qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03d2_wait_confirm',
            'deystvie_id',wait_claim.deystvie_id,
            'worker_id','db03d2_client_worker',
            'nomer_vladeniya',wait_claim.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03d2_wait_external',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    SELECT d.versiya_dialoga,d.pokolenie_ozhidaniya
      INTO v_version_before_take,v_generation_before_take
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d WHERE d.id=rin.dialog_id;

    SELECT * INTO pending_bot
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03d2_pending_create',
            'klyuch_povtora','db03d2_pending_bot',
            'dialog_id',rin.dialog_id,
            'ozhidaemaya_versiya_dialoga',v_version_before_take,
            'kanal','telegram',
            'akkaunt_kanala_id','db03d2_client_bot',
            'vneshniy_dialog_id','db03d2_client_chat',
            'tekst_ishodnyy','Черновой ответ, который Take должен отменить',
            'tekst_obezlichennyy','Черновой ответ, который Take должен отменить'
        )
      );

    SELECT * INTO take_event1
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_take_event_1',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_take_update_1',
            'tip_sobytiya','callback_take',
            'klyuch_idempotentnosti','db03d2_take_idem_1',
            'hash_soderzhaniya','db03d2_take_hash_1',
            'payload_ishodnyy',jsonb_build_object('dialog_id',rin.dialog_id,'telegram_user_id','db03d2_manager_1'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO take_event2
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_take_event_2',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_take_update_2',
            'tip_sobytiya','callback_take',
            'klyuch_idempotentnosti','db03d2_take_idem_2',
            'hash_soderzhaniya','db03d2_take_hash_2',
            'payload_ishodnyy',jsonb_build_object('dialog_id',rin.dialog_id,'telegram_user_id','db03d2_manager_2'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO take1
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(
        jsonb_build_object(
            'operaciya_id','db03d2_take_1',
            'sobytie_id',take_event1.sobytie_id,
            'dialog_id',rin.dialog_id,
            'telegram_user_id','db03d2_manager_1',
            'ozhidaemaya_versiya_dialoga',v_version_before_take
        )
      );

    SELECT * INTO take2
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(
        jsonb_build_object(
            'operaciya_id','db03d2_take_2',
            'sobytie_id',take_event2.sobytie_id,
            'dialog_id',rin.dialog_id,
            'telegram_user_id','db03d2_manager_2',
            'ozhidaemaya_versiya_dialoga',v_version_before_take
        )
      );

    SELECT d.versiya_dialoga,d.pokolenie_ozhidaniya
      INTO v_version_human,v_generation_human
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d WHERE d.id=rin.dialog_id;

    IF take1.rezultat<>'uspeshno'
       OR take1.menedzher_id IS DISTINCT FROM v_manager1
       OR take2.rezultat<>'konflikt'
       OR take2.kod_oshibki<>'stale_dialog_version'
       OR v_version_human<>v_version_before_take+1
       OR v_generation_human<>v_generation_before_take+1
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND (
                    d.vladelec<>'chelovek'
                    OR d.tekushchiy_menedzher_id IS DISTINCT FROM v_manager1
                    OR d.status<>'peredan_cheloveku'
                    OR d.ozhidaetsya_otvet
                    OR d.t0 IS NOT NULL
               )
       )
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
             WHERE n.dialog_id=rin.dialog_id
               AND n.status IN ('zaplanirovano','v_rabote')
       )
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS j
             WHERE j.dialog_id=rin.dialog_id
               AND j.status IN ('ozhidaet','povtor','v_rabote')
       )
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
             WHERE a.id=pending_bot.deystvie_id
               AND a.status<>'otmeneno'
       ) THEN
        RAISE EXCEPTION
            'DB-03D2 Take/first-commit-wins/cancel failed: take1=%, take2=%',
            row_to_json(take1),row_to_json(take2);
    END IF;

    -- Manual message by current manager.
    SELECT * INTO manual_event1
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_manual_event_1',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_manual_update_1',
            'tip_sobytiya','operator_message',
            'klyuch_idempotentnosti','db03d2_manual_idem_1',
            'hash_soderzhaniya','db03d2_manual_hash_1',
            'payload_ishodnyy',jsonb_build_object('message_thread_id','db03d2_thread','telegram_user_id','db03d2_manager_1'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO manual1
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(
        jsonb_build_object(
            'operaciya_id','db03d2_manual_create_1',
            'sobytie_id',manual_event1.sobytie_id,
            'telegram_user_id','db03d2_manager_1',
            'sluzhebnyy_chat_id','db03d2_service_group',
            'message_thread_id','db03d2_thread',
            'tekst','Ручной ответ менеджера',
            'tekst_obezlichennyy','Ручной ответ менеджера',
            'ozhidaemaya_versiya_dialoga',v_version_human
        )
      );

    SELECT * INTO manual_dup
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(
        jsonb_build_object(
            'operaciya_id','db03d2_manual_create_dup',
            'sobytie_id',manual_event1.sobytie_id,
            'telegram_user_id','db03d2_manager_1',
            'sluzhebnyy_chat_id','db03d2_service_group',
            'message_thread_id','db03d2_thread',
            'tekst','Ручной ответ менеджера',
            'tekst_obezlichennyy','Ручной ответ менеджера',
            'ozhidaemaya_versiya_dialoga',v_version_human
        )
      );

    SELECT * INTO manual_event2
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_manual_event_2',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_manual_update_2',
            'tip_sobytiya','operator_message',
            'klyuch_idempotentnosti','db03d2_manual_idem_2',
            'hash_soderzhaniya','db03d2_manual_hash_2',
            'payload_ishodnyy',jsonb_build_object('message_thread_id','db03d2_thread','telegram_user_id','db03d2_manager_2'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO manual_foreign
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(
        jsonb_build_object(
            'operaciya_id','db03d2_manual_foreign',
            'sobytie_id',manual_event2.sobytie_id,
            'telegram_user_id','db03d2_manager_2',
            'sluzhebnyy_chat_id','db03d2_service_group',
            'message_thread_id','db03d2_thread',
            'tekst','Чужой менеджер',
            'ozhidaemaya_versiya_dialoga',v_version_human
        )
      );

    IF manual1.rezultat<>'uspeshno'
       OR manual_dup.rezultat<>'dublikat'
       OR manual_foreign.rezultat<>'otkaz'
       OR manual_foreign.kod_oshibki<>'ne_tekushchiy_menedzher'
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
              JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m ON m.id=a.soobshchenie_id
             WHERE a.id=manual1.deystvie_id
               AND a.istochnik='menedzher'
               AND a.status='zaplanirovano'
               AND m.avtor='menedzher'
       ) THEN
        RAISE EXCEPTION
            'DB-03D2 manual current-manager/idempotency/foreign-deny failed: new=%, dup=%, foreign=%',
            row_to_json(manual1),row_to_json(manual_dup),row_to_json(manual_foreign);
    END IF;

    SELECT * INTO manager_claim
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03d2_manager_claim',
            'worker_id','db03d2_client_worker_manager',
            'arenda_sekund',120
        )
      );

    IF manager_claim.rezultat<>'uspeshno'
       OR manager_claim.deystvie_id IS DISTINCT FROM manual1.deystvie_id THEN
        RAISE EXCEPTION
            'DB-03D2 upgraded C4 claim did not return manager action: %',
            row_to_json(manager_claim);
    END IF;

    SELECT * INTO manager_confirm
      FROM qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03d2_manager_confirm',
            'deystvie_id',manager_claim.deystvie_id,
            'worker_id','db03d2_client_worker_manager',
            'nomer_vladeniya',manager_claim.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03d2_manager_external',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF manager_confirm.rezultat<>'uspeshno'
       OR manager_confirm.status_deystviya<>'podtverzhdeno'
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS z
             WHERE z.klyuch_idempotentnosti='bot_confirmed:'||manual1.soobshchenie_id::text
       )
       OR NOT EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
             WHERE m.id=manual1.soobshchenie_id
               AND m.status_otpravki='podtverzhdeno'
               AND m.vneshnee_soobshchenie_id='db03d2_manager_external'
       )
       OR NOT EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND d.poslednee_ishodyashchee_id=manual1.soobshchenie_id
       ) THEN
        RAISE EXCEPTION
            'DB-03D2 manager confirmed result/mirror suppression failed: %',
            row_to_json(manager_confirm);
    END IF;

    -- Foreign Return denied, current manager Return succeeds and creates no outgoing action.
    SELECT * INTO return_event_bad
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_return_event_bad',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_return_update_bad',
            'tip_sobytiya','callback_return',
            'klyuch_idempotentnosti','db03d2_return_idem_bad',
            'hash_soderzhaniya','db03d2_return_hash_bad',
            'payload_ishodnyy',jsonb_build_object('dialog_id',rin.dialog_id,'telegram_user_id','db03d2_manager_2'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO return_bad
      FROM qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(
        jsonb_build_object(
            'operaciya_id','db03d2_return_bad',
            'sobytie_id',return_event_bad.sobytie_id,
            'dialog_id',rin.dialog_id,
            'telegram_user_id','db03d2_manager_2',
            'ozhidaemaya_versiya_dialoga',v_version_human
        )
      );

    SELECT count(*) INTO v_actions_before_return
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.dialog_id=rin.dialog_id;

    SELECT * INTO return_event_ok
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'operaciya_id','db03d2_return_event_ok',
            'akkaunt_istochnika_id','db03d2_service_bot',
            'vneshnee_sobytie_id','db03d2_return_update_ok',
            'tip_sobytiya','callback_return',
            'klyuch_idempotentnosti','db03d2_return_idem_ok',
            'hash_soderzhaniya','db03d2_return_hash_ok',
            'payload_ishodnyy',jsonb_build_object('dialog_id',rin.dialog_id,'telegram_user_id','db03d2_manager_1'),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO return_ok
      FROM qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(
        jsonb_build_object(
            'operaciya_id','db03d2_return_ok',
            'sobytie_id',return_event_ok.sobytie_id,
            'dialog_id',rin.dialog_id,
            'telegram_user_id','db03d2_manager_1',
            'ozhidaemaya_versiya_dialoga',v_version_human
        )
      );

    SELECT count(*) INTO v_actions_after_return
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.dialog_id=rin.dialog_id;

    IF return_bad.rezultat<>'otkaz'
       OR return_bad.kod_oshibki<>'ne_tekushchiy_menedzher'
       OR return_ok.rezultat<>'uspeshno'
       OR return_ok.vladelec<>'bot'
       OR return_ok.versiya_dialoga<>v_version_human+1
       OR v_actions_after_return<>v_actions_before_return
       OR EXISTS (
            SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
             WHERE d.id=rin.dialog_id
               AND (
                    d.vladelec<>'bot'
                    OR d.tekushchiy_menedzher_id IS NOT NULL
                    OR d.status<>'aktivnyy'
                    OR d.ozhidaetsya_otvet
                    OR d.t0 IS NOT NULL
               )
       ) THEN
        RAISE EXCEPTION
            'DB-03D2 Return/current-manager/no-auto-message failed: bad=%, ok=%, actions before/after=%/%',
            row_to_json(return_bad),row_to_json(return_ok),
            v_actions_before_return,v_actions_after_return;
    END IF;

    -- Bot private alert accepts manager UUID, not chat id; D1 claim resolves exact private chat.
    SELECT * INTO private_new
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(
        jsonb_build_object(
            'operaciya_id','db03d2_private_new',
            'klyuch_povtora','db03d2_private_key',
            'dialog_id',rin.dialog_id,
            'menedzher_id',v_manager1,
            'prichina','nuzhen_chelovek',
            'tekst','Нужен менеджер'
        )
      );

    SELECT * INTO private_dup
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(
        jsonb_build_object(
            'operaciya_id','db03d2_private_dup',
            'klyuch_povtora','db03d2_private_key',
            'dialog_id',rin.dialog_id,
            'menedzher_id',v_manager1,
            'prichina','nuzhen_chelovek',
            'tekst','Нужен менеджер'
        )
      );

    SELECT * INTO private_claim
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d2_private_claim',
            'worker_id','db03d2_service_worker',
            'sobytie_zerkala_id',private_new.sobytie_zerkala_id,
            'arenda_sekund',120
        )
      );

    SELECT * INTO private_done
      FROM qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d2_private_done',
            'sobytie_zerkala_id',private_claim.sobytie_zerkala_id,
            'worker_id','db03d2_service_worker',
            'nomer_vladeniya',private_claim.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_message_id','db03d2_private_external',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF private_new.rezultat<>'uspeshno'
       OR private_dup.rezultat<>'dublikat'
       OR private_claim.rezultat<>'uspeshno'
       OR private_claim.cel_chat_id<>'db03d2_private_1'
       OR private_claim.cel_menedzher_id IS DISTINCT FROM v_manager1
       OR private_done.rezultat<>'uspeshno' THEN
        RAISE EXCEPTION
            'DB-03D2 private alert/trusted target failed: new=%, dup=%, claim=%, done=%',
            row_to_json(private_new),row_to_json(private_dup),
            row_to_json(private_claim),row_to_json(private_done);
    END IF;
END
$db03d2$;

ROLLBACK TO SAVEPOINT db03d2_probe;
RELEASE SAVEPOINT db03d2_probe;

-- ===========================================================================
-- 9. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03d2$
DECLARE
    v_table record;
BEGIN
    IF EXISTS (
        SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
         WHERE m.telegram_user_id LIKE 'db03d2_manager_%'
    )
    OR EXISTS (
        SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id='db03d2_service_bot'
    )
    OR EXISTS (
        SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id='db03d2_client_bot'
    ) THEN
        RAISE EXCEPTION 'DB-03D2 probe rows remain after rollback';
    END IF;

    FOR v_table IN
        SELECT c.oid,c.relname
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya' AND c.relkind='r'
    LOOP
        IF pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',v_table.oid,'SELECT')
        OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',v_table.oid,'INSERT')
        OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',v_table.oid,'UPDATE')
        OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',v_table.oid,'DELETE') THEN
            RAISE EXCEPTION
                'Service role unexpectedly has direct table privilege on qbit_bot_pervichnogo_obrascheniya.%',
                v_table.relname;
        END IF;
    END LOOP;

    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(jsonb)','EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    ) THEN
        RAISE EXCEPTION 'C4 privileges changed unexpectedly by CREATE OR REPLACE';
    END IF;
END
$db03d2$;

RESET ROLE;

COMMIT;

SELECT jsonb_build_object(
    'db03d2_status','applied',
    'database',current_database(),
    'schema','qbit_bot_pervichnogo_obrascheniya',
    'functions_ok',
    (
        SELECT count(*)=4
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie'
           )
           AND p.prosecdef
    ),
    'c4_manager_upgrade_ok',
    pg_catalog.pg_get_functiondef(
        'qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)'::regprocedure
    ) LIKE '%menedzher_bolshe_ne_vladelec%'
    AND pg_catalog.pg_get_functiondef(
        'qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(jsonb)'::regprocedure
    ) LIKE '%v_action.istochnik = ''menedzher''%',
    'service_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(jsonb)','EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(jsonb)','EXECUTE'
    ),
    'bot_private_alert_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb)','EXECUTE'
    ),
    'cross_role_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(jsonb)','EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(jsonb)','EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(jsonb)','EXECUTE'
    ),
    'service_raw_select_denied',
    NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind='r'
           AND pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'SELECT')
    ),
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id='db03d2_service_bot'
    ),
    'result',
    'DB-03D2 SQL APPLIED: atomic Take/Return/manual manager outgoing/C4 manager claim-result/private alert verified; Return creates no client auto-message; service raw SELECT denied; probe data removed; production untouched.'
) AS db03d2_result;
