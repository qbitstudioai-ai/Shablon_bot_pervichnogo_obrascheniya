-- DB-03C1 v0.3: client ingress, attachment, STT and PII API
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02, DB-03A and DB-03B successfully applied.
--
-- CREATES 4 SECURITY DEFINER FUNCTIONS
--   zaregistrirovat_vhod_klienta(jsonb)
--   sohranit_vlozhenie(jsonb, bytea)
--   sohranit_transkripciyu_golosa(jsonb)
--   sohranit_obezlichivanie(jsonb)
--
-- ALSO ADDS
--   two narrow UNIQUE indexes for attachment retry idempotency:
--     uq_vlozheniya_msg_file_id
--     uq_vlozheniya_msg_file_unique
--
-- SECURITY
--   * Functions are owned by qbit_test_owner.
--   * search_path is fixed to pg_catalog, qbit_test.
--   * PUBLIC has no EXECUTE.
--   * EXECUTE is granted only to qbit_test_bot.
--   * qbit_test_bot still has no direct table DML.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * No Credentials/secrets are created.
--   * Probe rows are rolled back to SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03C1 migration back.
--   * v0.2 fixes PL/pgSQL output-column ambiguity found by server-run of v0.1.
--   * Phone PII is canonicalized after local detection; region comes only from trusted settings.
--   * v0.3 fixes topic target variables found by server-run of v0.2.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03c1$
DECLARE
    v_required text;
    v_fn text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03C1 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03C1 must run from trusted postgres session. session_user=%',
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

    FOREACH v_required IN ARRAY ARRAY[
        'polzovateli',
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'vlozheniya_soobshcheniy',
        'transkripcii_golosa',
        'sootvetstviya_pii',
        'narusheniya_tematiky',
        'sobytiya_dialogov',
        'sobytiya_integraciy',
        'zadaniya_obrabotki',
        'napominaniya',
        'operator_telegram_temy',
        'sobytiya_zerkala_operatora'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_test.%I', v_required)
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required table qbit_test.% is missing',
                v_required;
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND rel.relname = 'soobshcheniya'
           AND con.conname = 'fk_soobshcheniya_sobytie_integracii'
           AND con.contype = 'f'
           AND con.convalidated = true
    ) THEN
        RAISE EXCEPTION
            'DB-03A integration-event FK is missing';
    END IF;

    FOREACH v_fn IN ARRAY ARRAY[
        'zaregistrirovat_vhod_klienta',
        'sohranit_vlozhenie',
        'sohranit_transkripciyu_golosa',
        'sohranit_obezlichivanie'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_test'
               AND p.proname = v_fn
        ) THEN
            RAISE EXCEPTION
                'DB-03C1 function qbit_test.% already exists; stop instead of overwriting',
                v_fn;
        END IF;
    END LOOP;

    IF pg_catalog.to_regclass(
        'qbit_test.uq_vlozheniya_msg_file_id'
    ) IS NOT NULL
    OR pg_catalog.to_regclass(
        'qbit_test.uq_vlozheniya_msg_file_unique'
    ) IS NOT NULL THEN
        RAISE EXCEPTION
            'DB-03C1 attachment idempotency index already exists';
    END IF;
END
$db03c1$;

-- ===========================================================================
-- 1. OWNER-CREATED SUPPORTING INDEXES
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE UNIQUE INDEX uq_vlozheniya_msg_file_id
    ON qbit_test.vlozheniya_soobshcheniy (
        soobshchenie_id,
        vneshniy_file_id
    )
    WHERE vneshniy_file_id IS NOT NULL;

CREATE UNIQUE INDEX uq_vlozheniya_msg_file_unique
    ON qbit_test.vlozheniya_soobshcheniy (
        soobshchenie_id,
        vneshniy_file_unique_id
    )
    WHERE vneshniy_file_unique_id IS NOT NULL;

COMMENT ON INDEX qbit_test.uq_vlozheniya_msg_file_id IS
'DB-03C1: один provider file_id внутри одного логического сообщения сохраняется только один раз.';

COMMENT ON INDEX qbit_test.uq_vlozheniya_msg_file_unique IS
'DB-03C1: один provider file_unique_id внутри одного логического сообщения сохраняется только один раз.';

-- ===========================================================================
-- 2. REGISTER CLIENT INGRESS
-- ===========================================================================

