-- DB-SCHEMA-01 v0.4: rename qBit test schema for project-level clarity
-- Project: Shablon_bot_pervichnogo_obrascheniya
--
-- RENAME
--   qbit_test -> qbit_bot_pervichnogo_obrascheniya
--
-- IMPORTANT
--   * Existing roles qbit_test_* are intentionally NOT renamed in this task.
--   * Production schema/roles and kompaniya_001_test are not modified.
--   * Current DB-03 functions are CREATE OR REPLACE'd only because their
--     PL/pgSQL source contains schema-qualified references and fixed search_path.
--   * Function OIDs, owners and ACLs must remain unchanged.
--   * pg_get_functiondef assertions first materialize only prokind='f' allowlisted project functions; aggregates cannot reach pg_get_functiondef.
--   * qbit_test_owner receives CREATE ON DATABASE postgres only temporarily
--     for ALTER SCHEMA RENAME; the privilege is revoked before COMMIT.
--   * After ALTER/CREATE OR REPLACE, role is reset to postgres BEFORE
--     snapshot assertions; no access to postgres-owned TEMP tables is granted.
--   * Any error before COMMIT rolls the entire rename back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '240s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK + SNAPSHOT
-- ===========================================================================

DO $dbschema01$
DECLARE
    v_owner text;
    v_fn_count integer;
    v_table_count integer;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION 'DB-SCHEMA-01 requires PostgreSQL 17+';
    END IF;

    IF session_user <> 'postgres'
       OR NOT pg_catalog.pg_has_role(session_user,'qbit_test_owner','SET') THEN
        RAISE EXCEPTION
            'DB-SCHEMA-01 requires trusted postgres session with SET qbit_test_owner';
    END IF;

    IF current_database() <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-SCHEMA-01 expected database postgres, actual %',
            current_database();
    END IF;

    IF (
        SELECT r.rolname
          FROM pg_catalog.pg_database AS d
          JOIN pg_catalog.pg_roles AS r ON r.oid=d.datdba
         WHERE d.datname=current_database()
    ) IS DISTINCT FROM session_user THEN
        RAISE EXCEPTION
            'DB-SCHEMA-01 requires postgres to own current database so temporary CREATE can be granted safely';
    END IF;

    IF pg_catalog.has_database_privilege(
        'qbit_test_owner',
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'qbit_test_owner unexpectedly already has CREATE on database; stop for privilege review';
    END IF;

    IF pg_catalog.to_regnamespace('qbit_test') IS NULL THEN
        RAISE EXCEPTION 'Source schema qbit_test does not exist';
    END IF;

    IF pg_catalog.to_regnamespace('qbit_bot_pervichnogo_obrascheniya') IS NOT NULL THEN
        RAISE EXCEPTION 'Target schema qbit_bot_pervichnogo_obrascheniya already exists';
    END IF;

    SELECT r.rolname
      INTO v_owner
      FROM pg_catalog.pg_namespace AS n
      JOIN pg_catalog.pg_roles AS r ON r.oid=n.nspowner
     WHERE n.nspname='qbit_test';

    IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION
            'Source schema owner mismatch: expected qbit_test_owner, actual %',
            v_owner;
    END IF;

    SELECT count(*)
      INTO v_table_count
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
     WHERE n.nspname='qbit_test'
       AND c.relkind='r';

    IF v_table_count <> 25 THEN
        RAISE EXCEPTION
            'Unexpected table count before rename: expected 25, actual %',
            v_table_count;
    END IF;

    SELECT count(*)
      INTO v_fn_count
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
     WHERE n.nspname='qbit_test'
       AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
       );

    IF v_fn_count <> 28 THEN
        RAISE EXCEPTION
            'Unexpected DB-03 function count before rename: expected 28, actual %',
            v_fn_count;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_test'
           AND p.proname NOT IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
           )
    ) THEN
        RAISE EXCEPTION
            'Unexpected extra function exists in qbit_test; stop for manual review';
    END IF;
END
$dbschema01$;

CREATE TEMP TABLE dbschema01_schema_snapshot ON COMMIT DROP AS
SELECT
    n.oid AS schema_oid,
    n.nspacl AS schema_acl,
    n.nspowner AS schema_owner
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname='qbit_test';

CREATE TEMP TABLE dbschema01_fn_snapshot ON COMMIT DROP AS
SELECT
    p.oid AS function_oid,
    p.proname,
    p.proowner,
    p.proacl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='qbit_test'
  AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
  );

CREATE TEMP TABLE dbschema01_other_schema_snapshot ON COMMIT DROP AS
SELECT
    x.schema_name,
    n.oid AS schema_oid,
    n.nspowner AS schema_owner,
    n.nspacl AS schema_acl,
    (
        SELECT count(*)
          FROM pg_catalog.pg_class AS c
         WHERE c.relnamespace=n.oid
    ) AS relation_count,
    (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
         WHERE p.pronamespace=n.oid
    ) AS function_count
FROM (
    VALUES ('qbit'::text),('kompaniya_001_test'::text)
) AS x(schema_name)
LEFT JOIN pg_catalog.pg_namespace AS n
  ON n.nspname=x.schema_name;

-- ===========================================================================
-- 1. TEMPORARY DATABASE PRIVILEGE + RENAME SCHEMA
-- ===========================================================================

-- PostgreSQL requires the schema owner to also have CREATE on the database
-- for ALTER SCHEMA ... RENAME. qbit_test_owner intentionally does not keep
-- this privilege during normal runtime, so grant it only inside this migration.
GRANT CREATE ON DATABASE postgres TO qbit_test_owner;

SET LOCAL ROLE qbit_test_owner;

ALTER SCHEMA qbit_test
    RENAME TO qbit_bot_pervichnogo_obrascheniya;

