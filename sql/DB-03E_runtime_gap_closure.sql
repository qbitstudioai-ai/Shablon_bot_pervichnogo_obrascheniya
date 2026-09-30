-- DB-03E v0.11: runtime gap closure for n8n
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Date: 2026-09-28
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17+
--   schema: qbit_bot_pervichnogo_obrascheniya ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01..DB-03D2 and DB-SCHEMA-01F already applied/verified.
--
-- ADDS 7 NARROW SECURITY DEFINER FUNCTIONS
--   poluchit_soderzhimoe_zadaniya(jsonb)
--   poluchit_sostoyanie_operatora(jsonb)
--   sozdat_preduprezhdenie_tematiky(jsonb)
--   poluchit_soderzhimoe_ishodyashchego(jsonb)
--   ustanovit_zapret_iniciativy(jsonb)
--   zaprosit_cheloveka(jsonb)
--   obrabotat_sleduyushchee_napominanie(jsonb)
-- UPGRADES
--   zabrat_ishodyashchee_deystvie(jsonb): exact blocking thematic warning may still be claimed.
--
-- IMPORTANT
--   * Preparation only until Pavel explicitly authorizes application to Supabase.
--   * Run the WHOLE file as one query when application is authorized.
--   * Production schema qbit is not touched.
--   * Runtime roles still receive no direct table DML.
--   * Existing in-flight external attempts are not erased.
--   * Built-in behavior probes are rolled back to SAVEPOINT.
--   * On any error before COMMIT, the whole migration is rolled back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03e$
DECLARE
    v_required text;
    v_target text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03E requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03E must run from trusted postgres session. session_user=%',
            session_user;
    END IF;

    IF NOT pg_catalog.pg_has_role(
        session_user,
        'qbit_test_owner',
        'SET'
    ) THEN
        RAISE EXCEPTION
            'session_user % cannot SET ROLE qbit_test_owner',
            session_user;
    END IF;

    IF (
        SELECT r.rolname
          FROM pg_catalog.pg_namespace AS n
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = n.nspowner
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
    ) IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION
            'qbit_bot_pervichnogo_obrascheniya is not owned by qbit_test_owner';
    END IF;

    FOREACH v_required IN ARRAY ARRAY[
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'sobytiya_integraciy',
        'zadaniya_obrabotki',
        'ishodyashchie_deystviya',
        'napominaniya',
        'operator_telegram_temy',
        'sobytiya_zerkala_operatora',
        'sobytiya_dialogov'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format(
                'qbit_bot_pervichnogo_obrascheniya.%I',
                v_required
            )
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required table qbit_bot_pervichnogo_obrascheniya.% is missing',
                v_required;
        END IF;
    END LOOP;

    FOREACH v_required IN ARRAY ARRAY[
        'zaregistrirovat_vhod_klienta',
        'zabrat_zadanie_obrabotki',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'zabrat_sobytie_zerkala',
        'zabrat_dialog_operatorom',
        'zapisat_narushenie_tematiky'
    ]
    LOOP
        IF pg_catalog.to_regprocedure(
            pg_catalog.format(
                'qbit_bot_pervichnogo_obrascheniya.%I(jsonb)',
                v_required
            )
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required function qbit_bot_pervichnogo_obrascheniya.%(jsonb) is missing',
                v_required;
        END IF;
    END LOOP;

    FOREACH v_target IN ARRAY ARRAY[
        'poluchit_soderzhimoe_zadaniya',
        'poluchit_sostoyanie_operatora',
        'sozdat_preduprezhdenie_tematiky',
        'poluchit_soderzhimoe_ishodyashchego',
        'ustanovit_zapret_iniciativy',
        'zaprosit_cheloveka',
        'obrabotat_sleduyushchee_napominanie'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
               AND p.proname = v_target
        ) THEN
            RAISE EXCEPTION
                'DB-03E target function % already exists; stop instead of overwriting',
                v_target;
        END IF;
    END LOOP;
END
$db03e$;

-- ===========================================================================
-- 1. READ CONTENT OF THE CURRENT CLAIMED PROCESSING JOB
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    zadanie_id uuid,
    dialog_id uuid,
    identifikator_kanala_id uuid,
    sobytie_id uuid,
    soobshchenie_id uuid,
    tip_soobshcheniya text,
    tekst_ishodnyy text,
    payload_ishodnyy jsonb,
    vneshnee_soobshchenie_id text,
    kanal text,
    akkaunt_kanala_id text,
    vneshniy_dialog_id text,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_expected_version bigint;
    v_now timestamptz;
    v_row record;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_expected_version := NULLIF(
        p_dannye->>'ozhidaemaya_versiya_dialoga',
        ''
    )::bigint;
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_expected_version IS NULL
       OR v_expected_version < 1 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/job/worker/fencing/expected dialog version.'::text,
            NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT
        z.id AS job_id,
        z.dialog_id,
        z.sobytie_id,
        z.status AS job_status,
        z.vladelec_arendy,
        z.arenda_do,
        z.nomer_vladeniya,
        z.versiya_dialoga AS job_dialog_version,
        z.payload AS job_payload,
        d.versiya_dialoga AS current_dialog_version,
        d.vladelec AS dialog_owner,
        d.status AS dialog_status,
        i.logicheski_zablokirovan,
        i.id AS identity_id,
        i.kanal,
        i.akkaunt_kanala_id,
        i.vneshniy_dialog_id,
        m.id AS message_id,
        m.vid AS message_type,
        m.tekst_ishodnyy,
        m.vneshnee_soobshchenie_id,
        e.payload_ishodnyy
      INTO v_row
      FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
      JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
        ON d.id = z.dialog_id
      JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
      JOIN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
        ON e.id = z.sobytie_id
      JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
        ON m.id = NULLIF(z.payload->>'soobshchenie_id', '')::uuid
       AND m.dialog_id = z.dialog_id
     WHERE z.id = v_job_id
     FOR UPDATE OF z, d;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'zadanie_ne_naydeno'::text,
            'Processing job либо его exact source message не найдены.'::text,
            NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_row.job_status <> 'v_rabote'
       OR v_row.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_row.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Только текущий worker/fencing может читать source payload claimed job.'::text,
            NULL::timestamptz,
            v_row.job_id, v_row.dialog_id, v_row.identity_id, v_row.sobytie_id,
            v_row.message_id, v_row.message_type,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, v_row.current_dialog_version;
        RETURN;
    END IF;

    IF v_row.arenda_do IS NULL OR v_row.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая lease не разрешает читать source payload; нужен новый claim.'::text,
            NULL::timestamptz,
            v_row.job_id, v_row.dialog_id, v_row.identity_id, v_row.sobytie_id,
            v_row.message_id, v_row.message_type,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, v_row.current_dialog_version;
        RETURN;
    END IF;

    IF v_row.job_dialog_version IS DISTINCT FROM v_expected_version
       OR v_row.current_dialog_version IS DISTINCT FROM v_expected_version THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Source payload запрошен для устаревшей dialog version.'::text,
            NULL::timestamptz,
            v_row.job_id, v_row.dialog_id, v_row.identity_id, v_row.sobytie_id,
            v_row.message_id, v_row.message_type,
            NULL::text, NULL::jsonb, NULL::text, NULL::text, NULL::text,
            NULL::text, v_row.current_dialog_version;
        RETURN;
    END IF;

    IF v_row.logicheski_zablokirovan
       OR v_row.dialog_owner <> 'bot'
       OR v_row.dialog_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_razreshaet_bot'::text,
            'Текущее состояние dialog/identity больше не разрешает bot processing.'::text,
            NULL::timestamptz,
            v_row.job_id, v_row.dialog_id, v_row.identity_id, v_row.sobytie_id,
            v_row.message_id, v_row.message_type,
            NULL::text, NULL::jsonb, NULL::text,
            v_row.kanal, v_row.akkaunt_kanala_id, v_row.vneshniy_dialog_id,
            v_row.current_dialog_version;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Возвращено только source content текущего fenced processing job для локального PII/STT adapter.'::text,
        NULL::timestamptz,
        v_row.job_id, v_row.dialog_id, v_row.identity_id, v_row.sobytie_id,
        v_row.message_id, v_row.message_type,
        v_row.tekst_ishodnyy,
        v_row.payload_ishodnyy,
        v_row.vneshnee_soobshchenie_id,
        v_row.kanal,
        v_row.akkaunt_kanala_id,
        v_row.vneshniy_dialog_id,
        v_row.current_dialog_version;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(jsonb) IS
'DB-03E v0.2: narrow local-only read of exact raw message/provider payload for the current live processing worker/fencing/version; needed for recoverable PII/STT processing, never an AI-safe package.';

RESET ROLE;

-- ===========================================================================
-- 2. READ NARROW OPERATOR STATE FOR CAS BUTTONS / MANUAL REPLY
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    sluzhebnyy_chat_id text,
    message_thread_id text,
    status_temy text,
    vladelec text,
    status_dialoga text,
    etap text,
    tekushchiy_menedzher_id uuid,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_dialog_id uuid;
    v_chat text;
    v_thread text;
    v_row record;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::uuid,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_chat := NULLIF(btrim(p_dannye->>'sluzhebnyy_chat_id'), '');
    v_thread := NULLIF(btrim(p_dannye->>'message_thread_id'), '');

    IF v_operaciya IS NULL
       OR (
            v_dialog_id IS NULL
            AND (v_chat IS NULL OR v_thread IS NULL)
       )
       OR (
            (v_chat IS NULL) IS DISTINCT FROM (v_thread IS NULL)
       ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation и dialog_id либо trusted service chat+thread.'::text,
            NULL::timestamptz,
            v_dialog_id, v_chat, v_thread, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::uuid,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT
        t.dialog_id,
        t.sluzhebnyy_chat_id,
        t.message_thread_id,
        t.status AS topic_status,
        d.vladelec,
        d.status AS dialog_status,
        d.etap,
        d.tekushchiy_menedzher_id,
        d.versiya_dialoga,
        d.pokolenie_ozhidaniya
      INTO v_row
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
      JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
        ON d.id = t.dialog_id
     WHERE (v_dialog_id IS NULL OR t.dialog_id = v_dialog_id)
       AND (
            v_chat IS NULL
            OR (
                t.sluzhebnyy_chat_id = v_chat
                AND t.message_thread_id = v_thread
            )
       )
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'operator_sostoyanie_ne_naydeno'::text,
            'Operator topic/dialog mapping не найден или trusted chat/thread не совпал.'::text,
            NULL::timestamptz,
            v_dialog_id, v_chat, v_thread, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::uuid,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Возвращено только operator state для CAS callback/manual reply; client content и PII не раскрываются.'::text,
        NULL::timestamptz,
        v_row.dialog_id,
        v_row.sluzhebnyy_chat_id,
        v_row.message_thread_id,
        v_row.topic_status,
        v_row.vladelec,
        v_row.dialog_status,
        v_row.etap,
        v_row.tekushchiy_menedzher_id,
        v_row.versiya_dialoga,
        v_row.pokolenie_ozhidaniya;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(jsonb) IS
'DB-03E v0.11: service-only narrow state lookup by existing dialog/topic mapping; returns owner/status/stage/current manager/version/generation for CAS buttons and manual reply without raw messages, PII, memory or attachments.';

RESET ROLE;

-- ===========================================================================
-- 3. CREATE DURABLE THEMATIC WARNING, INCLUDING THE BLOCKING THIRD WARNING
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(
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
    narushenie_id uuid,
    nomer_narusheniya integer,
    logicheski_zablokirovan boolean,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_dialog_id uuid;
    v_source_message_id uuid;
    v_expected bigint;
    v_text text;
    v_text_safe text;
    v_now timestamptz;
    v_dialog record;
    v_identity record;
    v_violation record;
    v_existing record;
    v_message_id uuid;
    v_action_id uuid;
    v_key text;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text,NULL::timestamptz,
            NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::integer,
            NULL::boolean,NULL::bigint;
        RETURN;
    END IF;

    v_operaciya:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_dialog_id:=NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_source_message_id:=NULLIF(p_dannye->>'soobshchenie_id','')::uuid;
    v_expected:=NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga','')::bigint;
    v_text:=p_dannye->>'tekst_ishodnyy';
    v_text_safe:=COALESCE(p_dannye->>'tekst_obezlichennyy',v_text);
    v_now:=COALESCE(
        NULLIF(p_dannye->>'vremya_sobytiya','')::timestamptz,
        clock_timestamp()
    );

    IF v_operaciya IS NULL OR v_dialog_id IS NULL
       OR v_source_message_id IS NULL OR v_expected IS NULL OR v_expected<1
       OR v_text IS NULL OR btrim(v_text)='' THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/dialog/source message/expected version/trusted warning text.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog_id,NULL::uuid,NULL::uuid,
            NULL::integer,NULL::boolean,NULL::bigint;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'dialog_ne_nayden'::text,
            'Dialog не найден.'::text,NULL::timestamptz,
            NULL::uuid,v_dialog_id,NULL::uuid,NULL::uuid,NULL::integer,
            NULL::boolean,NULL::bigint;
        RETURN;
    END IF;

    SELECT i.* INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id=v_dialog.identifikator_kanala_id
     FOR UPDATE;

    SELECT n.* INTO v_violation
      FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky AS n
     WHERE n.dialog_id=v_dialog.id
       AND n.soobshchenie_id=v_source_message_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'narushenie_ne_naydeno'::text,
            'Warning создаётся только для уже подтверждённого thematic violation exact source message.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog.id,NULL::uuid,NULL::uuid,
            NULL::integer,v_identity.logicheski_zablokirovan,v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operaciya,'konflikt'::text,'stale_dialog_version'::text,
            'Dialog изменился после thematic violation.'::text,NULL::timestamptz,
            NULL::uuid,v_dialog.id,NULL::uuid,v_violation.id,
            v_violation.nomer_narusheniya,v_identity.logicheski_zablokirovan,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.vladelec<>'bot'
       OR v_dialog.status IN ('peredan_cheloveku','zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya,'konflikt'::text,'dialog_ne_razreshaet_bot'::text,
            'Human owner/closed dialog имеет приоритет над thematic warning.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog.id,NULL::uuid,v_violation.id,
            v_violation.nomer_narusheniya,v_identity.logicheski_zablokirovan,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_identity.logicheski_zablokirovan
       AND NOT v_violation.privelo_k_blokirovke THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'blok_ne_ot_etogo_narusheniya'::text,
            'Blocked identity permits only the warning tied to the exact blocking violation.'::text,
            NULL::timestamptz,NULL::uuid,v_dialog.id,NULL::uuid,v_violation.id,
            v_violation.nomer_narusheniya,true,v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    v_key:='tematicheskoe_preduprezhdenie:'||v_violation.id::text;

    SELECT a.* INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora=v_key
     FOR UPDATE;

    IF FOUND THEN
        RETURN QUERY SELECT
            v_operaciya,'dublikat'::text,NULL::text,
            'Thematic warning action уже существует.'::text,
            v_existing.povtor_posle,
            v_existing.id,v_dialog.id,v_existing.soobshchenie_id,
            v_violation.id,v_violation.nomer_narusheniya,
            v_identity.logicheski_zablokirovan,v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m (
        dialog_id,napravlenie,avtor,vid,tekst_ishodnyy,tekst_obezlichennyy,
        vremya_priema,status_otpravki,ozhidaetsya_otvet,
        tip_zaversheniya,prichina_resheniya,trassirovka_id
    ) VALUES (
        v_dialog.id,'ishodyashchee','bot','text',v_text,v_text_safe,
        v_now,'zaplanirovano',false,NULL,
        'tematicheskoe_preduprezhdenie',v_operaciya
    )
    RETURNING m.id INTO v_message_id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a (
        dialog_id,soobshchenie_id,vid_deystviya,istochnik,klyuch_povtora,
        kanal,akkaunt_kanala_id,vneshniy_dialog_id,payload,status,
        sleduyushchiy_zapusk,versiya_dialoga
    ) VALUES (
        v_dialog.id,v_message_id,'soobshchenie','sistema',v_key,
        v_identity.kanal,v_identity.akkaunt_kanala_id,v_identity.vneshniy_dialog_id,
        jsonb_build_object(
            'iniciativnoe',false,
            'tematicheskoe_preduprezhdenie',true,
            'narushenie_id',v_violation.id,
            'nomer_narusheniya',v_violation.nomer_narusheniya
        ),
        'zaplanirovano',v_now,v_dialog.versiya_dialoga
    )
    RETURNING a.id INTO v_action_id;

    RETURN QUERY SELECT
        v_operaciya,'uspeshno'::text,NULL::text,
        CASE WHEN v_violation.privelo_k_blokirovke
             THEN 'Blocking thematic warning intent сохранён; sender разрешит только exact DB-verified violation.'
             ELSE 'Thematic warning intent сохранён до внешнего Telegram API.'
        END::text,
        NULL::timestamptz,
        v_action_id,v_dialog.id,v_message_id,v_violation.id,
        v_violation.nomer_narusheniya,v_identity.logicheski_zablokirovan,
        v_dialog.versiya_dialoga;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(jsonb) IS
'DB-03E v0.11: creates one stable ordinary outgoing warning for an exact recorded thematic violation; the third warning may be created after that same violation enabled logical block, without granting arbitrary blocked messaging.';

RESET ROLE;

-- ===========================================================================
-- 4. READ EXACT CONTENT OF CURRENT CLAIMED OUTGOING ACTION + FINAL PRE-SEND RECHECK
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(
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
    tekst_ishodnyy text,
    tekst_obezlichennyy text,
    payload jsonb,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga bigint
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
    v_now timestamptz;
    v_action record;
    v_dialog record;
    v_identity record;
    v_message record;
    v_special_warning boolean := false;
    v_allowed boolean := false;
    v_initiative boolean := false;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye)<>'object' THEN
        RETURN QUERY SELECT
            NULL::text,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text,NULL::timestamptz,
            NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::text,
            NULL::text,NULL::text,NULL::text,NULL::text,NULL::jsonb,
            NULL::integer,NULL::text,NULL::timestamptz,NULL::bigint,NULL::bigint;
        RETURN;
    END IF;

    v_operaciya:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_action_id:=NULLIF(p_dannye->>'deystvie_id','')::uuid;
    v_worker:=NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_ownership:=NULLIF(p_dannye->>'nomer_vladeniya','')::bigint;
    v_now:=clock_timestamp();

    IF v_operaciya IS NULL OR v_action_id IS NULL OR v_worker IS NULL
       OR v_ownership IS NULL OR v_ownership<1 THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'nekorrektnyy_vhod'::text,
            'Нужны operation/action/current worker/fencing.'::text,NULL::timestamptz,
            v_action_id,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::text,
            NULL::text,NULL::text,NULL::text,NULL::text,NULL::jsonb,
            NULL::integer,v_worker,NULL::timestamptz,v_ownership,NULL::bigint;
        RETURN;
    END IF;

    SELECT a.* INTO v_action
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.id=v_action_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya,'otkaz'::text,'deystvie_ne_naydeno'::text,
            'Outgoing action не найден.'::text,NULL::timestamptz,
            v_action_id,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::text,
            NULL::text,NULL::text,NULL::text,NULL::text,NULL::jsonb,
            NULL::integer,v_worker,NULL::timestamptz,v_ownership,NULL::bigint;
        RETURN;
    END IF;

    IF v_action.status<>'v_rabote'
       OR v_action.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_action.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya,'konflikt'::text,'stale_lease_owner'::text,
            'Sender больше не владеет action.'::text,NULL::timestamptz,
            v_action.id,v_action.dialog_id,v_action.soobshchenie_id,
            v_action.vid_deystviya,v_action.kanal,v_action.akkaunt_kanala_id,
            v_action.vneshniy_dialog_id,v_action.vneshnee_otvet_na_id,
            NULL::text,NULL::text,v_action.payload,v_action.popytki,
            v_action.vladelec_arendy,v_action.arenda_do,v_action.nomer_vladeniya,
            v_action.versiya_dialoga;
        RETURN;
    END IF;

    IF v_action.arenda_do IS NULL OR v_action.arenda_do<=v_now THEN
        RETURN QUERY SELECT
            v_operaciya,'konflikt'::text,'arenda_istekla'::text,
            'Истёкшая sender lease не даёт права начинать внешний API.'::text,
            NULL::timestamptz,
            v_action.id,v_action.dialog_id,v_action.soobshchenie_id,
            v_action.vid_deystviya,v_action.kanal,v_action.akkaunt_kanala_id,
            v_action.vneshniy_dialog_id,v_action.vneshnee_otvet_na_id,
            NULL::text,NULL::text,v_action.payload,v_action.popytki,
            v_action.vladelec_arendy,v_action.arenda_do,v_action.nomer_vladeniya,
            v_action.versiya_dialoga;
        RETURN;
    END IF;

    SELECT d.* INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id=v_action.dialog_id
     FOR UPDATE;

    SELECT i.* INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id=v_dialog.identifikator_kanala_id
     FOR UPDATE;

    IF v_action.soobshchenie_id IS NOT NULL THEN
        SELECT m.* INTO v_message
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
         WHERE m.id=v_action.soobshchenie_id;
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky AS nt
         WHERE nt.id::text IS NOT DISTINCT FROM v_action.payload->>'narushenie_id'
           AND nt.dialog_id=v_action.dialog_id
           AND nt.nomer_narusheniya::text
               IS NOT DISTINCT FROM v_action.payload->>'nomer_narusheniya'
           AND nt.privelo_k_blokirovke
           AND v_message.prichina_resheniya='tematicheskoe_preduprezhdenie'
           AND COALESCE(
                (v_action.payload->>'tematicheskoe_preduprezhdenie')='true',
                false
           )
    ) INTO v_special_warning;

    v_initiative:=COALESCE((v_action.payload->>'iniciativnoe')::boolean,false);

    IF v_action.versiya_dialoga IS NOT DISTINCT FROM v_dialog.versiya_dialoga THEN
        IF v_action.istochnik='menedzher' THEN
            v_allowed:=(
                v_dialog.vladelec='chelovek'
                AND v_dialog.status='peredan_cheloveku'
                AND v_dialog.tekushchiy_menedzher_id::text
                    IS NOT DISTINCT FROM NULLIF(v_action.payload->>'menedzher_id','')
            );
        ELSE
            v_allowed:=(
                v_dialog.vladelec='bot'
                AND v_dialog.status NOT IN ('peredan_cheloveku','zavershen')
                AND (NOT v_identity.logicheski_zablokirovan OR v_special_warning)
                AND NOT (v_initiative AND v_identity.zapret_iniciativnyh_soobshcheniy)
            );
        END IF;
    END IF;

    IF NOT v_allowed THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
           SET status='otmeneno',vladelec_arendy=NULL,arenda_do=NULL,
               kod_oshibki='finalnyy_recheck_ne_proyden',
               opisanie_oshibki='State changed after claim and before external API.',
               vremya_obnovleniya=clock_timestamp()
         WHERE a.id=v_action.id;

        IF v_action.soobshchenie_id IS NOT NULL THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
               SET status_otpravki='otmeneno'
             WHERE m.id=v_action.soobshchenie_id
               AND m.status_otpravki='v_rabote';
        END IF;

        RETURN QUERY SELECT
            v_operaciya,'uspeshno'::text,'finalnyy_recheck_ne_proyden'::text,
            'Action отменён до внешнего API: dialog/owner/version/block/opt-out изменились.'::text,
            NULL::timestamptz,
            v_action.id,v_action.dialog_id,v_action.soobshchenie_id,
            v_action.vid_deystviya,v_action.kanal,v_action.akkaunt_kanala_id,
            v_action.vneshniy_dialog_id,v_action.vneshnee_otvet_na_id,
            NULL::text,NULL::text,v_action.payload,v_action.popytki,
            NULL::text,NULL::timestamptz,v_action.nomer_vladeniya,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        v_operaciya,'uspeshno'::text,NULL::text,
        'Final pre-send recheck пройден; возвращено только содержимое текущего claimed action.'::text,
        NULL::timestamptz,
        v_action.id,v_action.dialog_id,v_action.soobshchenie_id,
        v_action.vid_deystviya,v_action.kanal,v_action.akkaunt_kanala_id,
        v_action.vneshniy_dialog_id,v_action.vneshnee_otvet_na_id,
        v_message.tekst_ishodnyy,v_message.tekst_obezlichennyy,
        v_action.payload,v_action.popytki,v_action.vladelec_arendy,
        v_action.arenda_do,v_action.nomer_vladeniya,v_action.versiya_dialoga;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(jsonb) IS
'DB-03E v0.11: bot sender-only fenced read of exact claimed outgoing content plus final pre-API owner/version/block/opt-out recheck; stale action is canceled before any external call.';

RESET ROLE;

-- ===========================================================================
-- 5. PERSISTENT INITIATIVE OPT-OUT / EXPLICIT OPT-IN
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    identifikator_kanala_id uuid,
    dialog_id uuid,
    zapret_iniciativy boolean,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_dialog_id uuid;
    v_expected bigint;
    v_block boolean;
    v_reason text;
    v_now timestamptz;

    v_job record;
    v_dialog record;
    v_identity record;
    v_new_version bigint;
    v_new_generation bigint;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::boolean, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_expected := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_block := NULLIF(p_dannye->>'zapreshcheno', '')::boolean;
    v_reason := COALESCE(
        NULLIF(btrim(p_dannye->>'prichina'), ''),
        CASE WHEN v_block THEN 'yavnyy_zapret_klienta' ELSE 'yavnoe_razreshenie_klienta' END
    );
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_sobytiya', '')::timestamptz,
        clock_timestamp()
    );

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_dialog_id IS NULL
       OR v_expected IS NULL
       OR v_expected < 1
       OR v_block IS NULL
       OR v_reason IS NULL THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/job/worker/fencing/dialog/expected version/zapreshcheno.'::text,
            NULL::timestamptz, NULL::uuid, v_dialog_id, v_block,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT z.*
      INTO v_job
      FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
     WHERE z.id = v_job_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'zadanie_ne_naydeno'::text,
            'Processing job не найден.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog_id, v_block, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_nayden'::text,
            'Dialog не найден.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog_id, v_block, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT i.*
      INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Dialog % references missing channel identity %',
            v_dialog.id,
            v_dialog.identifikator_kanala_id;
    END IF;

    -- Idempotent replay after the first successful commit.
    IF v_job.status = 'otmeneno'
       AND v_job.kod_oshibki = 'initiative_preference_changed'
       AND v_job.dialog_id = v_dialog.id
       AND v_dialog.versiya_dialoga = v_expected + 1
       AND v_identity.zapret_iniciativnyh_soobshcheniy = v_block THEN
        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Настройка инициативных сообщений уже применена.'::text,
            NULL::timestamptz,
            v_identity.id, v_dialog.id,
            v_identity.zapret_iniciativnyh_soobshcheniy,
            v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_job.dialog_id IS DISTINCT FROM v_dialog.id
       OR v_job.versiya_dialoga IS DISTINCT FROM v_expected
       OR v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Job/dialog version уже изменились.'::text, NULL::timestamptz,
            v_identity.id, v_dialog.id,
            v_identity.zapret_iniciativnyh_soobshcheniy,
            v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker больше не владеет processing lease.'::text,
            NULL::timestamptz,
            v_identity.id, v_dialog.id,
            v_identity.zapret_iniciativnyh_soobshcheniy,
            v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL OR v_job.arenda_do <= clock_timestamp() THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая processing lease не имеет права менять opt-out.'::text,
            NULL::timestamptz,
            v_identity.id, v_dialog.id,
            v_identity.zapret_iniciativnyh_soobshcheniy,
            v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_dialog.vladelec <> 'bot'
       OR v_dialog.status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Текущее состояние dialog не разрешает bot менять initiative preference.'::text,
            NULL::timestamptz,
            v_identity.id, v_dialog.id,
            v_identity.zapret_iniciativnyh_soobshcheniy,
            v_dialog.versiya_dialoga,
            v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
       SET zapret_iniciativnyh_soobshcheniy = v_block,
           vremya_zapreta_iniciativy = CASE WHEN v_block THEN v_now ELSE NULL END,
           vremya_obnovleniya = clock_timestamp()
     WHERE i.id = v_identity.id;

    v_new_version := v_dialog.versiya_dialoga + 1;
    v_new_generation := v_dialog.pokolenie_ozhidaniya + 1;

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
       SET status = CASE
               WHEN d.status = 'ozhidaet_otveta' THEN 'aktivnyy'
               ELSE d.status
           END,
           ozhidaetsya_otvet = false,
           t0 = NULL,
           pokolenie_ozhidaniya = v_new_generation,
           versiya_dialoga = v_new_version,
           vremya_obnovleniya = clock_timestamp()
     WHERE d.id = v_dialog.id;

    -- The current worker intentionally ends here. New client input will create
    -- a new version/job. This avoids continuing from the pre-opt-out snapshot.
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
       SET status = 'otmeneno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = 'initiative_preference_changed',
           opisanie_oshibki = v_reason,
           vremya_obnovleniya = clock_timestamp()
     WHERE z.dialog_id = v_dialog.id
       AND z.status IN ('ozhidaet', 'povtor', 'v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
       SET status = 'otmeneno',
           prichina = 'initiative_preference_changed',
           vremya_obnovleniya = clock_timestamp()
     WHERE n.dialog_id = v_dialog.id
       AND n.status IN ('zaplanirovano', 'v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
       SET status_otpravki = 'otmeneno'
     WHERE m.id IN (
        SELECT a.soobshchenie_id
          FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
         WHERE a.dialog_id = v_dialog.id
           AND a.istochnik IN ('bot', 'sistema')
           AND a.status IN ('zaplanirovano', 'povtor')
           AND a.soobshchenie_id IS NOT NULL
     );

    UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
       SET status = 'otmeneno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = 'initiative_preference_changed',
           opisanie_oshibki = 'Не начатая bot/system отправка отменена после изменения initiative preference.',
           vremya_obnovleniya = clock_timestamp()
     WHERE a.dialog_id = v_dialog.id
       AND a.istochnik IN ('bot', 'sistema')
       AND a.status IN ('zaplanirovano', 'povtor');

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        dialog_id,
        polzovatel_id,
        tip_sobytiya,
        vremya_sobytiya,
        prichina,
        istochnik,
        trassirovka_id
    )
    VALUES (
        v_dialog.id,
        v_dialog.polzovatel_id,
        CASE WHEN v_block THEN 'zapret_iniciativy' ELSE 'razreshenie_iniciativy' END,
        v_now,
        v_reason,
        'client_core',
        v_operaciya
    );

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        CASE
            WHEN v_block
            THEN 'Persistent initiative opt-out установлен; ожидание и не начатые bot actions отменены.'
            ELSE 'Явное разрешение инициативных сообщений сохранено; старое ожидание автоматически не восстановлено.'
        END::text,
        NULL::timestamptz,
        v_identity.id, v_dialog.id, v_block,
        v_new_version, v_new_generation;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(jsonb) IS
'DB-03E: current fenced bot worker atomically persists initiative opt-out/explicit opt-in on channel identity, clears wait/reminders and stale unstarted bot actions, increments dialog version/generation and cancels the current processing job. In-flight external attempts remain factual.';

-- ===========================================================================
-- 2. DURABLE "HUMAN NEEDED" SIGNAL WITHOUT PREMATURE OWNER CHANGE
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    sobytie_zerkala_id uuid,
    dialog_id uuid,
    vladelec text,
    status_dialoga text,
    etap text,
    versiya_dialoga bigint,
    pokolenie_ozhidaniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_dialog_id uuid;
    v_expected bigint;
    v_reason text;
    v_text text;
    v_now timestamptz;

    v_job record;
    v_dialog record;
    v_topic record;
    v_existing record;
    v_event_id uuid;
    v_new_version bigint;
    v_new_generation bigint;
    v_key text;
    v_safe_client text;
    v_stage_already boolean;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::text,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_expected := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_reason := COALESCE(
        NULLIF(btrim(p_dannye->>'prichina'), ''),
        'zapros_klienta_ili_bezopasnyy_fallback'
    );
    v_text := COALESCE(
        NULLIF(p_dannye->>'tekst', ''),
        'Требуется подключение менеджера.'
    );
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_sobytiya', '')::timestamptz,
        clock_timestamp()
    );

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_dialog_id IS NULL
       OR v_expected IS NULL
       OR v_expected < 1
       OR v_reason IS NULL
       OR v_text IS NULL THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/job/worker/fencing/dialog/expected version/reason.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::text, NULL::text, NULL::text,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT z.*
      INTO v_job
      FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
     WHERE z.id = v_job_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'zadanie_ne_naydeno'::text,
            'Processing job не найден.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::text, NULL::text, NULL::text,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_nayden'::text,
            'Dialog не найден.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog_id, NULL::text, NULL::text, NULL::text,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT t.*
      INTO v_topic
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id = v_dialog.id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'tema_ne_naydena'::text,
            'Operator topic intent не найден; human signal нельзя адресовать произвольно.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog.id, v_dialog.vladelec, v_dialog.status,
            v_dialog.etap, v_dialog.versiya_dialoga, v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    -- Replay after successful commit: event key is derived from resulting version.
    IF v_job.status = 'otmeneno'
       AND v_job.kod_oshibki = 'nuzhen_chelovek'
       AND v_job.dialog_id = v_dialog.id THEN
        SELECT e.*
          INTO v_existing
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
         WHERE e.dialog_id = v_dialog.id
           AND e.tip_sobytiya = 'nuzhen_chelovek'
           AND e.payload->>'ishodnoe_zadanie_id' = v_job.id::text
         ORDER BY e.vremya_sozdaniya DESC
         LIMIT 1;

        IF FOUND THEN
            RETURN QUERY SELECT
                v_operaciya, 'dublikat'::text, NULL::text,
                'Human-needed signal уже создан для этого processing job.'::text,
                NULL::timestamptz,
                v_existing.id, v_dialog.id, v_dialog.vladelec, v_dialog.status,
                v_dialog.etap, v_dialog.versiya_dialoga,
                v_dialog.pokolenie_ozhidaniya;
            RETURN;
        END IF;
    END IF;

    IF v_job.dialog_id IS DISTINCT FROM v_dialog.id
       OR v_job.versiya_dialoga IS DISTINCT FROM v_expected
       OR v_dialog.versiya_dialoga IS DISTINCT FROM v_expected THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Job/dialog version уже изменились.'::text, NULL::timestamptz,
            NULL::uuid, v_dialog.id, v_dialog.vladelec, v_dialog.status,
            v_dialog.etap, v_dialog.versiya_dialoga, v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker больше не владеет processing lease.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog.id, v_dialog.vladelec, v_dialog.status,
            v_dialog.etap, v_dialog.versiya_dialoga, v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL OR v_job.arenda_do <= clock_timestamp() THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая processing lease не имеет права создавать human signal.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog.id, v_dialog.vladelec, v_dialog.status,
            v_dialog.etap, v_dialog.versiya_dialoga, v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    IF v_dialog.vladelec <> 'bot'
       OR v_dialog.status = 'zavershen' THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Human-needed signal этого типа создаётся только пока owner=bot и dialog не завершён.'::text,
            NULL::timestamptz,
            NULL::uuid, v_dialog.id, v_dialog.vladelec, v_dialog.status,
            v_dialog.etap, v_dialog.versiya_dialoga, v_dialog.pokolenie_ozhidaniya;
        RETURN;
    END IF;

    v_stage_already := (v_dialog.etap = 'peredacha_cheloveku');

    IF v_stage_already THEN
        v_new_version := v_dialog.versiya_dialoga;
        v_new_generation := v_dialog.pokolenie_ozhidaniya;
    ELSE
        v_new_version := v_dialog.versiya_dialoga + 1;
        v_new_generation := v_dialog.pokolenie_ozhidaniya + 1;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov (
            dialog_id,
            staryy_etap,
            novyy_etap,
            vremya_sobytiya,
            prichina,
            istochnik
        )
        VALUES (
            v_dialog.id,
            v_dialog.etap,
            'peredacha_cheloveku',
            v_now,
            v_reason,
            'client_core'
        );

        UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
           SET etap = 'peredacha_cheloveku',
               status = CASE
                   WHEN d.status = 'ozhidaet_otveta' THEN 'aktivnyy'
                   ELSE d.status
               END,
               ozhidaetsya_otvet = false,
               t0 = NULL,
               pokolenie_ozhidaniya = v_new_generation,
               versiya_dialoga = v_new_version,
               vremya_obnovleniya = clock_timestamp()
         WHERE d.id = v_dialog.id;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
       SET status = 'otmeneno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = 'nuzhen_chelovek',
           opisanie_oshibki = v_reason,
           vremya_obnovleniya = clock_timestamp()
     WHERE z.dialog_id = v_dialog.id
       AND z.status IN ('ozhidaet', 'povtor', 'v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
       SET status = 'otmeneno',
           prichina = 'nuzhen_chelovek',
           vremya_obnovleniya = clock_timestamp()
     WHERE n.dialog_id = v_dialog.id
       AND n.status IN ('zaplanirovano', 'v_rabote');

    UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
       SET status_otpravki = 'otmeneno'
     WHERE m.id IN (
        SELECT a.soobshchenie_id
          FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
         WHERE a.dialog_id = v_dialog.id
           AND a.istochnik IN ('bot', 'sistema')
           AND a.status IN ('zaplanirovano', 'povtor')
           AND a.soobshchenie_id IS NOT NULL
     );

    UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
       SET status = 'otmeneno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = 'nuzhen_chelovek',
           opisanie_oshibki = 'Не начатая bot/system отправка отменена при запросе человека.',
           vremya_obnovleniya = clock_timestamp()
     WHERE a.dialog_id = v_dialog.id
       AND a.istochnik IN ('bot', 'sistema')
       AND a.status IN ('zaplanirovano', 'povtor');

    SELECT e.bezopasnaya_podpis_klienta
      INTO v_safe_client
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
     WHERE e.klyuch_idempotentnosti = 'tema:' || v_dialog.id::text;

    v_key := 'nuzhen_chelovek:' || v_dialog.id::text || ':' || v_new_version::text;

    SELECT e.*
      INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
     WHERE e.klyuch_idempotentnosti = v_key
     FOR UPDATE;

    IF FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Human-needed signal этой версии уже существует.'::text,
            NULL::timestamptz,
            v_existing.id, v_dialog.id, 'bot'::text,
            CASE WHEN v_dialog.status='ozhidaet_otveta' THEN 'aktivnyy' ELSE v_dialog.status END,
            'peredacha_cheloveku'::text,
            v_new_version, v_new_generation;
        RETURN;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
        dialog_id,
        tip_sobytiya,
        klyuch_idempotentnosti,
        prioritet,
        cel_chat_id,
        cel_thread_id,
        bezopasnaya_podpis_klienta,
        tekst,
        payload,
        status
    )
    VALUES (
        v_dialog.id,
        'nuzhen_chelovek',
        v_key,
        100,
        v_topic.sluzhebnyy_chat_id,
        v_topic.message_thread_id,
        COALESCE(v_safe_client, 'Клиент'),
        v_text,
        jsonb_build_object(
            'prichina', v_reason,
            'dialog_id', v_dialog.id,
            'versiya_dialoga', v_new_version,
            'ishodnoe_zadanie_id', v_job.id,
            'deystvie', 'zabrat_dialog'
        ),
        'zaplanirovano'
    )
    RETURNING id
    INTO v_event_id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        dialog_id,
        polzovatel_id,
        tip_sobytiya,
        vremya_sobytiya,
        prichina,
        istochnik,
        trassirovka_id
    )
    VALUES (
        v_dialog.id,
        v_dialog.polzovatel_id,
        'nuzhen_chelovek',
        v_now,
        v_reason,
        'client_core',
        v_operaciya
    );

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Human-needed signal создан; owner остаётся bot до отдельного service callback Take.'::text,
        NULL::timestamptz,
        v_event_id, v_dialog.id, 'bot'::text,
        CASE WHEN v_dialog.status='ozhidaet_otveta' THEN 'aktivnyy' ELSE v_dialog.status END,
        'peredacha_cheloveku'::text,
        v_new_version, v_new_generation;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(jsonb) IS
'DB-03E: current fenced bot worker creates stable group nuzhen_chelovek mirror intent, cancels bot wait/reminders/internal job and unstarted bot actions, moves stage to peredacha_cheloveku, but deliberately keeps owner=bot until DB-03D2 Take.';

-- ===========================================================================
-- 7. ATOMIC DUE REMINDER / LOSS DISCOVERY
-- ===========================================================================

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    napominanie_id uuid,
    tip_napominaniya text,
    dialog_id uuid,
    deystvie_id uuid,
    soobshchenie_id uuid,
    reshenie text,
    pokolenie_ozhidaniya bigint,
    status_dialoga text,
    rezultat_dialoga text,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_now timestamptz;
    v_text1 text;
    v_text2 text;
    v_safe1 text;
    v_safe2 text;
    v_loss_after integer;
    v_reminder record;
    v_prepare record;
    v_loss record;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::text, NULL::uuid, NULL::uuid, NULL::uuid,
            NULL::text, NULL::bigint, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_proverki', '')::timestamptz,
        clock_timestamp()
    );
    v_text1 := p_dannye->>'tekst_napominaniya_1';
    v_text2 := p_dannye->>'tekst_napominaniya_2';
    v_safe1 := COALESCE(p_dannye->>'tekst_obezlichennyy_1', v_text1);
    v_safe2 := COALESCE(p_dannye->>'tekst_obezlichennyy_2', v_text2);
    v_loss_after := COALESCE(
        NULLIF(p_dannye->>'poterya_posle_sekund', '')::integer,
        86400
    );

    IF v_operaciya IS NULL
       OR v_loss_after < 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operaciya_id и trusted poterya_posle_sekund >= 3600.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::text, NULL::uuid, NULL::uuid, NULL::uuid,
            NULL::text, NULL::bigint, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT n.*
      INTO v_reminder
      FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
     WHERE n.status = 'zaplanirovano'
       AND n.srok <= v_now
     ORDER BY n.srok, n.vremya_sozdaniya, n.id
     FOR UPDATE SKIP LOCKED
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'net_napominaniya'::text, NULL::text,
            'Готового reminder/loss-check сейчас нет.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::text, NULL::uuid, NULL::uuid, NULL::uuid,
            NULL::text, NULL::bigint, NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_reminder.tip = 'proverka_poteri' THEN
        SELECT *
          INTO v_loss
          FROM qbit_bot_pervichnogo_obrascheniya.zafiksirovat_poteryu_bez_otveta(
            jsonb_build_object(
                'operaciya_id',
                v_operaciya || ':loss:' || v_reminder.id::text,
                'napominanie_id',
                v_reminder.id,
                'vremya_proverki',
                v_now
            )
          );

        RETURN QUERY SELECT
            v_operaciya,
            v_loss.rezultat,
            v_loss.kod_oshibki,
            v_loss.opisanie,
            v_loss.povtor_posle,
            v_reminder.id,
            v_reminder.tip,
            v_reminder.dialog_id,
            NULL::uuid,
            NULL::uuid,
            'proverka_poteri'::text,
            v_reminder.pokolenie_ozhidaniya,
            v_loss.status_dialoga,
            v_loss.rezultat_dialoga,
            v_loss.versiya_dialoga;
        RETURN;
    END IF;

    IF v_reminder.tip = 'napominanie_1' AND v_text1 IS NULL THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_bad
           SET status = 'oshibka',
               prichina = 'net_teksta_napominaniya',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_bad.id = v_reminder.id;

        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'net_teksta_napominaniya'::text,
            'Не задан trusted текст reminder1; reminder переведён в oshibka без внешней отправки.'::text,
            NULL::timestamptz,
            v_reminder.id, v_reminder.tip, v_reminder.dialog_id,
            NULL::uuid, NULL::uuid, 'otmenit'::text,
            v_reminder.pokolenie_ozhidaniya,
            NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_reminder.tip = 'napominanie_2' AND v_text2 IS NULL THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_bad
           SET status = 'oshibka',
               prichina = 'net_teksta_napominaniya',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_bad.id = v_reminder.id;

        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'net_teksta_napominaniya'::text,
            'Не задан trusted текст reminder2; reminder переведён в oshibka без внешней отправки.'::text,
            NULL::timestamptz,
            v_reminder.id, v_reminder.tip, v_reminder.dialog_id,
            NULL::uuid, NULL::uuid, 'otmenit'::text,
            v_reminder.pokolenie_ozhidaniya,
            NULL::text, NULL::text, NULL::bigint;
        RETURN;
    END IF;

    SELECT *
      INTO v_prepare
      FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_napominanie(
        jsonb_build_object(
            'operaciya_id',
            v_operaciya || ':' || v_reminder.tip || ':' || v_reminder.id::text,
            'napominanie_id',
            v_reminder.id,
            'pokolenie_ozhidaniya',
            v_reminder.pokolenie_ozhidaniya,
            'tekst_ishodnyy',
            CASE
                WHEN v_reminder.tip = 'napominanie_1' THEN v_text1
                ELSE v_text2
            END,
            'tekst_obezlichennyy',
            CASE
                WHEN v_reminder.tip = 'napominanie_1' THEN v_safe1
                ELSE v_safe2
            END,
            'vremya_proverki',
            v_now,
            'poterya_posle_sekund',
            v_loss_after
        )
      );

    RETURN QUERY SELECT
        v_operaciya,
        v_prepare.rezultat,
        v_prepare.kod_oshibki,
        v_prepare.opisanie,
        v_prepare.povtor_posle,
        v_reminder.id,
        v_reminder.tip,
        v_reminder.dialog_id,
        v_prepare.deystvie_id,
        v_prepare.soobshchenie_id,
        v_prepare.reshenie,
        v_prepare.pokolenie_ozhidaniya,
        NULL::text,
        NULL::text,
        NULL::bigint;
END
$fn$;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(jsonb) IS
'DB-03E: atomically discovers one due scheduled reminder/loss-check via FOR UPDATE SKIP LOCKED and delegates to verified DB-03C4 final-recheck functions; runtime role needs no direct SELECT on napominaniya.';

RESET ROLE;

-- ===========================================================================
-- 8. UPGRADE OUTGOING CLAIM: EXACT BLOCKING WARNING IS THE ONLY BLOCK EXCEPTION
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

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
             AND NOT EXISTS (
                    SELECT 1
                      FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky AS nt
                      JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS sm
                        ON sm.id = v_candidate.soobshchenie_id
                     WHERE nt.id::text IS NOT DISTINCT FROM v_candidate.payload->>'narushenie_id'
                       AND nt.dialog_id = v_candidate.dialog_id
                       AND nt.nomer_narusheniya::text
                           IS NOT DISTINCT FROM v_candidate.payload->>'nomer_narusheniya'
                       AND nt.privelo_k_blokirovke
                       AND sm.prichina_resheniya = 'tematicheskoe_preduprezhdenie'
                       AND COALESCE(
                            (v_candidate.payload->>'tematicheskoe_preduprezhdenie') = 'true',
                            false
                       )
             )
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



RESET ROLE;

-- ===========================================================================
-- 9. PRIVILEGES + STATIC SECURITY ASSERTIONS
-- ===========================================================================
-- New DB-03E functions are owned by qbit_test_owner. Perform ACL changes as
-- that owner; the trusted postgres session is allowed to SET ROLE to it.

SET LOCAL ROLE qbit_test_owner;

REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(jsonb) TO qbit_test_bot;

DO $db03e$
DECLARE
    v_fn record;
    v_role text;
    v_table record;
BEGIN
    FOR v_fn IN
        SELECT p.oid, p.proname, p.prosecdef, p.proconfig, r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
          JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
                'poluchit_soderzhimoe_zadaniya',
                'poluchit_sostoyanie_operatora',
                'sozdat_preduprezhdenie_tematiky',
                'poluchit_soderzhimoe_ishodyashchego',
                'ustanovit_zapret_iniciativy',
                'zaprosit_cheloveka',
                'obrabotat_sleduyushchee_napominanie'
           )
    LOOP
        IF NOT v_fn.prosecdef
           OR v_fn.owner_name IS DISTINCT FROM 'qbit_test_owner'
           OR NOT (
                COALESCE(v_fn.proconfig, ARRAY[]::text[])
                @> ARRAY['search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya']::text[]
           ) THEN
            RAISE EXCEPTION
                'Unsafe DB-03E function metadata: %, owner=%, config=%',
                v_fn.proname, v_fn.owner_name, v_fn.proconfig;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM pg_catalog.aclexplode(
                    COALESCE(
                        (SELECT p2.proacl FROM pg_catalog.pg_proc AS p2 WHERE p2.oid = v_fn.oid),
                        pg_catalog.acldefault(
                            'f',
                            (SELECT p2.proowner FROM pg_catalog.pg_proc AS p2 WHERE p2.oid = v_fn.oid)
                        )
                    )
              ) AS a
             WHERE a.grantee = 0
               AND a.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'PUBLIC unexpectedly has EXECUTE on %', v_fn.proname;
        END IF;

        IF v_fn.proname = 'poluchit_sostoyanie_operatora' THEN
            IF NOT pg_catalog.has_function_privilege(
                'qbit_test_sluzhebnyy', v_fn.oid, 'EXECUTE'
            )
            OR pg_catalog.has_function_privilege(
                'qbit_test_bot', v_fn.oid, 'EXECUTE'
            ) THEN
                RAISE EXCEPTION
                    'DB-03E operator-state privilege split is wrong';
            END IF;
        ELSE
            IF NOT pg_catalog.has_function_privilege(
                'qbit_test_bot', v_fn.oid, 'EXECUTE'
            )
            OR pg_catalog.has_function_privilege(
                'qbit_test_sluzhebnyy', v_fn.oid, 'EXECUTE'
            ) THEN
                RAISE EXCEPTION
                    'DB-03E client function privilege split is wrong for %',
                    v_fn.proname;
            END IF;
        END IF;
    END LOOP;

    IF (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
                'poluchit_soderzhimoe_zadaniya',
                'poluchit_sostoyanie_operatora',
                'sozdat_preduprezhdenie_tematiky',
                'poluchit_soderzhimoe_ishodyashchego',
                'ustanovit_zapret_iniciativy',
                'zaprosit_cheloveka',
                'obrabotat_sleduyushchee_napominanie'
           )
           AND p.prosecdef
    ) <> 7 THEN
        RAISE EXCEPTION 'DB-03E expected exactly 7 SECURITY DEFINER functions';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy'
    ]
    LOOP
        FOR v_table IN
            SELECT c.oid, c.relname
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = c.relnamespace
             WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
               AND c.relkind = 'r'
        LOOP
            IF pg_catalog.has_table_privilege(v_role, v_table.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % unexpectedly has direct DML on qbit_bot_pervichnogo_obrascheniya.%',
                    v_role,
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;
END
$db03e$;

-- ===========================================================================
-- 10. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================
-- The probe intentionally exercises owner-only direct setup/assertions together
-- with SECURITY DEFINER APIs. Section 9 already switched to qbit_test_owner;
-- keep that owner role through this disposable probe. Runtime-role EXECUTE
-- separation is verified independently in section 9.

SAVEPOINT db03e_probe;

DO $db03e$
DECLARE
    r1 record;
    c1 record;
    content1 record;
    operator_state record;
    warn_in1 record;
    warn_in2 record;
    warn_in3 record;
    warn_v1 record;
    warn_v2 record;
    warn_v3 record;
    warn_action record;
    warn_claim record;
    warn_content record;
    warn_done record;
    optout1 record;
    optout_dup record;
    r2 record;
    c2 record;
    optin1 record;
    r3 record;
    c3 record;
    human1 record;
    human_dup record;

    rr record;
    v_basis uuid;
    v_t0 timestamptz;
    v_rem1 uuid;
    v_loss uuid;
    sched1 record;
    sched_loss record;
    reminder_diag jsonb;
BEGIN
    -- ---------------------------------------------------------------
    -- A. opt-out and explicit opt-in
    -- ---------------------------------------------------------------
    SELECT *
      INTO r1
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03e_ingress_1',
            'klyuch_idempotentnosti', 'db03e_in_1',
            'hash_soderzhaniya', 'db03e_hash_1',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03e_client_bot',
            'vneshnee_sobytie_id', 'db03e_event_1',
            'vneshniy_polzovatel_id', 'db03e_user_1',
            'vneshniy_dialog_id', 'db03e_chat_1',
            'vneshnee_soobshchenie_id', 'db03e_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Больше не присылайте напоминания',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03e_probe',
            'versiya_prompta', 'db03e_probe',
            'sluzhebnyy_chat_id', 'db03e_service_group',
            'payload_ishodnyy', jsonb_build_object(
                'update_id', 'db03e_event_1',
                'message', jsonb_build_object('text', 'Больше не присылайте напоминания')
            )
        )
      );

    SELECT *
      INTO c1
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03e_claim_1',
            'worker_id', 'db03e_worker',
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO content1
      FROM qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(
        jsonb_build_object(
            'operaciya_id', 'db03e_content_1',
            'zadanie_id', c1.zadanie_id,
            'worker_id', c1.vladelec_arendy,
            'nomer_vladeniya', c1.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', c1.versiya_dialoga
        )
      );

    IF content1.rezultat <> 'uspeshno'
       OR content1.soobshchenie_id IS DISTINCT FROM r1.soobshchenie_id
       OR content1.identifikator_kanala_id IS DISTINCT FROM r1.identifikator_kanala_id
       OR content1.tekst_ishodnyy IS DISTINCT FROM 'Больше не присылайте напоминания'
       OR content1.payload_ishodnyy->>'update_id' IS DISTINCT FROM 'db03e_event_1'
       OR content1.kanal IS DISTINCT FROM 'telegram'
       OR content1.akkaunt_kanala_id IS DISTINCT FROM 'db03e_client_bot'
       OR content1.vneshniy_dialog_id IS DISTINCT FROM 'db03e_chat_1' THEN
        RAISE EXCEPTION
            'DB-03E fenced source-content read failed: %',
            row_to_json(content1);
    END IF;

    SELECT *
      INTO operator_state
      FROM qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(
        jsonb_build_object(
            'operaciya_id', 'db03e_operator_state_1',
            'dialog_id', c1.dialog_id
        )
      );

    IF operator_state.rezultat <> 'uspeshno'
       OR operator_state.dialog_id IS DISTINCT FROM c1.dialog_id
       OR operator_state.vladelec IS DISTINCT FROM 'bot'
       OR operator_state.versiya_dialoga IS DISTINCT FROM c1.versiya_dialoga
       OR operator_state.sluzhebnyy_chat_id IS DISTINCT FROM 'db03e_service_group' THEN
        RAISE EXCEPTION
            'DB-03E narrow operator-state lookup failed: %',
            row_to_json(operator_state);
    END IF;

    SELECT *
      INTO optout1
      FROM qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(
        jsonb_build_object(
            'operaciya_id', 'db03e_optout_1',
            'zadanie_id', c1.zadanie_id,
            'worker_id', c1.vladelec_arendy,
            'nomer_vladeniya', c1.nomer_vladeniya,
            'dialog_id', c1.dialog_id,
            'ozhidaemaya_versiya_dialoga', c1.versiya_dialoga,
            'zapreshcheno', true,
            'prichina', 'client_explicit_optout'
        )
      );

    SELECT *
      INTO optout_dup
      FROM qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(
        jsonb_build_object(
            'operaciya_id', 'db03e_optout_1_retry',
            'zadanie_id', c1.zadanie_id,
            'worker_id', c1.vladelec_arendy,
            'nomer_vladeniya', c1.nomer_vladeniya,
            'dialog_id', c1.dialog_id,
            'ozhidaemaya_versiya_dialoga', c1.versiya_dialoga,
            'zapreshcheno', true,
            'prichina', 'client_explicit_optout'
        )
      );

    IF optout1.rezultat <> 'uspeshno'
       OR optout_dup.rezultat <> 'dublikat'
       OR NOT optout1.zapret_iniciativy
       OR optout1.versiya_dialoga <> c1.versiya_dialoga + 1
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
             WHERE i.id = r1.identifikator_kanala_id
               AND i.zapret_iniciativnyh_soobshcheniy
               AND i.vremya_zapreta_iniciativy IS NOT NULL
       )
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
             WHERE z.id = c1.zadanie_id
               AND z.status = 'otmeneno'
               AND z.kod_oshibki = 'initiative_preference_changed'
       ) THEN
        RAISE EXCEPTION
            'DB-03E opt-out/idempotency failed: first=%, duplicate=%',
            row_to_json(optout1),
            row_to_json(optout_dup);
    END IF;

    SELECT *
      INTO r2
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03e_ingress_2',
            'klyuch_idempotentnosti', 'db03e_in_2',
            'hash_soderzhaniya', 'db03e_hash_2',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03e_client_bot',
            'vneshnee_sobytie_id', 'db03e_event_2',
            'vneshniy_polzovatel_id', 'db03e_user_1',
            'vneshniy_dialog_id', 'db03e_chat_1',
            'vneshnee_soobshchenie_id', 'db03e_msg_2',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Теперь можно писать',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03e_probe',
            'versiya_prompta', 'db03e_probe',
            'sluzhebnyy_chat_id', 'db03e_service_group'
        )
      );

    SELECT *
      INTO c2
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03e_claim_2',
            'worker_id', 'db03e_worker',
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO optin1
      FROM qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(
        jsonb_build_object(
            'operaciya_id', 'db03e_optin_1',
            'zadanie_id', c2.zadanie_id,
            'worker_id', c2.vladelec_arendy,
            'nomer_vladeniya', c2.nomer_vladeniya,
            'dialog_id', c2.dialog_id,
            'ozhidaemaya_versiya_dialoga', c2.versiya_dialoga,
            'zapreshcheno', false,
            'prichina', 'client_explicit_optin'
        )
      );

    IF optin1.rezultat <> 'uspeshno'
       OR optin1.zapret_iniciativy
       OR EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
             WHERE i.id = r1.identifikator_kanala_id
               AND (
                    i.zapret_iniciativnyh_soobshcheniy
                    OR i.vremya_zapreta_iniciativy IS NOT NULL
               )
       ) THEN
        RAISE EXCEPTION
            'DB-03E explicit opt-in failed: %',
            row_to_json(optin1);
    END IF;

    -- ---------------------------------------------------------------
    -- B. human-needed signal keeps owner bot until Take
    -- ---------------------------------------------------------------
    SELECT *
      INTO r3
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03e_ingress_3',
            'klyuch_idempotentnosti', 'db03e_in_3',
            'hash_soderzhaniya', 'db03e_hash_3',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03e_client_bot',
            'vneshnee_sobytie_id', 'db03e_event_3',
            'vneshniy_polzovatel_id', 'db03e_user_1',
            'vneshniy_dialog_id', 'db03e_chat_1',
            'vneshnee_soobshchenie_id', 'db03e_msg_3',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Позовите менеджера',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03e_probe',
            'versiya_prompta', 'db03e_probe',
            'sluzhebnyy_chat_id', 'db03e_service_group'
        )
      );

    SELECT *
      INTO c3
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03e_claim_3',
            'worker_id', 'db03e_worker',
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO human1
      FROM qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(
        jsonb_build_object(
            'operaciya_id', 'db03e_human_1',
            'zadanie_id', c3.zadanie_id,
            'worker_id', c3.vladelec_arendy,
            'nomer_vladeniya', c3.nomer_vladeniya,
            'dialog_id', c3.dialog_id,
            'ozhidaemaya_versiya_dialoga', c3.versiya_dialoga,
            'prichina', 'client_requested_manager',
            'tekst', 'Клиент просит подключить менеджера.'
        )
      );

    SELECT *
      INTO human_dup
      FROM qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(
        jsonb_build_object(
            'operaciya_id', 'db03e_human_1_retry',
            'zadanie_id', c3.zadanie_id,
            'worker_id', c3.vladelec_arendy,
            'nomer_vladeniya', c3.nomer_vladeniya,
            'dialog_id', c3.dialog_id,
            'ozhidaemaya_versiya_dialoga', c3.versiya_dialoga,
            'prichina', 'client_requested_manager',
            'tekst', 'Клиент просит подключить менеджера.'
        )
      );

    IF human1.rezultat <> 'uspeshno'
       OR human_dup.rezultat <> 'dublikat'
       OR human1.vladelec <> 'bot'
       OR human1.etap <> 'peredacha_cheloveku'
       OR EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
             WHERE d.id = c3.dialog_id
               AND (
                    d.vladelec <> 'bot'
                    OR d.tekushchiy_menedzher_id IS NOT NULL
                    OR d.etap <> 'peredacha_cheloveku'
               )
       )
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
             WHERE e.id = human1.sobytie_zerkala_id
               AND e.tip_sobytiya = 'nuzhen_chelovek'
               AND e.status = 'zaplanirovano'
               AND e.payload->>'deystvie' = 'zabrat_dialog'
       ) THEN
        RAISE EXCEPTION
            'DB-03E human-needed signal/owner separation failed: first=%, duplicate=%',
            row_to_json(human1),
            row_to_json(human_dup);
    END IF;

    -- ---------------------------------------------------------------
    -- C. three thematic warnings: third warning remains sendable after exact block
    -- ---------------------------------------------------------------
    SELECT * INTO warn_in1
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,'operaciya_id','db03e_warn_in1',
            'klyuch_idempotentnosti','db03e_warn_in1','hash_soderzhaniya','db03e_warn_hash1',
            'kanal','telegram','akkaunt_kanala_id','db03e_client_bot',
            'vneshnee_sobytie_id','db03e_warn_event1',
            'vneshniy_polzovatel_id','db03e_warn_user',
            'vneshniy_dialog_id','db03e_warn_chat',
            'vneshnee_soobshchenie_id','db03e_warn_msg1',
            'tip_sobytiya','message','tip_soobshcheniya','text',
            'tekst_ishodnyy','offtopic 1','vremya_priema',clock_timestamp(),
            'versiya_workflow','db03e_probe','versiya_prompta','db03e_probe',
            'sluzhebnyy_chat_id','db03e_service_group'
        )
      );
    SELECT * INTO warn_v1
      FROM qbit_bot_pervichnogo_obrascheniya.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id','db03e_warn_v1',
            'identifikator_kanala_id',warn_in1.identifikator_kanala_id,
            'dialog_id',warn_in1.dialog_id,'soobshchenie_id',warn_in1.soobshchenie_id,
            'klassifikaciya','ne_po_teme','istochnik','db03e_probe',
            'uverennost',1,'prichina','probe','limit_narusheniy',3
        )
      );

    SELECT * INTO warn_in2
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,'operaciya_id','db03e_warn_in2',
            'klyuch_idempotentnosti','db03e_warn_in2','hash_soderzhaniya','db03e_warn_hash2',
            'kanal','telegram','akkaunt_kanala_id','db03e_client_bot',
            'vneshnee_sobytie_id','db03e_warn_event2',
            'vneshniy_polzovatel_id','db03e_warn_user',
            'vneshniy_dialog_id','db03e_warn_chat',
            'vneshnee_soobshchenie_id','db03e_warn_msg2',
            'tip_sobytiya','message','tip_soobshcheniya','text',
            'tekst_ishodnyy','offtopic 2','vremya_priema',clock_timestamp(),
            'versiya_workflow','db03e_probe','versiya_prompta','db03e_probe',
            'sluzhebnyy_chat_id','db03e_service_group'
        )
      );
    SELECT * INTO warn_v2
      FROM qbit_bot_pervichnogo_obrascheniya.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id','db03e_warn_v2',
            'identifikator_kanala_id',warn_in2.identifikator_kanala_id,
            'dialog_id',warn_in2.dialog_id,'soobshchenie_id',warn_in2.soobshchenie_id,
            'klassifikaciya','ne_po_teme','istochnik','db03e_probe',
            'uverennost',1,'prichina','probe','limit_narusheniy',3
        )
      );

    SELECT * INTO warn_in3
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,'operaciya_id','db03e_warn_in3',
            'klyuch_idempotentnosti','db03e_warn_in3','hash_soderzhaniya','db03e_warn_hash3',
            'kanal','telegram','akkaunt_kanala_id','db03e_client_bot',
            'vneshnee_sobytie_id','db03e_warn_event3',
            'vneshniy_polzovatel_id','db03e_warn_user',
            'vneshniy_dialog_id','db03e_warn_chat',
            'vneshnee_soobshchenie_id','db03e_warn_msg3',
            'tip_sobytiya','message','tip_soobshcheniya','text',
            'tekst_ishodnyy','offtopic 3','vremya_priema',clock_timestamp(),
            'versiya_workflow','db03e_probe','versiya_prompta','db03e_probe',
            'sluzhebnyy_chat_id','db03e_service_group'
        )
      );
    SELECT * INTO warn_v3
      FROM qbit_bot_pervichnogo_obrascheniya.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id','db03e_warn_v3',
            'identifikator_kanala_id',warn_in3.identifikator_kanala_id,
            'dialog_id',warn_in3.dialog_id,'soobshchenie_id',warn_in3.soobshchenie_id,
            'klassifikaciya','ne_po_teme','istochnik','db03e_probe',
            'uverennost',1,'prichina','probe','limit_narusheniy',3
        )
      );

    SELECT * INTO warn_action
      FROM qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(
        jsonb_build_object(
            'operaciya_id','db03e_warn_action3',
            'dialog_id',warn_in3.dialog_id,
            'soobshchenie_id',warn_in3.soobshchenie_id,
            'ozhidaemaya_versiya_dialoga',warn_v3.versiya_dialoga,
            'tekst_ishodnyy','Третье предупреждение.',
            'tekst_obezlichennyy','Третье предупреждение.'
        )
      );

    SELECT * INTO warn_claim
      FROM qbit_bot_pervichnogo_obrascheniya.zabrat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id','db03e_warn_claim3',
            'worker_id','db03e_warning_sender',
            'arenda_sekund',120
        )
      );

    SELECT * INTO warn_content
      FROM qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03e_warn_content3',
            'deystvie_id',warn_claim.deystvie_id,
            'worker_id','db03e_warning_sender',
            'nomer_vladeniya',warn_claim.nomer_vladeniya
        )
      );

    SELECT * INTO warn_done
      FROM qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id','db03e_warn_done3',
            'deystvie_id',warn_claim.deystvie_id,
            'worker_id','db03e_warning_sender',
            'nomer_vladeniya',warn_claim.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_id','db03e_warn_external3',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    IF warn_v1.nomer_narusheniya<>1
       OR warn_v2.nomer_narusheniya<>2
       OR warn_v3.nomer_narusheniya<>3
       OR NOT warn_v3.logicheski_zablokirovan
       OR warn_action.rezultat<>'uspeshno'
       OR NOT warn_action.logicheski_zablokirovan
       OR warn_claim.rezultat<>'uspeshno'
       OR warn_claim.deystvie_id IS DISTINCT FROM warn_action.deystvie_id
       OR warn_content.rezultat<>'uspeshno'
       OR warn_content.tekst_ishodnyy IS DISTINCT FROM 'Третье предупреждение.'
       OR warn_done.rezultat<>'uspeshno'
       OR warn_done.status_deystviya<>'podtverzhdeno' THEN
        RAISE EXCEPTION
            'DB-03E third thematic warning / blocked sender exception failed: v1=%, v2=%, v3=%, action=%, claim=%, done=%',
            row_to_json(warn_v1),row_to_json(warn_v2),row_to_json(warn_v3),
            row_to_json(warn_action),row_to_json(warn_claim),row_to_json(warn_done);
    END IF;

    -- ---------------------------------------------------------------
    -- D. due scheduler: reminder branch + loss branch

    -- ---------------------------------------------------------------
    SELECT *
      INTO rr
      FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03e_rem_ingress',
            'klyuch_idempotentnosti', 'db03e_rem_in',
            'hash_soderzhaniya', 'db03e_rem_hash',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03e_reminder_bot',
            'vneshnee_sobytie_id', 'db03e_rem_event',
            'vneshniy_polzovatel_id', 'db03e_user_rem',
            'vneshniy_dialog_id', 'db03e_chat_rem',
            'vneshnee_soobshchenie_id', 'db03e_rem_msg',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Тест напоминаний',
            'vremya_priema', clock_timestamp() - interval '20 minutes',
            'versiya_workflow', 'db03e_probe',
            'versiya_prompta', 'db03e_probe',
            'sluzhebnyy_chat_id', 'db03e_service_group'
        )
      );

    -- Waiting starts after the synthetic client input, so DB-03C4's
    -- "newer client input" final recheck must allow reminder1.
    v_t0 := clock_timestamp() - interval '10 minutes';

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
        dialog_id,
        napravlenie,
        avtor,
        vid,
        tekst_ishodnyy,
        tekst_obezlichennyy,
        vremya_priema,
        vremya_otpravki,
        status_otpravki,
        ozhidaetsya_otvet,
        trassirovka_id
    )
    VALUES (
        rr.dialog_id,
        'ishodyashchee',
        'bot',
        'text',
        'Пожалуйста, уточните ваш ответ.',
        'Пожалуйста, уточните ваш ответ.',
        v_t0,
        v_t0,
        'podtverzhdeno',
        true,
        'db03e_rem_basis'
    )
    RETURNING id
    INTO v_basis;

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
       SET status = 'ozhidaet_otveta',
           ozhidaetsya_otvet = true,
           t0 = v_t0,
           pokolenie_ozhidaniya = 1,
           poslednee_ishodyashchee_id = v_basis
     WHERE d.id = rr.dialog_id;

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
        rr.dialog_id,
        'napominanie_1',
        v_t0,
        v_basis,
        1,
        clock_timestamp() - interval '1 minute',
        clock_timestamp() + interval '1 hour',
        'zaplanirovano',
        'db03e_probe'
    )
    RETURNING id
    INTO v_rem1;

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
        rr.dialog_id,
        'napominanie_2',
        v_t0,
        v_basis,
        1,
        clock_timestamp() + interval '3 hours',
        clock_timestamp() + interval '4 hours',
        'zaplanirovano',
        'db03e_probe'
    );

    SELECT jsonb_build_object(
        'vladelec', d.vladelec, 'status', d.status,
        'ozhidaetsya_otvet', d.ozhidaetsya_otvet,
        'dialog_t0', d.t0, 'reminder_t0', n.t0,
        'dialog_generation', d.pokolenie_ozhidaniya,
        'reminder_generation', n.pokolenie_ozhidaniya,
        'logicheski_zablokirovan', i.logicheski_zablokirovan,
        'zapret_iniciativy', i.zapret_iniciativnyh_soobshcheniy,
        'basis_status', basis.status_otpravki,
        'newer_client_input', EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya mi WHERE mi.dialog_id=d.id AND mi.napravlenie='vhodyashchee' AND mi.avtor='klient' AND mi.vremya_priema > n.t0)
    ) INTO reminder_diag
    FROM qbit_bot_pervichnogo_obrascheniya.napominaniya n
    JOIN qbit_bot_pervichnogo_obrascheniya.dialogi d ON d.id=n.dialog_id
    JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov i ON i.id=d.identifikator_kanala_id
    LEFT JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya basis ON basis.id=n.soobshchenie_osnovanie_id
    WHERE n.id=v_rem1;

    SELECT *
      INTO sched1
      FROM qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(
        jsonb_build_object(
            'operaciya_id', 'db03e_scheduler_1',
            'tekst_napominaniya_1', 'Напоминаем: ждём ваш ответ.',
            'tekst_napominaniya_2', 'Ещё раз напоминаем: ждём ваш ответ.',
            'poterya_posle_sekund', 86400,
            'vremya_proverki', clock_timestamp()
        )
      );

    IF sched1.rezultat NOT IN ('uspeshno', 'dublikat')
       OR sched1.napominanie_id IS DISTINCT FROM v_rem1
       OR sched1.tip_napominaniya <> 'napominanie_1'
       OR sched1.reshenie <> 'otpravit'
       OR sched1.deystvie_id IS NULL THEN
        RAISE EXCEPTION
            'DB-03E due reminder scheduler branch failed: scheduler=%, precheck=%',
            row_to_json(sched1), reminder_diag;
    END IF;

    -- Prepare the mandatory durable fact for a valid loss-check: reminder2
    -- must already have a confirmed actual send in the same generation/t0.
    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_rem2
       SET status = 'podtverzhdeno',
           vremya_fakticheskoy_otpravki = clock_timestamp() - interval '2 minutes',
           vremya_obnovleniya = clock_timestamp()
     WHERE n_rem2.dialog_id = rr.dialog_id
       AND n_rem2.pokolenie_ozhidaniya = 1
       AND n_rem2.tip = 'napominanie_2';

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
        rr.dialog_id,
        'proverka_poteri',
        v_t0,
        v_basis,
        1,
        clock_timestamp() - interval '30 seconds',
        clock_timestamp() + interval '1 hour',
        'zaplanirovano',
        'db03e_probe'
    )
    RETURNING id
    INTO v_loss;

    SELECT *
      INTO sched_loss
      FROM qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(
        jsonb_build_object(
            'operaciya_id', 'db03e_scheduler_loss',
            'tekst_napominaniya_1', 'Напоминаем: ждём ваш ответ.',
            'tekst_napominaniya_2', 'Ещё раз напоминаем: ждём ваш ответ.',
            'poterya_posle_sekund', 86400,
            'vremya_proverki', clock_timestamp()
        )
      );

    IF sched_loss.rezultat <> 'uspeshno'
       OR sched_loss.napominanie_id IS DISTINCT FROM v_loss
       OR sched_loss.tip_napominaniya <> 'proverka_poteri'
       OR sched_loss.reshenie <> 'proverka_poteri'
       OR sched_loss.status_dialoga <> 'zavershen'
       OR sched_loss.rezultat_dialoga <> 'net_otveta'
       OR sched_loss.versiya_dialoga IS NULL
       OR EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
             WHERE n.id = v_loss
               AND n.status <> 'podtverzhdeno'
       ) THEN
        RAISE EXCEPTION
            'DB-03E due loss scheduler branch failed: %',
            row_to_json(sched_loss);
    END IF;
