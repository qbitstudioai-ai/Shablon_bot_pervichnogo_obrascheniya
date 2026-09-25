-- DB-03D1 v0.1: service ingress, private manager chat, operator topic and mirror queue
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02, DB-03A, DB-03B and DB-03C1..C4 applied.
--
-- CREATES 7 SECURITY DEFINER FUNCTIONS
--   zaregistrirovat_sluzhebnoe_sobytie(jsonb) -> qbit_test_sluzhebnyy
--   podtverdit_lichnyy_chat_menedzhera(jsonb)  -> qbit_test_sluzhebnyy
--   zabrat_sobytie_zerkala(jsonb)              -> qbit_test_sluzhebnyy
--   zafiksirovat_rezultat_zerkala(jsonb)       -> qbit_test_sluzhebnyy
--   zabrat_sozdanie_operator_temy(jsonb)        -> qbit_test_sluzhebnyy
--   podtverdit_operator_temu(jsonb)             -> qbit_test_sluzhebnyy
--   otmetit_temu_neizvestnoy(jsonb)             -> qbit_test_sluzhebnyy
--
-- RELIABILITY MODEL
--   * service webhook is durably registered before routing;
--   * unknown manager is never auto-added by /start;
--   * topic creation is one durable intent per dialog;
--   * createForumTopic ambiguous result becomes neizvestno and is never blind-retried;
--   * mirror/topic claims use lease + monotonic fencing number;
--   * mirror unknown is terminal for blind retry;
--   * service role gets only narrow function results, never general archive SELECT;
--   * topic confirmation binds queued group mirror events to trusted thread_id;
--   * claimed media returns only bytes/storage reference of that exact mirror event.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * Probe rows are rolled back to SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03D1 migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03d1$
DECLARE
    v_required_table text;
    v_required_fn text;
    v_new_fn text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03D1 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03D1 must run from trusted postgres session. session_user=%',
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
        'sobytiya_integraciy',
        'sistemnye_sobytiya',
        'dialogi',
        'soobshcheniya',
        'vlozheniya_soobshcheniy',
        'menedzhery_telegram',
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
        'zafiksirovat_rezultat_ishodyashchego'
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
        'zaregistrirovat_sluzhebnoe_sobytie',
        'podtverdit_lichnyy_chat_menedzhera',
        'zabrat_sobytie_zerkala',
        'zafiksirovat_rezultat_zerkala',
        'zabrat_sozdanie_operator_temy',
        'podtverdit_operator_temu',
        'otmetit_temu_neizvestnoy'
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
                'DB-03D1 function qbit_test.% already exists; stop instead of overwriting',
                v_new_fn;
        END IF;
    END LOOP;

    IF pg_catalog.to_regclass('qbit_test.uq_sobint_istochnik_sobytie') IS NULL
       OR pg_catalog.to_regclass('qbit_test.uq_sobint_idempotentnost') IS NULL
       OR pg_catalog.to_regclass('qbit_test.uq_operator_tema_chat_thread') IS NULL
       OR pg_catalog.to_regclass('qbit_test.uq_zerkalo_klyuch') IS NULL THEN
        RAISE EXCEPTION
            'Required DB-03A/DB-03B unique indexes are missing';
    END IF;
END
$db03d1$;

SET LOCAL ROLE qbit_test_owner;

-- ===========================================================================
-- 1. DURABLE SERVICE TELEGRAM INGRESS
-- ===========================================================================

