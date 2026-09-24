-- DB-03C2 v0.1: context, memory, rate limit, thematic guard and admin unblock
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02, DB-03A, DB-03B and DB-03C1 v0.3 successfully applied.
--
-- CREATES 5 SECURITY DEFINER FUNCTIONS
--   poluchit_kontekst_dialoga(jsonb)       -> qbit_test_bot
--   sohranit_fakty_i_pamyat(jsonb)         -> qbit_test_bot
--   proverit_limit_chastoty(jsonb)         -> qbit_test_bot
--   zapisat_narushenie_tematiky(jsonb)     -> qbit_test_bot
--   razblokirovat_polzovatelya(jsonb)      -> qbit_test_dash_admin
--
-- SECURITY / BEHAVIOR
--   * AI-safe context is returned separately from local protected PII.
--   * Memory save uses CAS on dialog version and memory version.
--   * PII fact values are never copied as JSON strings into AI fact cache.
--   * Rate limit counts stored logical incoming messages, not raw provider events.
--   * Thematic counter is changed only by confirmed thematic violations.
--   * Third/limit violation may logically block the channel identity, bump dialog
--     version and cancel pending waiting/reminders.
--   * Administrative unblock is audited and does not grant direct table DML.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * Probe rows are rolled back to SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03C2 migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03c2$
DECLARE
    v_required_table text;
    v_required_fn text;
    v_new_fn text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03C2 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03C2 must run from trusted postgres session. session_user=%',
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

    FOREACH v_required_table IN ARRAY ARRAY[
        'polzovateli',
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'transkripcii_golosa',
        'fakty_dialoga',
        'sootvetstviya_pii',
        'narusheniya_tematiky',
        'sobytiya_dialogov',
        'zadaniya_obrabotki',
        'napominaniya',
        'pamyat_dialoga',
        'zhurnal_administrirovaniya'
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
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie'
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
                'Required DB-03C1 function qbit_test.% is missing',
                v_required_fn;
        END IF;
    END LOOP;

    FOREACH v_new_fn IN ARRAY ARRAY[
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya'
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
                'DB-03C2 function qbit_test.% already exists; stop instead of overwriting',
                v_new_fn;
        END IF;
    END LOOP;

    IF pg_catalog.to_regclass(
        'qbit_test.uq_narusheniya_soobshchenie'
    ) IS NULL THEN
        RAISE EXCEPTION
            'DB-02 unique violation-per-message index is missing';
    END IF;
END
$db03c2$;

SET LOCAL ROLE qbit_test_owner;

-- ===========================================================================
-- 1. AI-SAFE CONTEXT
-- ===========================================================================

CREATE FUNCTION qbit_test.poluchit_kontekst_dialoga(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    zadanie_id uuid,
    versiya_dialoga bigint,
    versiya_pamyati bigint,
    vladelec text,
    status_dialoga text,
    logicheski_zablokirovan boolean,
    mozhno_ai boolean,
    ai_kontekst jsonb,
    lokalnye_pii jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_dialog_id uuid;
    v_job_id uuid;
    v_expected_version bigint;

    v_identity_id uuid;
    v_current_version bigint;
    v_owner text;
    v_status text;
    v_stage text;
    v_blocked boolean;
    v_memory_version bigint := 0;
    v_summary text;
    v_window jsonb := '[]'::jsonb;
    v_memory_facts jsonb := '{}'::jsonb;
    v_processed_id uuid;
    v_processed_time timestamptz;
    v_job_dialog uuid;
    v_job_version bigint;
    v_job_status text;

    v_ai_facts jsonb := '{}'::jsonb;
    v_new_messages jsonb := '[]'::jsonb;
    v_local_facts jsonb := '[]'::jsonb;
    v_local_map jsonb := '[]'::jsonb;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::bigint, NULL::bigint,
            NULL::text, NULL::text, NULL::boolean, false,
            '{}'::jsonb, '{}'::jsonb;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_expected_version := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;

    IF v_operaciya IS NULL
       OR v_dialog_id IS NULL
       OR v_job_id IS NULL
       OR v_expected_version IS NULL
       OR v_expected_version < 1 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operaciya_id, dialog_id, zadanie_id и ожидаемая версия диалога.'::text,
            NULL::timestamptz,
            v_dialog_id, v_job_id, NULL::bigint, NULL::bigint,
            NULL::text, NULL::text, NULL::boolean, false,
            '{}'::jsonb, '{}'::jsonb;
        RETURN;
    END IF;

    SELECT
        d.identifikator_kanala_id,
        d.versiya_dialoga,
        d.vladelec,
        d.status,
        d.etap,
        i.logicheski_zablokirovan
      INTO
        v_identity_id,
        v_current_version,
        v_owner,
        v_status,
        v_stage,
        v_blocked
      FROM qbit_test.dialogi AS d
      JOIN qbit_test.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
     WHERE d.id = v_dialog_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_nayden'::text,
            'Диалог не найден.'::text, NULL::timestamptz,
            v_dialog_id, v_job_id, NULL::bigint, NULL::bigint,
            NULL::text, NULL::text, NULL::boolean, false,
            '{}'::jsonb, '{}'::jsonb;
        RETURN;
    END IF;

    SELECT z.dialog_id, z.versiya_dialoga, z.status
      INTO v_job_dialog, v_job_version, v_job_status
      FROM qbit_test.zadaniya_obrabotki AS z
     WHERE z.id = v_job_id;

    IF NOT FOUND
       OR v_job_dialog IS DISTINCT FROM v_dialog_id
       OR v_job_status NOT IN ('ozhidaet', 'v_rabote', 'povtor') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'zadanie_ne_sootvetstvuet_dialogu'::text,
            'Задание не найдено, относится к другому диалогу или уже терминальное.'::text,
            NULL::timestamptz,
            v_dialog_id, v_job_id, v_current_version, 0::bigint,
            v_owner, v_status, v_blocked, false,
            '{}'::jsonb, '{}'::jsonb;
        RETURN;
    END IF;

    IF v_current_version IS DISTINCT FROM v_expected_version
       OR v_job_version IS DISTINCT FROM v_expected_version THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Версия диалога изменилась после постановки/получения задания.'::text,
            NULL::timestamptz,
            v_dialog_id, v_job_id, v_current_version, 0::bigint,
            v_owner, v_status, v_blocked, false,
            '{}'::jsonb, '{}'::jsonb;
        RETURN;
    END IF;

    SELECT
        p.versiya_pamyati,
        p.rezyume,
        p.poslednie_soobshcheniya,
        p.podtverzhdennye_fakty,
        p.obrabotano_do_id
      INTO
        v_memory_version,
        v_summary,
        v_window,
        v_memory_facts,
        v_processed_id
      FROM qbit_test.pamyat_dialoga AS p
     WHERE p.dialog_id = v_dialog_id;

    IF NOT FOUND THEN
        v_memory_version := 0;
        v_summary := NULL;
        v_window := '[]'::jsonb;
        v_memory_facts := '{}'::jsonb;
        v_processed_id := NULL;
    END IF;

    IF v_processed_id IS NOT NULL THEN
        SELECT m.vremya_sozdaniya
          INTO v_processed_time
          FROM qbit_test.soobshcheniya AS m
         WHERE m.id = v_processed_id
           AND m.dialog_id = v_dialog_id;
    END IF;

    SELECT COALESCE(
        jsonb_object_agg(f.kod_polya, f.znachenie_dlya_ai),
        '{}'::jsonb
    )
      INTO v_ai_facts
      FROM qbit_test.fakty_dialoga AS f
     WHERE f.dialog_id = v_dialog_id
       AND f.zamenen_faktom_id IS NULL
       AND f.podtverzhden = true
       AND f.znachenie_dlya_ai IS NOT NULL
       AND (
            f.deystvitelno_do IS NULL
            OR f.deystvitelno_do >= clock_timestamp()
       );

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'soobshchenie_id', x.id,
                'napravlenie', x.napravlenie,
                'avtor', x.avtor,
                'vid', x.vid,
                'tekst', x.safe_text,
                'vremya', x.vremya_priema
            )
            ORDER BY x.vremya_sozdaniya, x.id
        ),
        '[]'::jsonb
    )
      INTO v_new_messages
      FROM (
            SELECT
                m.id,
                m.napravlenie,
                m.avtor,
                m.vid,
                COALESCE(
                    m.tekst_obezlichennyy,
                    tg.tekst_obezlichennyy
                ) AS safe_text,
                m.vremya_priema,
                m.vremya_sozdaniya
              FROM qbit_test.soobshcheniya AS m
              LEFT JOIN qbit_test.transkripcii_golosa AS tg
                ON tg.soobshchenie_id = m.id
             WHERE m.dialog_id = v_dialog_id
               AND (
                    v_processed_time IS NULL
                    OR (m.vremya_sozdaniya, m.id)
                       > (v_processed_time, v_processed_id)
               )
               AND COALESCE(
                    m.tekst_obezlichennyy,
                    tg.tekst_obezlichennyy
               ) IS NOT NULL
      ) AS x;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'kod_polya', f.kod_polya,
                'znachenie_zashchishchennoe', f.znachenie_zashchishchennoe,
                'soobshchenie_dokazatelstvo_id', f.soobshchenie_dokazatelstvo_id,
                'vremya_fakta', f.vremya_fakta
            )
            ORDER BY f.kod_polya
        ),
        '[]'::jsonb
    )
      INTO v_local_facts
      FROM qbit_test.fakty_dialoga AS f
     WHERE f.dialog_id = v_dialog_id
       AND f.zamenen_faktom_id IS NULL
       AND f.podtverzhden = true
       AND f.eto_pii = true
       AND (
            f.deystvitelno_do IS NULL
            OR f.deystvitelno_do >= clock_timestamp()
       );

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'psevdometka', p.psevdometka,
                'tip_pii', p.tip_pii,
                'znachenie_zashchishchennoe', p.znachenie_zashchishchennoe
            )
            ORDER BY p.psevdometka
        ),
        '[]'::jsonb
    )
      INTO v_local_map
      FROM qbit_test.sootvetstviya_pii AS p
     WHERE p.dialog_id = v_dialog_id
       AND (
            p.deystvitelno_do IS NULL
            OR p.deystvitelno_do >= clock_timestamp()
       );

    IF v_owner <> 'bot'
       OR v_blocked
       OR v_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya,
            'otkaz'::text,
            CASE
                WHEN v_blocked THEN 'logicheski_zablokirovan'
                WHEN v_owner <> 'bot' THEN 'vladelec_ne_bot'
                ELSE 'dialog_ne_aktiven'
            END::text,
            'AI-обработка запрещена текущим состоянием диалога/идентичности.'::text,
            NULL::timestamptz,
            v_dialog_id, v_job_id, v_current_version, v_memory_version,
            v_owner, v_status, v_blocked, false,
            jsonb_build_object(
                'dialog', jsonb_build_object(
                    'id', v_dialog_id,
                    'etap', v_stage,
                    'status', v_status
                )
            ),
            jsonb_build_object(
                'fakty', v_local_facts,
                'sootvetstviya', v_local_map
            );
        RETURN;
    END IF;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Возвращён AI-safe контекст и отдельно локальные PII.'::text,
        NULL::timestamptz,
        v_dialog_id, v_job_id, v_current_version, v_memory_version,
        v_owner, v_status, v_blocked, true,
        jsonb_build_object(
            'dialog', jsonb_build_object(
                'id', v_dialog_id,
                'etap', v_stage,
                'status', v_status,
                'versiya_dialoga', v_current_version
            ),
            'pamyat', jsonb_build_object(
                'rezyume', v_summary,
                'poslednie_soobshcheniya', COALESCE(v_window, '[]'::jsonb),
                'podtverzhdennye_fakty', COALESCE(v_memory_facts, '{}'::jsonb),
                'versiya_pamyati', v_memory_version
            ),
            'fakty', COALESCE(v_ai_facts, '{}'::jsonb),
            'novye_soobshcheniya', COALESCE(v_new_messages, '[]'::jsonb)
        ),
        jsonb_build_object(
            'fakty', v_local_facts,
            'sootvetstviya', v_local_map
        );