-- ===========================================================================
-- 2. REPLACE CURRENT DB-03 FUNCTION BODIES WITH NEW QUALIFIED SCHEMA NAME
-- ===========================================================================

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_vhod_klienta(
    p_vhod jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    polzovatel_id uuid,
    identifikator_kanala_id uuid,
    dialog_id uuid,
    soobshchenie_id uuid,
    zadanie_id uuid,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya_id text;
    v_versiya_formata integer;
    v_klyuch_idempotentnosti text;
    v_hash_soderzhaniya text;
    v_kanal text;
    v_akkaunt text;
    v_vnesh_sobytie text;
    v_vnesh_polz text;
    v_vnesh_dialog text;
    v_vnesh_soobshchenie text;
    v_tip_sobytiya text;
    v_tip_soobshcheniya text;
    v_tekst text;
    v_vremya_istochnika timestamptz;
    v_vremya_priema timestamptz;
    v_trace text;
    v_workflow text;
    v_prompt text;
    v_payload jsonb;
    v_sluzhebnyy_chat text;
    v_bezopasnaya_podpis text;

    v_event_id uuid;
    v_existing_event record;
    v_existing_message record;
    v_existing_job record;
    v_identity record;
    v_dialog record;
    v_previous_dialog_id uuid;
    v_topic record;
    v_topic_created boolean := false;
    v_topic_row_count bigint := 0;
    v_is_new_dialog boolean := false;
    v_message_id uuid;
    v_job_id uuid;
    v_user_id uuid;
    v_identity_id uuid;
    v_dialog_id uuid;
    v_dialog_version bigint;
BEGIN
    IF p_vhod IS NULL
       OR jsonb_typeof(p_vhod) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::bigint;
        RETURN;
    END IF;

    v_operaciya_id := NULLIF(btrim(p_vhod->>'operaciya_id'), '');
    v_versiya_formata := COALESCE((p_vhod->>'versiya_formata')::integer, 1);
    v_klyuch_idempotentnosti := NULLIF(btrim(p_vhod->>'klyuch_idempotentnosti'), '');
    v_hash_soderzhaniya := NULLIF(btrim(p_vhod->>'hash_soderzhaniya'), '');
    v_kanal := NULLIF(btrim(p_vhod->>'kanal'), '');
    v_akkaunt := NULLIF(btrim(p_vhod->>'akkaunt_kanala_id'), '');
    v_vnesh_sobytie := NULLIF(btrim(p_vhod->>'vneshnee_sobytie_id'), '');
    v_vnesh_polz := NULLIF(btrim(p_vhod->>'vneshniy_polzovatel_id'), '');
    v_vnesh_dialog := NULLIF(btrim(p_vhod->>'vneshniy_dialog_id'), '');
    v_vnesh_soobshchenie := NULLIF(btrim(p_vhod->>'vneshnee_soobshchenie_id'), '');
    v_tip_sobytiya := NULLIF(btrim(p_vhod->>'tip_sobytiya'), '');
    v_tip_soobshcheniya := NULLIF(btrim(p_vhod->>'tip_soobshcheniya'), '');
    v_tekst := p_vhod->>'tekst_ishodnyy';
    v_vremya_istochnika := NULLIF(p_vhod->>'vremya_istochnika', '')::timestamptz;
    v_vremya_priema := NULLIF(p_vhod->>'vremya_priema', '')::timestamptz;
    v_trace := NULLIF(btrim(p_vhod->>'trassirovka_id'), '');
    v_workflow := NULLIF(btrim(p_vhod->>'versiya_workflow'), '');
    v_prompt := NULLIF(btrim(p_vhod->>'versiya_prompta'), '');
    v_payload := COALESCE(p_vhod->'payload_ishodnyy', p_vhod);
    v_sluzhebnyy_chat := NULLIF(btrim(p_vhod->>'sluzhebnyy_chat_id'), '');
    v_bezopasnaya_podpis := NULLIF(btrim(p_vhod->>'bezopasnaya_podpis_klienta'), '');

    IF v_versiya_formata <> 1
       OR v_operaciya_id IS NULL
       OR v_klyuch_idempotentnosti IS NULL
       OR v_hash_soderzhaniya IS NULL
       OR v_kanal IS NULL
       OR v_akkaunt IS NULL
       OR v_vnesh_sobytie IS NULL
       OR v_vnesh_polz IS NULL
       OR v_vnesh_dialog IS NULL
       OR v_tip_sobytiya IS NULL
       OR v_tip_soobshcheniya IS NULL
       OR v_vremya_priema IS NULL
       OR v_workflow IS NULL
       OR v_prompt IS NULL
       OR v_sluzhebnyy_chat IS NULL
       OR jsonb_typeof(v_payload) NOT IN ('object', 'array')
       OR v_tip_soobshcheniya NOT IN (
            'text',
            'voice',
            'photo',
            'video',
            'document',
            'sticker',
            'system'
       )
    THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Не заполнены обязательные поля нормализованного ingress v1.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::bigint;
        RETURN;
    END IF;

    -- Persist the integration event first. ON CONFLICT waits for a concurrent
    -- transaction and then allows us to compare its committed hash.
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (
        versiya_formata,
        operaciya_id,
        istochnik,
        akkaunt_istochnika_id,
        vneshnee_sobytie_id,
        tip_sobytiya,
        klyuch_idempotentnosti,
        hash_soderzhaniya,
        payload_ishodnyy,
        vremya_istochnika,
        vremya_priema,
        status,
        trassirovka_id
    )
    VALUES (
        v_versiya_formata,
        v_operaciya_id,
        v_kanal,
        v_akkaunt,
        v_vnesh_sobytie,
        v_tip_sobytiya,
        v_klyuch_idempotentnosti,
        v_hash_soderzhaniya,
        v_payload,
        v_vremya_istochnika,
        v_vremya_priema,
        'registriruetsya',
        v_trace
    )
    ON CONFLICT DO NOTHING
    RETURNING id
    INTO v_event_id;

    IF v_event_id IS NULL THEN
        SELECT e.*
          INTO v_existing_event
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
         WHERE e.klyuch_idempotentnosti = v_klyuch_idempotentnosti
            OR (
                e.istochnik = v_kanal
                AND e.akkaunt_istochnika_id = v_akkaunt
                AND e.vneshnee_sobytie_id = v_vnesh_sobytie
            )
         ORDER BY
            CASE
                WHEN e.klyuch_idempotentnosti = v_klyuch_idempotentnosti
                THEN 0 ELSE 1
            END,
            e.vremya_zapisi
         LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Idempotency conflict detected but committed event was not found';
        END IF;

        IF v_existing_event.hash_soderzhaniya IS DISTINCT FROM v_hash_soderzhaniya THEN
            RETURN QUERY SELECT
                v_operaciya_id, 'konflikt'::text, 'idempotency_hash_conflict'::text,
                'Тот же ключ/внешнее событие уже зарегистрированы с другим содержимым.'::text,
                NULL::timestamptz,
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::bigint;
            RETURN;
        END IF;

        IF v_existing_event.status = 'konflikt' THEN
            RETURN QUERY SELECT
                v_operaciya_id, 'konflikt'::text,
                COALESCE(v_existing_event.kod_oshibki, 'registraciya_conflict')::text,
                'Ранее этот вход уже был зафиксирован как конфликт.'::text,
                NULL::timestamptz,
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::bigint;
            RETURN;
        END IF;

        -- A duplicate provider event may intentionally have no own message row:
        -- resolve the prior logical message by trusted channel identity + external message ID.
        IF v_existing_event.status = 'dublikat'
           AND v_vnesh_soobshchenie IS NOT NULL THEN
            SELECT
                m.id AS message_id,
                m.dialog_id,
                d.polzovatel_id,
                d.identifikator_kanala_id
              INTO v_existing_message
              FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
              JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
                ON d.identifikator_kanala_id = i.id
              JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
                ON m.dialog_id = d.id
             WHERE i.kanal = v_kanal
               AND i.akkaunt_kanala_id = v_akkaunt
               AND i.vneshniy_polzovatel_id = v_vnesh_polz
               AND m.vneshnee_soobshchenie_id = v_vnesh_soobshchenie
             ORDER BY m.vremya_sozdaniya
             LIMIT 1;

            IF FOUND THEN
                SELECT z.id, z.versiya_dialoga
                  INTO v_existing_job
                  FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
                  JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS original_message
                    ON original_message.sobytie_id = z.sobytie_id
                 WHERE original_message.id = v_existing_message.message_id
                 ORDER BY z.vremya_sozdaniya
                 LIMIT 1;

                RETURN QUERY SELECT
                    v_operaciya_id, 'dublikat'::text, NULL::text,
                    'Повтор duplicate-event вернул исходное логическое сообщение.'::text,
                    NULL::timestamptz,
                    v_existing_message.polzovatel_id,
                    v_existing_message.identifikator_kanala_id,
                    v_existing_message.dialog_id,
                    v_existing_message.message_id,
                    v_existing_job.id,
                    v_existing_job.versiya_dialoga;
                RETURN;
            END IF;
        END IF;

        SELECT
            m.id AS message_id,
            m.dialog_id,
            d.polzovatel_id,
            d.identifikator_kanala_id
          INTO v_existing_message
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
          JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
            ON d.id = m.dialog_id
         WHERE m.sobytie_id = v_existing_event.id
         ORDER BY m.vremya_sozdaniya
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                v_operaciya_id, 'povtorit'::text, 'event_without_registered_message'::text,
                'Событие существует, но регистрация сообщения не завершена; требуется безопасный повтор.'::text,
                clock_timestamp() + interval '5 seconds',
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid, NULL::bigint;
            RETURN;
        END IF;

        SELECT z.id, z.versiya_dialoga
          INTO v_existing_job
          FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
         WHERE z.sobytie_id = v_existing_event.id
           AND z.dialog_id = v_existing_message.dialog_id
         ORDER BY z.vremya_sozdaniya
         LIMIT 1;

        RETURN QUERY SELECT
            v_operaciya_id,
            'dublikat'::text,
            NULL::text,
            'Вход уже зарегистрирован; возвращён прежний результат.'::text,
            NULL::timestamptz,
            v_existing_message.polzovatel_id,
            v_existing_message.identifikator_kanala_id,
            v_existing_message.dialog_id,
            v_existing_message.message_id,
            v_existing_job.id,
            v_existing_job.versiya_dialoga;
        RETURN;
    END IF;

    -- Serialize identity/dialog creation for one channel identity.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            v_kanal || pg_catalog.chr(31) || v_akkaunt || pg_catalog.chr(31) || v_vnesh_polz,
            0
        )
    );

    SELECT i.*
      INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.kanal = v_kanal
       AND i.akkaunt_kanala_id = v_akkaunt
       AND i.vneshniy_polzovatel_id = v_vnesh_polz
     FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.polzovateli (
            vremya_pervogo_obrashcheniya,
            vremya_poslednego_obrashcheniya,
            pervyy_kanal
        )
        VALUES (
            v_vremya_priema,
            v_vremya_priema,
            v_kanal
        )
        RETURNING id INTO v_user_id;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
            polzovatel_id,
            kanal,
            akkaunt_kanala_id,
            vneshniy_polzovatel_id,
            vneshniy_dialog_id
        )
        VALUES (
            v_user_id,
            v_kanal,
            v_akkaunt,
            v_vnesh_polz,
            v_vnesh_dialog
        )
        RETURNING id
        INTO v_identity_id;
    ELSE
        v_user_id := v_identity.polzovatel_id;
        v_identity_id := v_identity.id;

        -- Provider may redeliver an old message after its dialog is already closed.
        -- Resolve the external message across every dialog of this channel identity
        -- before touching last-contact time or creating/reopening any dialog.
        IF v_vnesh_soobshchenie IS NOT NULL THEN
            SELECT
                m.id AS message_id,
                m.dialog_id,
                d.polzovatel_id,
                d.identifikator_kanala_id,
                m.vid,
                m.tekst_ishodnyy,
                m.sobytie_id
              INTO v_existing_message
              FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
              JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
                ON m.dialog_id = d.id
             WHERE d.identifikator_kanala_id = v_identity_id
               AND m.vneshnee_soobshchenie_id = v_vnesh_soobshchenie
             ORDER BY m.vremya_sozdaniya
             LIMIT 1;

            IF FOUND THEN
                UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy
                   SET status = CASE
                       WHEN v_existing_message.vid = v_tip_soobshcheniya
                        AND v_existing_message.tekst_ishodnyy IS NOT DISTINCT FROM v_tekst
                       THEN 'dublikat'
                       ELSE 'konflikt'
                   END,
                   kod_oshibki = CASE
                       WHEN v_existing_message.vid = v_tip_soobshcheniya
                        AND v_existing_message.tekst_ishodnyy IS NOT DISTINCT FROM v_tekst
                       THEN NULL
                       ELSE 'external_message_conflict'
                   END
                 WHERE id = v_event_id;

                IF v_existing_message.vid IS DISTINCT FROM v_tip_soobshcheniya
                   OR v_existing_message.tekst_ishodnyy IS DISTINCT FROM v_tekst THEN
                    RETURN QUERY SELECT
                        v_operaciya_id, 'konflikt'::text, 'external_message_conflict'::text,
                        'Тот же внешний ID сообщения уже связан с другим содержимым.'::text,
                        NULL::timestamptz,
                        v_user_id, v_identity_id, v_existing_message.dialog_id,
                        v_existing_message.message_id, NULL::uuid, NULL::bigint;
                    RETURN;
                END IF;

                SELECT z.id, z.versiya_dialoga
                  INTO v_existing_job
                  FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
                 WHERE z.sobytie_id = v_existing_message.sobytie_id
                 ORDER BY z.vremya_sozdaniya
                 LIMIT 1;

                RETURN QUERY SELECT
                    v_operaciya_id, 'dublikat'::text, NULL::text,
                    'Внешнее сообщение уже зарегистрировано без изменения пользователя/диалога.'::text,
                    NULL::timestamptz,
                    v_user_id, v_identity_id, v_existing_message.dialog_id,
                    v_existing_message.message_id, v_existing_job.id, v_existing_job.versiya_dialoga;
                RETURN;
            END IF;
        END IF;

        UPDATE qbit_bot_pervichnogo_obrascheniya.polzovateli AS p_upd
           SET vremya_poslednego_obrashcheniya =
                   GREATEST(p_upd.vremya_poslednego_obrashcheniya, v_vremya_priema),
               vremya_obnovleniya = clock_timestamp()
         WHERE p_upd.id = v_user_id;

        UPDATE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov
           SET vneshniy_dialog_id = v_vnesh_dialog,
               vremya_obnovleniya = clock_timestamp()
         WHERE id = v_identity_id;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.identifikator_kanala_id = v_identity_id
       AND d.status <> 'zavershen'
     ORDER BY d.vremya_nachala DESC
     LIMIT 1
     FOR UPDATE;

    IF NOT FOUND THEN
        SELECT d.id
          INTO v_previous_dialog_id
          FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
         WHERE d.identifikator_kanala_id = v_identity_id
         ORDER BY d.vremya_nachala DESC
         LIMIT 1;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.dialogi AS new_dialog (
            polzovatel_id,
            identifikator_kanala_id,
            predydushchiy_dialog_id,
            vremya_nachala,
            etap,
            status,
            versiya_dialoga,
            ozhidaetsya_otvet,
            t0,
            pokolenie_ozhidaniya,
            vladelec,
            versiya_workflow,
            versiya_prompta
        )
        VALUES (
            v_user_id,
            v_identity_id,
            v_previous_dialog_id,
            v_vremya_priema,
            COALESCE(NULLIF(btrim(p_vhod->>'nachalnyy_etap'), ''), 'pervichnyy_kontakt'),
            'aktivnyy',
            1,
            false,
            NULL,
            0,
            'bot',
            v_workflow,
            v_prompt
        )
        RETURNING new_dialog.id, new_dialog.versiya_dialoga
        INTO v_dialog_id, v_dialog_version;

        v_is_new_dialog := true;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
            dialog_id,
            polzovatel_id,
            tip_sobytiya,
            vremya_sobytiya,
            istochnik,
            trassirovka_id
        )
        VALUES (
            v_dialog_id,
            v_user_id,
            'nachalo',
            v_vremya_priema,
            'ingress',
            v_trace
        );
    ELSE
        v_dialog_id := v_dialog.id;
        v_dialog_version := v_dialog.versiya_dialoga;

        -- Existing dialog must already belong to the same trusted service group.
        SELECT t.*
          INTO v_topic
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
         WHERE t.dialog_id = v_dialog_id;

        IF FOUND
           AND v_topic.sluzhebnyy_chat_id IS DISTINCT FROM v_sluzhebnyy_chat THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy
               SET status = 'konflikt',
                   kod_oshibki = 'service_chat_changed'
             WHERE id = v_event_id;

            RETURN QUERY SELECT
                v_operaciya_id, 'konflikt'::text, 'service_chat_changed'::text,
                'Существующий диалог уже привязан к другой доверенной служебной группе.'::text,
                NULL::timestamptz,
                v_user_id, v_identity_id, v_dialog_id,
                NULL::uuid, NULL::uuid, v_dialog_version;
            RETURN;
        END IF;

        UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_upd
           SET versiya_dialoga = d_upd.versiya_dialoga + 1,
               ozhidaetsya_otvet = false,
               t0 = NULL,
               pokolenie_ozhidaniya = pokolenie_ozhidaniya + 1,
               status = CASE
                   WHEN status = 'ozhidaet_otveta' THEN 'aktivnyy'
                   ELSE status
               END,
               versiya_workflow = v_workflow,
               versiya_prompta = v_prompt,
               vremya_obnovleniya = clock_timestamp()
         WHERE d_upd.id = v_dialog_id
         RETURNING d_upd.versiya_dialoga
         INTO v_dialog_version;

        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya
           SET status = 'otmeneno',
               prichina = 'novyy_vhod',
               vremya_obnovleniya = clock_timestamp()
         WHERE dialog_id = v_dialog_id
           AND status IN ('zaplanirovano', 'v_rabote');
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
        dialog_id,
        sobytie_id,
        napravlenie,
        avtor,
        vid,
        tekst_ishodnyy,
        vneshnee_soobshchenie_id,
        vremya_istochnika,
        vremya_priema,
        trassirovka_id
    )
    VALUES (
        v_dialog_id,
        v_event_id,
        'vhodyashchee',
        'klient',
        v_tip_soobshcheniya,
        v_tekst,
        v_vnesh_soobshchenie,
        v_vremya_istochnika,
        v_vremya_priema,
        v_trace
    )
    RETURNING id
    INTO v_message_id;

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi
       SET poslednee_vhodyashchee_id = v_message_id,
           vremya_obnovleniya = clock_timestamp()
     WHERE id = v_dialog_id;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
        dialog_id,
        sobytie_id,
        tip_zadaniya,
        status,
        prioritet,
        sleduyushchiy_zapusk,
        versiya_dialoga,
        payload
    )
    VALUES (
        v_dialog_id,
        v_event_id,
        'obrabotat_vhod',
        'ozhidaet',
        COALESCE((p_vhod->>'prioritet')::integer, 0),
        clock_timestamp(),
        v_dialog_version,
        jsonb_build_object(
            'soobshchenie_id', v_message_id,
            'tip_soobshcheniya', v_tip_soobshcheniya
        )
    )
    RETURNING id
    INTO v_job_id;

    -- Every dialog has a durable topic intent. Existing mapping is never
    -- silently moved to another service group.
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy (
        dialog_id,
        sluzhebnyy_chat_id,
        status
    )
    VALUES (
        v_dialog_id,
        v_sluzhebnyy_chat,
        'nuzhno_sozdat'
    )
    ON CONFLICT (dialog_id) DO NOTHING;

    GET DIAGNOSTICS v_topic_row_count = ROW_COUNT;
    v_topic_created := (v_topic_row_count = 1);

    SELECT t.*
      INTO v_topic
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id = v_dialog_id;

    IF v_topic_created THEN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
            dialog_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            prioritet,
            cel_chat_id,
            bezopasnaya_podpis_klienta,
            payload,
            status
        )
        VALUES (
            v_dialog_id,
            'obespechit_temu',
            'tema:' || v_dialog_id::text,
            100,
            v_sluzhebnyy_chat,
            COALESCE(v_bezopasnaya_podpis, 'Клиент'),
            jsonb_build_object(
                'dialog_id', v_dialog_id,
                'kanal', v_kanal
            ),
            'zaplanirovano'
        )
        ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;
    END IF;

    IF v_tip_soobshcheniya = 'text' THEN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
            dialog_id,
            soobshchenie_id,
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
            v_dialog_id,
            v_message_id,
            'soobshchenie_klienta',
            'klient:' || v_message_id::text,
            10,
            v_topic.sluzhebnyy_chat_id,
            v_topic.message_thread_id,
            COALESCE(v_bezopasnaya_podpis, 'Клиент'),
            v_tekst,
            jsonb_build_object(
                'soobshchenie_id', v_message_id,
                'kanal', v_kanal
            ),
            'zaplanirovano'
        )
        ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy
       SET status = 'zaregistrirovano',
           kod_oshibki = NULL
     WHERE id = v_event_id;

    RETURN QUERY SELECT
        v_operaciya_id, 'uspeshno'::text, NULL::text,
        'Вход зарегистрирован долговечно.'::text,
        NULL::timestamptz,
        v_user_id, v_identity_id, v_dialog_id, v_message_id, v_job_id, v_dialog_version;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_vlozhenie(
    p_dannye jsonb,
    p_soderzhimoe bytea DEFAULT NULL
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    vlozhenie_id uuid,
    soobshchenie_id uuid,
    dialog_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya_id text;
    v_message_id uuid;
    v_message record;
    v_tip text;
    v_file_id text;
    v_file_unique text;
    v_imya text;
    v_mime text;
    v_razmer bigint;
    v_actual bigint;
    v_limit bigint;
    v_dlitelnost integer;
    v_shirina integer;
    v_vysota integer;
    v_sha text;
    v_status text;
    v_storage text;
    v_key text;
    v_ai boolean;
    v_meta jsonb;
    v_existing record;
    v_attachment_id uuid;
    v_topic_chat text;
    v_topic_thread text;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid;
        RETURN;
    END IF;

    v_operaciya_id := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_message_id := NULLIF(p_dannye->>'soobshchenie_id', '')::uuid;
    v_tip := NULLIF(btrim(p_dannye->>'tip_vlozheniya'), '');
    v_file_id := NULLIF(btrim(p_dannye->>'vneshniy_file_id'), '');
    v_file_unique := NULLIF(btrim(p_dannye->>'vneshniy_file_unique_id'), '');
    v_imya := NULLIF(p_dannye->>'imya_fayla', '');
    v_mime := NULLIF(btrim(p_dannye->>'mime'), '');
    v_razmer := NULLIF(p_dannye->>'razmer_bayt', '')::bigint;
    v_limit := NULLIF(p_dannye->>'maks_razmer_bayt', '')::bigint;
    v_dlitelnost := NULLIF(p_dannye->>'dlitelnost_sekund', '')::integer;
    v_shirina := NULLIF(p_dannye->>'shirina', '')::integer;
    v_vysota := NULLIF(p_dannye->>'vysota', '')::integer;
    v_sha := NULLIF(btrim(p_dannye->>'sha256'), '');
    v_status := COALESCE(NULLIF(btrim(p_dannye->>'status_sohraneniya'), ''), 'tolko_metadannye');
    v_storage := NULLIF(btrim(p_dannye->>'hranilishche_tip'), '');
    v_key := NULLIF(p_dannye->>'hranilishche_klyuch', '');
    v_ai := COALESCE((p_dannye->>'razresheno_ai')::boolean, false);
    v_meta := COALESCE(p_dannye->'bezopasnye_metadannye', '{}'::jsonb);
    v_actual := CASE
        WHEN p_soderzhimoe IS NULL THEN NULL
        ELSE octet_length(p_soderzhimoe)
    END;

    IF v_operaciya_id IS NULL
       OR v_message_id IS NULL
       OR v_tip IS NULL
       OR (v_file_id IS NULL AND v_file_unique IS NULL)
       OR v_status NOT IN ('tolko_metadannye', 'sohraneno', 'oshibka', 'udaleno')
       OR jsonb_typeof(v_meta) <> 'object'
       OR (v_limit IS NOT NULL AND v_limit <= 0)
    THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Не заполнены обязательные поля вложения.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, NULL::uuid;
        RETURN;
    END IF;

    SELECT m.*
      INTO v_message
      FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
     WHERE m.id = v_message_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'soobshchenie_ne_naydeno'::text,
            'Сообщение для вложения не найдено.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, NULL::uuid;
        RETURN;
    END IF;

    IF v_message.napravlenie <> 'vhodyashchee'
       OR v_message.avtor <> 'klient' THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'nedopustimoe_soobshchenie'::text,
            'Вложение можно сохранить только для входящего сообщения клиента.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    IF v_actual IS NOT NULL
       AND v_limit IS NULL THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'limit_ne_zadan'::text,
            'Для сохранения байтов требуется доверенный maks_razmer_bayt.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    IF v_actual IS NOT NULL
       AND v_actual > v_limit THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'prevyshen_limit_fayla'::text,
            'Фактический размер файла превышает доверенный лимит.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    IF v_razmer IS NOT NULL
       AND v_actual IS NOT NULL
       AND v_razmer <> v_actual THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'konflikt'::text, 'razmer_ne_sovpadaet'::text,
            'Заявленный и фактический размеры вложения не совпадают.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    IF v_tip IN ('photo', 'video')
       AND v_ai THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'media_ai_zapreshcheno'::text,
            'Фото/видео v1 нельзя помечать разрешёнными для AI.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            v_message_id::text
            || pg_catalog.chr(31)
            || COALESCE(v_file_unique, v_file_id),
            2
        )
    );

    SELECT a.*
      INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy AS a
     WHERE a.soobshchenie_id = v_message_id
       AND (
            (v_file_id IS NOT NULL AND a.vneshniy_file_id = v_file_id)
            OR
            (v_file_unique IS NOT NULL AND a.vneshniy_file_unique_id = v_file_unique)
       )
     ORDER BY a.vremya_sozdaniya
     LIMIT 1;

    IF FOUND THEN
        IF v_existing.tip_vlozheniya IS DISTINCT FROM v_tip
           OR v_existing.sha256 IS DISTINCT FROM v_sha
           OR v_existing.razmer_bayt IS DISTINCT FROM COALESCE(v_actual, v_razmer)
        THEN
            RETURN QUERY SELECT
                v_operaciya_id, 'konflikt'::text, 'vlozhenie_conflict'::text,
                'То же внешнее вложение уже сохранено с другими проверенными свойствами.'::text,
                NULL::timestamptz,
                v_existing.id, v_message_id, v_message.dialog_id;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operaciya_id, 'dublikat'::text, NULL::text,
            'Вложение уже сохранено; возвращён прежний ID.'::text,
            NULL::timestamptz,
            v_existing.id, v_message_id, v_message.dialog_id;
        RETURN;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (
        soobshchenie_id,
        tip_vlozheniya,
        vneshniy_file_id,
        vneshniy_file_unique_id,
        imya_fayla,
        mime,
        razmer_bayt,
        dlitelnost_sekund,
        shirina,
        vysota,
        sha256,
        status_sohraneniya,
        hranilishche_tip,
        soderzhimoe,
        hranilishche_klyuch,
        razresheno_ai,
        bezopasnye_metadannye
    )
    VALUES (
        v_message_id,
        v_tip,
        v_file_id,
        v_file_unique,
        v_imya,
        v_mime,
        COALESCE(v_actual, v_razmer),
        v_dlitelnost,
        v_shirina,
        v_vysota,
        v_sha,
        v_status,
        v_storage,
        p_soderzhimoe,
        v_key,
        v_ai,
        v_meta
    )
    RETURNING id
    INTO v_attachment_id;

    IF v_tip IN ('voice', 'photo', 'video') THEN
        SELECT
            t.sluzhebnyy_chat_id,
            t.message_thread_id
          INTO
            v_topic_chat,
            v_topic_thread
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
         WHERE t.dialog_id = v_message.dialog_id;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
            dialog_id,
            soobshchenie_id,
            vlozhenie_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            prioritet,
            cel_chat_id,
            cel_thread_id,
            payload,
            status
        )
        VALUES (
            v_message.dialog_id,
            v_message_id,
            v_attachment_id,
            'media_klienta',
            'media:' || v_attachment_id::text,
            20,
            v_topic_chat,
            v_topic_thread,
            jsonb_build_object(
                'vlozhenie_id', v_attachment_id,
                'tip_vlozheniya', v_tip,
                'mime', v_mime,
                'razmer_bayt', COALESCE(v_actual, v_razmer)
            ),
            'zaplanirovano'
        )
        ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;
    END IF;

    RETURN QUERY SELECT
        v_operaciya_id, 'uspeshno'::text, NULL::text,
        'Вложение сохранено локально; media mirror intent создан при необходимости.'::text,
        NULL::timestamptz,
        v_attachment_id, v_message_id, v_message.dialog_id;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_transkripciyu_golosa(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    transkripciya_id uuid,
    soobshchenie_id uuid,
    status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya_id text;
    v_message_id uuid;
    v_message record;
    v_status text;
    v_raw text;
    v_deid text;
    v_engine text;
    v_engine_version text;
    v_attempts integer;
    v_start timestamptz;
    v_finish timestamptz;
    v_error_code text;
    v_error_desc text;
    v_existing record;
    v_id uuid;
BEGIN
    v_operaciya_id := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_message_id := NULLIF(p_dannye->>'soobshchenie_id', '')::uuid;
    v_status := NULLIF(btrim(p_dannye->>'status'), '');
    v_raw := p_dannye->>'tekst_transkripcii';
    v_deid := p_dannye->>'tekst_obezlichennyy';
    v_engine := NULLIF(btrim(p_dannye->>'dvizhok'), '');
    v_engine_version := NULLIF(btrim(p_dannye->>'versiya_dvizhka'), '');
    v_attempts := COALESCE((p_dannye->>'popytki')::integer, 0);
    v_start := NULLIF(p_dannye->>'vremya_nachala', '')::timestamptz;
    v_finish := NULLIF(p_dannye->>'vremya_zaversheniya', '')::timestamptz;
    v_error_code := NULLIF(btrim(p_dannye->>'kod_oshibki'), '');
    v_error_desc := p_dannye->>'opisanie_oshibki';

    IF v_operaciya_id IS NULL
       OR v_message_id IS NULL
       OR v_status NOT IN ('zaplanirovana', 'v_rabote', 'gotova', 'oshibka')
       OR v_attempts < 0
       OR (v_status = 'gotova' AND v_raw IS NULL)
       OR (v_status = 'oshibka' AND v_error_code IS NULL)
    THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректные данные локальной транскрипции.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_status;
        RETURN;
    END IF;

    SELECT m.*
      INTO v_message
      FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
     WHERE m.id = v_message_id
     FOR UPDATE;

    IF NOT FOUND
       OR v_message.napravlenie <> 'vhodyashchee'
       OR v_message.avtor <> 'klient'
       OR v_message.vid <> 'voice' THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'ne_golosovoe_soobshchenie'::text,
            'Транскрипция разрешена только для существующего voice-сообщения клиента.'::text,
            NULL::timestamptz, NULL::uuid, v_message_id, v_status;
        RETURN;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            v_message_id::text,
            3
        )
    );

    SELECT t.*
      INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa AS t
     WHERE t.soobshchenie_id = v_message_id
     FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa (
            soobshchenie_id,
            status,
            tekst_transkripcii,
            tekst_obezlichennyy,
            dvizhok,
            versiya_dvizhka,
            popytki,
            vremya_nachala,
            vremya_zaversheniya,
            kod_oshibki,
            opisanie_oshibki
        )
        VALUES (
            v_message_id,
            v_status,
            v_raw,
            v_deid,
            v_engine,
            v_engine_version,
            v_attempts,
            v_start,
            v_finish,
            v_error_code,
            v_error_desc
        )
        RETURNING id
        INTO v_id;

        RETURN QUERY SELECT
            v_operaciya_id, 'uspeshno'::text, NULL::text,
            'Состояние локальной транскрипции сохранено.'::text,
            NULL::timestamptz, v_id, v_message_id, v_status;
        RETURN;
    END IF;

    v_id := v_existing.id;

    IF v_existing.status = v_status
       AND v_existing.tekst_transkripcii IS NOT DISTINCT FROM v_raw
       AND v_existing.tekst_obezlichennyy IS NOT DISTINCT FROM v_deid
       AND v_existing.dvizhok IS NOT DISTINCT FROM v_engine
       AND v_existing.versiya_dvizhka IS NOT DISTINCT FROM v_engine_version
       AND v_existing.kod_oshibki IS NOT DISTINCT FROM v_error_code THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'dublikat'::text, NULL::text,
            'То же состояние транскрипции уже сохранено.'::text,
            NULL::timestamptz, v_id, v_message_id, v_existing.status;
        RETURN;
    END IF;

    IF v_existing.status = 'gotova'
       AND (
            v_status <> 'gotova'
            OR v_existing.tekst_transkripcii IS DISTINCT FROM v_raw
       )
    THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'konflikt'::text, 'gotovaya_transkripciya_neizmenyaema'::text,
            'Готовая транскрипция уже зафиксирована и не перезаписывается другим содержимым.'::text,
            NULL::timestamptz, v_id, v_message_id, v_existing.status;
        RETURN;
    END IF;

    IF v_existing.status = 'oshibka'
       AND v_status = 'zaplanirovana' THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'konflikt'::text, 'nedopustimyy_perehod_statusa'::text,
            'После ошибки новый цикл должен начинаться со статуса v_rabote.'::text,
            NULL::timestamptz, v_id, v_message_id, v_existing.status;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa AS t_upd
       SET status = v_status,
           tekst_transkripcii = v_raw,
           tekst_obezlichennyy = v_deid,
           dvizhok = v_engine,
           versiya_dvizhka = v_engine_version,
           popytki = GREATEST(t_upd.popytki, v_attempts),
           vremya_nachala = COALESCE(v_start, vremya_nachala),
           vremya_zaversheniya = v_finish,
           kod_oshibki = v_error_code,
           opisanie_oshibki = v_error_desc,
           vremya_obnovleniya = clock_timestamp()
     WHERE t_upd.id = v_id;

    RETURN QUERY SELECT
        v_operaciya_id, 'uspeshno'::text, NULL::text,
        'Состояние локальной транскрипции обновлено.'::text,
        NULL::timestamptz, v_id, v_message_id, v_status;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_obezlichivanie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    soobshchenie_id uuid,
    dialog_id uuid,
    kolichestvo_sootvetstviy integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya_id text;
    v_message_id uuid;
    v_deid text;
    v_maps jsonb;
    v_message record;
    v_item jsonb;
    v_tip text;
    v_placeholder text;
    v_protected text;
    v_hash text;
    v_expiry timestamptz;
    v_phone_region text;
    v_phone_digits text;
    v_phone_explicit text;
    v_existing record;
    v_count integer := 0;
    v_all_same boolean := true;