CREATE FUNCTION qbit_test.zaregistrirovat_sluzhebnoe_sobytie(
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
SET search_path = pg_catalog, qbit_test
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

    INSERT INTO qbit_test.sobytiya_integraciy AS new_event (
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
      FROM qbit_test.sobytiya_integraciy AS e
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
          FROM qbit_test.sobytiya_integraciy AS e2
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

COMMENT ON FUNCTION qbit_test.zaregistrirovat_sluzhebnoe_sobytie(jsonb) IS
'DB-03D1: durable idempotent ingress Telegram service bot; hardcodes source telegram_service, detects same-event content conflict, returns persisted payload for internal routing and never creates client dialog.';

-- ===========================================================================
-- 2. CONFIRM PRIVATE CHAT ONLY FOR PRE-ALLOWED ACTIVE MANAGER
-- ===========================================================================

CREATE FUNCTION qbit_test.podtverdit_lichnyy_chat_menedzhera(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.sobytiya_integraciy AS e
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
      FROM qbit_test.menedzhery_telegram AS m
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
          FROM qbit_test.menedzhery_telegram AS other_manager
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

    UPDATE qbit_test.menedzhery_telegram AS m_upd
       SET private_chat_id = v_chat,
           private_chat_podtverzhden = true,
           vremya_podtverzhdeniya = v_confirmed_at,
           vremya_obnovleniya = clock_timestamp()
     WHERE m_upd.id = v_manager.id;

    UPDATE qbit_test.sobytiya_integraciy AS e_done
       SET status = 'obrabotano'
     WHERE e_done.id = v_event_id;

    RETURN QUERY SELECT
        v_operation, 'uspeshno'::text, NULL::text,
        'Private chat подтверждён только для заранее разрешённого active manager.'::text,
        NULL::timestamptz,
        v_manager.id, v_manager.telegram_user_id, v_chat, true;
END
$fn$;

COMMENT ON FUNCTION qbit_test.podtverdit_lichnyy_chat_menedzhera(jsonb) IS
'DB-03D1: /start confirms private chat only for an already existing active telegram_user_id; unknown users are rejected and existing confirmed chat is never silently replaced.';

-- ===========================================================================
-- 3. CLAIM OPERATOR TOPIC CREATION INTENT
-- ===========================================================================

CREATE FUNCTION qbit_test.zabrat_sozdanie_operator_temy(
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
SET search_path = pg_catalog, qbit_test
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
          FROM qbit_test.operator_telegram_temy AS t
          LEFT JOIN qbit_test.sobytiya_zerkala_operatora AS e
            ON e.klyuch_idempotentnosti = 'tema:' || t.dialog_id::text
         WHERE t.dialog_id = v_dialog_id
         FOR UPDATE OF t SKIP LOCKED;

        IF NOT FOUND THEN
            IF EXISTS (
                SELECT 1
                  FROM qbit_test.operator_telegram_temy AS t_busy
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
          FROM qbit_test.operator_telegram_temy AS t
          LEFT JOIN qbit_test.sobytiya_zerkala_operatora AS e
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

    UPDATE qbit_test.operator_telegram_temy AS t_claim
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

COMMENT ON FUNCTION qbit_test.zabrat_sozdanie_operator_temy(jsonb) IS
'DB-03D1: claims one durable operator topic intent with lease/fencing; gotova returns existing mapping, neizvestno blocks blind recreation, expired sozdaetsya can be reclaimed.';

-- ===========================================================================
-- 4. CONFIRM TOPIC MAPPING ONCE
-- ===========================================================================

CREATE FUNCTION qbit_test.podtverdit_operator_temu(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.operator_telegram_temy AS t
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
            UPDATE qbit_test.operator_telegram_temy AS t_card
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
          FROM qbit_test.operator_telegram_temy AS other_topic
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

    UPDATE qbit_test.operator_telegram_temy AS t_done
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

    UPDATE qbit_test.sobytiya_zerkala_operatora AS e_target
       SET cel_chat_id = v_topic.sluzhebnyy_chat_id,
           cel_thread_id = v_thread,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_target.dialog_id = v_dialog_id
       AND e_target.tip_sobytiya NOT IN ('obespechit_temu','lichnoe_uvedomlenie')
       AND e_target.status IN ('zaplanirovano','povtor');

    UPDATE qbit_test.sobytiya_zerkala_operatora AS e_ensure
       SET status = 'podtverzhdeno',
           vremya_podtverzhdeniya = v_confirmed_at,
           kod_oshibki = NULL,
           opisanie_oshibki = NULL,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_ensure.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

    IF v_card IS NULL THEN
        SELECT e.bezopasnaya_podpis_klienta
          INTO v_safe_client
          FROM qbit_test.sobytiya_zerkala_operatora AS e
         WHERE e.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
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

COMMENT ON FUNCTION qbit_test.podtverdit_operator_temu(jsonb) IS
'DB-03D1: confirms one dialog->service chat->thread mapping only for current topic owner/fencing; binds queued group mirror events to thread and creates initial card event when card id is not already known.';

-- ===========================================================================
-- 5. MARK AMBIGUOUS createForumTopic AS UNKNOWN
-- ===========================================================================

CREATE FUNCTION qbit_test.otmetit_temu_neizvestnoy(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.operator_telegram_temy AS t
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

    UPDATE qbit_test.operator_telegram_temy AS t_unknown
       SET status = 'neizvestno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = v_error_code,
           opisanie_oshibki = v_error_description
     WHERE t_unknown.dialog_id = v_dialog_id;

    UPDATE qbit_test.sobytiya_zerkala_operatora AS e_ensure
       SET status = 'neizvestno',
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = v_error_code,
           opisanie_oshibki = v_error_description,
           vremya_obnovleniya = clock_timestamp()
     WHERE e_ensure.klyuch_idempotentnosti = 'tema:' || v_dialog_id::text;

    INSERT INTO qbit_test.sistemnye_sobytiya (
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

COMMENT ON FUNCTION qbit_test.otmetit_temu_neizvestnoy(jsonb) IS
'DB-03D1: persists ambiguous createForumTopic as neizvestno, clears lease, marks ensure-topic mirror unknown and writes one system warning; subsequent automatic claim refuses blind recreate.';

-- ===========================================================================
-- 6. CLAIM ONE MIRROR EVENT AND RETURN ONLY ITS NARROW DATA
-- ===========================================================================

CREATE FUNCTION qbit_test.zabrat_sobytie_zerkala(
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
SET search_path = pg_catalog, qbit_test
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
              FROM qbit_test.sobytiya_zerkala_operatora AS e
              LEFT JOIN qbit_test.operator_telegram_temy AS t
                ON t.dialog_id = e.dialog_id
              LEFT JOIN qbit_test.menedzhery_telegram AS m
                ON m.id = e.cel_menedzher_id
             WHERE e.id = v_event_id
             FOR UPDATE OF e SKIP LOCKED;

            IF NOT FOUND THEN
                IF EXISTS (
                    SELECT 1
                      FROM qbit_test.sobytiya_zerkala_operatora AS e_busy
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
              FROM qbit_test.sobytiya_zerkala_operatora AS e
              LEFT JOIN qbit_test.operator_telegram_temy AS t
                ON t.dialog_id = e.dialog_id
              LEFT JOIN qbit_test.menedzhery_telegram AS m
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
                UPDATE qbit_test.sobytiya_zerkala_operatora AS e_cancel
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

        UPDATE qbit_test.sobytiya_zerkala_operatora AS e_claim
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
              FROM qbit_test.vlozheniya_soobshcheniy AS a
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

COMMENT ON FUNCTION qbit_test.zabrat_sobytie_zerkala(jsonb) IS
'DB-03D1: claims one mirror event with lease/fencing and returns only event-specific text/payload/topic/private target and exact attachment bytes/storage reference; general archive SELECT remains denied.';

-- ===========================================================================
-- 7. RECORD MIRROR TELEGRAM RESULT
-- ===========================================================================

CREATE FUNCTION qbit_test.zafiksirovat_rezultat_zerkala(
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
SET search_path = pg_catalog, qbit_test
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
      FROM qbit_test.sobytiya_zerkala_operatora AS e
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

    UPDATE qbit_test.sobytiya_zerkala_operatora AS e_done
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
          FROM qbit_test.operator_telegram_temy AS t
         WHERE t.dialog_id=v_event.dialog_id
         FOR UPDATE;

        IF FOUND THEN
            UPDATE qbit_test.operator_telegram_temy AS t_sync
               SET vremya_posledney_sinhronizacii=v_confirm_time
             WHERE t_sync.dialog_id=v_event.dialog_id;

            IF v_event.tip_sobytiya='obnovit_kartochku'
               AND v_event.payload->>'rezhim'='initial' THEN
                IF v_topic.vneshniy_id_kartochki IS NULL THEN
                    UPDATE qbit_test.operator_telegram_temy AS t_card
                       SET vneshniy_id_kartochki=v_external_id
                     WHERE t_card.dialog_id=v_event.dialog_id;
                ELSIF v_topic.vneshniy_id_kartochki IS DISTINCT FROM v_external_id THEN
                    INSERT INTO qbit_test.sistemnye_sobytiya (
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

COMMENT ON FUNCTION qbit_test.zafiksirovat_rezultat_zerkala(jsonb) IS
'DB-03D1: fenced confirmed/retry/unknown/error result for one claimed mirror event; unknown is terminal for blind retry, confirmed initial card may fill topic card id once.';

-- ===========================================================================
-- 8. PRIVILEGES
-- ===========================================================================

REVOKE ALL ON FUNCTION qbit_test.zaregistrirovat_sluzhebnoe_sobytie(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.podtverdit_lichnyy_chat_menedzhera(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zabrat_sozdanie_operator_temy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.podtverdit_operator_temu(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.otmetit_temu_neizvestnoy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zabrat_sobytie_zerkala(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zafiksirovat_rezultat_zerkala(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_test.zaregistrirovat_sluzhebnoe_sobytie(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.podtverdit_lichnyy_chat_menedzhera(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.zabrat_sozdanie_operator_temy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.podtverdit_operator_temu(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.otmetit_temu_neizvestnoy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.zabrat_sobytie_zerkala(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_test.zafiksirovat_rezultat_zerkala(jsonb) TO qbit_test_sluzhebnyy;

-- ===========================================================================
-- 9. STATIC SECURITY ASSERTIONS
-- ===========================================================================

DO $db03d1$
DECLARE
    v_fn record;
BEGIN
    FOR v_fn IN
        SELECT p.oid,p.proname,p.prosecdef,p.proconfig,r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
          JOIN pg_catalog.pg_roles AS r ON r.oid=p.proowner
         WHERE n.nspname='qbit_test'
           AND p.proname IN (
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy'
           )
    LOOP
        IF NOT v_fn.prosecdef
           OR v_fn.owner_name IS DISTINCT FROM 'qbit_test_owner'
           OR NOT (
                COALESCE(v_fn.proconfig,ARRAY[]::text[])
                @> ARRAY['search_path=pg_catalog, qbit_test']::text[]
           ) THEN
            RAISE EXCEPTION
                'Unsafe DB-03D1 function metadata: %, owner=%, config=%',
                v_fn.proname,v_fn.owner_name,v_fn.proconfig;
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
             WHERE a.grantee=0
               AND a.privilege_type='EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'PUBLIC unexpectedly has EXECUTE on %',
                v_fn.proname;
        END IF;

        IF NOT pg_catalog.has_function_privilege(
            'qbit_test_sluzhebnyy',v_fn.oid,'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_sluzhebnyy lacks EXECUTE on %',
                v_fn.proname;
        END IF;

        IF pg_catalog.has_function_privilege(
            'qbit_test_bot',v_fn.oid,'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_bot unexpectedly has service EXECUTE on %',
                v_fn.proname;
        END IF;
    END LOOP;

    IF (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_test'
           AND p.proname IN (
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy'
           )
    ) <> 7 THEN
        RAISE EXCEPTION 'DB-03D1 expected exactly 7 functions';
    END IF;
END
$db03d1$;

-- ===========================================================================
-- 10. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03d1_probe;

DO $db03d1$
DECLARE
    s1 record;
    sdup record;
    sconflict record;
    pc1 record;
    pcdup record;
    pcunknown record;

    rin record;
    topic1 record;
    topic_busy record;
    topic_ok record;
    topic_dup record;
    topic_conflict record;

    mirror_card record;
    mirror_card_done record;
    mirror_text record;
    mirror_text_done record;
    mirror_media record;
    mirror_media_done record;
    mirror_private record;
    mirror_private_done record;
    mirror_retry1 record;
    mirror_retry_done record;
    mirror_retry2 record;
    mirror_unknown_done record;
    mirror_unknown_claim record;

    topic_unknown_claim record;
    topic_unknown_done record;
    topic_unknown_again record;

    v_manager1 uuid;
    v_manager2 uuid;
    v_attachment uuid;
    v_unknown_dialog uuid;
    v_topic_card text;
BEGIN
    INSERT INTO qbit_test.menedzhery_telegram (
        telegram_user_id,
        otobrazhaemoe_imya,
        aktiven,
        mozhet_zabirat,
        mozhet_vozvrashchat,
        lichnye_uvedomleniya,
        prioritet_naznacheniya
    )
    VALUES (
        'db03d1_manager_1',
        'Менеджер D1',
        true,true,true,true,10
    )
    RETURNING menedzhery_telegram.id INTO v_manager1;

    INSERT INTO qbit_test.menedzhery_telegram (
        telegram_user_id,
        otobrazhaemoe_imya,
        aktiven,
        mozhet_zabirat,
        mozhet_vozvrashchat,
        lichnye_uvedomleniya,
        prioritet_naznacheniya
    )
    VALUES (
        'db03d1_manager_2',
        'Менеджер D1-2',
        true,true,true,true,20
    )
    RETURNING menedzhery_telegram.id INTO v_manager2;

    -- Durable service ingress + duplicate + content conflict.
    SELECT * INTO s1
      FROM qbit_test.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03d1_service_start',
            'akkaunt_istochnika_id','db03d1_service_bot',
            'vneshnee_sobytie_id','db03d1_update_1',
            'tip_sobytiya','start',
            'klyuch_idempotentnosti','db03d1_service_idem_1',
            'hash_soderzhaniya','db03d1_service_hash_1',
            'payload_ishodnyy',jsonb_build_object(
                'telegram_user_id','db03d1_manager_1',
                'private_chat_id','db03d1_private_1'
            ),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO sdup
      FROM qbit_test.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03d1_service_start_dup',
            'akkaunt_istochnika_id','db03d1_service_bot',
            'vneshnee_sobytie_id','db03d1_update_1',
            'tip_sobytiya','start',
            'klyuch_idempotentnosti','db03d1_service_idem_1',
            'hash_soderzhaniya','db03d1_service_hash_1',
            'payload_ishodnyy',jsonb_build_object(
                'telegram_user_id','db03d1_manager_1',
                'private_chat_id','db03d1_private_1'
            ),
            'vremya_priema',clock_timestamp()
        )
      );

    SELECT * INTO sconflict
      FROM qbit_test.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03d1_service_start_conflict',
            'akkaunt_istochnika_id','db03d1_service_bot',
            'vneshnee_sobytie_id','db03d1_update_1',
            'tip_sobytiya','start',
            'klyuch_idempotentnosti','db03d1_service_idem_other',
            'hash_soderzhaniya','db03d1_service_hash_DIFFERENT',
            'payload_ishodnyy',jsonb_build_object(
                'telegram_user_id','db03d1_manager_1',
                'private_chat_id','different'
            ),
            'vremya_priema',clock_timestamp()
        )
      );

    IF s1.rezultat<>'uspeshno'
       OR sdup.rezultat<>'dublikat'
       OR sdup.sobytie_id IS DISTINCT FROM s1.sobytie_id
       OR sconflict.rezultat<>'konflikt' THEN
        RAISE EXCEPTION
            'DB-03D1 service ingress idempotency/conflict failed: new=%, dup=%, conflict=%',
            row_to_json(s1),row_to_json(sdup),row_to_json(sconflict);
    END IF;

    SELECT * INTO pc1
      FROM qbit_test.podtverdit_lichnyy_chat_menedzhera(
        jsonb_build_object(
            'operaciya_id','db03d1_confirm_private',
            'sobytie_id',s1.sobytie_id,
            'telegram_user_id','db03d1_manager_1',
            'private_chat_id','db03d1_private_1'
        )
      );

    SELECT * INTO pcdup
      FROM qbit_test.podtverdit_lichnyy_chat_menedzhera(
        jsonb_build_object(
            'operaciya_id','db03d1_confirm_private_dup',
            'sobytie_id',s1.sobytie_id,
            'telegram_user_id','db03d1_manager_1',
            'private_chat_id','db03d1_private_1'
        )
      );

    SELECT * INTO pcunknown
      FROM qbit_test.podtverdit_lichnyy_chat_menedzhera(
        jsonb_build_object(
            'operaciya_id','db03d1_confirm_unknown_manager',
            'sobytie_id',s1.sobytie_id,
            'telegram_user_id','db03d1_unknown_manager',
            'private_chat_id','db03d1_private_unknown'
        )
      );

    IF pc1.rezultat<>'uspeshno'
       OR pcdup.rezultat<>'dublikat'
       OR pcunknown.rezultat<>'otkaz'
       OR pcunknown.kod_oshibki<>'menedzher_ne_razreshen' THEN
        RAISE EXCEPTION
            'DB-03D1 private chat allowlist failed: new=%, dup=%, unknown=%',
            row_to_json(pc1),row_to_json(pcdup),row_to_json(pcunknown);
    END IF;

    -- Client ingress creates one topic intent and queued client text mirror.
    SELECT * INTO rin
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','db03d1_client_ingress',
            'klyuch_idempotentnosti','db03d1_client_idem',
            'hash_soderzhaniya','db03d1_client_hash',
            'kanal','telegram',
            'akkaunt_kanala_id','db03d1_client_bot',
            'vneshnee_sobytie_id','db03d1_client_event',
            'vneshniy_polzovatel_id','db03d1_client_user',
            'vneshniy_dialog_id','db03d1_client_chat',
            'vneshnee_soobshchenie_id','db03d1_client_msg',
            'tip_sobytiya','message',
            'tip_soobshcheniya','text',
            'tekst_ishodnyy','DB-03D1 клиентский текст',
            'vremya_priema',clock_timestamp(),
            'versiya_workflow','db03d1_probe',
            'versiya_prompta','db03d1_probe',
            'sluzhebnyy_chat_id','db03d1_service_group',
            'bezopasnaya_podpis_klienta','Клиент D1'
        )
      );

    SELECT * INTO topic1
      FROM qbit_test.zabrat_sozdanie_operator_temy(
        jsonb_build_object(
            'operaciya_id','db03d1_topic_create_1',
            'worker_id','topic_worker_1',
            'dialog_id',rin.dialog_id,
            'arenda_sekund',120
        )
      );

    SELECT * INTO topic_busy
      FROM qbit_test.zabrat_sozdanie_operator_temy(
        jsonb_build_object(
            'operaciya_id','db03d1_topic_create_2',
            'worker_id','topic_worker_2',
            'dialog_id',rin.dialog_id,
            'arenda_sekund',120
        )
      );

    IF topic1.rezultat<>'uspeshno'
       OR topic1.nomer_vladeniya<>1
       OR topic_busy.rezultat<>'zanyato' THEN
        RAISE EXCEPTION
            'DB-03D1 topic first-owner-wins failed: first=%, second=%',
            row_to_json(topic1),row_to_json(topic_busy);
    END IF;

    SELECT * INTO topic_ok
      FROM qbit_test.podtverdit_operator_temu(
        jsonb_build_object(
            'operaciya_sozdaniya_id',topic1.operaciya_sozdaniya_id,
            'dialog_id',rin.dialog_id,
            'worker_id','topic_worker_1',
            'nomer_vladeniya',topic1.nomer_vladeniya,
            'message_thread_id','db03d1_thread_1'
        )
      );

    SELECT * INTO topic_dup
      FROM qbit_test.podtverdit_operator_temu(
        jsonb_build_object(
            'operaciya_sozdaniya_id',topic1.operaciya_sozdaniya_id,
            'dialog_id',rin.dialog_id,
            'worker_id','topic_worker_1',
            'nomer_vladeniya',topic1.nomer_vladeniya,
            'message_thread_id','db03d1_thread_1'
        )
      );

    SELECT * INTO topic_conflict
      FROM qbit_test.podtverdit_operator_temu(
        jsonb_build_object(
            'operaciya_sozdaniya_id',topic1.operaciya_sozdaniya_id,
            'dialog_id',rin.dialog_id,
            'worker_id','topic_worker_1',
            'nomer_vladeniya',topic1.nomer_vladeniya,
            'message_thread_id','db03d1_thread_OTHER'
        )
      );

    IF topic_ok.rezultat<>'uspeshno'
       OR topic_dup.rezultat<>'dublikat'
       OR topic_conflict.rezultat<>'konflikt' THEN
        RAISE EXCEPTION
            'DB-03D1 topic confirm/idempotency/conflict failed: ok=%, dup=%, conflict=%',
            row_to_json(topic_ok),row_to_json(topic_dup),row_to_json(topic_conflict);
    END IF;

    -- Initial card is higher priority than client text.
    SELECT * INTO mirror_card
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_card_claim',
            'worker_id','mirror_worker_1',
            'arenda_sekund',120
        )
      );

    IF mirror_card.rezultat<>'uspeshno'
       OR mirror_card.tip_sobytiya<>'obnovit_kartochku'
       OR mirror_card.cel_chat_id<>'db03d1_service_group'
       OR mirror_card.cel_thread_id<>'db03d1_thread_1' THEN
        RAISE EXCEPTION
            'DB-03D1 initial card mirror claim failed: %',
            row_to_json(mirror_card);
    END IF;

    SELECT * INTO mirror_card_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_card_done',
            'sobytie_zerkala_id',mirror_card.sobytie_zerkala_id,
            'worker_id','mirror_worker_1',
            'nomer_vladeniya',mirror_card.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_message_id','db03d1_card_msg',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    SELECT t.vneshniy_id_kartochki
      INTO v_topic_card
      FROM qbit_test.operator_telegram_temy AS t
     WHERE t.dialog_id=rin.dialog_id;

    IF mirror_card_done.rezultat<>'uspeshno'
       OR v_topic_card<>'db03d1_card_msg' THEN
        RAISE EXCEPTION
            'DB-03D1 initial card result did not bind card id: result=%, card=%',
            row_to_json(mirror_card_done),v_topic_card;
    END IF;

    SELECT * INTO mirror_text
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_text_claim',
            'worker_id','mirror_worker_2',
            'arenda_sekund',120
        )
      );

    IF mirror_text.rezultat<>'uspeshno'
       OR mirror_text.tip_sobytiya<>'soobshchenie_klienta'
       OR mirror_text.soobshchenie_id IS DISTINCT FROM rin.soobshchenie_id
       OR mirror_text.tekst IS DISTINCT FROM 'DB-03D1 клиентский текст'
       OR mirror_text.cel_thread_id<>'db03d1_thread_1' THEN
        RAISE EXCEPTION
            'DB-03D1 narrow client text mirror failed: %',
            row_to_json(mirror_text);
    END IF;

    SELECT * INTO mirror_text_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_text_done',
            'sobytie_zerkala_id',mirror_text.sobytie_zerkala_id,
            'worker_id','mirror_worker_2',
            'nomer_vladeniya',mirror_text.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_message_id','db03d1_client_mirror_msg',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    -- Exact media bytes are returned only through the claimed mirror event.
    INSERT INTO qbit_test.vlozheniya_soobshcheniy (
        soobshchenie_id,
        tip_vlozheniya,
        imya_fayla,
        mime,
        razmer_bayt,
        sha256,
        status_sohraneniya,
        hranilishche_tip,
        soderzhimoe,
        razresheno_ai,
        bezopasnye_metadannye
    )
    VALUES (
        rin.soobshchenie_id,
        'photo',
        'probe.jpg',
        'image/jpeg',
        3,
        'db03d1_sha',
        'sohraneno',
        'postgres_bytea',
        decode('010203','hex'),
        false,
        '{}'::jsonb
    )
    RETURNING vlozheniya_soobshcheniy.id INTO v_attachment;

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
        rin.dialog_id,
        rin.soobshchenie_id,
        v_attachment,
        'media_klienta',
        'db03d1_media_probe',
        30,
        'db03d1_service_group',
        'db03d1_thread_1',
        jsonb_build_object('probe',true),
        'zaplanirovano'
    );

    SELECT * INTO mirror_media
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_media_claim',
            'worker_id','mirror_worker_media',
            'arenda_sekund',120
        )
      );

    IF mirror_media.rezultat<>'uspeshno'
       OR mirror_media.tip_sobytiya<>'media_klienta'
       OR mirror_media.vlozhenie_id IS DISTINCT FROM v_attachment
       OR mirror_media.soderzhimoe IS DISTINCT FROM decode('010203','hex')
       OR mirror_media.tip_vlozheniya<>'photo' THEN
        RAISE EXCEPTION
            'DB-03D1 narrow media mirror bytes failed: event=%',
            row_to_json(mirror_media);
    END IF;

    SELECT * INTO mirror_media_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_mirror_media_done',
            'sobytie_zerkala_id',mirror_media.sobytie_zerkala_id,
            'worker_id','mirror_worker_media',
            'nomer_vladeniya',mirror_media.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_message_id','db03d1_media_msg',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    -- Private event resolves target only from approved manager record.
    INSERT INTO qbit_test.sobytiya_zerkala_operatora (
        dialog_id,
        tip_sobytiya,
        klyuch_idempotentnosti,
        prioritet,
        cel_menedzher_id,
        tekst,
        payload,
        status
    )
    VALUES (
        rin.dialog_id,
        'lichnoe_uvedomlenie',
        'db03d1_private_probe',
        80,
        v_manager1,
        'Нужен менеджер',
        jsonb_build_object('probe',true),
        'zaplanirovano'
    );

    SELECT * INTO mirror_private
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_private_claim',
            'worker_id','mirror_worker_private',
            'arenda_sekund',120
        )
      );

    IF mirror_private.rezultat<>'uspeshno'
       OR mirror_private.tip_sobytiya<>'lichnoe_uvedomlenie'
       OR mirror_private.cel_chat_id<>'db03d1_private_1'
       OR mirror_private.cel_thread_id IS NOT NULL
       OR mirror_private.cel_menedzher_id IS DISTINCT FROM v_manager1 THEN
        RAISE EXCEPTION
            'DB-03D1 trusted private target resolution failed: %',
            row_to_json(mirror_private);
    END IF;

    SELECT * INTO mirror_private_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_private_done',
            'sobytie_zerkala_id',mirror_private.sobytie_zerkala_id,
            'worker_id','mirror_worker_private',
            'nomer_vladeniya',mirror_private.nomer_vladeniya,
            'status','podtverzhdeno',
            'vneshniy_message_id','db03d1_private_msg',
            'vremya_podtverzhdeniya',clock_timestamp()
        )
      );

    -- Retry may be reclaimed later; unknown is terminal for blind retry.
    INSERT INTO qbit_test.sobytiya_zerkala_operatora (
        dialog_id,
        tip_sobytiya,
        klyuch_idempotentnosti,
        prioritet,
        cel_chat_id,
        cel_thread_id,
        payload,
        status
    )
    VALUES (
        rin.dialog_id,
        'obnovit_kartochku',
        'db03d1_retry_unknown_probe',
        70,
        'db03d1_service_group',
        'db03d1_thread_1',
        jsonb_build_object('rezhim','update'),
        'zaplanirovano'
    );

    SELECT * INTO mirror_retry1
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_retry_claim_1',
            'worker_id','mirror_worker_retry_1',
            'arenda_sekund',120
        )
      );

    SELECT * INTO mirror_retry_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_retry_result',
            'sobytie_zerkala_id',mirror_retry1.sobytie_zerkala_id,
            'worker_id','mirror_worker_retry_1',
            'nomer_vladeniya',mirror_retry1.nomer_vladeniya,
            'status','povtor',
            'povtor_posle',clock_timestamp()+interval '10 minutes',
            'kod_oshibki','temporary_probe'
        )
      );

    UPDATE qbit_test.sobytiya_zerkala_operatora AS e_due
       SET sleduyushchiy_zapusk=clock_timestamp()-interval '1 second'
     WHERE e_due.id=mirror_retry1.sobytie_zerkala_id;

    SELECT * INTO mirror_retry2
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_retry_claim_2',
            'worker_id','mirror_worker_retry_2',
            'arenda_sekund',120,
            'sobytie_zerkala_id',mirror_retry1.sobytie_zerkala_id
        )
      );

    SELECT * INTO mirror_unknown_done
      FROM qbit_test.zafiksirovat_rezultat_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_unknown_result',
            'sobytie_zerkala_id',mirror_retry2.sobytie_zerkala_id,
            'worker_id','mirror_worker_retry_2',
            'nomer_vladeniya',mirror_retry2.nomer_vladeniya,
            'status','neizvestno',
            'kod_oshibki','telegram_ambiguous_probe'
        )
      );

    SELECT * INTO mirror_unknown_claim
      FROM qbit_test.zabrat_sobytie_zerkala(
        jsonb_build_object(
            'operaciya_id','db03d1_unknown_reclaim_attempt',
            'worker_id','mirror_worker_retry_3',
            'arenda_sekund',120,
            'sobytie_zerkala_id',mirror_retry2.sobytie_zerkala_id
        )
      );

    IF mirror_retry_done.rezultat<>'uspeshno'
       OR mirror_retry2.rezultat<>'uspeshno'
       OR mirror_retry2.nomer_vladeniya<>mirror_retry1.nomer_vladeniya+1
       OR mirror_unknown_done.rezultat<>'uspeshno'
       OR mirror_unknown_claim.rezultat<>'neizvestno' THEN
        RAISE EXCEPTION
            'DB-03D1 mirror retry/unknown terminal semantics failed: retry1=%, retry2=%, unknown=%, reclaim=%',
            row_to_json(mirror_retry_done),row_to_json(mirror_retry2),
            row_to_json(mirror_unknown_done),row_to_json(mirror_unknown_claim);
    END IF;

    -- Separate synthetic dialog proves ambiguous createForumTopic is terminal.
    INSERT INTO qbit_test.dialogi (
        polzovatel_id,
        identifikator_kanala_id,
        predydushchiy_dialog_id,
        vremya_nachala,
        etap,
        status,
        versiya_dialoga,
        ozhidaetsya_otvet,
        pokolenie_ozhidaniya,
        vladelec,
        versiya_workflow,
        versiya_prompta
    )
    SELECT
        d.polzovatel_id,
        d.identifikator_kanala_id,
        d.id,
        clock_timestamp(),
        'pervichnyy_kontakt',
        'aktivnyy',
        1,
        false,
        0,
        'bot',
        'db03d1_probe',
        'db03d1_probe'
      FROM qbit_test.dialogi AS d
     WHERE d.id=rin.dialog_id
    RETURNING dialogi.id INTO v_unknown_dialog;

    INSERT INTO qbit_test.operator_telegram_temy (
        dialog_id,
        sluzhebnyy_chat_id,
        status
    )
    VALUES (
        v_unknown_dialog,
        'db03d1_service_group',
        'nuzhno_sozdat'
    );

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
        v_unknown_dialog,
        'obespechit_temu',
        'tema:'||v_unknown_dialog::text,
        100,
        'db03d1_service_group',
        'Клиент D1 unknown',
        jsonb_build_object('dialog_id',v_unknown_dialog),
        'zaplanirovano'
    );

    SELECT * INTO topic_unknown_claim
      FROM qbit_test.zabrat_sozdanie_operator_temy(
        jsonb_build_object(
            'operaciya_id','db03d1_topic_unknown_create',
            'worker_id','topic_worker_unknown',
            'dialog_id',v_unknown_dialog,
            'arenda_sekund',120
        )
      );

    SELECT * INTO topic_unknown_done
      FROM qbit_test.otmetit_temu_neizvestnoy(
        jsonb_build_object(
            'operaciya_sozdaniya_id',topic_unknown_claim.operaciya_sozdaniya_id,
            'dialog_id',v_unknown_dialog,
            'worker_id','topic_worker_unknown',
            'nomer_vladeniya',topic_unknown_claim.nomer_vladeniya,
            'kod_oshibki','probe_ambiguous'
        )
      );

    SELECT * INTO topic_unknown_again
      FROM qbit_test.zabrat_sozdanie_operator_temy(
        jsonb_build_object(
            'operaciya_id','db03d1_topic_unknown_retry',
            'worker_id','topic_worker_unknown_2',
            'dialog_id',v_unknown_dialog,
            'arenda_sekund',120
        )
      );

    IF topic_unknown_claim.rezultat<>'uspeshno'
       OR topic_unknown_done.rezultat<>'uspeshno'
       OR topic_unknown_again.rezultat<>'neizvestno'
       OR NOT EXISTS (
            SELECT 1
              FROM qbit_test.sistemnye_sobytiya AS se
             WHERE se.klyuch_gruppirovki='topic_unknown:'||v_unknown_dialog::text
               AND se.kod='create_forum_topic_neizvestno'
       ) THEN
        RAISE EXCEPTION
            'DB-03D1 topic unknown/no-blind-recreate failed: claim=%, unknown=%, again=%',
            row_to_json(topic_unknown_claim),row_to_json(topic_unknown_done),
            row_to_json(topic_unknown_again);
    END IF;