END
$fn$;

COMMENT ON FUNCTION qbit_test.poluchit_kontekst_dialoga(jsonb) IS
'DB-03C2: проверяет job/dialog version и возвращает AI-safe память/факты/новые обезличенные сообщения отдельно от локальных protected PII; при block/human/closed mozhno_ai=false.';

-- ===========================================================================
-- 2. FACTS + MEMORY CAS
-- ===========================================================================

CREATE FUNCTION qbit_test.sohranit_fakty_i_pamyat(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    versiya_dialoga bigint,
    versiya_pamyati bigint,
    kolichestvo_novyh_faktov integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_dialog_id uuid;
    v_expected_dialog bigint;
    v_expected_memory bigint;
    v_summary text;
    v_window jsonb;
    v_processed_id uuid;
    v_tokens integer;
    v_facts jsonb;

    v_dialog_version bigint;
    v_user_id uuid;
    v_previous_dialog uuid;
    v_memory_exists boolean := false;
    v_current_memory bigint := 0;
    v_new_memory bigint;

    v_item jsonb;
    v_window_message_id uuid;
    v_window_text text;
    v_window_direction text;
    v_window_author text;
    v_window_type text;
    v_safe_text text;
    v_db_direction text;
    v_db_author text;
    v_db_type text;

    v_code text;
    v_protected jsonb;
    v_ai jsonb;
    v_is_pii boolean;
    v_confirmed boolean;
    v_source text;
    v_evidence uuid;
    v_fact_time timestamptz;
    v_expiry timestamptz;
    v_evidence_dialog uuid;
    v_current_fact record;
    v_has_current_fact boolean := false;
    v_new_fact_id uuid;
    v_inserted integer := 0;
    v_cache jsonb := '{}'::jsonb;
    v_pii_value text;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::bigint, NULL::bigint, 0;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_expected_dialog := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_expected_memory := COALESCE(
        NULLIF(p_dannye->>'ozhidaemaya_versiya_pamyati', '')::bigint,
        0
    );
    v_summary := p_dannye->>'rezyume';
    v_window := COALESCE(p_dannye->'poslednie_soobshcheniya', '[]'::jsonb);
    v_processed_id := NULLIF(p_dannye->>'obrabotano_do_id', '')::uuid;
    v_tokens := COALESCE((p_dannye->>'kolichestvo_tokenov')::integer, 0);
    v_facts := COALESCE(p_dannye->'fakty', '[]'::jsonb);

    IF v_operaciya IS NULL
       OR v_dialog_id IS NULL
       OR v_expected_dialog IS NULL
       OR v_expected_dialog < 1
       OR v_expected_memory < 0
       OR v_tokens < 0
       OR jsonb_typeof(v_window) <> 'array'
       OR jsonb_array_length(v_window) > 5
       OR jsonb_typeof(v_facts) <> 'array' THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректные версии/окно/факты памяти.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::bigint, NULL::bigint, 0;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM (
                SELECT
                    NULLIF(btrim(x.value->>'kod_polya'), '') AS code,
                    count(*) AS c
                  FROM jsonb_array_elements(v_facts) AS x(value)
                 GROUP BY NULLIF(btrim(x.value->>'kod_polya'), '')
          ) AS q
         WHERE q.code IS NULL
            OR q.c > 1
    ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dubl_kodov_faktov'::text,
            'В одном сохранении каждый kod_polya должен встречаться максимум один раз.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::bigint, NULL::bigint, 0;
        RETURN;
    END IF;

    SELECT
        d.versiya_dialoga,
        d.polzovatel_id,
        d.predydushchiy_dialog_id
      INTO
        v_dialog_version,
        v_user_id,
        v_previous_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_nayden'::text,
            'Диалог не найден.'::text, NULL::timestamptz,
            v_dialog_id, NULL::bigint, NULL::bigint, 0;
        RETURN;
    END IF;

    IF v_dialog_version IS DISTINCT FROM v_expected_dialog THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Диалог изменился; результат обработки устарел.'::text,
            NULL::timestamptz,
            v_dialog_id, v_dialog_version, NULL::bigint, 0;
        RETURN;
    END IF;

    SELECT p.versiya_pamyati
      INTO v_current_memory
      FROM qbit_test.pamyat_dialoga AS p
     WHERE p.dialog_id = v_dialog_id
     FOR UPDATE;

    v_memory_exists := FOUND;
    IF NOT v_memory_exists THEN
        v_current_memory := 0;
    END IF;

    IF v_current_memory IS DISTINCT FROM v_expected_memory THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_memory_version'::text,
            'Память уже была изменена другим выполнением.'::text,
            NULL::timestamptz,
            v_dialog_id, v_dialog_version, v_current_memory, 0;
        RETURN;
    END IF;

    IF v_processed_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
              FROM qbit_test.soobshcheniya AS m
             WHERE m.id = v_processed_id
               AND m.dialog_id = v_dialog_id
       ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'obrabotano_do_ne_iz_dialoga'::text,
            'obrabotano_do_id не относится к этому диалогу.'::text,
            NULL::timestamptz,
            v_dialog_id, v_dialog_version, v_current_memory, 0;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM (
                SELECT
                    NULLIF(x.value->>'soobshchenie_id', '') AS message_id,
                    count(*) AS c
                  FROM jsonb_array_elements(v_window) AS x(value)
                 GROUP BY NULLIF(x.value->>'soobshchenie_id', '')
          ) AS q
         WHERE q.message_id IS NULL
            OR q.c > 1
    ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnoe_okno'::text,
            'Окно памяти не должно содержать пустые/повторяющиеся message ID.'::text,
            NULL::timestamptz,
            v_dialog_id, v_dialog_version, v_current_memory, 0;
        RETURN;
    END IF;

    IF jsonb_array_length(v_window) > 0
       AND (
            v_processed_id IS NULL
            OR NOT EXISTS (
                SELECT 1
                  FROM jsonb_array_elements(v_window) AS x(value)
                 WHERE NULLIF(x.value->>'soobshchenie_id', '')::uuid = v_processed_id
            )
       ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'obrabotano_do_ne_v_okne'::text,
            'При непустом окне obrabotano_do_id должен быть одним из сообщений окна.'::text,
            NULL::timestamptz,
            v_dialog_id, v_dialog_version, v_current_memory, 0;
        RETURN;
    END IF;

    FOR v_item IN
        SELECT x.value
          FROM jsonb_array_elements(v_window) AS x(value)
    LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RETURN QUERY SELECT
                v_operaciya, 'otkaz'::text, 'nekorrektnoe_okno'::text,
                'Каждый элемент окна памяти должен быть JSON object.'::text,
                NULL::timestamptz,
                v_dialog_id, v_dialog_version, v_current_memory, 0;
            RETURN;
        END IF;

        v_window_message_id := NULLIF(v_item->>'soobshchenie_id', '')::uuid;
        v_window_text := v_item->>'tekst';
        v_window_direction := NULLIF(v_item->>'napravlenie', '');
        v_window_author := NULLIF(v_item->>'avtor', '');
        v_window_type := NULLIF(v_item->>'vid', '');

        SELECT
            COALESCE(
                m.tekst_obezlichennyy,
                tg.tekst_obezlichennyy
            ),
            m.napravlenie,
            m.avtor,
            m.vid
          INTO
            v_safe_text,
            v_db_direction,
            v_db_author,
            v_db_type
          FROM qbit_test.soobshcheniya AS m
          LEFT JOIN qbit_test.transkripcii_golosa AS tg
            ON tg.soobshchenie_id = m.id
         WHERE m.id = v_window_message_id
           AND m.dialog_id = v_dialog_id;

        IF NOT FOUND
           OR v_safe_text IS NULL
           OR v_window_text IS DISTINCT FROM v_safe_text
           OR v_window_direction IS DISTINCT FROM v_db_direction
           OR v_window_author IS DISTINCT FROM v_db_author
           OR v_window_type IS DISTINCT FROM v_db_type THEN
            RETURN QUERY SELECT
                v_operaciya, 'otkaz'::text, 'okno_ne_obezlicheno'::text,
                'Окно памяти должно точно соответствовать сохранённым direction/author/type и обезличенному тексту.'::text,
                NULL::timestamptz,
                v_dialog_id, v_dialog_version, v_current_memory, 0;
            RETURN;
        END IF;
    END LOOP;

    -- Summary is generated from deidentified context; additionally reject any
    -- exact protected PII value already known for this dialog.
    IF v_summary IS NOT NULL THEN
        FOR v_pii_value IN
            SELECT p.znachenie_zashchishchennoe
              FROM qbit_test.sootvetstviya_pii AS p
             WHERE p.dialog_id = v_dialog_id
               AND p.znachenie_zashchishchennoe IS NOT NULL
               AND length(p.znachenie_zashchishchennoe) >= 3
        LOOP
            IF position(v_pii_value IN v_summary) > 0 THEN
                RETURN QUERY SELECT
                    v_operaciya, 'otkaz'::text, 'rezyume_soderzhit_pii'::text,
                    'Резюме содержит локальное protected PII и не может быть сохранено в AI-memory.'::text,
                    NULL::timestamptz,
                    v_dialog_id, v_dialog_version, v_current_memory, 0;
                RETURN;
            END IF;
        END LOOP;
    END IF;

    -- Validate the entire facts array before any fact mutation.
    FOR v_item IN
        SELECT x.value
          FROM jsonb_array_elements(v_facts) AS x(value)
    LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RETURN QUERY SELECT
                v_operaciya, 'otkaz'::text, 'nekorrektnyy_fakt'::text,
                'Каждый факт должен быть JSON object.'::text,
                NULL::timestamptz,
                v_dialog_id, v_dialog_version, v_current_memory, 0;
            RETURN;
        END IF;

        v_code := NULLIF(btrim(v_item->>'kod_polya'), '');
        v_protected := v_item->'znachenie_zashchishchennoe';
        v_ai := v_item->'znachenie_dlya_ai';
        v_is_pii := COALESCE((v_item->>'eto_pii')::boolean, false);
        v_confirmed := COALESCE((v_item->>'podtverzhden')::boolean, false);
        v_source := NULLIF(btrim(v_item->>'istochnik'), '');
        v_evidence := NULLIF(v_item->>'soobshchenie_dokazatelstvo_id', '')::uuid;
        v_fact_time := NULLIF(v_item->>'vremya_fakta', '')::timestamptz;
        v_expiry := NULLIF(v_item->>'deystvitelno_do', '')::timestamptz;

        IF v_code IS NULL
           OR NOT v_confirmed
           OR v_source IS NULL
           OR v_evidence IS NULL
           OR v_fact_time IS NULL
           OR (v_expiry IS NOT NULL AND v_expiry < v_fact_time)
           OR (
                v_is_pii
                AND v_protected IS NULL
           )
           OR (
                v_is_pii
                AND v_ai IS NOT NULL
                AND jsonb_typeof(v_ai) NOT IN ('boolean', 'object', 'array')
           )
        THEN
            RETURN QUERY SELECT
                v_operaciya, 'otkaz'::text, 'nekorrektnyy_fakt'::text,
                'Подтверждённый факт требует code/source/evidence/time; PII AI-value не может быть scalar string/number.'::text,
                NULL::timestamptz,
                v_dialog_id, v_dialog_version, v_current_memory, 0;
            RETURN;
        END IF;

        SELECT m.dialog_id
          INTO v_evidence_dialog
          FROM qbit_test.soobshcheniya AS m
         WHERE m.id = v_evidence;

        IF NOT FOUND
           OR v_evidence_dialog IS DISTINCT FROM v_dialog_id THEN
            RETURN QUERY SELECT
                v_operaciya, 'otkaz'::text, 'dokazatelstvo_ne_iz_dialoga'::text,
                'Сообщение-доказательство не относится к этому диалогу.'::text,
                NULL::timestamptz,
                v_dialog_id, v_dialog_version, v_current_memory, 0;
            RETURN;
        END IF;
    END LOOP;

    -- Insert/replace facts only after complete validation.
    FOR v_item IN
        SELECT x.value
          FROM jsonb_array_elements(v_facts) AS x(value)
    LOOP
        v_code := NULLIF(btrim(v_item->>'kod_polya'), '');
        v_protected := v_item->'znachenie_zashchishchennoe';
        v_ai := v_item->'znachenie_dlya_ai';
        v_is_pii := COALESCE((v_item->>'eto_pii')::boolean, false);
        v_source := NULLIF(btrim(v_item->>'istochnik'), '');
        v_evidence := NULLIF(v_item->>'soobshchenie_dokazatelstvo_id', '')::uuid;
        v_fact_time := NULLIF(v_item->>'vremya_fakta', '')::timestamptz;
        v_expiry := NULLIF(v_item->>'deystvitelno_do', '')::timestamptz;

        SELECT f.*
          INTO v_current_fact
          FROM qbit_test.fakty_dialoga AS f
         WHERE f.dialog_id = v_dialog_id
           AND f.kod_polya = v_code
           AND f.zamenen_faktom_id IS NULL
         ORDER BY f.vremya_fakta DESC, f.vremya_sozdaniya DESC
         LIMIT 1
         FOR UPDATE;

        v_has_current_fact := FOUND;

        IF v_has_current_fact THEN
            IF v_current_fact.znachenie_zashchishchennoe IS NOT DISTINCT FROM v_protected
               AND v_current_fact.znachenie_dlya_ai IS NOT DISTINCT FROM v_ai
               AND v_current_fact.eto_pii IS NOT DISTINCT FROM v_is_pii
               AND v_current_fact.podtverzhden = true THEN
                CONTINUE;
            END IF;
        END IF;

        INSERT INTO qbit_test.fakty_dialoga AS new_fact (
            dialog_id,
            polzovatel_id,
            kod_polya,
            znachenie_zashchishchennoe,
            znachenie_dlya_ai,
            eto_pii,
            podtverzhden,
            istochnik,
            soobshchenie_dokazatelstvo_id,
            vremya_fakta,
            deystvitelno_do
        )
        VALUES (
            v_dialog_id,
            v_user_id,
            v_code,
            v_protected,
            v_ai,
            v_is_pii,
            true,
            v_source,
            v_evidence,
            v_fact_time,
            v_expiry
        )
        RETURNING new_fact.id
        INTO v_new_fact_id;

        IF v_has_current_fact THEN
            UPDATE qbit_test.fakty_dialoga AS old_fact
               SET zamenen_faktom_id = v_new_fact_id
             WHERE old_fact.id = v_current_fact.id;
        END IF;

        v_inserted := v_inserted + 1;
        v_has_current_fact := false;
    END LOOP;

    SELECT COALESCE(
        jsonb_object_agg(f.kod_polya, f.znachenie_dlya_ai),
        '{}'::jsonb
    )
      INTO v_cache
      FROM qbit_test.fakty_dialoga AS f
     WHERE f.dialog_id = v_dialog_id
       AND f.zamenen_faktom_id IS NULL
       AND f.podtverzhden = true
       AND f.znachenie_dlya_ai IS NOT NULL
       AND (
            f.deystvitelno_do IS NULL
            OR f.deystvitelno_do >= clock_timestamp()
       );

    IF NOT v_memory_exists THEN
        INSERT INTO qbit_test.pamyat_dialoga AS new_memory (
            dialog_id,
            rezyume,
            poslednie_soobshcheniya,
            podtverzhdennye_fakty,
            obrabotano_do_id,
            versiya_pamyati,
            kolichestvo_tokenov,
            predydushchiy_dialog_id,
            vremya_obnovleniya
        )
        VALUES (
            v_dialog_id,
            v_summary,
            v_window,
            v_cache,
            v_processed_id,
            1,
            v_tokens,
            v_previous_dialog,
            clock_timestamp()
        )
        RETURNING new_memory.versiya_pamyati
        INTO v_new_memory;
    ELSE
        UPDATE qbit_test.pamyat_dialoga AS p_upd
           SET rezyume = v_summary,
               poslednie_soobshcheniya = v_window,
               podtverzhdennye_fakty = v_cache,
               obrabotano_do_id = v_processed_id,
               versiya_pamyati = p_upd.versiya_pamyati + 1,
               kolichestvo_tokenov = v_tokens,
               predydushchiy_dialog_id = v_previous_dialog,
               vremya_obnovleniya = clock_timestamp()
         WHERE p_upd.dialog_id = v_dialog_id
         RETURNING p_upd.versiya_pamyati
         INTO v_new_memory;
    END IF;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Факты и AI-safe память сохранены по CAS.'::text,
        NULL::timestamptz,
        v_dialog_id, v_dialog_version, v_new_memory, v_inserted;
END
$fn$;

COMMENT ON FUNCTION qbit_test.sohranit_fakty_i_pamyat(jsonb) IS
'DB-03C2: CAS по dialog/memory version, валидирует deidentified window и evidence, пишет immutable current facts with replacement chain и строит AI fact cache только из znachenie_dlya_ai.';

-- ===========================================================================
-- 3. RATE LIMIT: LOGICAL MESSAGES, NOT PROVIDER EVENTS
-- ===========================================================================

CREATE FUNCTION qbit_test.proverit_limit_chastoty(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    identifikator_kanala_id uuid,
    okno_sekund integer,
    limit_soobshcheniy integer,
    kolichestvo_soobshcheniy integer,
    razresheno boolean,
    schetchik_narusheniy integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_identity_id uuid;
    v_window_seconds integer;
    v_limit integer;
    v_now timestamptz;
    v_cutoff timestamptz;
    v_count integer;
    v_allowed boolean;
    v_retry timestamptz;
    v_offset integer;
    v_violation_counter integer;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_identity_id := NULLIF(p_dannye->>'identifikator_kanala_id', '')::uuid;
    v_window_seconds := NULLIF(p_dannye->>'okno_sekund', '')::integer;
    v_limit := NULLIF(p_dannye->>'limit_soobshcheniy', '')::integer;
    v_now := COALESCE(
        NULLIF(p_dannye->>'vremya_proverki', '')::timestamptz,
        clock_timestamp()
    );

    IF v_operaciya IS NULL
       OR v_identity_id IS NULL
       OR v_window_seconds IS NULL
       OR v_limit IS NULL
       OR v_window_seconds < 1
       OR v_window_seconds > 86400
       OR v_limit < 1
       OR v_limit > 10000 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны identity, trusted window 1..86400 и limit 1..10000.'::text,
            NULL::timestamptz,
            v_identity_id, v_window_seconds, v_limit, 0, false, NULL::integer;
        RETURN;
    END IF;

    SELECT i.schetchik_narusheniy
      INTO v_violation_counter
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_identity_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'identity_ne_nayden'::text,
            'Канальная идентичность не найдена.'::text,
            NULL::timestamptz,
            v_identity_id, v_window_seconds, v_limit, 0, false, NULL::integer;
        RETURN;
    END IF;

    v_cutoff := v_now - make_interval(secs => v_window_seconds);

    SELECT count(*)::integer
      INTO v_count
      FROM qbit_test.dialogi AS d
      JOIN qbit_test.soobshcheniya AS m
        ON m.dialog_id = d.id
     WHERE d.identifikator_kanala_id = v_identity_id
       AND m.napravlenie = 'vhodyashchee'
       AND m.avtor = 'klient'
       AND m.vremya_priema > v_cutoff
       AND m.vremya_priema <= v_now;

    v_allowed := v_count <= v_limit;

    IF NOT v_allowed THEN
        v_offset := GREATEST(v_count - v_limit - 1, 0);

        SELECT q.vremya_priema + make_interval(secs => v_window_seconds)
          INTO v_retry
          FROM (
                SELECT m.vremya_priema
                  FROM qbit_test.dialogi AS d
                  JOIN qbit_test.soobshcheniya AS m
                    ON m.dialog_id = d.id
                 WHERE d.identifikator_kanala_id = v_identity_id
                   AND m.napravlenie = 'vhodyashchee'
                   AND m.avtor = 'klient'
                   AND m.vremya_priema > v_cutoff
                   AND m.vremya_priema <= v_now
                 ORDER BY m.vremya_priema
                 OFFSET v_offset
                 LIMIT 1
          ) AS q;
    END IF;

    RETURN QUERY SELECT
        v_operaciya,
        'uspeshno'::text,
        CASE WHEN v_allowed THEN NULL ELSE 'limit_chastoty' END::text,
        CASE
            WHEN v_allowed THEN 'Лимит частоты не превышен.'
            ELSE 'Лимит частоты превышен; thematic counter не изменён.'
        END::text,
        v_retry,
        v_identity_id,
        v_window_seconds,
        v_limit,
        v_count,
        v_allowed,
        v_violation_counter;
END
$fn$;

COMMENT ON FUNCTION qbit_test.proverit_limit_chastoty(jsonb) IS
'DB-03C2: считает долговечно сохранённые логические incoming client messages в trusted time window; duplicate provider events без второго message не считаются и thematic violation counter не меняется.';

-- ===========================================================================
-- 4. THEMATIC VIOLATION / LOGICAL BLOCK
-- ===========================================================================

CREATE FUNCTION qbit_test.zapisat_narushenie_tematiky(
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
    soobshchenie_id uuid,
    nomer_narusheniya integer,
    logicheski_zablokirovan boolean,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_identity_id uuid;
    v_dialog_id uuid;
    v_message_id uuid;
    v_class text;
    v_source text;
    v_conf numeric;
    v_reason text;
    v_time timestamptz;
    v_limit integer;

    v_identity record;
    v_dialog record;
    v_message_dialog uuid;
    v_existing record;
    v_new_count integer;
    v_block_now boolean;
    v_dialog_version bigint;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_identity_id := NULLIF(p_dannye->>'identifikator_kanala_id', '')::uuid;
    v_dialog_id := NULLIF(p_dannye->>'dialog_id', '')::uuid;
    v_message_id := NULLIF(p_dannye->>'soobshchenie_id', '')::uuid;
    v_class := NULLIF(btrim(p_dannye->>'klassifikaciya'), '');
    v_source := NULLIF(btrim(p_dannye->>'istochnik'), '');
    v_conf := NULLIF(p_dannye->>'uverennost', '')::numeric;
    v_reason := p_dannye->>'prichina';
    v_time := COALESCE(
        NULLIF(p_dannye->>'vremya_sobytiya', '')::timestamptz,
        clock_timestamp()
    );
    v_limit := NULLIF(p_dannye->>'limit_narusheniy', '')::integer;

    IF v_operaciya IS NULL
       OR v_identity_id IS NULL
       OR v_dialog_id IS NULL
       OR v_message_id IS NULL
       OR v_class NOT IN ('ne_po_teme', 'ataka_ili_injection')
       OR v_source IS NULL
       OR v_limit IS NULL
       OR v_limit < 1
       OR v_limit > 100
       OR (v_conf IS NOT NULL AND (v_conf < 0 OR v_conf > 1)) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректные данные подтверждённого тематического нарушения.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            NULL::integer, NULL::boolean, NULL::bigint;
        RETURN;
    END IF;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_identity_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'identity_ne_nayden'::text,
            'Канальная идентичность не найдена.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            NULL::integer, NULL::boolean, NULL::bigint;
        RETURN;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_dialog_id
       AND d.identifikator_kanala_id = v_identity_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_sootvetstvuet_identity'::text,
            'Диалог не найден у этой канальной идентичности.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            NULL::integer, v_identity.logicheski_zablokirovan, NULL::bigint;
        RETURN;
    END IF;

    SELECT m.dialog_id
      INTO v_message_dialog
      FROM qbit_test.soobshcheniya AS m
     WHERE m.id = v_message_id
       AND m.napravlenie = 'vhodyashchee'
       AND m.avtor = 'klient';

    IF NOT FOUND
       OR v_message_dialog IS DISTINCT FROM v_dialog_id THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'soobshchenie_ne_sootvetstvuet_dialogu'::text,
            'Нарушение можно фиксировать только по входящему сообщению клиента этого диалога.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            NULL::integer, v_identity.logicheski_zablokirovan, v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    SELECT n.*
      INTO v_existing
      FROM qbit_test.narusheniya_tematiky AS n
     WHERE n.soobshchenie_id = v_message_id;

    IF FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Для этого сообщения нарушение уже было зафиксировано; счётчик не увеличен.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            v_existing.nomer_narusheniya,
            v_identity.logicheski_zablokirovan,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_identity.logicheski_zablokirovan THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'uzhe_zablokirovan'::text,
            'Идентичность уже логически заблокирована; новый thematic counter не начисляется.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            v_identity.schetchik_narusheniy,
            true,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    IF v_dialog.vladelec <> 'bot'
       OR v_dialog.status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'dialog_ne_upravlyaetsya_botom'::text,
            'Передача человеку/закрытие имеет приоритет над thematic counter.'::text,
            NULL::timestamptz,
            v_identity_id, v_dialog_id, v_message_id,
            v_identity.schetchik_narusheniy,
            false,
            v_dialog.versiya_dialoga;
        RETURN;
    END IF;

    v_new_count := v_identity.schetchik_narusheniy + 1;
    v_block_now := v_new_count >= v_limit;

    INSERT INTO qbit_test.narusheniya_tematiky (
        identifikator_kanala_id,
        dialog_id,
        soobshchenie_id,
        klassifikaciya,
        nomer_narusheniya,
        istochnik,
        uverennost,
        prichina,
        vremya_sobytiya,
        privelo_k_blokirovke
    )
    VALUES (
        v_identity_id,
        v_dialog_id,
        v_message_id,
        v_class,
        v_new_count,
        v_source,
        v_conf,
        v_reason,
        v_time,
        v_block_now
    );

    UPDATE qbit_test.identifikatory_kanalov AS i_upd
       SET schetchik_narusheniy = v_new_count,
           logicheski_zablokirovan = v_block_now,
           vremya_blokirovki = CASE
               WHEN v_block_now THEN v_time
               ELSE NULL
           END,
           prichina_blokirovki = CASE
               WHEN v_block_now THEN 'limit_tematiky'
               ELSE NULL
           END,
           vremya_obnovleniya = clock_timestamp()
     WHERE i_upd.id = v_identity_id;

    v_dialog_version := v_dialog.versiya_dialoga;

    IF v_block_now THEN
        UPDATE qbit_test.dialogi AS d_upd
           SET versiya_dialoga = d_upd.versiya_dialoga + 1,
               ozhidaetsya_otvet = false,
               t0 = NULL,
               pokolenie_ozhidaniya = d_upd.pokolenie_ozhidaniya + 1,
               status = CASE
                   WHEN d_upd.status = 'ozhidaet_otveta' THEN 'aktivnyy'
                   ELSE d_upd.status
               END,
               vremya_obnovleniya = clock_timestamp()
         WHERE d_upd.id = v_dialog_id
         RETURNING d_upd.versiya_dialoga
         INTO v_dialog_version;

        UPDATE qbit_test.napominaniya AS n_upd
           SET status = 'otmeneno',
               prichina = 'logicheskaya_blokirovka',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_upd.dialog_id = v_dialog_id
           AND n_upd.status IN ('zaplanirovano', 'v_rabote');

        INSERT INTO qbit_test.sobytiya_dialogov (
            dialog_id,
            polzovatel_id,
            tip_sobytiya,
            vremya_sobytiya,
            prichina,
            istochnik
        )
        VALUES (
            v_dialog_id,
            v_dialog.polzovatel_id,
            'logicheskaya_blokirovka',
            v_time,
            'limit_tematiky',
            'thematic_guard'
        );
    END IF;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        CASE
            WHEN v_block_now
            THEN 'Нарушение зафиксировано; достигнут trusted limit и включена логическая блокировка.'
            ELSE 'Нарушение зафиксировано; возвращён номер предупреждения.'
        END::text,
        NULL::timestamptz,
        v_identity_id, v_dialog_id, v_message_id,
        v_new_count, v_block_now, v_dialog_version;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zapisat_narushenie_tematiky(jsonb) IS
'DB-03C2: под row lock identity создаёт максимум одно подтверждённое нарушение на message, отдельно от flood limit; при trusted limit включает logical block, bump dialog version и отменяет wait/reminders.';

-- ===========================================================================
-- 5. ADMIN UNBLOCK + AUDIT
-- ===========================================================================

CREATE FUNCTION qbit_test.razblokirovat_polzovatelya(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    identifikator_kanala_id uuid,
    byl_zablokirovan boolean,
    schetchik_do integer,
    schetchik_posle integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_identity_id uuid;
    v_reason text;
    v_admin_id text;
    v_new_counter integer;
    v_identity record;
    v_existing_journal uuid;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_identity_id := NULLIF(p_dannye->>'identifikator_kanala_id', '')::uuid;
    v_reason := NULLIF(btrim(p_dannye->>'prichina'), '');
    v_admin_id := NULLIF(btrim(p_dannye->>'admin_id'), '');
    v_new_counter := COALESCE(
        NULLIF(p_dannye->>'novyy_schetchik_narusheniy', '')::integer,
        0
    );

    IF v_operaciya IS NULL
       OR v_identity_id IS NULL
       OR v_reason IS NULL
       OR v_admin_id IS NULL
       OR v_new_counter < 0 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation, identity, admin, причина и неотрицательный новый счётчик.'::text,
            NULL::timestamptz,
            v_identity_id, NULL::boolean, NULL::integer, NULL::integer;
        RETURN;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'db03c2_unblock' || pg_catalog.chr(31) || v_operaciya,
            6
        )
    );

    SELECT z.id
      INTO v_existing_journal
      FROM qbit_test.zhurnal_administrirovaniya AS z
     WHERE z.deystvie = 'razblokirovat_polzovatelya'
       AND z.tip_obekta = 'identifikator_kanala'
       AND z.obekt_id = v_identity_id::text
       AND z.trassirovka_id = v_operaciya
     LIMIT 1;

    IF FOUND THEN
        SELECT i.*
          INTO v_identity
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.id = v_identity_id;

        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Эта admin operation уже была выполнена; повтор не меняет данные.'::text,
            NULL::timestamptz,
            v_identity_id,
            false,
            COALESCE(v_identity.schetchik_narusheniy, v_new_counter),
            COALESCE(v_identity.schetchik_narusheniy, v_new_counter);
        RETURN;
    END IF;

    SELECT i.*
      INTO v_identity
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = v_identity_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'identity_ne_nayden'::text,
            'Канальная идентичность не найдена.'::text,
            NULL::timestamptz,
            v_identity_id, NULL::boolean, NULL::integer, NULL::integer;
        RETURN;
    END IF;

    IF v_new_counter > v_identity.schetchik_narusheniy THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'schetchik_nelzya_uvelichit'::text,
            'Операция unblock может только уменьшить/сбросить thematic counter.'::text,
            NULL::timestamptz,
            v_identity_id,
            v_identity.logicheski_zablokirovan,
            v_identity.schetchik_narusheniy,
            v_identity.schetchik_narusheniy;
        RETURN;
    END IF;

    IF NOT v_identity.logicheski_zablokirovan THEN
        INSERT INTO qbit_test.zhurnal_administrirovaniya (
            tip_avtora,
            avtor_id,
            deystvie,
            tip_obekta,
            obekt_id,
            vremya,
            izmeneniya,
            rezultat,
            trassirovka_id
        )
        VALUES (
            'administrator',
            v_admin_id,
            'razblokirovat_polzovatelya',
            'identifikator_kanala',
            v_identity_id::text,
            clock_timestamp(),
            jsonb_build_object(
                'prichina', v_reason,
                'schetchik_do', v_identity.schetchik_narusheniy,
                'schetchik_posle', v_identity.schetchik_narusheniy
            ),
            'uzhe_razblokirovan',
            v_operaciya
        );

        RETURN QUERY SELECT
            v_operaciya, 'dublikat'::text, NULL::text,
            'Идентичность уже была разблокирована; noop зааудирован.'::text,
            NULL::timestamptz,
            v_identity_id,
            false,
            v_identity.schetchik_narusheniy,
            v_identity.schetchik_narusheniy;
        RETURN;
    END IF;

    UPDATE qbit_test.identifikatory_kanalov AS i_upd
       SET logicheski_zablokirovan = false,
           vremya_blokirovki = NULL,
           prichina_blokirovki = NULL,
           schetchik_narusheniy = v_new_counter,
           vremya_obnovleniya = clock_timestamp()
     WHERE i_upd.id = v_identity_id;

    -- State change invalidates any stale in-flight bot decision.
    UPDATE qbit_test.dialogi AS d_upd
       SET versiya_dialoga = d_upd.versiya_dialoga + 1,
           vremya_obnovleniya = clock_timestamp()
     WHERE d_upd.identifikator_kanala_id = v_identity_id
       AND d_upd.status <> 'zavershen'
       AND d_upd.vladelec = 'bot';

    INSERT INTO qbit_test.zhurnal_administrirovaniya (
        tip_avtora,
        avtor_id,
        deystvie,
        tip_obekta,
        obekt_id,
        vremya,
        izmeneniya,
        rezultat,
        trassirovka_id
    )
    VALUES (
        'administrator',
        v_admin_id,
        'razblokirovat_polzovatelya',
        'identifikator_kanala',
        v_identity_id::text,
        clock_timestamp(),
        jsonb_build_object(
            'prichina', v_reason,
            'schetchik_do', v_identity.schetchik_narusheniy,
            'schetchik_posle', v_new_counter
        ),
        'uspeshno',
        v_operaciya
    );

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Логическая блокировка снята и административное действие зааудировано.'::text,
        NULL::timestamptz,
        v_identity_id,
        true,
        v_identity.schetchik_narusheniy,
        v_new_counter;
END
$fn$;

COMMENT ON FUNCTION qbit_test.razblokirovat_polzovatelya(jsonb) IS
'DB-03C2: dash_admin-only idempotent unblock по operation ID; снимает logical block, может только уменьшить counter, invalidates stale bot version и пишет safe admin journal.';

-- ===========================================================================
-- 6. PRIVILEGES
-- ===========================================================================

REVOKE ALL ON FUNCTION qbit_test.poluchit_kontekst_dialoga(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.sohranit_fakty_i_pamyat(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.proverit_limit_chastoty(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zapisat_narushenie_tematiky(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.razblokirovat_polzovatelya(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_test.poluchit_kontekst_dialoga(jsonb)
TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.sohranit_fakty_i_pamyat(jsonb)
TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.proverit_limit_chastoty(jsonb)
TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.zapisat_narushenie_tematiky(jsonb)
TO qbit_test_bot;

GRANT EXECUTE ON FUNCTION qbit_test.razblokirovat_polzovatelya(jsonb)
TO qbit_test_dash_admin;

-- ===========================================================================
-- 7. STATIC SECURITY ASSERTIONS
-- ===========================================================================

DO $db03c2$
DECLARE
    v_fn record;
    v_expected_role text;
BEGIN
    FOR v_fn IN
        SELECT
            p.oid,
            p.proname,
            p.prosecdef,
            p.proconfig,
            r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = p.proowner
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya'
           )
    LOOP
        IF NOT v_fn.prosecdef THEN
            RAISE EXCEPTION
                'Function % is not SECURITY DEFINER',
                v_fn.proname;
        END IF;

        IF v_fn.owner_name IS DISTINCT FROM 'qbit_test_owner' THEN
            RAISE EXCEPTION
                'Function % has wrong owner %',
                v_fn.proname,
                v_fn.owner_name;
        END IF;

        IF NOT (
            COALESCE(v_fn.proconfig, ARRAY[]::text[])
            @> ARRAY['search_path=pg_catalog, qbit_test']::text[]
        ) THEN
            RAISE EXCEPTION
                'Function % has unsafe search_path %',
                v_fn.proname,
                v_fn.proconfig;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM pg_catalog.aclexplode(
                    COALESCE(
                        (SELECT p2.proacl
                           FROM pg_catalog.pg_proc AS p2
                          WHERE p2.oid = v_fn.oid),
                        pg_catalog.acldefault(
                            'f',
                            (SELECT p2.proowner
                               FROM pg_catalog.pg_proc AS p2
                              WHERE p2.oid = v_fn.oid)
                        )
                    )
              ) AS a
             WHERE a.grantee = 0
               AND a.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'PUBLIC unexpectedly has EXECUTE on %',
                v_fn.proname;
        END IF;

        v_expected_role := CASE
            WHEN v_fn.proname = 'razblokirovat_polzovatelya'
            THEN 'qbit_test_dash_admin'
            ELSE 'qbit_test_bot'
        END;

        IF NOT pg_catalog.has_function_privilege(
            v_expected_role,
            v_fn.oid,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'Expected role % lacks EXECUTE on %',
                v_expected_role,
                v_fn.proname;
        END IF;

        IF v_fn.proname = 'razblokirovat_polzovatelya'
           AND pg_catalog.has_function_privilege(
                'qbit_test_bot',
                v_fn.oid,
                'EXECUTE'
           ) THEN
            RAISE EXCEPTION
                'qbit_test_bot unexpectedly has admin unblock EXECUTE';
        END IF;

        IF v_fn.proname <> 'razblokirovat_polzovatelya'
           AND pg_catalog.has_function_privilege(
                'qbit_test_sluzhebnyy',
                v_fn.oid,
                'EXECUTE'
           ) THEN
            RAISE EXCEPTION
                'qbit_test_sluzhebnyy unexpectedly has client API EXECUTE on %',
                v_fn.proname;
        END IF;
    END LOOP;

    IF (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya'
           )
    ) <> 5 THEN
        RAISE EXCEPTION
            'DB-03C2 expected exactly 5 API functions';
    END IF;
END
$db03c2$;

-- ===========================================================================
-- 8. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03c2_probe;

DO $db03c2$
DECLARE
    r1 record;
    r2 record;
    r3 record;
    rdup_provider record;
    rpii record;
    rctx record;
    rmem record;
    rstale record;
    rrate record;
    rv1 record;
    rvdup record;
    rv2 record;
    rv3 record;
    rblocked record;
    rblocked_ai record;
    runblock record;
    runblock_dup record;
    v_counter_before integer;
    v_counter_after integer;
    v_journal_count integer;
    v_block_job_id uuid;
    v_wait_message_id uuid;
    v_wait_reminder_id uuid;
BEGIN
    -- First incoming message contains PII in a non-canonical visual format.
    SELECT *
      INTO r1
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c2_ingress_1',
            'klyuch_idempotentnosti', 'db03c2_idem_1',
            'hash_soderzhaniya', 'db03c2_hash_1',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c2_client_bot',
            'vneshnee_sobytie_id', 'db03c2_event_1',
            'vneshniy_polzovatel_id', 'db03c2_user',
            'vneshniy_dialog_id', 'db03c2_chat',
            'vneshnee_soobshchenie_id', 'db03c2_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Мой телефон 8 (961) 123-45-67',
            'vremya_istochnika', '2026-09-24T19:00:00+00',
            'vremya_priema', '2026-09-24T19:00:01+00',
            'versiya_workflow', 'db03c2_probe',
            'versiya_prompta', 'db03c2_probe',
            'sluzhebnyy_chat_id', 'db03c2_service_group',
            'payload_ishodnyy', jsonb_build_object('update_id', 'db03c2_event_1')
        )
      );

    IF r1.rezultat <> 'uspeshno'
       OR r1.versiya_dialoga <> 1 THEN
        RAISE EXCEPTION
            'DB-03C2 setup ingress1 failed: %',
            row_to_json(r1);
    END IF;

    SELECT *
      INTO rpii
      FROM qbit_test.sohranit_obezlichivanie(
        jsonb_build_object(
            'operaciya_id', 'db03c2_pii_1',
            'soobshchenie_id', r1.soobshchenie_id,
            'tekst_obezlichennyy', 'Мой телефон <TELEFON_1>',
            'region_telefona', 'RU',
            'sootvetstviya', jsonb_build_array(
                jsonb_build_object(
                    'tip_pii', 'telefon',
                    'psevdometka', '<TELEFON_1>',
                    'znachenie_zashchishchennoe', '8 (961) 123-45-67',
                    'hash_normalizovannogo_znacheniya', 'db03c2_phone_hash'
                )
            )
        )
      );

    IF rpii.rezultat <> 'uspeshno' THEN
        RAISE EXCEPTION
            'DB-03C2 setup PII failed: %',
            row_to_json(rpii);
    END IF;

    -- Context before memory must expose only deidentified text to AI package.
    SELECT *
      INTO rctx
      FROM qbit_test.poluchit_kontekst_dialoga(
        jsonb_build_object(
            'operaciya_id', 'db03c2_ctx_before_memory',
            'dialog_id', r1.dialog_id,
            'zadanie_id', r1.zadanie_id,
            'ozhidaemaya_versiya_dialoga', 1
        )
      );

    IF rctx.rezultat <> 'uspeshno'
       OR NOT rctx.mozhno_ai
       OR rctx.ai_kontekst::text NOT LIKE '%<TELEFON_1>%'
       OR rctx.ai_kontekst::text LIKE '%89611234567%'
       OR rctx.ai_kontekst::text LIKE '%8 (961) 123-45-67%'
       OR rctx.lokalnye_pii::text NOT LIKE '%+79611234567%' THEN
        RAISE EXCEPTION
            'DB-03C2 AI/local PII separation failed: %',
            row_to_json(rctx);
    END IF;

    -- AI-memory summary must reject a known protected PII value.
    SELECT *
      INTO rstale
      FROM qbit_test.sohranit_fakty_i_pamyat(
        jsonb_build_object(
            'operaciya_id', 'db03c2_memory_pii_reject',
            'dialog_id', r1.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'ozhidaemaya_versiya_pamyati', 0,
            'rezyume', 'Телефон +79611234567',
            'poslednie_soobshcheniya', '[]'::jsonb,
            'kolichestvo_tokenov', 3,
            'fakty', '[]'::jsonb
        )
      );

    IF rstale.rezultat <> 'otkaz'
       OR rstale.kod_oshibki <> 'rezyume_soderzhit_pii' THEN
        RAISE EXCEPTION
            'DB-03C2 raw PII summary was not rejected: %',
            row_to_json(rstale);
    END IF;

    -- First memory save: one PII fact has boolean AI representation only.
    SELECT *
      INTO rmem
      FROM qbit_test.sohranit_fakty_i_pamyat(
        jsonb_build_object(
            'operaciya_id', 'db03c2_memory_1',
            'dialog_id', r1.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'ozhidaemaya_versiya_pamyati', 0,
            'rezyume', 'Клиент оставил <TELEFON_1>.',
            'poslednie_soobshcheniya', jsonb_build_array(
                jsonb_build_object(
                    'soobshchenie_id', r1.soobshchenie_id,
                    'napravlenie', 'vhodyashchee',
                    'avtor', 'klient',
                    'vid', 'text',
                    'tekst', 'Мой телефон <TELEFON_1>'
                )
            ),
            'obrabotano_do_id', r1.soobshchenie_id,
            'kolichestvo_tokenov', 12,
            'fakty', jsonb_build_array(
                jsonb_build_object(
                    'kod_polya', 'telefon_poluchen',
                    'znachenie_zashchishchennoe', to_jsonb('+79611234567'::text),
                    'znachenie_dlya_ai', 'true'::jsonb,
                    'eto_pii', true,
                    'podtverzhden', true,
                    'istochnik', 'klient',
                    'soobshchenie_dokazatelstvo_id', r1.soobshchenie_id,
                    'vremya_fakta', '2026-09-24T19:00:01+00'
                )
            )
        )
      );

    IF rmem.rezultat <> 'uspeshno'
       OR rmem.versiya_pamyati <> 1
       OR rmem.kolichestvo_novyh_faktov <> 1 THEN
        RAISE EXCEPTION
            'DB-03C2 first memory save failed: %',
            row_to_json(rmem);
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_test.pamyat_dialoga AS p
         WHERE p.dialog_id = r1.dialog_id
           AND p.podtverzhdennye_fakty::text LIKE '%+79611234567%'
    ) THEN
        RAISE EXCEPTION
            'DB-03C2 AI memory cache leaked protected phone';
    END IF;

    -- Same expected memory version is stale and must not write another fact.
    SELECT *
      INTO rstale
      FROM qbit_test.sohranit_fakty_i_pamyat(
        jsonb_build_object(
            'operaciya_id', 'db03c2_memory_stale',
            'dialog_id', r1.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'ozhidaemaya_versiya_pamyati', 0,
            'rezyume', 'stale',
            'poslednie_soobshcheniya', '[]'::jsonb,
            'kolichestvo_tokenov', 1,
            'fakty', '[]'::jsonb
        )
      );

    IF rstale.rezultat <> 'konflikt'
       OR rstale.kod_oshibki <> 'stale_memory_version' THEN
        RAISE EXCEPTION
            'DB-03C2 stale memory CAS not rejected: %',
            row_to_json(rstale);
    END IF;

    -- Add two more logical inputs for rate-limit and thematic warning probes.
    SELECT *
      INTO r2
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c2_ingress_2',
            'klyuch_idempotentnosti', 'db03c2_idem_2',
            'hash_soderzhaniya', 'db03c2_hash_2',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c2_client_bot',
            'vneshnee_sobytie_id', 'db03c2_event_2',
            'vneshniy_polzovatel_id', 'db03c2_user',
            'vneshniy_dialog_id', 'db03c2_chat',
            'vneshnee_soobshchenie_id', 'db03c2_msg_2',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Второе тестовое сообщение',
            'vremya_priema', '2026-09-24T19:00:10+00',
            'versiya_workflow', 'db03c2_probe',
            'versiya_prompta', 'db03c2_probe',
            'sluzhebnyy_chat_id', 'db03c2_service_group'
        )
      );

    SELECT *
      INTO r3
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c2_ingress_3',
            'klyuch_idempotentnosti', 'db03c2_idem_3',
            'hash_soderzhaniya', 'db03c2_hash_3',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c2_client_bot',
            'vneshnee_sobytie_id', 'db03c2_event_3',
            'vneshniy_polzovatel_id', 'db03c2_user',
            'vneshniy_dialog_id', 'db03c2_chat',
            'vneshnee_soobshchenie_id', 'db03c2_msg_3',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Третье тестовое сообщение',
            'vremya_priema', '2026-09-24T19:00:20+00',
            'versiya_workflow', 'db03c2_probe',
            'versiya_prompta', 'db03c2_probe',
            'sluzhebnyy_chat_id', 'db03c2_service_group'
        )
      );

    IF r2.rezultat <> 'uspeshno'
       OR r3.rezultat <> 'uspeshno'
       OR r2.versiya_dialoga <> 2
       OR r3.versiya_dialoga <> 3 THEN
        RAISE EXCEPTION
            'DB-03C2 setup ingress2/3 failed: r2=%, r3=%',
            row_to_json(r2),
            row_to_json(r3);
    END IF;

    -- Old dialog version is now stale.
    SELECT *
      INTO rstale
      FROM qbit_test.sohranit_fakty_i_pamyat(
        jsonb_build_object(
            'operaciya_id', 'db03c2_dialog_stale',
            'dialog_id', r1.dialog_id,
            'ozhidaemaya_versiya_dialoga', 1,
            'ozhidaemaya_versiya_pamyati', 1,
            'rezyume', 'stale dialog',
            'poslednie_soobshcheniya', '[]'::jsonb,
            'kolichestvo_tokenov', 1,
            'fakty', '[]'::jsonb
        )
      );

    IF rstale.rezultat <> 'konflikt'
       OR rstale.kod_oshibki <> 'stale_dialog_version' THEN
        RAISE EXCEPTION
            'DB-03C2 stale dialog CAS not rejected: %',
            row_to_json(rstale);
    END IF;

    -- Provider retry with another event ID but same external message must not
    -- create a fourth logical incoming message and therefore must not affect rate.
    SELECT *
      INTO rdup_provider
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c2_ingress_3_provider_retry',
            'klyuch_idempotentnosti', 'db03c2_idem_3_provider_retry',
            'hash_soderzhaniya', 'db03c2_hash_3_provider_retry',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c2_client_bot',
            'vneshnee_sobytie_id', 'db03c2_event_3_provider_retry',
            'vneshniy_polzovatel_id', 'db03c2_user',
            'vneshniy_dialog_id', 'db03c2_chat',
            'vneshnee_soobshchenie_id', 'db03c2_msg_3',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Третье тестовое сообщение',
            'vremya_priema', '2026-09-24T19:00:21+00',
            'versiya_workflow', 'db03c2_probe',
            'versiya_prompta', 'db03c2_probe',
            'sluzhebnyy_chat_id', 'db03c2_service_group'
        )
      );

    IF rdup_provider.rezultat <> 'dublikat'
       OR rdup_provider.soobshchenie_id IS DISTINCT FROM r3.soobshchenie_id THEN
        RAISE EXCEPTION
            'DB-03C2 provider retry setup failed: %',
            row_to_json(rdup_provider);
    END IF;

    SELECT i.schetchik_narusheniy
      INTO v_counter_before
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = r1.identifikator_kanala_id;

    SELECT *
      INTO rrate
      FROM qbit_test.proverit_limit_chastoty(
        jsonb_build_object(
            'operaciya_id', 'db03c2_rate',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'okno_sekund', 60,
            'limit_soobshcheniy', 2,
            'vremya_proverki', '2026-09-24T19:00:30+00'
        )
      );

    SELECT i.schetchik_narusheniy
      INTO v_counter_after
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.id = r1.identifikator_kanala_id;

    IF rrate.rezultat <> 'uspeshno'
       OR rrate.razresheno
       OR rrate.kolichestvo_soobshcheniy <> 3
       OR v_counter_before <> v_counter_after
       OR v_counter_after <> 0 THEN
        RAISE EXCEPTION
            'DB-03C2 rate limit/thematic separation failed: %',
            row_to_json(rrate);
    END IF;

    -- Warning 1.
    SELECT *
      INTO rv1
      FROM qbit_test.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id', 'db03c2_violation_1',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'dialog_id', r1.dialog_id,
            'soobshchenie_id', r1.soobshchenie_id,
            'klassifikaciya', 'ne_po_teme',
            'istochnik', 'probe',
            'uverennost', 0.99,
            'prichina', 'probe',
            'vremya_sobytiya', '2026-09-24T19:01:00+00',
            'limit_narusheniy', 3
        )
      );

    SELECT *
      INTO rvdup
      FROM qbit_test.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id', 'db03c2_violation_1_retry',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'dialog_id', r1.dialog_id,
            'soobshchenie_id', r1.soobshchenie_id,
            'klassifikaciya', 'ne_po_teme',
            'istochnik', 'probe',
            'uverennost', 0.99,
            'prichina', 'probe',
            'limit_narusheniy', 3
        )
      );

    -- Warning 2.
    SELECT *
      INTO rv2
      FROM qbit_test.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id', 'db03c2_violation_2',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'dialog_id', r1.dialog_id,
            'soobshchenie_id', r2.soobshchenie_id,
            'klassifikaciya', 'ne_po_teme',
            'istochnik', 'probe',
            'uverennost', 0.99,
            'prichina', 'probe',
            'vremya_sobytiya', '2026-09-24T19:01:10+00',
            'limit_narusheniy', 3
        )
      );

    -- Prepare an active wait/reminder that block must cancel.
    v_wait_message_id := '00000000-0000-4000-8000-000000000351'::uuid;

    INSERT INTO qbit_test.soobshcheniya (
        id,
        dialog_id,
        napravlenie,
        avtor,
        vid,
        tekst_ishodnyy,
        tekst_obezlichennyy,
        vremya_priema,
        status_otpravki,
        ozhidaetsya_otvet
    )
    VALUES (
        v_wait_message_id,
        r1.dialog_id,
        'ishodyashchee',
        'bot',
        'text',
        'DB-03C2 waiting probe',
        'DB-03C2 waiting probe',
        '2026-09-24T19:01:15+00',
        'podtverzhdeno',
        true
    );

    UPDATE qbit_test.dialogi AS d_wait
       SET status = 'ozhidaet_otveta',
           ozhidaetsya_otvet = true,
           t0 = '2026-09-24T19:01:15+00',
           pokolenie_ozhidaniya = 1
     WHERE d_wait.id = r1.dialog_id;

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
    VALUES (
        r1.dialog_id,
        'napominanie_1',
        '2026-09-24T19:01:15+00',
        v_wait_message_id,
        1,
        '2026-09-24T22:01:15+00',
        '2026-09-24T23:01:15+00',
        'zaplanirovano'
    )
    RETURNING id INTO v_wait_reminder_id;

    -- Warning 3 + block, bumps dialog version from 3 to 4.
    SELECT *
      INTO rv3
      FROM qbit_test.zapisat_narushenie_tematiky(
        jsonb_build_object(
            'operaciya_id', 'db03c2_violation_3',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'dialog_id', r1.dialog_id,
            'soobshchenie_id', r3.soobshchenie_id,
            'klassifikaciya', 'ataka_ili_injection',
            'istochnik', 'probe',
            'uverennost', 0.99,
            'prichina', 'probe',
            'vremya_sobytiya', '2026-09-24T19:01:20+00',
            'limit_narusheniy', 3
        )
      );

    IF rv1.rezultat <> 'uspeshno'
       OR rv1.nomer_narusheniya <> 1
       OR rv1.logicheski_zablokirovan
       OR rvdup.rezultat <> 'dublikat'
       OR rvdup.nomer_narusheniya <> 1
       OR rv2.nomer_narusheniya <> 2
       OR rv2.logicheski_zablokirovan
       OR rv3.nomer_narusheniya <> 3
       OR NOT rv3.logicheski_zablokirovan
       OR rv3.versiya_dialoga <> 4
       OR EXISTS (
            SELECT 1
              FROM qbit_test.dialogi AS d
             WHERE d.id = r1.dialog_id
               AND (
                    d.ozhidaetsya_otvet
                    OR d.t0 IS NOT NULL
                    OR d.status = 'ozhidaet_otveta'
               )
       )
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_test.napominaniya AS n
             WHERE n.id = v_wait_reminder_id
               AND n.status = 'otmeneno'
               AND n.prichina = 'logicheskaya_blokirovka'
       ) THEN
        RAISE EXCEPTION
            'DB-03C2 thematic warning/block sequence failed: rv1=%, dup=%, rv2=%, rv3=%',
            row_to_json(rv1),
            row_to_json(rvdup),
            row_to_json(rv2),
            row_to_json(rv3);
    END IF;

    -- Context must now refuse AI even if caller supplies current dialog version.
    SELECT *
      INTO rblocked
      FROM qbit_test.poluchit_kontekst_dialoga(
        jsonb_build_object(
            'operaciya_id', 'db03c2_ctx_blocked',
            'dialog_id', r1.dialog_id,
            'zadanie_id', r3.zadanie_id,
            'ozhidaemaya_versiya_dialoga', 4
        )
      );

    -- r3 job still carries version 3, so current version 4 must be rejected as stale.
    IF rblocked.rezultat <> 'konflikt'
       OR rblocked.kod_oshibki <> 'stale_dialog_version' THEN
        RAISE EXCEPTION
            'DB-03C2 block did not invalidate stale job context: %',
            row_to_json(rblocked);
    END IF;

    -- A fresh job at current version 4 still must not receive AI context while blocked.
    INSERT INTO qbit_test.zadaniya_obrabotki (
        dialog_id,
        sobytie_id,
        tip_zadaniya,
        status,
        prioritet,
        sleduyushchiy_zapusk,
        versiya_dialoga,
        payload
    )
    SELECT
        r1.dialog_id,
        m.sobytie_id,
        'obrabotat_vhod',
        'ozhidaet',
        0,
        clock_timestamp(),
        4,
        jsonb_build_object('probe', 'blocked_context')
      FROM qbit_test.soobshcheniya AS m
     WHERE m.id = r3.soobshchenie_id
    RETURNING id INTO v_block_job_id;

    SELECT *
      INTO rblocked_ai
      FROM qbit_test.poluchit_kontekst_dialoga(
        jsonb_build_object(
            'operaciya_id', 'db03c2_ctx_blocked_ai',
            'dialog_id', r1.dialog_id,
            'zadanie_id', v_block_job_id,
            'ozhidaemaya_versiya_dialoga', 4
        )
      );

    IF rblocked_ai.rezultat <> 'otkaz'
       OR rblocked_ai.kod_oshibki <> 'logicheski_zablokirovan'
       OR rblocked_ai.mozhno_ai THEN
        RAISE EXCEPTION
            'DB-03C2 blocked identity unexpectedly received AI context: %',
            row_to_json(rblocked_ai);
    END IF;

    -- Admin unblock is idempotent and resets counter to zero.
    SELECT *
      INTO runblock
      FROM qbit_test.razblokirovat_polzovatelya(
        jsonb_build_object(
            'operaciya_id', 'db03c2_admin_unblock_1',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'prichina', 'probe_manual_review',
            'admin_id', 'db03c2_admin',
            'novyy_schetchik_narusheniy', 0
        )
      );

    SELECT *
      INTO runblock_dup
      FROM qbit_test.razblokirovat_polzovatelya(
        jsonb_build_object(
            'operaciya_id', 'db03c2_admin_unblock_1',
            'identifikator_kanala_id', r1.identifikator_kanala_id,
            'prichina', 'probe_manual_review',
            'admin_id', 'db03c2_admin',
            'novyy_schetchik_narusheniy', 0
        )
      );

    SELECT count(*)::integer
      INTO v_journal_count
      FROM qbit_test.zhurnal_administrirovaniya AS z
     WHERE z.trassirovka_id = 'db03c2_admin_unblock_1'
       AND z.deystvie = 'razblokirovat_polzovatelya';

    IF runblock.rezultat <> 'uspeshno'
       OR NOT runblock.byl_zablokirovan
       OR runblock.schetchik_do <> 3
       OR runblock.schetchik_posle <> 0
       OR runblock_dup.rezultat <> 'dublikat'
       OR v_journal_count <> 1
       OR EXISTS (
            SELECT 1
              FROM qbit_test.identifikatory_kanalov AS i
             WHERE i.id = r1.identifikator_kanala_id
               AND (
                    i.logicheski_zablokirovan
                    OR i.schetchik_narusheniy <> 0
                    OR i.vremya_blokirovki IS NOT NULL
                    OR i.prichina_blokirovki IS NOT NULL
               )
       ) THEN
        RAISE EXCEPTION
            'DB-03C2 admin unblock/idempotency failed: first=%, retry=%, journals=%',
            row_to_json(runblock),
            row_to_json(runblock_dup),
            v_journal_count;
    END IF;