CREATE FUNCTION qbit_test.zaregistrirovat_vhod_klienta(
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
SET search_path = pg_catalog, qbit_test
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
    INSERT INTO qbit_test.sobytiya_integraciy (
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
          FROM qbit_test.sobytiya_integraciy AS e
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
              FROM qbit_test.identifikatory_kanalov AS i
              JOIN qbit_test.dialogi AS d
                ON d.identifikator_kanala_id = i.id
              JOIN qbit_test.soobshcheniya AS m
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
                  FROM qbit_test.zadaniya_obrabotki AS z
                  JOIN qbit_test.soobshcheniya AS original_message
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
          FROM qbit_test.soobshcheniya AS m
          JOIN qbit_test.dialogi AS d
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
          FROM qbit_test.zadaniya_obrabotki AS z
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
      FROM qbit_test.identifikatory_kanalov AS i
     WHERE i.kanal = v_kanal
       AND i.akkaunt_kanala_id = v_akkaunt
       AND i.vneshniy_polzovatel_id = v_vnesh_polz
     FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO qbit_test.polzovateli (
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

        INSERT INTO qbit_test.identifikatory_kanalov (
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
              FROM qbit_test.dialogi AS d
              JOIN qbit_test.soobshcheniya AS m
                ON m.dialog_id = d.id
             WHERE d.identifikator_kanala_id = v_identity_id
               AND m.vneshnee_soobshchenie_id = v_vnesh_soobshchenie
             ORDER BY m.vremya_sozdaniya
             LIMIT 1;

            IF FOUND THEN
                UPDATE qbit_test.sobytiya_integraciy
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
                  FROM qbit_test.zadaniya_obrabotki AS z
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

        UPDATE qbit_test.polzovateli AS p_upd
           SET vremya_poslednego_obrashcheniya =
                   GREATEST(p_upd.vremya_poslednego_obrashcheniya, v_vremya_priema),
               vremya_obnovleniya = clock_timestamp()
         WHERE p_upd.id = v_user_id;

        UPDATE qbit_test.identifikatory_kanalov
           SET vneshniy_dialog_id = v_vnesh_dialog,
               vremya_obnovleniya = clock_timestamp()
         WHERE id = v_identity_id;
    END IF;

    SELECT d.*
      INTO v_dialog
      FROM qbit_test.dialogi AS d
     WHERE d.identifikator_kanala_id = v_identity_id
       AND d.status <> 'zavershen'
     ORDER BY d.vremya_nachala DESC
     LIMIT 1
     FOR UPDATE;

    IF NOT FOUND THEN
        SELECT d.id
          INTO v_previous_dialog_id
          FROM qbit_test.dialogi AS d
         WHERE d.identifikator_kanala_id = v_identity_id
         ORDER BY d.vremya_nachala DESC
         LIMIT 1;

        INSERT INTO qbit_test.dialogi AS new_dialog (
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

        INSERT INTO qbit_test.sobytiya_dialogov (
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
          FROM qbit_test.operator_telegram_temy AS t
         WHERE t.dialog_id = v_dialog_id;

        IF FOUND
           AND v_topic.sluzhebnyy_chat_id IS DISTINCT FROM v_sluzhebnyy_chat THEN
            UPDATE qbit_test.sobytiya_integraciy
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

        UPDATE qbit_test.dialogi AS d_upd
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

        UPDATE qbit_test.napominaniya
           SET status = 'otmeneno',
               prichina = 'novyy_vhod',
               vremya_obnovleniya = clock_timestamp()
         WHERE dialog_id = v_dialog_id
           AND status IN ('zaplanirovano', 'v_rabote');
    END IF;

    INSERT INTO qbit_test.soobshcheniya (
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

    UPDATE qbit_test.dialogi
       SET poslednee_vhodyashchee_id = v_message_id,
           vremya_obnovleniya = clock_timestamp()
     WHERE id = v_dialog_id;

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
    INSERT INTO qbit_test.operator_telegram_temy (
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
      FROM qbit_test.operator_telegram_temy AS t
     WHERE t.dialog_id = v_dialog_id;

    IF v_topic_created THEN
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
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
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
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

    UPDATE qbit_test.sobytiya_integraciy
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

COMMENT ON FUNCTION qbit_test.zaregistrirovat_vhod_klienta(jsonb) IS
'DB-03C1: атомарно регистрирует client ingress v1: event → identity/user → dialog/message → processing job, отменяет старое ожидание и создаёт topic/text mirror intent.';

-- ===========================================================================
-- 3. SAVE ATTACHMENT
-- ===========================================================================

CREATE FUNCTION qbit_test.sohranit_vlozhenie(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.soobshcheniya AS m
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
      FROM qbit_test.vlozheniya_soobshcheniy AS a
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

    INSERT INTO qbit_test.vlozheniya_soobshcheniy (
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
          FROM qbit_test.operator_telegram_temy AS t
         WHERE t.dialog_id = v_message.dialog_id;

        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
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

COMMENT ON FUNCTION qbit_test.sohranit_vlozhenie(jsonb, bytea) IS
'DB-03C1: сохраняет проверенные metadata/bytes вложения с лимитом и idempotency по message+provider file ID; voice/photo/video создают media mirror intent.';

-- ===========================================================================
-- 4. SAVE LOCAL VOICE TRANSCRIPTION
-- ===========================================================================

CREATE FUNCTION qbit_test.sohranit_transkripciyu_golosa(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.soobshcheniya AS m
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
      FROM qbit_test.transkripcii_golosa AS t
     WHERE t.soobshchenie_id = v_message_id
     FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO qbit_test.transkripcii_golosa (
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

    UPDATE qbit_test.transkripcii_golosa AS t_upd
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

COMMENT ON FUNCTION qbit_test.sohranit_transkripciyu_golosa(jsonb) IS
'DB-03C1: сохраняет только локальный STT state/raw/deidentified transcript; ошибки STT не меняют thematic violation counter.';

-- ===========================================================================
-- 5. SAVE DEIDENTIFICATION / LOCAL PII MAP
-- ===========================================================================

CREATE FUNCTION qbit_test.sohranit_obezlichivanie(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.soobshcheniya AS m
      JOIN qbit_test.dialogi AS d
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
          FROM qbit_test.sootvetstviya_pii AS p
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
          FROM qbit_test.sootvetstviya_pii AS p
         WHERE p.dialog_id = v_message.dialog_id
           AND p.psevdometka = v_placeholder;

        IF NOT FOUND THEN
            INSERT INTO qbit_test.sootvetstviya_pii (
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
        UPDATE qbit_test.soobshcheniya
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

COMMENT ON FUNCTION qbit_test.sohranit_obezlichivanie(jsonb) IS
'DB-03C1: атомарно сохраняет обезличенный текст и локальную reverse-map PII; найденный телефон канонизирует по доверенному region_telefona или явному normalized value, поэтому разные визуальные форматы одного номера совпадают.';

-- ===========================================================================
-- 6. PRIVILEGES
-- ===========================================================================

REVOKE ALL ON FUNCTION
    qbit_test.zaregistrirovat_vhod_klienta(jsonb)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    qbit_test.sohranit_vlozhenie(jsonb, bytea)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    qbit_test.sohranit_transkripciyu_golosa(jsonb)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    qbit_test.sohranit_obezlichivanie(jsonb)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    qbit_test.zaregistrirovat_vhod_klienta(jsonb)
TO qbit_test_bot;

GRANT EXECUTE ON FUNCTION
    qbit_test.sohranit_vlozhenie(jsonb, bytea)
TO qbit_test_bot;

GRANT EXECUTE ON FUNCTION
    qbit_test.sohranit_transkripciyu_golosa(jsonb)
TO qbit_test_bot;

GRANT EXECUTE ON FUNCTION
    qbit_test.sohranit_obezlichivanie(jsonb)
TO qbit_test_bot;

-- ===========================================================================
-- 7. STATIC SECURITY ASSERTIONS
-- ===========================================================================

DO $db03c1$
DECLARE
    v_fn record;
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
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie'
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
                'Function % has unsafe search_path config %',
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

        IF NOT pg_catalog.has_function_privilege(
            'qbit_test_bot',
            v_fn.oid,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_bot lacks EXECUTE on %',
                v_fn.proname;
        END IF;

        IF pg_catalog.has_function_privilege(
            'qbit_test_sluzhebnyy',
            v_fn.oid,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_sluzhebnyy unexpectedly has EXECUTE on %',
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
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie'
           )
    ) <> 4 THEN
        RAISE EXCEPTION
            'DB-03C1 expected exactly 4 API functions';
    END IF;
END
$db03c1$;

-- ===========================================================================
-- 8. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03c1_probe;

DO $db03c1$
DECLARE
    r1 record;
    rdup record;
    rconf record;
    r2 record;
    ratt record;
    rattdup record;
    rattconf record;
    rstt record;
    rsttdup record;
    rsttconf record;
    rpii record;
    rpiidup record;
    rpiidup2 record;
    rpiiconf record;
    v_old_reminder uuid;
    v_before_violations integer;
    v_after_violations integer;
BEGIN
    SELECT *
      INTO r1
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_ingress_1',
            'klyuch_idempotentnosti', 'db03c1_idem_1',
            'hash_soderzhaniya', 'db03c1_hash_1',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_1',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Телефон 8 (961) 123-45-67',
            'vremya_istochnika', '2026-09-24T17:00:00+00',
            'vremya_priema', '2026-09-24T17:00:01+00',
            'trassirovka_id', 'db03c1_trace_1',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group',
            'bezopasnaya_podpis_klienta', 'Клиент DB-03C1',
            'payload_ishodnyy', jsonb_build_object('update_id', 'db03c1_event_1')
        )
      );

    IF r1.rezultat <> 'uspeshno'
       OR r1.polzovatel_id IS NULL
       OR r1.dialog_id IS NULL
       OR r1.soobshchenie_id IS NULL
       OR r1.zadanie_id IS NULL
       OR r1.versiya_dialoga <> 1 THEN
        RAISE EXCEPTION
            'DB-03C1 ingress first result invalid: %',
            row_to_json(r1);
    END IF;

    SELECT *
      INTO rdup
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_ingress_1_retry',
            'klyuch_idempotentnosti', 'db03c1_idem_1',
            'hash_soderzhaniya', 'db03c1_hash_1',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_1',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Телефон 8 (961) 123-45-67',
            'vremya_istochnika', '2026-09-24T17:00:00+00',
            'vremya_priema', '2026-09-24T17:00:01+00',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group',
            'payload_ishodnyy', jsonb_build_object('update_id', 'db03c1_event_1')
        )
      );

    IF rdup.rezultat <> 'dublikat'
       OR rdup.dialog_id IS DISTINCT FROM r1.dialog_id
       OR rdup.soobshchenie_id IS DISTINCT FROM r1.soobshchenie_id
       OR rdup.zadanie_id IS DISTINCT FROM r1.zadanie_id
       OR rdup.versiya_dialoga IS DISTINCT FROM r1.versiya_dialoga THEN
        RAISE EXCEPTION
            'DB-03C1 same-key/same-hash did not return prior result: %',
            row_to_json(rdup);
    END IF;

    SELECT *
      INTO rconf
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_ingress_1_conflict',
            'klyuch_idempotentnosti', 'db03c1_idem_1',
            'hash_soderzhaniya', 'DIFFERENT_HASH',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_1',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'other',
            'vremya_priema', '2026-09-24T17:00:02+00',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group'
        )
      );

    IF rconf.rezultat <> 'konflikt'
       OR rconf.kod_oshibki <> 'idempotency_hash_conflict' THEN
        RAISE EXCEPTION
            'DB-03C1 same-key/different-hash was not rejected: %',
            row_to_json(rconf);
    END IF;

    -- Different provider event ID but same external message ID: no second message/version bump.
    SELECT *
      INTO rconf
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_duplicate_provider_event',
            'klyuch_idempotentnosti', 'db03c1_idem_duplicate_provider',
            'hash_soderzhaniya', 'db03c1_hash_duplicate_provider',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_duplicate_provider',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Телефон 8 (961) 123-45-67',
            'vremya_priema', '2026-09-24T17:00:02+00',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group'
        )
      );

    IF rconf.rezultat <> 'dublikat'
       OR rconf.soobshchenie_id IS DISTINCT FROM r1.soobshchenie_id
       OR rconf.versiya_dialoga IS DISTINCT FROM r1.versiya_dialoga THEN
        RAISE EXCEPTION
            'DB-03C1 duplicate external message mutated/duplicated state: %',
            row_to_json(rconf);
    END IF;

    SELECT *
      INTO rconf
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_duplicate_provider_event_retry',
            'klyuch_idempotentnosti', 'db03c1_idem_duplicate_provider',
            'hash_soderzhaniya', 'db03c1_hash_duplicate_provider',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_duplicate_provider',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Телефон 8 (961) 123-45-67',
            'vremya_priema', '2026-09-24T17:00:02+00',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group'
        )
      );

    IF rconf.rezultat <> 'dublikat'
       OR rconf.soobshchenie_id IS DISTINCT FROM r1.soobshchenie_id
       OR rconf.versiya_dialoga IS DISTINCT FROM r1.versiya_dialoga THEN
        RAISE EXCEPTION
            'DB-03C1 repeat of duplicate provider event was not stable: %',
            row_to_json(rconf);
    END IF;

    -- The same old external message must remain duplicate even if its dialog is closed.
    UPDATE qbit_test.dialogi
       SET status = 'zavershen',
           vremya_zaversheniya = '2026-09-24T17:00:03+00',
           rezultat = 'konsultaciya_zavershena'
     WHERE id = r1.dialog_id;

    SELECT *
      INTO rconf
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_closed_dialog_duplicate',
            'klyuch_idempotentnosti', 'db03c1_idem_closed_duplicate',
            'hash_soderzhaniya', 'db03c1_hash_closed_duplicate',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_closed_duplicate',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Телефон 8 (961) 123-45-67',
            'vremya_priema', '2026-09-24T17:00:03+00',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group'
        )
      );

    IF rconf.rezultat <> 'dublikat'
       OR rconf.dialog_id IS DISTINCT FROM r1.dialog_id
       OR (
            SELECT count(*)
              FROM qbit_test.dialogi
             WHERE identifikator_kanala_id = r1.identifikator_kanala_id
       ) <> 1 THEN
        RAISE EXCEPTION
            'DB-03C1 old duplicate created/reopened a dialog: %',
            row_to_json(rconf);
    END IF;

    UPDATE qbit_test.dialogi
       SET status = 'aktivnyy',
           vremya_zaversheniya = NULL,
           rezultat = NULL
     WHERE id = r1.dialog_id;

    -- Simulate an active waiting state that the next client input must cancel.
    UPDATE qbit_test.dialogi
       SET status = 'ozhidaet_otveta',
           ozhidaetsya_otvet = true,
           t0 = '2026-09-24T17:00:02+00',
           pokolenie_ozhidaniya = 1
     WHERE id = r1.dialog_id;

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
        '00000000-0000-4000-8000-000000000341',
        r1.dialog_id,
        'ishodyashchee',
        'bot',
        'text',
        'DB-03C1 waiting probe',
        'DB-03C1 waiting probe',
        '2026-09-24T17:00:02+00',
        'podtverzhdeno',
        true
    );

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
        '2026-09-24T17:00:02+00',
        '00000000-0000-4000-8000-000000000341',
        1,
        '2026-09-24T20:00:02+00',
        '2026-09-24T21:00:02+00',
        'zaplanirovano'
    )
    RETURNING id INTO v_old_reminder;

    SELECT *
      INTO r2
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c1_ingress_2',
            'klyuch_idempotentnosti', 'db03c1_idem_2',
            'hash_soderzhaniya', 'db03c1_hash_2',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c1_client_bot',
            'vneshnee_sobytie_id', 'db03c1_event_2',
            'vneshniy_polzovatel_id', 'db03c1_user',
            'vneshniy_dialog_id', 'db03c1_chat',
            'vneshnee_soobshchenie_id', 'db03c1_msg_2',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'voice',
            'vremya_istochnika', '2026-09-24T17:01:00+00',
            'vremya_priema', '2026-09-24T17:01:01+00',
            'trassirovka_id', 'db03c1_trace_2',
            'versiya_workflow', 'db03c1_probe',
            'versiya_prompta', 'db03c1_probe',
            'sluzhebnyy_chat_id', 'db03c1_service_group',
            'payload_ishodnyy', jsonb_build_object('update_id', 'db03c1_event_2')
        )
      );

    IF r2.rezultat <> 'uspeshno'
       OR r2.dialog_id IS DISTINCT FROM r1.dialog_id
       OR r2.versiya_dialoga <> 2 THEN
        RAISE EXCEPTION
            'DB-03C1 second ingress did not reuse/increment dialog: %',
            row_to_json(r2);
    END IF;

    IF EXISTS (
        SELECT 1
          FROM qbit_test.dialogi AS d
         WHERE d.id = r1.dialog_id
           AND (
                d.ozhidaetsya_otvet = true
                OR d.t0 IS NOT NULL
                OR d.status = 'ozhidaet_otveta'
                OR d.pokolenie_ozhidaniya <> 2
           )
    ) THEN
        RAISE EXCEPTION
            'DB-03C1 new input did not invalidate old wait';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM qbit_test.napominaniya AS n
         WHERE n.id = v_old_reminder
           AND n.status = 'otmeneno'
           AND n.prichina = 'novyy_vhod'
    ) THEN
        RAISE EXCEPTION
            'DB-03C1 new input did not cancel old reminder';
    END IF;

    SELECT *
      INTO ratt
      FROM qbit_test.sohranit_vlozhenie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_attachment_1',
            'soobshchenie_id', r2.soobshchenie_id,
            'tip_vlozheniya', 'voice',
            'vneshniy_file_id', 'db03c1_file_id',
            'vneshniy_file_unique_id', 'db03c1_file_unique',
            'mime', 'audio/ogg',
            'razmer_bayt', 3,
            'maks_razmer_bayt', 1024,
            'sha256', 'db03c1_sha',
            'status_sohraneniya', 'sohraneno',
            'hranilishche_tip', 'postgres_bytea',
            'razresheno_ai', true,
            'bezopasnye_metadannye', jsonb_build_object('duration', 1)
        ),
        decode('010203', 'hex')
      );

    IF ratt.rezultat <> 'uspeshno'
       OR ratt.vlozhenie_id IS NULL THEN
        RAISE EXCEPTION
            'DB-03C1 attachment save failed: %',
            row_to_json(ratt);
    END IF;

    SELECT *
      INTO rattdup
      FROM qbit_test.sohranit_vlozhenie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_attachment_1_retry',
            'soobshchenie_id', r2.soobshchenie_id,
            'tip_vlozheniya', 'voice',
            'vneshniy_file_id', 'db03c1_file_id',
            'vneshniy_file_unique_id', 'db03c1_file_unique',
            'mime', 'audio/ogg',
            'razmer_bayt', 3,
            'maks_razmer_bayt', 1024,
            'sha256', 'db03c1_sha',
            'status_sohraneniya', 'sohraneno',
            'hranilishche_tip', 'postgres_bytea',
            'razresheno_ai', true
        ),
        decode('010203', 'hex')
      );

    IF rattdup.rezultat <> 'dublikat'
       OR rattdup.vlozhenie_id IS DISTINCT FROM ratt.vlozhenie_id THEN
        RAISE EXCEPTION
            'DB-03C1 attachment retry not idempotent: %',
            row_to_json(rattdup);
    END IF;

    SELECT *
      INTO rattconf
      FROM qbit_test.sohranit_vlozhenie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_attachment_conflict',
            'soobshchenie_id', r2.soobshchenie_id,
            'tip_vlozheniya', 'voice',
            'vneshniy_file_id', 'db03c1_file_id',
            'vneshniy_file_unique_id', 'db03c1_file_unique',
            'mime', 'audio/ogg',
            'razmer_bayt', 3,
            'maks_razmer_bayt', 1024,
            'sha256', 'DIFFERENT_SHA',
            'status_sohraneniya', 'sohraneno',
            'hranilishche_tip', 'postgres_bytea',
            'razresheno_ai', true
        ),
        decode('010203', 'hex')
      );

    IF rattconf.rezultat <> 'konflikt' THEN
        RAISE EXCEPTION
            'DB-03C1 attachment conflict not detected: %',
            row_to_json(rattconf);
    END IF;

    SELECT count(*)
      INTO v_before_violations
      FROM qbit_test.narusheniya_tematiky;

    SELECT *
      INTO rstt
      FROM qbit_test.sohranit_transkripciyu_golosa(
        jsonb_build_object(
            'operaciya_id', 'db03c1_stt_1',
            'soobshchenie_id', r2.soobshchenie_id,
            'status', 'gotova',
            'tekst_transkripcii', 'Меня зовут Тест',
            'tekst_obezlichennyy', 'Меня зовут <IMYA_1>',
            'dvizhok', 'local_probe',
            'versiya_dvizhka', '1',
            'popytki', 1,
            'vremya_nachala', '2026-09-24T17:01:02+00',
            'vremya_zaversheniya', '2026-09-24T17:01:03+00'
        )
      );

    IF rstt.rezultat <> 'uspeshno'
       OR rstt.status <> 'gotova' THEN
        RAISE EXCEPTION
            'DB-03C1 STT save failed: %',
            row_to_json(rstt);
    END IF;

    SELECT *
      INTO rsttdup
      FROM qbit_test.sohranit_transkripciyu_golosa(
        jsonb_build_object(
            'operaciya_id', 'db03c1_stt_1_retry',
            'soobshchenie_id', r2.soobshchenie_id,
            'status', 'gotova',
            'tekst_transkripcii', 'Меня зовут Тест',
            'tekst_obezlichennyy', 'Меня зовут <IMYA_1>',
            'dvizhok', 'local_probe',
            'versiya_dvizhka', '1',
            'popytki', 1,
            'vremya_nachala', '2026-09-24T17:01:02+00',
            'vremya_zaversheniya', '2026-09-24T17:01:03+00'
        )
      );

    IF rsttdup.rezultat <> 'dublikat' THEN
        RAISE EXCEPTION
            'DB-03C1 STT retry not idempotent: %',
            row_to_json(rsttdup);
    END IF;

    SELECT *
      INTO rsttconf
      FROM qbit_test.sohranit_transkripciyu_golosa(
        jsonb_build_object(
            'operaciya_id', 'db03c1_stt_conflict',
            'soobshchenie_id', r2.soobshchenie_id,
            'status', 'gotova',
            'tekst_transkripcii', 'Другой текст',
            'tekst_obezlichennyy', 'Другой текст',
            'dvizhok', 'local_probe',
            'versiya_dvizhka', '1',
            'popytki', 1
        )
      );

    IF rsttconf.rezultat <> 'konflikt' THEN
        RAISE EXCEPTION
            'DB-03C1 final STT conflict not detected: %',
            row_to_json(rsttconf);
    END IF;

    SELECT count(*)
      INTO v_after_violations
      FROM qbit_test.narusheniya_tematiky;

    IF v_after_violations <> v_before_violations THEN
        RAISE EXCEPTION
            'DB-03C1 STT unexpectedly changed thematic violations';
    END IF;

    SELECT *
      INTO rpii
      FROM qbit_test.sohranit_obezlichivanie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_pii_1',
            'soobshchenie_id', r1.soobshchenie_id,
            'tekst_obezlichennyy', 'Телефон <TELEFON_1>',
            'region_telefona', 'RU',
            'sootvetstviya', jsonb_build_array(
                jsonb_build_object(
                    'tip_pii', 'telefon',
                    'psevdometka', '<TELEFON_1>',
                    'znachenie_zashchishchennoe', '8 (961) 123-45-67',
                    'hash_normalizovannogo_znacheniya', 'db03c1_phone_hash'
                )
            )
        )
      );

    IF rpii.rezultat <> 'uspeshno'
       OR rpii.kolichestvo_sootvetstviy <> 1 THEN
        RAISE EXCEPTION
            'DB-03C1 PII save failed: %',
            row_to_json(rpii);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM qbit_test.sootvetstviya_pii AS p
         WHERE p.dialog_id = r1.dialog_id
           AND p.psevdometka = '<TELEFON_1>'
           AND p.znachenie_zashchishchennoe = '+79611234567'
    ) THEN
        RAISE EXCEPTION
            'DB-03C1 phone canonicalization failed for parentheses/dashes format';
    END IF;

    -- Same phone without punctuation must resolve to the same protected value.
    SELECT *
      INTO rpiidup
      FROM qbit_test.sohranit_obezlichivanie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_pii_1_retry_digits',
            'soobshchenie_id', r1.soobshchenie_id,
            'tekst_obezlichennyy', 'Телефон <TELEFON_1>',
            'region_telefona', 'RU',
            'sootvetstviya', jsonb_build_array(
                jsonb_build_object(
                    'tip_pii', 'telefon',
                    'psevdometka', '<TELEFON_1>',
                    'znachenie_zashchishchennoe', '89611234567',
                    'hash_normalizovannogo_znacheniya', 'db03c1_phone_hash'
                )
            )
        )
      );

    IF rpiidup.rezultat <> 'dublikat' THEN
        RAISE EXCEPTION
            'DB-03C1 PII digits-only phone retry not idempotent: %',
            row_to_json(rpiidup);
    END IF;

    -- Same phone in +7/spaces format must also be identical.
    SELECT *
      INTO rpiidup2
      FROM qbit_test.sohranit_obezlichivanie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_pii_1_retry_plus7',
            'soobshchenie_id', r1.soobshchenie_id,
            'tekst_obezlichennyy', 'Телефон <TELEFON_1>',
            'region_telefona', 'RU',
            'sootvetstviya', jsonb_build_array(
                jsonb_build_object(
                    'tip_pii', 'telefon',
                    'psevdometka', '<TELEFON_1>',
                    'znachenie_zashchishchennoe', '+7 961 123 45 67',
                    'hash_normalizovannogo_znacheniya', 'db03c1_phone_hash'
                )
            )
        )
      );

    IF rpiidup2.rezultat <> 'dublikat' THEN
        RAISE EXCEPTION
            'DB-03C1 PII +7/spaces phone retry not idempotent: %',
            row_to_json(rpiidup2);
    END IF;

    -- A genuinely different phone under the same placeholder must conflict.
    SELECT *
      INTO rpiiconf
      FROM qbit_test.sohranit_obezlichivanie(
        jsonb_build_object(
            'operaciya_id', 'db03c1_pii_conflict',
            'soobshchenie_id', r1.soobshchenie_id,
            'tekst_obezlichennyy', 'Телефон <TELEFON_1>',
            'region_telefona', 'RU',
            'sootvetstviya', jsonb_build_array(
                jsonb_build_object(
                    'tip_pii', 'telefon',
                    'psevdometka', '<TELEFON_1>',
                    'znachenie_zashchishchennoe', '8-962-123-45-67',
                    'hash_normalizovannogo_znacheniya', 'different_hash'
                )
            )
        )
      );

    IF rpiiconf.rezultat <> 'konflikt' THEN
        RAISE EXCEPTION
            'DB-03C1 PII different-phone conflict not detected: %',
            row_to_json(rpiiconf);
    END IF;

    IF (
        SELECT count(*)
          FROM qbit_test.sobytiya_zerkala_operatora
         WHERE dialog_id = r1.dialog_id
    ) <> 3 THEN
        RAISE EXCEPTION
            'DB-03C1 expected topic + text + media mirror intents';
    END IF;