END
$db03e$;

ROLLBACK TO SAVEPOINT db03e_probe;
RELEASE SAVEPOINT db03e_probe;

-- ===========================================================================
-- 11. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03e$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03e_client_bot'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i_rem
         WHERE i_rem.akkaunt_kanala_id = 'db03e_reminder_bot'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id IN ('db03e_client_bot', 'db03e_reminder_bot')
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS z
         WHERE z.klyuch_idempotentnosti LIKE 'nuzhen_chelovek:%'
           AND z.payload->>'ishodnoe_zadanie_id' IS NOT NULL
           AND EXISTS (
                SELECT 1
                  FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS j
                 WHERE j.id::text = z.payload->>'ishodnoe_zadanie_id'
                   AND j.kod_oshibki = 'nuzhen_chelovek'
           )
    ) THEN
        RAISE EXCEPTION 'DB-03E probe rows remain after SAVEPOINT rollback';
    END IF;
END
$db03e$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 12. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03e_status', 'applied',
    'database', current_database(),
    'schema', 'qbit_bot_pervichnogo_obrascheniya',
    'functions_ok',
    (
        SELECT count(*) = 7
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
                'poluchit_soderzhimoe_zadaniya',
                'poluchit_sostoyanie_operatora',
                'sozdat_preduprezhdenie_tematiky',
                'poluchit_soderzhimoe_ishodyashchego',
                'ustanovit_zapret_iniciativy',
                'zaprosit_cheloveka',
                'obrabotat_sleduyushchee_napominanie'
           )
           AND p.prosecdef = true
    ),
    'bot_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(jsonb)',
        'EXECUTE'
    ),
    'service_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_sostoyanie_operatora(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_zadaniya(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.ustanovit_zapret_iniciativy(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.zaprosit_cheloveka(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.obrabotat_sleduyushchee_napominanie(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.sozdat_preduprezhdenie_tematiky(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.poluchit_soderzhimoe_ishodyashchego(jsonb)',
        'EXECUTE'
    ),
    'runtime_direct_dml_denied',
    NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND (
                pg_catalog.has_table_privilege('qbit_test_bot', c.oid, 'SELECT')
                OR pg_catalog.has_table_privilege('qbit_test_bot', c.oid, 'INSERT')
                OR pg_catalog.has_table_privilege('qbit_test_bot', c.oid, 'UPDATE')
                OR pg_catalog.has_table_privilege('qbit_test_bot', c.oid, 'DELETE')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy', c.oid, 'SELECT')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy', c.oid, 'INSERT')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy', c.oid, 'UPDATE')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy', c.oid, 'DELETE')
           )
    ),
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03e_client_bot'
    ),
    'production_untouched', true,
    'migration_version', 'DB-03E_v0.11',
    'next_stage', 'PRE-02E_runtime_then_WF-02B2'
) AS db03e_result;