END
$db03c2$;

ROLLBACK TO SAVEPOINT db03c2_probe;
RELEASE SAVEPOINT db03c2_probe;

-- ===========================================================================
-- 9. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03c2$
DECLARE
    v_role text;
    v_table record;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03c2_client_bot'
            OR i.vneshniy_polzovatel_id = 'db03c2_user'
    ) THEN
        RAISE EXCEPTION
            'DB-03C2 probe identity rows remain after rollback';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_test.zhurnal_administrirovaniya AS z
         WHERE z.trassirovka_id = 'db03c2_admin_unblock_1'
    ) THEN
        RAISE EXCEPTION
            'DB-03C2 probe admin journal remains after rollback';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_dash_admin'
    ]
    LOOP
        FOR v_table IN
            SELECT c.oid, c.relname
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = c.relnamespace
             WHERE n.nspname = 'qbit_test'
               AND c.relkind = 'r'
        LOOP
            IF pg_catalog.has_table_privilege(v_role, v_table.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % unexpectedly has direct DML on qbit_test.%',
                    v_role,
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;
END
$db03c2$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 10. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03c2_status',
    'applied',
    'database',
    current_database(),
    'schema',
    'qbit_test',
    'functions_ok',
    (
        SELECT count(*) = 5
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya'
           )
           AND p.prosecdef = true
    ),
    'bot_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.poluchit_kontekst_dialoga(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.sohranit_fakty_i_pamyat(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.proverit_limit_chastoty(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.zapisat_narushenie_tematiky(jsonb)',
        'EXECUTE'
    ),
    'admin_unblock_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_dash_admin',
        'qbit_test.razblokirovat_polzovatelya(jsonb)',
        'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.razblokirovat_polzovatelya(jsonb)',
        'EXECUTE'
    ),
    'service_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.poluchit_kontekst_dialoga(jsonb)',
        'EXECUTE'
    ),
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03c2_client_bot'
            OR i.vneshniy_polzovatel_id = 'db03c2_user'
    )
    +
    (
        SELECT count(*)
          FROM qbit_test.zhurnal_administrirovaniya AS z
         WHERE z.trassirovka_id = 'db03c2_admin_unblock_1'
    ),
    'runtime_direct_dml',
    false,
    'result',
    'DB-03C2 SQL APPLIED: AI-safe context/memory CAS/rate-limit/thematic block/admin-unblock verified; probe data removed; production untouched.'
) AS db03c2_result;