END
$db03c1$;

ROLLBACK TO SAVEPOINT db03c1_probe;
RELEASE SAVEPOINT db03c1_probe;

-- ===========================================================================
-- 9. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03c1$
DECLARE
    v_role text;
    v_table record;
    v_probe_rows bigint;
BEGIN
    SELECT
          (SELECT count(*) FROM qbit_test.polzovateli)
        + (SELECT count(*) FROM qbit_test.identifikatory_kanalov)
        + (SELECT count(*) FROM qbit_test.dialogi)
        + (SELECT count(*) FROM qbit_test.soobshcheniya)
        + (SELECT count(*) FROM qbit_test.vlozheniya_soobshcheniy)
        + (SELECT count(*) FROM qbit_test.transkripcii_golosa)
        + (SELECT count(*) FROM qbit_test.sootvetstviya_pii)
        + (SELECT count(*) FROM qbit_test.sobytiya_integraciy)
        + (SELECT count(*) FROM qbit_test.zadaniya_obrabotki)
        + (SELECT count(*) FROM qbit_test.napominaniya)
        + (SELECT count(*) FROM qbit_test.operator_telegram_temy)
        + (SELECT count(*) FROM qbit_test.sobytiya_zerkala_operatora)
      INTO v_probe_rows;

    IF v_probe_rows <> 0 THEN
        RAISE EXCEPTION
            'DB-03C1 probe rows remain after SAVEPOINT rollback: %',
            v_probe_rows;
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot'
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
                    'qbit_test_bot unexpectedly has direct DML on qbit_test.%',
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;
END
$db03c1$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 10. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03c1_status',
    'applied',
    'database',
    current_database(),
    'schema',
    'qbit_test',
    'functions_ok',
    (
        SELECT count(*) = 4
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie'
           )
           AND p.prosecdef = true
    ),
    'attachment_idempotency_indexes_ok',
    pg_catalog.to_regclass('qbit_test.uq_vlozheniya_msg_file_id') IS NOT NULL
    AND pg_catalog.to_regclass('qbit_test.uq_vlozheniya_msg_file_unique') IS NOT NULL,
    'bot_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.zaregistrirovat_vhod_klienta(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.sohranit_vlozhenie(jsonb,bytea)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.sohranit_transkripciyu_golosa(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.sohranit_obezlichivanie(jsonb)',
        'EXECUTE'
    ),
    'service_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.zaregistrirovat_vhod_klienta(jsonb)',
        'EXECUTE'
    ),
    'probe_rows_remaining',
      (SELECT count(*) FROM qbit_test.polzovateli)
    + (SELECT count(*) FROM qbit_test.identifikatory_kanalov)
    + (SELECT count(*) FROM qbit_test.dialogi)
    + (SELECT count(*) FROM qbit_test.soobshcheniya)
    + (SELECT count(*) FROM qbit_test.vlozheniya_soobshcheniy)
    + (SELECT count(*) FROM qbit_test.transkripcii_golosa)
    + (SELECT count(*) FROM qbit_test.sootvetstviya_pii)
    + (SELECT count(*) FROM qbit_test.sobytiya_integraciy)
    + (SELECT count(*) FROM qbit_test.zadaniya_obrabotki)
    + (SELECT count(*) FROM qbit_test.napominaniya)
    + (SELECT count(*) FROM qbit_test.operator_telegram_temy)
    + (SELECT count(*) FROM qbit_test.sobytiya_zerkala_operatora),
    'runtime_direct_dml',
    false,
    'result',
    'DB-03C1 v0.3 SQL APPLIED: ingress/media/STT/PII API verified; variable/ambiguity/phone-normalization/idempotency/conflict/wait-cancel probes passed; production untouched.'
) AS db03c1_result;