BEGIN
    v_operaciya_id := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_message_id := NULLIF(p_dannye->>'soobshchenie_id', '')::uuid;
    v_deid := p_dannye->>'tekst_obezlichennyy';
    v_maps := COALESCE(p_dannye->'sootvetstviya', '[]'::jsonb);

    IF v_operaciya_id IS NULL
       OR v_message_id IS NULL
       OR v_deid IS NULL
       OR jsonb_typeof(v_maps) <> 'array' THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректный пакет обезличивания.'::text,
            NULL::timestamptz, v_message_id, NULL::uuid, 0;
        RETURN;
    END IF;

    SELECT m.*, d.polzovatel_id
      INTO v_message
      FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
      JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
        ON d.id = m.dialog_id
     WHERE m.id = v_message_id
     FOR UPDATE OF m;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'otkaz'::text, 'soobshchenie_ne_naydeno'::text,
            'Сообщение для обезличивания не найдено.'::text,
            NULL::timestamptz, v_message_id, NULL::uuid, 0;
        RETURN;
    END IF;

    IF v_message.tekst_obezlichennyy IS NOT NULL
       AND v_message.tekst_obezlichennyy IS DISTINCT FROM v_deid THEN
        RETURN QUERY SELECT
            v_operaciya_id, 'konflikt'::text, 'obezlichivanie_conflict'::text,
            'Для сообщения уже сохранён другой обезличенный текст.'::text,
            NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
        RETURN;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            v_message.dialog_id::text,
            4
        )
    );

    -- Pass 1: validate the whole mapping before any insert, so a conflict
    -- cannot leave a partially written reverse map.
    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_maps)
    LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION
                'PII mapping item must be an object';
        END IF;

        v_tip := NULLIF(btrim(v_item->>'tip_pii'), '');
        v_placeholder := NULLIF(btrim(v_item->>'psevdometka'), '');
        v_protected := v_item->>'znachenie_zashchishchennoe';
        v_hash := NULLIF(btrim(v_item->>'hash_normalizovannogo_znacheniya'), '');
        v_expiry := NULLIF(v_item->>'deystvitelno_do', '')::timestamptz;
        v_phone_region := upper(
            COALESCE(
                NULLIF(btrim(v_item->>'region_telefona'), ''),
                NULLIF(btrim(p_dannye->>'region_telefona'), '')
            )
        );
        v_phone_explicit := NULLIF(btrim(v_item->>'znachenie_normalizovannoe'), '');

        -- Detection happens locally before this function. Here an already
        -- detected phone is canonicalized so punctuation/8/+7 formatting
        -- cannot create different protected values.
        IF v_tip = 'telefon' THEN
            IF v_phone_explicit IS NOT NULL THEN
                IF v_phone_explicit !~ '^\+[0-9]{8,15}$' THEN
                    RETURN QUERY SELECT
                        v_operaciya_id, 'otkaz'::text, 'telefon_ne_normalizovan'::text,
                        'Нормализованный телефон должен иметь формат + и 8–15 цифр.'::text,
                        NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                    RETURN;
                END IF;
                v_protected := v_phone_explicit;
            ELSE
                v_phone_digits := regexp_replace(v_protected, '[^0-9]', '', 'g');

                IF v_phone_region = 'RU' THEN
                    IF length(v_phone_digits) = 11
                       AND left(v_phone_digits, 1) IN ('7', '8') THEN
                        v_protected := '+7' || right(v_phone_digits, 10);
                    ELSIF length(v_phone_digits) = 10 THEN
                        v_protected := '+7' || v_phone_digits;
                    ELSIF btrim(v_item->>'znachenie_zashchishchennoe') LIKE '+%'
                       AND length(v_phone_digits) BETWEEN 8 AND 15 THEN
                        v_protected := '+' || v_phone_digits;
                    ELSE
                        RETURN QUERY SELECT
                            v_operaciya_id, 'otkaz'::text, 'telefon_ne_normalizovan'::text,
                            'Телефон не удалось безопасно нормализовать для региона RU.'::text,
                            NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                        RETURN;
                    END IF;
                ELSIF btrim(v_item->>'znachenie_zashchishchennoe') LIKE '+%'
                   AND length(v_phone_digits) BETWEEN 8 AND 15 THEN
                    v_protected := '+' || v_phone_digits;
                ELSE
                    RETURN QUERY SELECT
                        v_operaciya_id, 'otkaz'::text, 'telefon_nuzhen_region'::text,
                        'Для национального формата нужен доверенный region_telefona или явное нормализованное значение.'::text,
                        NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                    RETURN;
                END IF;
            END IF;
        END IF;

        IF v_tip IS NULL
           OR v_placeholder IS NULL
           OR v_protected IS NULL
           OR v_protected = '' THEN
            RAISE EXCEPTION
                'PII mapping requires tip_pii, psevdometka and protected value';
        END IF;

        SELECT p.*
          INTO v_existing
          FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii AS p
         WHERE p.dialog_id = v_message.dialog_id
           AND p.psevdometka = v_placeholder
         FOR UPDATE;

        IF FOUND
           AND (
                v_existing.tip_pii IS DISTINCT FROM v_tip
                OR v_existing.znachenie_zashchishchennoe IS DISTINCT FROM v_protected
                OR v_existing.hash_normalizovannogo_znacheniya IS DISTINCT FROM v_hash
           )
        THEN
            RETURN QUERY SELECT
                v_operaciya_id, 'konflikt'::text, 'pii_placeholder_conflict'::text,
                'Та же PII-псевдометка уже связана с другим локальным значением.'::text,
                NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
            RETURN;
        END IF;
    END LOOP;

    -- Pass 2: after the whole set is known conflict-free, insert only missing mappings.
    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_maps)
    LOOP
        v_tip := NULLIF(btrim(v_item->>'tip_pii'), '');
        v_placeholder := NULLIF(btrim(v_item->>'psevdometka'), '');
        v_protected := v_item->>'znachenie_zashchishchennoe';
        v_hash := NULLIF(btrim(v_item->>'hash_normalizovannogo_znacheniya'), '');
        v_expiry := NULLIF(v_item->>'deystvitelno_do', '')::timestamptz;
        v_phone_region := upper(
            COALESCE(
                NULLIF(btrim(v_item->>'region_telefona'), ''),
                NULLIF(btrim(p_dannye->>'region_telefona'), '')
            )
        );
        v_phone_explicit := NULLIF(btrim(v_item->>'znachenie_normalizovannoe'), '');

        -- Detection happens locally before this function. Here an already
        -- detected phone is canonicalized so punctuation/8/+7 formatting
        -- cannot create different protected values.
        IF v_tip = 'telefon' THEN
            IF v_phone_explicit IS NOT NULL THEN
                IF v_phone_explicit !~ '^\+[0-9]{8,15}$' THEN
                    RETURN QUERY SELECT
                        v_operaciya_id, 'otkaz'::text, 'telefon_ne_normalizovan'::text,
                        'Нормализованный телефон должен иметь формат + и 8–15 цифр.'::text,
                        NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                    RETURN;
                END IF;
                v_protected := v_phone_explicit;
            ELSE
                v_phone_digits := regexp_replace(v_protected, '[^0-9]', '', 'g');

                IF v_phone_region = 'RU' THEN
                    IF length(v_phone_digits) = 11
                       AND left(v_phone_digits, 1) IN ('7', '8') THEN
                        v_protected := '+7' || right(v_phone_digits, 10);
                    ELSIF length(v_phone_digits) = 10 THEN
                        v_protected := '+7' || v_phone_digits;
                    ELSIF btrim(v_item->>'znachenie_zashchishchennoe') LIKE '+%'
                       AND length(v_phone_digits) BETWEEN 8 AND 15 THEN
                        v_protected := '+' || v_phone_digits;
                    ELSE
                        RETURN QUERY SELECT
                            v_operaciya_id, 'otkaz'::text, 'telefon_ne_normalizovan'::text,
                            'Телефон не удалось безопасно нормализовать для региона RU.'::text,
                            NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                        RETURN;
                    END IF;
                ELSIF btrim(v_item->>'znachenie_zashchishchennoe') LIKE '+%'
                   AND length(v_phone_digits) BETWEEN 8 AND 15 THEN
                    v_protected := '+' || v_phone_digits;
                ELSE
                    RETURN QUERY SELECT
                        v_operaciya_id, 'otkaz'::text, 'telefon_nuzhen_region'::text,
                        'Для национального формата нужен доверенный region_telefona или явное нормализованное значение.'::text,
                        NULL::timestamptz, v_message_id, v_message.dialog_id, 0;
                    RETURN;
                END IF;
            END IF;
        END IF;

        SELECT p.*
          INTO v_existing
          FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii AS p
         WHERE p.dialog_id = v_message.dialog_id
           AND p.psevdometka = v_placeholder;

        IF NOT FOUND THEN
            INSERT INTO qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (
                dialog_id,
                polzovatel_id,
                soobshchenie_id,
                tip_pii,
                psevdometka,
                znachenie_zashchishchennoe,
                hash_normalizovannogo_znacheniya,
                deystvitelno_do
            )
            VALUES (
                v_message.dialog_id,
                v_message.polzovatel_id,
                v_message_id,
                v_tip,
                v_placeholder,
                v_protected,
                v_hash,
                v_expiry
            );
            v_all_same := false;
        END IF;

        v_count := v_count + 1;
    END LOOP;

    IF v_message.tekst_obezlichennyy IS NULL THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya
           SET tekst_obezlichennyy = v_deid
         WHERE id = v_message_id;
        v_all_same := false;
    END IF;

    RETURN QUERY SELECT
        v_operaciya_id,
        CASE WHEN v_all_same THEN 'dublikat' ELSE 'uspeshno' END::text,
        NULL::text,
        CASE
            WHEN v_all_same
            THEN 'Обезличенный текст и PII-соответствия уже были сохранены.'
            ELSE 'Обезличенный текст и локальные PII-соответствия сохранены атомарно.'
        END::text,
        NULL::timestamptz,
        v_message_id,
        v_message.dialog_id,
        v_count;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontekst_dialoga(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
      JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
      FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
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
      FROM qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga AS p
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
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
         WHERE m.id = v_processed_id
           AND m.dialog_id = v_dialog_id;
    END IF;

    SELECT COALESCE(
        jsonb_object_agg(f.kod_polya, f.znachenie_dlya_ai),
        '{}'::jsonb
    )
      INTO v_ai_facts
      FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS f
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
              FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
              LEFT JOIN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa AS tg
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
      FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS f
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
      FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii AS p
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_fakty_i_pamyat(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
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
      FROM qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga AS p
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
              FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
          LEFT JOIN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa AS tg
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
              FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii AS p
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
          FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
          FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS f
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

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS new_fact (
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
            UPDATE qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS old_fact
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
      FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga AS f
     WHERE f.dialog_id = v_dialog_id
       AND f.zamenen_faktom_id IS NULL
       AND f.podtverzhden = true
       AND f.znachenie_dlya_ai IS NOT NULL
       AND (
            f.deystvitelno_do IS NULL
            OR f.deystvitelno_do >= clock_timestamp()
       );

    IF NOT v_memory_exists THEN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga AS new_memory (
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
        UPDATE qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga AS p_upd
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.proverit_limit_chastoty(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
      JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
                  FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
                  JOIN qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zapisat_narushenie_tematiky(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
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
      FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
      FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky AS n
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

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i_upd
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
        UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_upd
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

        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_upd
           SET status = 'otmeneno',
               prichina = 'logicheskaya_blokirovka',
               vremya_obnovleniya = clock_timestamp()
         WHERE n_upd.dialog_id = v_dialog_id
           AND n_upd.status IN ('zaplanirovano', 'v_rabote');

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.razblokirovat_polzovatelya(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya AS z
     WHERE z.deystvie = 'razblokirovat_polzovatelya'
       AND z.tip_obekta = 'identifikator_kanala'
       AND z.obekt_id = v_identity_id::text
       AND z.trassirovka_id = v_operaciya
     LIMIT 1;

    IF FOUND THEN
        SELECT i.*
          INTO v_identity
          FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i_upd
       SET logicheski_zablokirovan = false,
           vremya_blokirovki = NULL,
           prichina_blokirovki = NULL,
           schetchik_narusheniy = v_new_counter,
           vremya_obnovleniya = clock_timestamp()
     WHERE i_upd.id = v_identity_id;

    -- State change invalidates any stale in-flight bot decision.
    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_upd
       SET versiya_dialoga = d_upd.versiya_dialoga + 1,
           vremya_obnovleniya = clock_timestamp()
     WHERE d_upd.identifikator_kanala_id = v_identity_id
       AND d_upd.status <> 'zavershen'
       AND d_upd.vladelec = 'bot';

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_obrabotki(
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
    sobytie_id uuid,
    tip_zadaniya text,
    status_zadaniya text,
    prioritet integer,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga bigint,
    payload jsonb,
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
    v_cleanup_reason text;
    v_was_reclaim boolean;
    v_iteration integer;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
            NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint, NULL::jsonb, false;
        RETURN;
    END IF;

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
            'Нужны operaciya_id, worker_id и trusted arenda_sekund 10..3600.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
            NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint, NULL::jsonb, false;
        RETURN;
    END IF;

    -- A single call may clean a bounded number of stale due jobs before
    -- returning one usable job. It never waits on rows claimed elsewhere.
    FOR v_iteration IN 1..50 LOOP
        v_now := clock_timestamp();

        SELECT
            z.id AS job_id,
            z.dialog_id,
            z.sobytie_id,
            z.tip_zadaniya,
            z.status AS job_status,
            z.prioritet,
            z.popytki,
            z.vladelec_arendy,
            z.arenda_do,
            z.nomer_vladeniya,
            z.versiya_dialoga AS job_dialog_version,
            z.payload,
            d.versiya_dialoga AS current_dialog_version,
            d.vladelec AS dialog_owner,
            d.status AS dialog_status,
            i.logicheski_zablokirovan AS identity_blocked
          INTO v_candidate
          FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z
          JOIN qbit_bot_pervichnogo_obrascheniya.dialogi AS d
            ON d.id = z.dialog_id
          JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
            ON i.id = d.identifikator_kanala_id
         WHERE (
                (
                    z.status IN ('ozhidaet', 'povtor')
                    AND z.sleduyushchiy_zapusk <= v_now
                    AND NOT EXISTS (
                        SELECT 1
                          FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS active_job
                         WHERE active_job.dialog_id = z.dialog_id
                           AND active_job.status = 'v_rabote'
                    )
                )
                OR
                (
                    z.status = 'v_rabote'
                    AND z.arenda_do <= v_now
                )
         )
         ORDER BY
            z.prioritet DESC,
            CASE
                WHEN z.status = 'v_rabote' THEN z.arenda_do
                ELSE z.sleduyushchiy_zapusk
            END,
            z.vremya_sozdaniya,
            z.id
         FOR UPDATE OF z, d SKIP LOCKED
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                v_operaciya, 'net_zadaniya'::text, NULL::text,
                'Готового задания сейчас нет.'::text, NULL::timestamptz,
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
                NULL::bigint, NULL::bigint, NULL::jsonb, false;
            RETURN;
        END IF;

        v_cleanup_reason := CASE
            WHEN v_candidate.job_dialog_version
                 IS DISTINCT FROM v_candidate.current_dialog_version
            THEN 'stale_dialog_version'
            WHEN v_candidate.identity_blocked
            THEN 'logicheski_zablokirovan'
            WHEN v_candidate.dialog_owner <> 'bot'
            THEN 'vladelec_ne_bot'
            WHEN v_candidate.dialog_status IN ('peredan_cheloveku', 'zavershen')
            THEN 'dialog_ne_aktiven'
            ELSE NULL
        END;

        IF v_cleanup_reason IS NOT NULL THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z_cancel
               SET status = 'otmeneno',
                   vladelec_arendy = NULL,
                   arenda_do = NULL,
                   kod_oshibki = v_cleanup_reason,
                   opisanie_oshibki = 'DB-03C3 claim cleanup: задание устарело или больше не разрешено состоянием диалога.',
                   vremya_obnovleniya = clock_timestamp()
             WHERE z_cancel.id = v_candidate.job_id;
            CONTINUE;
        END IF;

        v_was_reclaim := (
            v_candidate.job_status = 'v_rabote'
            AND v_candidate.arenda_do <= v_now
        );

        UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z_claim
           SET status = 'v_rabote',
               popytki = z_claim.popytki + 1,
               vladelec_arendy = v_worker,
               arenda_do = v_now + make_interval(secs => v_lease_seconds),
               nomer_vladeniya = z_claim.nomer_vladeniya + 1,
               kod_oshibki = NULL,
               opisanie_oshibki = NULL,
               vremya_obnovleniya = clock_timestamp()
         WHERE z_claim.id = v_candidate.job_id
         RETURNING
            z_claim.id,
            z_claim.dialog_id,
            z_claim.sobytie_id,
            z_claim.tip_zadaniya,
            z_claim.status,
            z_claim.prioritet,
            z_claim.popytki,
            z_claim.vladelec_arendy,
            z_claim.arenda_do,
            z_claim.nomer_vladeniya,
            z_claim.versiya_dialoga,
            z_claim.payload
          INTO v_claimed;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            CASE
                WHEN v_was_reclaim
                THEN 'Истёкшая аренда безопасно перехвачена с новым fencing number.'
                ELSE 'Готовое задание атомарно выдано worker.'
            END::text,
            NULL::timestamptz,
            v_claimed.id,
            v_claimed.dialog_id,
            v_claimed.sobytie_id,
            v_claimed.tip_zadaniya,
            v_claimed.status,
            v_claimed.prioritet,
            v_claimed.popytki,
            v_claimed.vladelec_arendy,
            v_claimed.arenda_do,
            v_claimed.nomer_vladeniya,
            v_claimed.versiya_dialoga,
            v_claimed.payload,
            v_was_reclaim;
        RETURN;
    END LOOP;

    RETURN QUERY SELECT
        v_operaciya, 'povtor'::text, 'ochistka_limit'::text,
        'За один claim очищено 50 неактуальных due jobs; безопасно повторить claim.'::text,
        clock_timestamp() + interval '1 second',
        NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
        NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
        NULL::bigint, NULL::bigint, NULL::jsonb, false;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    zadanie_id uuid,
    status_zadaniya text,
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
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_lease_seconds integer;
    v_now timestamptz;
    v_job record;
    v_dialog_version bigint;
    v_dialog_owner text;
    v_dialog_status text;
    v_identity_blocked boolean;
    v_new_lease timestamptz;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund', '')::integer;
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны job, worker, fencing number и trusted lease 10..3600.'::text,
            NULL::timestamptz,
            v_job_id, NULL::text, NULL::text, NULL::timestamptz,
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
            'Задание не найдено.'::text, NULL::timestamptz,
            v_job_id, NULL::text, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker больше не является текущим владельцем этой аренды.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL
       OR v_job.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшую аренду нельзя продлить старым worker; нужен новый claim.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    SELECT
        d.versiya_dialoga,
        d.vladelec,
        d.status,
        i.logicheski_zablokirovan
      INTO
        v_dialog_version,
        v_dialog_owner,
        v_dialog_status,
        v_identity_blocked
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
      JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
     WHERE d.id = v_job.dialog_id
     FOR UPDATE OF d;

    IF NOT FOUND
       OR v_dialog_version IS DISTINCT FROM v_job.versiya_dialoga THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Версия диалога изменилась; stale worker больше не может продлевать lease.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    IF v_identity_blocked
       OR v_dialog_owner <> 'bot'
       OR v_dialog_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Состояние identity/dialog больше не разрешает продление bot lease.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    v_new_lease := GREATEST(
        v_job.arenda_do,
        v_now + make_interval(secs => v_lease_seconds)
    );

    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z_upd
       SET arenda_do = v_new_lease,
           vremya_obnovleniya = clock_timestamp()
     WHERE z_upd.id = v_job_id;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Аренда текущего worker продлена без изменения fencing number.'::text,
        NULL::timestamptz,
        v_job_id, 'v_rabote'::text, v_worker,
        v_new_lease, v_ownership, v_job.versiya_dialoga;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_obrabotki(
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
    status_zadaniya text,
    popytki integer,
    sleduyushchiy_zapusk timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga_zadaniya bigint,
    tekushchaya_versiya_dialoga bigint
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
    v_expected_dialog bigint;
    v_target_status text;
    v_retry_at timestamptz;
    v_error_code text;
    v_error_description text;
    v_now timestamptz;

    v_job record;
    v_dialog_version bigint;
    v_dialog_owner text;
    v_dialog_status text;
    v_identity_blocked boolean;
    v_saved record;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_expected_dialog := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_target_status := NULLIF(btrim(p_dannye->>'status'), '');
    v_retry_at := NULLIF(p_dannye->>'sleduyushchiy_zapusk', '')::timestamptz;
    v_error_code := NULLIF(btrim(p_dannye->>'kod_oshibki'), '');
    v_error_description := NULLIF(btrim(p_dannye->>'opisanie_oshibki'), '');
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_expected_dialog IS NULL
       OR v_expected_dialog < 1
       OR v_target_status NOT IN ('zaversheno', 'povtor', 'otmeneno', 'oshibka')
       OR (
            v_target_status = 'povtor'
            AND (
                v_retry_at IS NULL
                OR v_retry_at <= v_now
                OR v_error_code IS NULL
            )
       )
       OR (
            v_target_status = 'oshibka'
            AND v_error_code IS NULL
       ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректные completion данные; retry требует future time+error, oshibka требует error code.'::text,
            NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::text, NULL::integer,
            NULL::timestamptz, NULL::bigint, NULL::bigint, NULL::bigint;
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
            'Задание не найдено.'::text, NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::text, NULL::integer,
            NULL::timestamptz, NULL::bigint, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker/fencing number больше не владеет этим заданием.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL
       OR v_job.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая аренда не имеет права записывать результат.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    SELECT
        d.versiya_dialoga,
        d.vladelec,
        d.status,
        i.logicheski_zablokirovan
      INTO
        v_dialog_version,
        v_dialog_owner,
        v_dialog_status,
        v_identity_blocked
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
      JOIN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
     WHERE d.id = v_job.dialog_id
     FOR UPDATE OF d;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_nayden'::text,
            'Диалог задания больше не существует.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.versiya_dialoga IS DISTINCT FROM v_expected_dialog
       OR v_dialog_version IS DISTINCT FROM v_expected_dialog THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Результат вычислен для устаревшей версии диалога.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, v_dialog_version;
        RETURN;
    END IF;

    IF v_identity_blocked
       OR v_dialog_owner <> 'bot'
       OR v_dialog_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Состояние identity/dialog больше не разрешает bot completion.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, v_dialog_version;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS z_done
       SET status = v_target_status,
           sleduyushchiy_zapusk = CASE
               WHEN v_target_status = 'povtor' THEN v_retry_at
               ELSE z_done.sleduyushchiy_zapusk
           END,
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = CASE
               WHEN v_target_status = 'zaversheno' THEN NULL
               ELSE v_error_code
           END,
           opisanie_oshibki = CASE
               WHEN v_target_status = 'zaversheno' THEN NULL
               ELSE v_error_description
           END,
           vremya_obnovleniya = clock_timestamp()
     WHERE z_done.id = v_job_id
     RETURNING
        z_done.id,
        z_done.dialog_id,
        z_done.status,
        z_done.popytki,
        z_done.sleduyushchiy_zapusk,
        z_done.nomer_vladeniya,
        z_done.versiya_dialoga
      INTO v_saved;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        CASE v_target_status
            WHEN 'zaversheno' THEN 'Задание завершено текущим владельцем.'
            WHEN 'povtor' THEN 'Безопасный retry запланирован; аренда освобождена.'
            WHEN 'otmeneno' THEN 'Задание отменено текущим владельцем; аренда освобождена.'
            ELSE 'Задание завершено постоянной ошибкой; аренда освобождена.'
        END::text,
        CASE WHEN v_target_status = 'povtor' THEN v_retry_at ELSE NULL END,
        v_saved.id,
        v_saved.dialog_id,
        v_saved.status,
        v_saved.popytki,
        v_saved.sleduyushchiy_zapusk,
        v_saved.nomer_vladeniya,
        v_saved.versiya_dialoga,
        v_dialog_version;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ishodyashchee_deystvie(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora = v_key;

    IF FOUND THEN
        IF v_existing.soobshchenie_id IS NOT NULL THEN
            SELECT m.*
              INTO v_existing_message
              FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
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
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
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
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS new_message (
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

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS new_action (
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.podgotovit_napominanie(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id = v_reminder.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    SELECT m.*
      INTO v_basis
      FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m
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
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_skip
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
          FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n2
         WHERE n2.dialog_id = v_reminder.dialog_id
           AND n2.pokolenie_ozhidaniya = v_reminder.pokolenie_ozhidaniya
           AND n2.tip = 'napominanie_2';

        IF v_next_rem2 IS NOT NULL
           AND v_now >= v_next_rem2 THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_skip2
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
              FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_in
             WHERE m_in.dialog_id = v_dialog.id
               AND m_in.napravlenie = 'vhodyashchee'
               AND m_in.avtor = 'klient'
               AND m_in.vremya_priema > v_reminder.t0
       ) THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_cancel
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
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
     WHERE a.klyuch_povtora = v_key;

    IF FOUND THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_link
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

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS new_message (
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

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS new_action (
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_work
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zafiksirovat_poteryu_bez_otveta(
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
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
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
      FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
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
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
     WHERE d.id = v_loss.dialog_id
     FOR UPDATE;

    SELECT i.*
      INTO v_identity
      FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov AS i
     WHERE i.id = v_dialog.identifikator_kanala_id
     FOR UPDATE;

    SELECT n2.*
      INTO v_rem2
      FROM qbit_bot_pervichnogo_obrascheniya.napominaniya AS n2
     WHERE n2.dialog_id = v_loss.dialog_id
       AND n2.pokolenie_ozhidaniya = v_loss.pokolenie_ozhidaniya
       AND n2.tip = 'napominanie_2';

    IF NOT FOUND
       OR v_rem2.status <> 'podtverzhdeno'
       OR v_rem2.vremya_fakticheskoy_otpravki IS NULL THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_bad
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
              FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS m_in
             WHERE m_in.dialog_id = v_dialog.id
               AND m_in.napravlenie = 'vhodyashchee'
               AND m_in.avtor = 'klient'
               AND m_in.vremya_priema > v_loss.t0
       ) THEN
        UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_cancel
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d_loss
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n_loss
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

    UPDATE qbit_bot_pervichnogo_obrascheniya.polzovateli AS p_loss
       SET tekushchaya_metka = 'poteryannyy',
           vremya_obnovleniya = clock_timestamp()
     WHERE p_loss.id = v_dialog.polzovatel_id;

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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    sobytie_id uuid,
    tip_sobytiya text,
    status_sobytiya text,
    payload jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_version integer;
    v_operation text;
    v_account text;
    v_external_event text;
    v_type text;
    v_idem text;
    v_hash text;
    v_payload jsonb;
    v_source_time timestamptz;
    v_receive_time timestamptz;
    v_trace text;
    v_inserted_id uuid;
    v_existing record;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::text, NULL::text, NULL::jsonb;
        RETURN;
    END IF;

    v_version := COALESCE(NULLIF(p_dannye->>'versiya_formata','')::integer, 1);
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_account := NULLIF(btrim(p_dannye->>'akkaunt_istochnika_id'),'');
    v_external_event := NULLIF(btrim(p_dannye->>'vneshnee_sobytie_id'),'');
    v_type := NULLIF(btrim(p_dannye->>'tip_sobytiya'),'');
    v_idem := NULLIF(btrim(p_dannye->>'klyuch_idempotentnosti'),'');
    v_hash := NULLIF(btrim(p_dannye->>'hash_soderzhaniya'),'');
    v_payload := p_dannye->'payload_ishodnyy';
    v_source_time := NULLIF(p_dannye->>'vremya_istochnika','')::timestamptz;
    v_receive_time := COALESCE(
        NULLIF(p_dannye->>'vremya_priema','')::timestamptz,
        clock_timestamp()
    );
    v_trace := NULLIF(btrim(p_dannye->>'trassirovka_id'),'');

    IF v_version < 1
       OR v_operation IS NULL
       OR v_account IS NULL
       OR v_external_event IS NULL
       OR v_type IS NULL
       OR v_idem IS NULL
       OR v_hash IS NULL
       OR v_payload IS NULL
       OR jsonb_typeof(v_payload) NOT IN ('object','array') THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны version/operation/account/external event/type/idempotency/hash/payload.'::text,
            NULL::timestamptz,
            NULL::uuid, v_type, NULL::text, NULL::jsonb;
        RETURN;
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS new_event (
        versiya_formata,
        operaciya_id,
        istochnik,
        akkaunt_istochnika_id,
        vneshnee_sobytie_id,
        tip_sobytiya,
        klyuch_idempotentnosti,
        hash_soderzhaniya,
        payload_ishodnyy,
        vremya_istochnika,
        vremya_priema,
        status,
        trassirovka_id
    )
    VALUES (
        v_version,
        v_operation,
        'telegram_service',
        v_account,
        v_external_event,
        v_type,
        v_idem,
        v_hash,
        v_payload,
        v_source_time,
        v_receive_time,
        'zaregistrirovano',
        v_trace
    )
    ON CONFLICT DO NOTHING
    RETURNING new_event.id
    INTO v_inserted_id;

    IF v_inserted_id IS NOT NULL THEN
        RETURN QUERY SELECT
            v_operation, 'uspeshno'::text, NULL::text,
            'Служебное Telegram-событие долговечно зарегистрировано до маршрутизации.'::text,
            NULL::timestamptz,
            v_inserted_id, v_type, 'zaregistrirovano'::text, v_payload;
        RETURN;
    END IF;

    SELECT e.*
      INTO v_existing
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
     WHERE (
            e.istochnik = 'telegram_service'
            AND e.akkaunt_istochnika_id = v_account
            AND e.vneshnee_sobytie_id = v_external_event
       )
        OR e.klyuch_idempotentnosti = v_idem
     ORDER BY
        CASE
            WHEN e.istochnik = 'telegram_service'
             AND e.akkaunt_istochnika_id = v_account
             AND e.vneshnee_sobytie_id = v_external_event
            THEN 0 ELSE 1
        END,
        e.vremya_zapisi
     LIMIT 1
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'DB-03D1 ON CONFLICT had no matching existing service event';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e2
         WHERE e2.id <> v_existing.id
           AND (
                (
                    e2.istochnik = 'telegram_service'
                    AND e2.akkaunt_istochnika_id = v_account
                    AND e2.vneshnee_sobytie_id = v_external_event
                )
                OR e2.klyuch_idempotentnosti = v_idem
           )
    ) THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'dva_raznyh_sobytiya_dlya_klyuchey'::text,
            'External event key и idempotency key указывают на разные сохранённые события.'::text,
            NULL::timestamptz,
            v_existing.id, v_existing.tip_sobytiya, v_existing.status,
            NULL::jsonb;
        RETURN;
    END IF;

    IF v_existing.istochnik = 'telegram_service'
       AND v_existing.akkaunt_istochnika_id = v_account
       AND v_existing.vneshnee_sobytie_id = v_external_event THEN
        IF v_existing.hash_soderzhaniya IS DISTINCT FROM v_hash
           OR v_existing.tip_sobytiya IS DISTINCT FROM v_type
           OR v_existing.payload_ishodnyy IS DISTINCT FROM v_payload THEN
            RETURN QUERY SELECT
                v_operation, 'konflikt'::text, 'same_event_different_content'::text,
                'Тот же внешний service event пришёл с другим содержимым.'::text,
                NULL::timestamptz,
                v_existing.id, v_existing.tip_sobytiya, v_existing.status,
                NULL::jsonb;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'dublikat'::text, NULL::text,
            'Внешнее service-событие уже было зарегистрировано.'::text,
            NULL::timestamptz,
            v_existing.id, v_existing.tip_sobytiya, v_existing.status,
            v_existing.payload_ishodnyy;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        v_operation, 'konflikt'::text, 'idempotency_key_reused'::text,
        'Idempotency key уже принадлежит другому внешнему service event.'::text,
        NULL::timestamptz,
        v_existing.id, v_existing.tip_sobytiya, v_existing.status,
        NULL::jsonb;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.podtverdit_lichnyy_chat_menedzhera(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    menedzher_id uuid,
    telegram_user_id text,
    private_chat_id text,
    private_chat_podtverzhden boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_event_id uuid;
    v_user text;
    v_chat text;
    v_confirmed_at timestamptz;
    v_event record;
    v_manager record;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_event_id := NULLIF(p_dannye->>'sobytie_id','')::uuid;
    v_user := NULLIF(btrim(p_dannye->>'telegram_user_id'),'');
    v_chat := NULLIF(btrim(p_dannye->>'private_chat_id'),'');
    v_confirmed_at := COALESCE(
        NULLIF(p_dannye->>'vremya_podtverzhdeniya','')::timestamptz,
        clock_timestamp()
    );

    IF v_operation IS NULL
       OR v_event_id IS NULL
       OR v_user IS NULL
       OR v_chat IS NULL THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/service event/telegram user/private chat.'::text,
            NULL::timestamptz,
            NULL::uuid, v_user, v_chat, false;
        RETURN;
    END IF;

    SELECT e.*
      INTO v_event
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e
     WHERE e.id = v_event_id
       AND e.istochnik = 'telegram_service'
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'sluzhebnoe_sobytie_ne_naydeno'::text,
            'Перед /start подтверждением должен существовать зарегистрированный service event.'::text,
            NULL::timestamptz,
            NULL::uuid, v_user, v_chat, false;
        RETURN;
    END IF;

    SELECT m.*
      INTO v_manager
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.telegram_user_id = v_user
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'menedzher_ne_razreshen'::text,
            'Неизвестный Telegram user не добавляется автоматически.'::text,
            NULL::timestamptz,
            NULL::uuid, v_user, v_chat, false;
        RETURN;
    END IF;

    IF NOT v_manager.aktiven THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'menedzher_ne_razreshen'::text,
            'Неактивный Telegram user не может подтвердить private chat.'::text,
            NULL::timestamptz,
            v_manager.id, v_user, v_chat, false;
        RETURN;
    END IF;

    IF v_manager.private_chat_podtverzhden THEN
        IF v_manager.private_chat_id IS NOT DISTINCT FROM v_chat THEN
            RETURN QUERY SELECT
                v_operation, 'dublikat'::text, NULL::text,
                'Private chat этого разрешённого менеджера уже подтверждён.'::text,
                NULL::timestamptz,
                v_manager.id, v_manager.telegram_user_id,
                v_manager.private_chat_id, true;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'drugoy_private_chat'::text,
            'У менеджера уже подтверждён другой private chat; автоматическая замена запрещена.'::text,
            NULL::timestamptz,
            v_manager.id, v_manager.telegram_user_id,
            v_manager.private_chat_id, true;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS other_manager
         WHERE other_manager.id <> v_manager.id
           AND other_manager.private_chat_id = v_chat
    ) THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'private_chat_uzhe_zanyat'::text,
            'Этот private chat уже связан с другим менеджером.'::text,
            NULL::timestamptz,
            v_manager.id, v_manager.telegram_user_id, NULL::text, false;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m_upd
       SET private_chat_id = v_chat,
           private_chat_podtverzhden = true,
           vremya_podtverzhdeniya = v_confirmed_at,
           vremya_obnovleniya = clock_timestamp()
     WHERE m_upd.id = v_manager.id;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy AS e_done
       SET status = 'obrabotano'
     WHERE e_done.id = v_event_id;

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        'Private chat подтверждён только для заранее разрешённого active manager.'::text,
        NULL::timestamptz,
        v_manager.id, v_manager.telegram_user_id, v_chat, true;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_sozdanie_operator_temy(
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
    vneshniy_id_kartochki text,
    status_temy text,
    operaciya_sozdaniya_id text,
    bezopasnaya_podpis_klienta text,
    payload jsonb,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    byl_perehvachen boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_worker text;
    v_dialog_id uuid;
    v_lease_seconds integer;
    v_now timestamptz;
    v_topic record;
    v_claimed record;
    v_reclaim boolean;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund','')::integer;
    v_now := clock_timestamp();

    IF v_operation IS NULL
       OR v_worker IS NULL
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/worker/trusted lease 10..3600; dialog_id optional.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::jsonb, NULL::integer,
            NULL::text, NULL::timestamptz, NULL::bigint, false;
        RETURN;
    END IF;

    IF v_dialog_id IS NOT NULL THEN
        SELECT
            t.*,
            e.bezopasnaya_podpis_klienta AS safe_client,
            e.payload AS ensure_payload
          INTO v_topic
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
          LEFT JOIN qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
            ON e.klyuch_idempotentnosti = 'tema:' || t.dialog_id::text
         WHERE t.dialog_id = v_dialog_id
         FOR UPDATE OF t SKIP LOCKED;

        IF NOT FOUND THEN
            IF EXISTS (
                SELECT 1
                  FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_busy
                 WHERE t_busy.dialog_id = v_dialog_id
            ) THEN
                RETURN QUERY SELECT
                    v_operation, 'zanyato'::text, 'tema_zablokirovana_drugim_worker'::text,
                    'Topic intent сейчас заблокирован другим worker.'::text,
                    v_now + interval '2 seconds',
                    v_dialog_id, NULL::text, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::jsonb, NULL::integer,
                    NULL::text, NULL::timestamptz, NULL::bigint, false;
                RETURN;
            END IF;

            RETURN QUERY SELECT
                v_operation, 'otkaz'::text, 'tema_ne_naydena'::text,
                'Topic intent для dialog не найден.'::text,
                NULL::timestamptz,
                v_dialog_id, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::jsonb, NULL::integer,
                NULL::text, NULL::timestamptz, NULL::bigint, false;
            RETURN;
        END IF;

        IF v_topic.status = 'gotova' THEN
            RETURN QUERY SELECT
                v_operation, 'dublikat'::text, NULL::text,
                'Operator topic уже подтверждён; второй topic не создаётся.'::text,
                NULL::timestamptz,
                v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                v_topic.message_thread_id, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.operaciya_sozdaniya_id,
                COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                v_topic.popytki, NULL::text, NULL::timestamptz,
                v_topic.nomer_vladeniya, false;
            RETURN;
        END IF;

        IF v_topic.status = 'neizvestno' THEN
            RETURN QUERY SELECT
                v_operation, 'neizvestno'::text, 'tema_create_neizvestno'::text,
                'Предыдущий createForumTopic имеет неоднозначный результат; blind recreate запрещён.'::text,
                NULL::timestamptz,
                v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                NULL::text, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.operaciya_sozdaniya_id,
                COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                v_topic.popytki, NULL::text, NULL::timestamptz,
                v_topic.nomer_vladeniya, false;
            RETURN;
        END IF;

        IF v_topic.status IN ('oshibka','zakryta') THEN
            RETURN QUERY SELECT
                v_operation, 'otkaz'::text, 'tema_ne_gotova_k_avtopovtoru'::text,
                'Topic intent находится в terminal состоянии; автоматическое создание запрещено.'::text,
                NULL::timestamptz,
                v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                v_topic.message_thread_id, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.operaciya_sozdaniya_id,
                COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                v_topic.popytki, NULL::text, NULL::timestamptz,
                v_topic.nomer_vladeniya, false;
            RETURN;
        END IF;

        IF v_topic.status = 'sozdaetsya'
           AND v_topic.arenda_do > v_now THEN
            IF v_topic.vladelec_arendy IS NOT DISTINCT FROM v_worker
               AND v_topic.operaciya_sozdaniya_id IS NOT DISTINCT FROM v_operation THEN
                RETURN QUERY SELECT
                    v_operation, 'dublikat'::text, NULL::text,
                    'Этот worker уже владеет текущей попыткой создания topic.'::text,
                    v_topic.arenda_do,
                    v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                    NULL::text, v_topic.vneshniy_id_kartochki,
                    v_topic.status, v_topic.operaciya_sozdaniya_id,
                    COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                    v_topic.popytki, v_topic.vladelec_arendy,
                    v_topic.arenda_do, v_topic.nomer_vladeniya, false;
                RETURN;
            END IF;

            RETURN QUERY SELECT
                v_operation, 'zanyato'::text, 'tema_uzhe_sozdaetsya'::text,
                'Topic уже создаётся другим worker.'::text,
                v_topic.arenda_do,
                v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                NULL::text, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.operaciya_sozdaniya_id,
                COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                v_topic.popytki, v_topic.vladelec_arendy,
                v_topic.arenda_do, v_topic.nomer_vladeniya, false;
            RETURN;
        END IF;

        IF v_topic.status = 'nuzhno_sozdat'
           AND v_topic.sleduyushchiy_zapusk > v_now THEN
            RETURN QUERY SELECT
                v_operation, 'povtor'::text, 'eshche_rano'::text,
                'Topic intent ещё не due.'::text,
                v_topic.sleduyushchiy_zapusk,
                v_topic.dialog_id, v_topic.sluzhebnyy_chat_id,
                NULL::text, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.operaciya_sozdaniya_id,
                COALESCE(v_topic.safe_client,'Клиент'), v_topic.ensure_payload,
                v_topic.popytki, NULL::text, NULL::timestamptz,
                v_topic.nomer_vladeniya, false;
            RETURN;
        END IF;
    ELSE
        SELECT
            t.*,
            e.bezopasnaya_podpis_klienta AS safe_client,
            e.payload AS ensure_payload
          INTO v_topic
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
          LEFT JOIN qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
            ON e.klyuch_idempotentnosti = 'tema:' || t.dialog_id::text
         WHERE (
                (
                    t.status = 'nuzhno_sozdat'
                    AND t.sleduyushchiy_zapusk <= v_now
                )
                OR
                (
                    t.status = 'sozdaetsya'
                    AND t.arenda_do <= v_now
                )
         )
         ORDER BY
            CASE WHEN t.status='sozdaetsya' THEN 0 ELSE 1 END,
            CASE
                WHEN t.status='sozdaetsya' THEN t.arenda_do
                ELSE t.sleduyushchiy_zapusk
            END,
            t.vremya_sozdaniya,
            t.dialog_id
         FOR UPDATE OF t SKIP LOCKED
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                v_operation, 'net_temy'::text, NULL::text,
                'Due topic intent сейчас нет.'::text,
                NULL::timestamptz,
                NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::jsonb, NULL::integer,
                NULL::text, NULL::timestamptz, NULL::bigint, false;
            RETURN;
        END IF;
    END IF;

    v_reclaim := (
        v_topic.status = 'sozdaetsya'
        AND v_topic.arenda_do <= v_now
    );

    UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_claim
       SET status = 'sozdaetsya',
           operaciya_sozdaniya_id = v_operation,
           popytki = t_claim.popytki + 1,
           vladelec_arendy = v_worker,
           arenda_do = v_now + make_interval(secs => v_lease_seconds),
           nomer_vladeniya = t_claim.nomer_vladeniya + 1,
           kod_oshibki = NULL,
           opisanie_oshibki = NULL
     WHERE t_claim.dialog_id = v_topic.dialog_id
     RETURNING t_claim.*
     INTO v_claimed;

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        CASE
            WHEN v_reclaim
            THEN 'Истёкшая аренда создания topic перехвачена новым fencing number.'
            ELSE 'Topic intent выдан worker для createForumTopic.'
        END::text,
        NULL::timestamptz,
        v_claimed.dialog_id, v_claimed.sluzhebnyy_chat_id,
        v_claimed.message_thread_id, v_claimed.vneshniy_id_kartochki,
        v_claimed.status, v_claimed.operaciya_sozdaniya_id,
        COALESCE(v_topic.safe_client,'Клиент'),
        COALESCE(v_topic.ensure_payload,'{}'::jsonb),
        v_claimed.popytki, v_claimed.vladelec_arendy,
        v_claimed.arenda_do, v_claimed.nomer_vladeniya, v_reclaim;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.podtverdit_operator_temu(
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
    vneshniy_id_kartochki text,
    status_temy text,
    nomer_vladeniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_dialog_id uuid;
    v_worker text;
    v_ownership bigint;
    v_thread text;
    v_card text;
    v_confirmed_at timestamptz;
    v_topic record;
    v_safe_client text;
    v_return_card text;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_sozdaniya_id'),'');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya','')::bigint;
    v_thread := NULLIF(btrim(p_dannye->>'message_thread_id'),'');
    v_card := NULLIF(btrim(p_dannye->>'vneshniy_id_kartochki'),'');
    v_confirmed_at := COALESCE(
        NULLIF(p_dannye->>'vremya_podtverzhdeniya','')::timestamptz,
        clock_timestamp()
    );

    IF v_operation IS NULL
       OR v_dialog_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_thread IS NULL THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны dialog/create-operation/worker/fencing/thread id.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::text, v_thread, v_card, NULL::text, v_ownership;
        RETURN;
    END IF;

    SELECT t.*
      INTO v_topic
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'tema_ne_naydena'::text,
            'Topic intent не найден.'::text, NULL::timestamptz,
            v_dialog_id, NULL::text, v_thread, v_card, NULL::text, v_ownership;
        RETURN;
    END IF;

    v_return_card := v_topic.vneshniy_id_kartochki;

    IF v_topic.status = 'gotova' THEN
        IF v_topic.message_thread_id IS DISTINCT FROM v_thread THEN
            RETURN QUERY SELECT
                v_operation, 'konflikt'::text, 'drugoy_thread_id'::text,
                'Dialog уже связан с другим confirmed topic; второй mapping запрещён.'::text,
                NULL::timestamptz,
                v_dialog_id, v_topic.sluzhebnyy_chat_id,
                v_topic.message_thread_id, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.nomer_vladeniya;
            RETURN;
        END IF;

        IF v_topic.vneshniy_id_kartochki IS NOT NULL
           AND v_card IS NOT NULL
           AND v_topic.vneshniy_id_kartochki IS DISTINCT FROM v_card THEN
            RETURN QUERY SELECT
                v_operation, 'konflikt'::text, 'drugaya_kartochka'::text,
                'У topic уже подтверждён другой card message id.'::text,
                NULL::timestamptz,
                v_dialog_id, v_topic.sluzhebnyy_chat_id,
                v_topic.message_thread_id, v_topic.vneshniy_id_kartochki,
                v_topic.status, v_topic.nomer_vladeniya;
            RETURN;
        END IF;

        IF v_topic.vneshniy_id_kartochki IS NULL AND v_card IS NOT NULL THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_card
               SET vneshniy_id_kartochki = v_card,
                   vremya_posledney_sinhronizacii = clock_timestamp()
             WHERE t_card.dialog_id = v_dialog_id;
            v_return_card := v_card;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'dublikat'::text, NULL::text,
            'Topic mapping уже подтверждён этим thread id.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.sluzhebnyy_chat_id,
            v_topic.message_thread_id, v_topic.vneshniy_id_kartochki,
            'gotova'::text, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_topic.status = 'neizvestno' THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'tema_uzhe_neizvestna'::text,
            'Topic помечен neizvestno; автоматическое подтверждение другой попытки запрещено.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.sluzhebnyy_chat_id,
            NULL::text, v_topic.vneshniy_id_kartochki,
            v_topic.status, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_topic.status <> 'sozdaetsya'
       OR v_topic.operaciya_sozdaniya_id IS DISTINCT FROM v_operation
       OR v_topic.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_topic.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'stale_topic_owner'::text,
            'Create operation/worker/fencing больше не владеет topic intent.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.sluzhebnyy_chat_id,
            NULL::text, v_topic.vneshniy_id_kartochki,
            v_topic.status, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_topic.arenda_do IS NULL
       OR v_topic.arenda_do <= clock_timestamp() THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая topic lease не может подтверждать mapping.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.sluzhebnyy_chat_id,
            NULL::text, v_topic.vneshniy_id_kartochki,
            v_topic.status, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS other_topic
         WHERE other_topic.dialog_id <> v_dialog_id
           AND other_topic.sluzhebnyy_chat_id = v_topic.sluzhebnyy_chat_id
           AND other_topic.message_thread_id = v_thread
    ) THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'thread_uzhe_privyazan'::text,
            'Этот service chat/thread уже связан с другим dialog.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.sluzhebnyy_chat_id,
            v_thread, v_card, v_topic.status, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_done
       SET status = 'gotova',
           message_thread_id = v_thread,
           vneshniy_id_kartochki = COALESCE(v_card, t_done.vneshniy_id_kartochki),
           vladelec_arendy = NULL,
           arenda_do = NULL,
           vremya_podtverzhdeniya = v_confirmed_at,
           vremya_posledney_sinhronizacii = v_confirmed_at,
           kod_oshibki = NULL,
           opisanie_oshibki = NULL
     WHERE t_done.dialog_id = v_dialog_id;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_target
       SET cel_chat_id = v_topic.sluzhebnyy_chat_id,
           cel_thread_id = v_thread,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_target.dialog_id = v_dialog_id
       AND e_target.tip_sobytiya NOT IN ('obespechit_temu','lichnoe_uvedomlenie')
       AND e_target.status IN ('zaplanirovano','povtor');

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_ensure
       SET status = 'podtverzhdeno',
           vremya_podtverzhdeniya = v_confirmed_at,
           kod_oshibki = NULL,
           opisanie_oshibki = NULL,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_ensure.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

    IF v_card IS NULL THEN
        SELECT e.bezopasnaya_podpis_klienta
          INTO v_safe_client
          FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
         WHERE e.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora (
            dialog_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            prioritet,
            cel_chat_id,
            cel_thread_id,
            bezopasnaya_podpis_klienta,
            payload,
            status
        )
        VALUES (
            v_dialog_id,
            'obnovit_kartochku',
            'kartochka:' || v_dialog_id::text || ':initial',
            90,
            v_topic.sluzhebnyy_chat_id,
            v_thread,
            COALESCE(v_safe_client,'Клиент'),
            jsonb_build_object(
                'rezhim','initial',
                'dialog_id',v_dialog_id
            ),
            'zaplanirovano'
        )
        ON CONFLICT (klyuch_idempotentnosti) DO NOTHING;
    END IF;

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        'Operator topic mapping подтверждён один раз; queued mirror events привязаны к thread.'::text,
        NULL::timestamptz,
        v_dialog_id, v_topic.sluzhebnyy_chat_id,
        v_thread, v_card, 'gotova'::text, v_ownership;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.otmetit_temu_neizvestnoy(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    dialog_id uuid,
    status_temy text,
    nomer_vladeniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_dialog_id uuid;
    v_worker text;
    v_ownership bigint;
    v_error_code text;
    v_error_description text;
    v_topic record;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_sozdaniya_id'),'');
    v_dialog_id := NULLIF(p_dannye->>'dialog_id','')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya','')::bigint;
    v_error_code := COALESCE(
        NULLIF(btrim(p_dannye->>'kod_oshibki'),''),
        'create_forum_topic_neizvestno'
    );
    v_error_description := COALESCE(
        NULLIF(btrim(p_dannye->>'opisanie_oshibki'),''),
        'Результат createForumTopic неоднозначен; blind recreate запрещён.'
    );

    IF v_operation IS NULL
       OR v_dialog_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1 THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны dialog/create-operation/worker/fencing.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::text, v_ownership;
        RETURN;
    END IF;

    SELECT t.*
      INTO v_topic
      FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
     WHERE t.dialog_id = v_dialog_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'tema_ne_naydena'::text,
            'Topic intent не найден.'::text,
            NULL::timestamptz,
            v_dialog_id, NULL::text, v_ownership;
        RETURN;
    END IF;

    IF v_topic.status = 'neizvestno' THEN
        IF v_topic.operaciya_sozdaniya_id IS NOT DISTINCT FROM v_operation THEN
            RETURN QUERY SELECT
                v_operation, 'dublikat'::text, NULL::text,
                'Topic уже помечен neizvestno для этой create operation.'::text,
                NULL::timestamptz,
                v_dialog_id, 'neizvestno'::text, v_topic.nomer_vladeniya;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'drugaya_neizvestnaya_operaciya'::text,
            'Topic уже neizvestno после другой create operation.'::text,
            NULL::timestamptz,
            v_dialog_id, 'neizvestno'::text, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_topic.status = 'gotova' THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'tema_uzhe_gotova'::text,
            'Confirmed topic нельзя переводить в neizvestno.'::text,
            NULL::timestamptz,
            v_dialog_id, 'gotova'::text, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_topic.status <> 'sozdaetsya'
       OR v_topic.operaciya_sozdaniya_id IS DISTINCT FROM v_operation
       OR v_topic.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_topic.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'stale_topic_owner'::text,
            'Create operation/worker/fencing больше не владеет topic intent.'::text,
            NULL::timestamptz,
            v_dialog_id, v_topic.status, v_topic.nomer_vladeniya;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_unknown
       SET status = 'neizvestno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = v_error_code,
           opisanie_oshibki = v_error_description
     WHERE t_unknown.dialog_id = v_dialog_id;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_ensure
       SET status = 'neizvestno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = v_error_code,
           opisanie_oshibki = v_error_description,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_ensure.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
        kompaniya_kod,
        sreda,
        komponent,
        operaciya_id,
        vremya_sobytiya,
        uroven,
        kod,
        opisanie,
        klyuch_gruppirovki,
        status_uvedomleniya
    )
    VALUES (
        'qbit',
        'test',
        'operator_telegram',
        v_operation,
        clock_timestamp(),
        'preduprezhdenie',
        'create_forum_topic_neizvestno',
        'Результат создания operator topic неизвестен; автоматический повтор запрещён.',
        'topic_unknown:' || v_dialog_id::text,
        'ozhidaet'
    );

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        'Topic помечен neizvestno; blind createForumTopic retry заблокирован.'::text,
        NULL::timestamptz,
        v_dialog_id, 'neizvestno'::text, v_ownership;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_sobytie_zerkala(
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
    tip_sobytiya text,
    klyuch_idempotentnosti text,
    cel_chat_id text,
    cel_thread_id text,
    cel_menedzher_id uuid,
    bezopasnaya_podpis_klienta text,
    tekst text,
    payload jsonb,
    soobshchenie_id uuid,
    vlozhenie_id uuid,
    tip_vlozheniya text,
    mime text,
    imya_fayla text,
    soderzhimoe bytea,
    hranilishche_tip text,
    hranilishche_klyuch text,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    byl_perehvachen boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_worker text;
    v_event_id uuid;
    v_lease_seconds integer;
    v_now timestamptz;
    v_event record;
    v_claimed record;
    v_target_chat text;
    v_target_thread text;
    v_reclaim boolean;
    v_iteration integer;

    v_attachment_type text;
    v_attachment_mime text;
    v_attachment_name text;
    v_attachment_bytes bytea;
    v_storage_type text;
    v_storage_key text;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_event_id := NULLIF(p_dannye->>'sobytie_zerkala_id','')::uuid;
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund','')::integer;

    IF v_operation IS NULL
       OR v_worker IS NULL
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operation/worker/trusted lease 10..3600; mirror event id optional.'::text,
            NULL::timestamptz,
            v_event_id, NULL::uuid, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
            NULL::jsonb, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
            NULL::text, NULL::bytea, NULL::text, NULL::text, NULL::integer,
            NULL::text, NULL::timestamptz, NULL::bigint, false;
        RETURN;
    END IF;

    FOR v_iteration IN 1..50 LOOP
        v_now := clock_timestamp();

        IF v_event_id IS NOT NULL THEN
            SELECT
                e.*,
                t.status AS topic_status,
                t.sluzhebnyy_chat_id AS topic_chat,
                t.message_thread_id AS topic_thread,
                m.aktiven AS manager_active,
                m.private_chat_podtverzhden AS manager_private_ok,
                m.private_chat_id AS manager_private_chat,
                m.lichnye_uvedomleniya AS manager_notify
              INTO v_event
              FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
              LEFT JOIN qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
                ON t.dialog_id = e.dialog_id
              LEFT JOIN qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
                ON m.id = e.cel_menedzher_id
             WHERE e.id = v_event_id
             FOR UPDATE OF e SKIP LOCKED;

            IF NOT FOUND THEN
                IF EXISTS (
                    SELECT 1
                      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_busy
                     WHERE e_busy.id = v_event_id
                ) THEN
                    RETURN QUERY SELECT
                        v_operation, 'zanyato'::text, 'zerkalo_zablokirovano'::text,
                        'Mirror event сейчас заблокирован другим worker.'::text,
                        v_now + interval '2 seconds',
                        v_event_id, NULL::uuid, NULL::text, NULL::text,
                        NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
                        NULL::jsonb, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                        NULL::text, NULL::bytea, NULL::text, NULL::text, NULL::integer,
                        NULL::text, NULL::timestamptz, NULL::bigint, false;
                    RETURN;
                END IF;

                RETURN QUERY SELECT
                    v_operation, 'otkaz'::text, 'zerkalo_ne_naydeno'::text,
                    'Mirror event не найден.'::text, NULL::timestamptz,
                    v_event_id, NULL::uuid, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
                    NULL::jsonb, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                    NULL::text, NULL::bytea, NULL::text, NULL::text, NULL::integer,
                    NULL::text, NULL::timestamptz, NULL::bigint, false;
                RETURN;
            END IF;

            IF v_event.tip_sobytiya = 'obespechit_temu' THEN
                RETURN QUERY SELECT
                    v_operation, 'otkaz'::text, 'ispolzuy_topic_api'::text,
                    'obespechit_temu обрабатывается отдельным topic claim API.'::text,
                    NULL::timestamptz,
                    v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                    v_event.klyuch_idempotentnosti, NULL::text, NULL::text,
                    v_event.cel_menedzher_id, v_event.bezopasnaya_podpis_klienta,
                    v_event.tekst, v_event.payload, v_event.soobshchenie_id,
                    v_event.vlozhenie_id, NULL::text, NULL::text, NULL::text,
                    NULL::bytea, NULL::text, NULL::text, v_event.popytki,
                    NULL::text, NULL::timestamptz, v_event.nomer_vladeniya, false;
                RETURN;
            END IF;

            IF v_event.status IN ('podtverzhdeno','neizvestno','otmeneno','oshibka') THEN
                RETURN QUERY SELECT
                    v_operation,
                    CASE WHEN v_event.status='neizvestno' THEN 'neizvestno' ELSE 'dublikat' END::text,
                    NULL::text,
                    'Mirror event уже terminal; blind повтор не выполняется.'::text,
                    NULL::timestamptz,
                    v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                    v_event.klyuch_idempotentnosti, v_event.cel_chat_id,
                    v_event.cel_thread_id, v_event.cel_menedzher_id,
                    v_event.bezopasnaya_podpis_klienta, v_event.tekst,
                    v_event.payload, v_event.soobshchenie_id, v_event.vlozhenie_id,
                    NULL::text, NULL::text, NULL::text, NULL::bytea,
                    NULL::text, NULL::text, v_event.popytki,
                    NULL::text, NULL::timestamptz, v_event.nomer_vladeniya, false;
                RETURN;
            END IF;

            IF v_event.status = 'v_rabote'
               AND v_event.arenda_do > v_now THEN
                RETURN QUERY SELECT
                    v_operation, 'zanyato'::text, 'zerkalo_uzhe_v_rabote'::text,
                    'Mirror event уже обрабатывается.'::text,
                    v_event.arenda_do,
                    v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                    v_event.klyuch_idempotentnosti, v_event.cel_chat_id,
                    v_event.cel_thread_id, v_event.cel_menedzher_id,
                    v_event.bezopasnaya_podpis_klienta, v_event.tekst,
                    v_event.payload, v_event.soobshchenie_id, v_event.vlozhenie_id,
                    NULL::text, NULL::text, NULL::text, NULL::bytea,
                    NULL::text, NULL::text, v_event.popytki,
                    v_event.vladelec_arendy, v_event.arenda_do,
                    v_event.nomer_vladeniya, false;
                RETURN;
            END IF;

            IF v_event.status IN ('zaplanirovano','povtor')
               AND v_event.sleduyushchiy_zapusk > v_now THEN
                RETURN QUERY SELECT
                    v_operation, 'povtor'::text, 'eshche_rano'::text,
                    'Mirror event ещё не due.'::text,
                    v_event.sleduyushchiy_zapusk,
                    v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                    v_event.klyuch_idempotentnosti, v_event.cel_chat_id,
                    v_event.cel_thread_id, v_event.cel_menedzher_id,
                    v_event.bezopasnaya_podpis_klienta, v_event.tekst,
                    v_event.payload, v_event.soobshchenie_id, v_event.vlozhenie_id,
                    NULL::text, NULL::text, NULL::text, NULL::bytea,
                    NULL::text, NULL::text, v_event.popytki,
                    NULL::text, NULL::timestamptz, v_event.nomer_vladeniya, false;
                RETURN;
            END IF;
        ELSE
            SELECT
                e.*,
                t.status AS topic_status,
                t.sluzhebnyy_chat_id AS topic_chat,
                t.message_thread_id AS topic_thread,
                m.aktiven AS manager_active,
                m.private_chat_podtverzhden AS manager_private_ok,
                m.private_chat_id AS manager_private_chat,
                m.lichnye_uvedomleniya AS manager_notify
              INTO v_event
              FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
              LEFT JOIN qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
                ON t.dialog_id = e.dialog_id
              LEFT JOIN qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
                ON m.id = e.cel_menedzher_id
             WHERE e.tip_sobytiya <> 'obespechit_temu'
               AND (
                    (
                        e.status IN ('zaplanirovano','povtor')
                        AND e.sleduyushchiy_zapusk <= v_now
                    )
                    OR
                    (
                        e.status='v_rabote'
                        AND e.arenda_do <= v_now
                    )
               )
               AND (
                    e.tip_sobytiya='lichnoe_uvedomlenie'
                    OR (
                        t.status='gotova'
                        AND t.message_thread_id IS NOT NULL
                    )
               )
             ORDER BY
                e.prioritet DESC,
                CASE WHEN e.status='v_rabote' THEN 0 ELSE 1 END,
                CASE
                    WHEN e.status='v_rabote' THEN e.arenda_do
                    ELSE e.sleduyushchiy_zapusk
                END,
                e.vremya_sozdaniya,
                e.id
             FOR UPDATE OF e SKIP LOCKED
             LIMIT 1;

            IF NOT FOUND THEN
                RETURN QUERY SELECT
                    v_operation, 'net_sobytiya'::text, NULL::text,
                    'Готового mirror event сейчас нет.'::text,
                    NULL::timestamptz,
                    NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
                    NULL::jsonb, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                    NULL::text, NULL::bytea, NULL::text, NULL::text, NULL::integer,
                    NULL::text, NULL::timestamptz, NULL::bigint, false;
                RETURN;
            END IF;
        END IF;

        IF v_event.tip_sobytiya='lichnoe_uvedomlenie' THEN
            IF v_event.cel_menedzher_id IS NULL
               OR NOT COALESCE(v_event.manager_active,false)
               OR NOT COALESCE(v_event.manager_private_ok,false)
               OR NOT COALESCE(v_event.manager_notify,false)
               OR v_event.manager_private_chat IS NULL THEN
                UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_cancel
                   SET status='otmeneno',
                       vladelec_arendy=NULL,
                       arenda_do=NULL,
                       kod_oshibki='lichnoe_uvedomlenie_ne_razresheno',
                       opisanie_oshibki='Manager/private chat/notification setting no longer permits private notification.',
                       vremya_obnovleniya=clock_timestamp()
                 WHERE e_cancel.id=v_event.id;

                IF v_event_id IS NOT NULL THEN
                    RETURN QUERY SELECT
                        v_operation, 'otkaz'::text, 'lichnoe_uvedomlenie_ne_razresheno'::text,
                        'Private notification отменено final recheck.'::text,
                        NULL::timestamptz,
                        v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                        v_event.klyuch_idempotentnosti, NULL::text, NULL::text,
                        v_event.cel_menedzher_id, v_event.bezopasnaya_podpis_klienta,
                        v_event.tekst, v_event.payload, v_event.soobshchenie_id,
                        v_event.vlozhenie_id, NULL::text, NULL::text, NULL::text,
                        NULL::bytea, NULL::text, NULL::text, v_event.popytki,
                        NULL::text, NULL::timestamptz, v_event.nomer_vladeniya, false;
                    RETURN;
                END IF;

                CONTINUE;
            END IF;

            v_target_chat := v_event.manager_private_chat;
            v_target_thread := NULL;
        ELSE
            IF v_event.topic_status IS DISTINCT FROM 'gotova'
               OR v_event.topic_chat IS NULL
               OR v_event.topic_thread IS NULL THEN
                IF v_event_id IS NOT NULL THEN
                    RETURN QUERY SELECT
                        v_operation, 'povtor'::text, 'tema_esche_ne_gotova'::text,
                        'Mirror event ждёт confirmed operator topic.'::text,
                        v_now + interval '5 seconds',
                        v_event.id, v_event.dialog_id, v_event.tip_sobytiya,
                        v_event.klyuch_idempotentnosti, NULL::text, NULL::text,
                        v_event.cel_menedzher_id, v_event.bezopasnaya_podpis_klienta,
                        v_event.tekst, v_event.payload, v_event.soobshchenie_id,
                        v_event.vlozhenie_id, NULL::text, NULL::text, NULL::text,
                        NULL::bytea, NULL::text, NULL::text, v_event.popytki,
                        NULL::text, NULL::timestamptz, v_event.nomer_vladeniya, false;
                    RETURN;
                END IF;

                CONTINUE;
            END IF;

            v_target_chat := v_event.topic_chat;
            v_target_thread := v_event.topic_thread;
        END IF;

        v_reclaim := (
            v_event.status='v_rabote'
            AND v_event.arenda_do <= v_now
        );

        UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_claim
           SET status='v_rabote',
               popytki=e_claim.popytki+1,
               cel_chat_id=v_target_chat,
               cel_thread_id=v_target_thread,
               vladelec_arendy=v_worker,
               arenda_do=v_now+make_interval(secs=>v_lease_seconds),
               nomer_vladeniya=e_claim.nomer_vladeniya+1,
               kod_oshibki=NULL,
               opisanie_oshibki=NULL,
               vremya_obnovleniya=clock_timestamp()
         WHERE e_claim.id=v_event.id
         RETURNING e_claim.*
         INTO v_claimed;

        v_attachment_type := NULL;
        v_attachment_mime := NULL;
        v_attachment_name := NULL;
        v_attachment_bytes := NULL;
        v_storage_type := NULL;
        v_storage_key := NULL;

        IF v_claimed.vlozhenie_id IS NOT NULL THEN
            SELECT
                a.tip_vlozheniya,
                a.mime,
                a.imya_fayla,
                a.soderzhimoe,
                a.hranilishche_tip,
                a.hranilishche_klyuch
              INTO
                v_attachment_type,
                v_attachment_mime,
                v_attachment_name,
                v_attachment_bytes,
                v_storage_type,
                v_storage_key
              FROM qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy AS a
             WHERE a.id=v_claimed.vlozhenie_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Mirror event % references missing attachment %',
                    v_claimed.id,
                    v_claimed.vlozhenie_id;
            END IF;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'uspeshno'::text, NULL::text,
            CASE WHEN v_reclaim
                THEN 'Истёкшая mirror lease перехвачена новым fencing number.'
                ELSE 'Mirror event выдан service worker узким payload.'
            END::text,
            NULL::timestamptz,
            v_claimed.id, v_claimed.dialog_id, v_claimed.tip_sobytiya,
            v_claimed.klyuch_idempotentnosti, v_claimed.cel_chat_id,
            v_claimed.cel_thread_id, v_claimed.cel_menedzher_id,
            v_claimed.bezopasnaya_podpis_klienta, v_claimed.tekst,
            v_claimed.payload, v_claimed.soobshchenie_id,
            v_claimed.vlozhenie_id, v_attachment_type, v_attachment_mime,
            v_attachment_name, v_attachment_bytes, v_storage_type, v_storage_key,
            v_claimed.popytki, v_claimed.vladelec_arendy,
            v_claimed.arenda_do, v_claimed.nomer_vladeniya, v_reclaim;
        RETURN;
    END LOOP;

    RETURN QUERY SELECT
        v_operation, 'povtor'::text, 'ochistka_limit'::text,
        'За один claim очищено 50 недоступных private events; безопасно повторить.'::text,
        clock_timestamp()+interval '1 second',
        NULL::uuid, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
        NULL::jsonb, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::bytea, NULL::text, NULL::text, NULL::integer,
        NULL::text, NULL::timestamptz, NULL::bigint, false;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zafiksirovat_rezultat_zerkala(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    sobytie_zerkala_id uuid,
    status_sobytiya text,
    vneshniy_message_id text,
    nomer_vladeniya bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_operation text;
    v_event_id uuid;
    v_worker text;
    v_ownership bigint;
    v_status text;
    v_external_id text;
    v_confirm_time timestamptz;
    v_retry_at timestamptz;
    v_error_code text;
    v_error_description text;
    v_now timestamptz;
    v_event record;
    v_topic record;
BEGIN
    v_operation := NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_event_id := NULLIF(p_dannye->>'sobytie_zerkala_id','')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'),'');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya','')::bigint;
    v_status := NULLIF(btrim(p_dannye->>'status'),'');
    v_external_id := NULLIF(btrim(p_dannye->>'vneshniy_message_id'),'');
    v_confirm_time := NULLIF(p_dannye->>'vremya_podtverzhdeniya','')::timestamptz;
    v_retry_at := NULLIF(p_dannye->>'povtor_posle','')::timestamptz;
    v_error_code := NULLIF(btrim(p_dannye->>'kod_oshibki'),'');
    v_error_description := NULLIF(btrim(p_dannye->>'opisanie_oshibki'),'');
    v_now := clock_timestamp();

    IF v_operation IS NULL
       OR v_event_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_status NOT IN ('podtverzhdeno','povtor','neizvestno','oshibka')
       OR (v_status='podtverzhdeno' AND (v_external_id IS NULL OR v_confirm_time IS NULL))
       OR (
            v_status='povtor'
            AND (
                v_retry_at IS NULL
                OR v_retry_at <= v_now
                OR v_error_code IS NULL
            )
       )
       OR (v_status IN ('neizvestno','oshibka') AND v_error_code IS NULL) THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Confirmed требует external id/time; retry future+error; unknown/error code.'::text,
            NULL::timestamptz,
            v_event_id, NULL::text, v_external_id, v_ownership;
        RETURN;
    END IF;

    SELECT e.*
      INTO v_event
      FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e
     WHERE e.id=v_event_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operation, 'otkaz'::text, 'zerkalo_ne_naydeno'::text,
            'Mirror event не найден.'::text, NULL::timestamptz,
            v_event_id, NULL::text, v_external_id, v_ownership;
        RETURN;
    END IF;

    IF v_event.status IN ('podtverzhdeno','neizvestno','oshibka','otmeneno') THEN
        IF v_event.status IS NOT DISTINCT FROM v_status
           AND (
                v_status <> 'podtverzhdeno'
                OR v_event.vneshniy_message_id IS NOT DISTINCT FROM v_external_id
           ) THEN
            RETURN QUERY SELECT
                v_operation, 'dublikat'::text, NULL::text,
                'Terminal mirror result уже сохранён.'::text,
                NULL::timestamptz,
                v_event.id, v_event.status,
                v_event.vneshniy_message_id, v_event.nomer_vladeniya;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'terminal_result_conflict'::text,
            'Mirror event уже имеет другой terminal result.'::text,
            NULL::timestamptz,
            v_event.id, v_event.status,
            v_event.vneshniy_message_id, v_event.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_event.status <> 'v_rabote'
       OR v_event.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_event.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'stale_mirror_owner'::text,
            'Worker/fencing больше не владеет mirror event.'::text,
            NULL::timestamptz,
            v_event.id, v_event.status,
            v_event.vneshniy_message_id, v_event.nomer_vladeniya;
        RETURN;
    END IF;

    IF v_event.arenda_do IS NULL OR v_event.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operation, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая mirror lease не может записывать результат.'::text,
            NULL::timestamptz,
            v_event.id, v_event.status,
            v_event.vneshniy_message_id, v_event.nomer_vladeniya;
        RETURN;
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.sobytiya_zerkala_operatora AS e_done
       SET status=v_status,
           vladelec_arendy=NULL,
           arenda_do=NULL,
           vneshniy_message_id=CASE
               WHEN v_status='podtverzhdeno' THEN v_external_id
               ELSE e_done.vneshniy_message_id
           END,
           vremya_podtverzhdeniya=CASE
               WHEN v_status='podtverzhdeno' THEN v_confirm_time
               ELSE NULL
           END,
           sleduyushchiy_zapusk=CASE
               WHEN v_status='povtor' THEN v_retry_at
               ELSE e_done.sleduyushchiy_zapusk
           END,
           kod_oshibki=CASE
               WHEN v_status IN ('povtor','neizvestno','oshibka') THEN v_error_code
               ELSE NULL
           END,
           opisanie_oshibki=CASE
               WHEN v_status IN ('povtor','neizvestno','oshibka') THEN v_error_description
               ELSE NULL
           END,
           vremya_obnovleniya=clock_timestamp()
     WHERE e_done.id=v_event.id;

    IF v_status='podtverzhdeno' THEN
        SELECT t.*
          INTO v_topic
          FROM qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t
         WHERE t.dialog_id=v_event.dialog_id
         FOR UPDATE;

        IF FOUND THEN
            UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_sync
               SET vremya_posledney_sinhronizacii=v_confirm_time
             WHERE t_sync.dialog_id=v_event.dialog_id;

            IF v_event.tip_sobytiya='obnovit_kartochku'
               AND v_event.payload->>'rezhim'='initial' THEN
                IF v_topic.vneshniy_id_kartochki IS NULL THEN
                    UPDATE qbit_bot_pervichnogo_obrascheniya.operator_telegram_temy AS t_card
                       SET vneshniy_id_kartochki=v_external_id
                     WHERE t_card.dialog_id=v_event.dialog_id;
                ELSIF v_topic.vneshniy_id_kartochki IS DISTINCT FROM v_external_id THEN
                    INSERT INTO qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
                        kompaniya_kod,
                        sreda,
                        komponent,
                        operaciya_id,
                        vremya_sobytiya,
                        uroven,
                        kod,
                        opisanie,
                        klyuch_gruppirovki,
                        status_uvedomleniya
                    )
                    VALUES (
                        'qbit',
                        'test',
                        'operator_telegram',
                        v_operation,
                        v_confirm_time,
                        'preduprezhdenie',
                        'initial_card_id_conflict',
                        'Подтверждена ещё одна initial card; существующий card mapping не перезаписан.',
                        'card_conflict:' || v_event.dialog_id::text,
                        'ozhidaet'
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        CASE
            WHEN v_status='neizvestno'
            THEN 'Mirror result сохранён как neizvestno; blind retry запрещён.'
            WHEN v_status='povtor'
            THEN 'Retry mirror event запланирован с освобождённой lease.'
            WHEN v_status='podtverzhdeno'
            THEN 'Подтверждённый Telegram mirror result сохранён.'
            ELSE 'Постоянная ошибка mirror event сохранена.'
        END::text,
        CASE WHEN v_status='povtor' THEN v_retry_at ELSE NULL END,
        v_event.id, v_status,
        CASE WHEN v_status='podtverzhdeno' THEN v_external_id ELSE v_event.vneshniy_message_id END,
        v_event.nomer_vladeniya;
END
$fn$;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_dialog_operatorom(p_dannye jsonb)
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.vernut_dialog_botu(p_dannye jsonb)
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_ruchnoe_ishodyashchee(p_dannye jsonb)
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

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sozdat_lichnoe_uvedomlenie(p_dannye jsonb)
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

-- Return to the trusted session role before reading postgres-owned TEMP
-- snapshots. This also keeps post-rename assertions independent from runtime
-- privileges of qbit_test_owner.
RESET ROLE;

-- Restore the exact intended steady-state database privilege boundary before
-- assertions. Any later failure still rolls the whole transaction back.
REVOKE CREATE ON DATABASE postgres FROM qbit_test_owner;

-- ===========================================================================
-- 3. POST-RENAME ASSERTIONS
-- ===========================================================================

DO $dbschema01$
DECLARE
    v_owner text;
    v_table_count integer;
    v_fn_count integer;
BEGIN
    IF pg_catalog.to_regnamespace('qbit_test') IS NOT NULL THEN
        RAISE EXCEPTION 'Old schema qbit_test still exists after rename';
    END IF;

    IF pg_catalog.to_regnamespace('qbit_bot_pervichnogo_obrascheniya') IS NULL THEN
        RAISE EXCEPTION 'New schema qbit_bot_pervichnogo_obrascheniya is missing after rename';
    END IF;

    IF (
        SELECT n.oid
          FROM pg_catalog.pg_namespace AS n
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
    ) IS DISTINCT FROM (
        SELECT s.schema_oid FROM dbschema01_schema_snapshot AS s
    ) THEN
        RAISE EXCEPTION 'Schema OID changed unexpectedly';
    END IF;

    SELECT r.rolname
      INTO v_owner
      FROM pg_catalog.pg_namespace AS n
      JOIN pg_catalog.pg_roles AS r ON r.oid=n.nspowner
     WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya';

    IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'New schema owner mismatch: %',v_owner;
    END IF;

    IF (
        SELECT n.nspacl
          FROM pg_catalog.pg_namespace AS n
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
    ) IS DISTINCT FROM (
        SELECT s.schema_acl FROM dbschema01_schema_snapshot AS s
    ) THEN
        RAISE EXCEPTION 'Schema ACL changed unexpectedly';
    END IF;

    SELECT count(*)
      INTO v_table_count
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
     WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
       AND c.relkind='r';

    IF v_table_count <> 25 THEN
        RAISE EXCEPTION
            'Table count changed during rename: expected 25, actual %',
            v_table_count;
    END IF;

    SELECT count(*)
      INTO v_fn_count
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
     WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
       AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
       );

    IF v_fn_count <> 28 THEN
        RAISE EXCEPTION
            'Function count after rename mismatch: expected 28, actual %',
            v_fn_count;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM dbschema01_fn_snapshot AS old_fn
          LEFT JOIN pg_catalog.pg_proc AS p
            ON p.oid=old_fn.function_oid
         WHERE p.oid IS NULL
            OR p.proowner IS DISTINCT FROM old_fn.proowner
            OR p.proacl IS DISTINCT FROM old_fn.proacl
    ) THEN
        RAISE EXCEPTION 'Function OID/owner/ACL changed unexpectedly';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.prokind='f'
           AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
           )
           AND (
                NOT p.prosecdef
                OR NOT (
                    COALESCE(p.proconfig,ARRAY[]::text[])
                    @> ARRAY['search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya']::text[]
                )
           )
    ) THEN
        RAISE EXCEPTION 'One or more functions lost SECURITY DEFINER/fixed new search_path';
    END IF;

    IF EXISTS (
        WITH target_functions AS MATERIALIZED (
            SELECT p.oid
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
               AND p.prokind='f'
               AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
               )
        )
        SELECT 1
          FROM target_functions AS tf
         WHERE pg_catalog.strpos(
                pg_catalog.pg_get_functiondef(tf.oid),
                'qbit_test.'
         ) > 0
    ) THEN
        RAISE EXCEPTION 'Old schema-qualified reference remains inside function definition';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(
                p.proacl,
                pg_catalog.acldefault('f',p.proowner)
            )
          ) AS a
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
           )
           AND a.grantee=0
           AND a.privilege_type='EXECUTE'
    ) THEN
        RAISE EXCEPTION 'PUBLIC unexpectedly has EXECUTE on application function';
    END IF;

    IF NOT pg_catalog.has_schema_privilege(
        'qbit_test_bot','qbit_bot_pervichnogo_obrascheniya','USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya','USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_dash_read','qbit_bot_pervichnogo_obrascheniya','USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_dash_admin','qbit_bot_pervichnogo_obrascheniya','USAGE'
    ) THEN
        RAISE EXCEPTION 'Expected runtime schema USAGE grant was not preserved';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind='r'
           AND (
                pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'INSERT')
                OR pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'UPDATE')
                OR pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'DELETE')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'INSERT')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'UPDATE')
                OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'DELETE')
           )
    ) THEN
        RAISE EXCEPTION 'Runtime direct DML unexpectedly appeared after rename';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM dbschema01_other_schema_snapshot AS s
          LEFT JOIN pg_catalog.pg_namespace AS n
            ON n.nspname=s.schema_name
         WHERE n.oid IS DISTINCT FROM s.schema_oid
            OR n.nspowner IS DISTINCT FROM s.schema_owner
            OR n.nspacl IS DISTINCT FROM s.schema_acl
            OR (
                SELECT count(*)
                  FROM pg_catalog.pg_class AS c
                 WHERE c.relnamespace=n.oid
            ) IS DISTINCT FROM s.relation_count
            OR (
                SELECT count(*)
                  FROM pg_catalog.pg_proc AS p
                 WHERE p.pronamespace=n.oid
            ) IS DISTINCT FROM s.function_count
    ) THEN
        RAISE EXCEPTION 'Production/canary schema snapshot changed unexpectedly';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_owner')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_deploy')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_bot')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_sluzhebnyy')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_dash_read')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_dash_admin') THEN
        RAISE EXCEPTION 'Expected qbit_test_* roles changed or disappeared';
    END IF;