END
$db03d1$;

ROLLBACK TO SAVEPOINT db03d1_probe;
RELEASE SAVEPOINT db03d1_probe;

-- ===========================================================================
-- 11. POST-PROBE SECURITY / CLEANUP ASSERTIONS
-- ===========================================================================

DO $db03d1$
DECLARE
    v_table record;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_test.menedzhery_telegram AS m
         WHERE m.telegram_user_id LIKE 'db03d1_manager_%'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_test.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id='db03d1_service_bot'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id='db03d1_client_bot'
    ) THEN
        RAISE EXCEPTION 'DB-03D1 probe rows remain after rollback';
    END IF;

    FOR v_table IN
        SELECT c.oid,c.relname
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_test'
           AND c.relkind='r'
    LOOP
        IF pg_catalog.has_table_privilege(
            'qbit_test_sluzhebnyy',v_table.oid,'SELECT'
        )
        OR pg_catalog.has_table_privilege(
            'qbit_test_sluzhebnyy',v_table.oid,'INSERT'
        )
        OR pg_catalog.has_table_privilege(
            'qbit_test_sluzhebnyy',v_table.oid,'UPDATE'
        )
        OR pg_catalog.has_table_privilege(
            'qbit_test_sluzhebnyy',v_table.oid,'DELETE'
        ) THEN
            RAISE EXCEPTION
                'Service role unexpectedly has direct table privilege on qbit_test.%',
                v_table.relname;
        END IF;
    END LOOP;
END
$db03d1$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 12. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03d1_status','applied',
    'database',current_database(),
    'schema','qbit_test',
    'functions_ok',
    (
        SELECT count(*)=7
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
         WHERE n.nspname='qbit_test'
           AND p.proname IN (
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy'
           )
           AND p.prosecdef=true
    ),
    'service_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.zaregistrirovat_sluzhebnoe_sobytie(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.zabrat_sobytie_zerkala(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.zabrat_sozdanie_operator_temy(jsonb)',
        'EXECUTE'
    ),
    'bot_service_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.zaregistrirovat_sluzhebnoe_sobytie(jsonb)',
        'EXECUTE'
    ),
    'service_raw_select_denied',
    NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
         WHERE n.nspname='qbit_test'
           AND c.relkind='r'
           AND pg_catalog.has_table_privilege(
                'qbit_test_sluzhebnyy',c.oid,'SELECT'
           )
    ),
    'topic_unique_mapping_ok',
    pg_catalog.to_regclass('qbit_test.uq_operator_tema_chat_thread') IS NOT NULL,
    'mirror_unique_key_ok',
    pg_catalog.to_regclass('qbit_test.uq_zerkalo_klyuch') IS NOT NULL,
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_test.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id='db03d1_service_bot'
    ),
    'result',
    'DB-03D1 SQL APPLIED: service ingress/private-chat/topic claim-confirm-unknown/mirror narrow payload+media/retry-unknown verified; service raw SELECT denied; probe data removed; production untouched.'
) AS db03d1_result;