END
$dbschema01$;

DO $dbschema01$
BEGIN
    IF pg_catalog.has_database_privilege(
        'qbit_test_owner',
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'Temporary CREATE privilege on database was not revoked from qbit_test_owner';
    END IF;

    IF NOT pg_catalog.has_database_privilege(
        session_user,
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'Trusted postgres session unexpectedly lost CREATE on database';
    END IF;
END
$dbschema01$;

COMMIT;

-- ===========================================================================
-- 4. SINGLE RESULT SET
-- ===========================================================================

SELECT jsonb_build_object(
    'db_schema_01_status','applied',
    'database',current_database(),
    'old_schema_absent',pg_catalog.to_regnamespace('qbit_test') IS NULL,
    'schema','qbit_bot_pervichnogo_obrascheniya',
    'schema_exists',pg_catalog.to_regnamespace('qbit_bot_pervichnogo_obrascheniya') IS NOT NULL,
    'owner_ok',
    (
        SELECT r.rolname='qbit_test_owner'
          FROM pg_catalog.pg_namespace AS n
          JOIN pg_catalog.pg_roles AS r ON r.oid=n.nspowner
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
    ),
    'tables_ok',
    (
        SELECT count(*)=25
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind='r'
    ),
    'functions_ok',
    (
        SELECT count(*)=28
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
           )
    ),
    'old_function_schema_refs',
    (
        WITH target_functions AS MATERIALIZED (
            SELECT p.oid
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
               AND p.prokind='f'
               AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
               )
        )
        SELECT count(*)
          FROM target_functions AS tf
         WHERE pg_catalog.strpos(
                pg_catalog.pg_get_functiondef(tf.oid),
                'qbit_test.'
         )>0
    ),
    'search_path_ok',
    NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND p.proname IN (
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky',
        'razblokirovat_polzovatelya',
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki',
        'sozdat_ishodyashchee_deystvie',
        'zabrat_ishodyashchee_deystvie',
        'zafiksirovat_rezultat_ishodyashchego',
        'podgotovit_napominanie',
        'zafiksirovat_poteryu_bez_otveta',
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_dialog_operatorom',
        'vernut_dialog_botu',
        'sozdat_ruchnoe_ishodyashchee',
        'sozdat_lichnoe_uvedomlenie'
           )
           AND NOT (
                COALESCE(p.proconfig,ARRAY[]::text[])
                @> ARRAY['search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya']::text[]
           )
    ),
    'temporary_database_create_revoked',
    NOT pg_catalog.has_database_privilege(
        'qbit_test_owner',
        current_database(),
        'CREATE'
    ),
    'roles_unchanged',
    EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_owner')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_deploy')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_bot')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_sluzhebnyy')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_dash_read')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='qbit_test_dash_admin'),
    'runtime_direct_dml',false,
    'production_untouched',true,
    'canary_untouched',true,
    'result',
    'DB-SCHEMA-01 SQL APPLIED: qbit_test renamed to qbit_bot_pervichnogo_obrascheniya; 25 tables and 28 current functions preserved, function bodies/search_path updated, owners/ACL/runtime isolation preserved, temporary database CREATE revoked; production/canary untouched.'
) AS db_schema_01_result;
