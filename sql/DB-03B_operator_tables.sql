-- DB-03B v0.1: operator Telegram tables and current-manager FK
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02 and DB-03A successfully applied.
--
-- CREATES 3 TABLES
--   menedzhery_telegram
--   operator_telegram_temy
--   sobytiya_zerkala_operatora
--
-- ALSO ADDS
--   dialogi.tekushchiy_menedzher_id -> menedzhery_telegram(id)
--
-- NOT INCLUDED
--   Take/Return/manual outgoing/private alert functions: DB-03D.
--   Client/queue/outgoing functions: DB-03C.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * kompaniya_001_test remains an isolation canary.
--   * Runtime roles receive no direct table DML.
--   * Probe rows are rolled back to a SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03B migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03b$
DECLARE
    v_required text;
    v_new_table text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03B requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03B must run from trusted postgres session. session_user=%',
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
         WHERE n.nspname = 'qbit_test'
    ) IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'qbit_test is not owned by qbit_test_owner';
    END IF;

    FOREACH v_required IN ARRAY ARRAY[
        'polzovateli',
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'vlozheniya_soobshcheniy',
        'sobytiya_integraciy',
        'zadaniya_obrabotki',
        'ishodyashchie_deystviya',
        'napominaniya',
        'pamyat_dialoga'
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
            'DB-03A integration FK is missing';
    END IF;

    FOREACH v_new_table IN ARRAY ARRAY[
        'menedzhery_telegram',
        'operator_telegram_temy',
        'sobytiya_zerkala_operatora'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_test.%I', v_new_table)
        ) IS NOT NULL THEN
            RAISE EXCEPTION
                'DB-03B object qbit_test.% already exists; stop instead of overwriting',
                v_new_table;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND rel.relname = 'dialogi'
           AND con.conname = 'fk_dialogi_tekushchiy_menedzher'
    ) THEN
        RAISE EXCEPTION
            'Forward FK fk_dialogi_tekushchiy_menedzher already exists';
    END IF;
END
$db03b$;

-- ===========================================================================
-- 1. CREATE OPERATOR TABLES
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_test.menedzhery_telegram (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    telegram_user_id text NOT NULL,
    private_chat_id text,
    private_chat_podtverzhden boolean NOT NULL DEFAULT false,
    vremya_podtverzhdeniya timestamptz,
    otobrazhaemoe_imya text NOT NULL,
    aktiven boolean NOT NULL DEFAULT true,
    mozhet_zabirat boolean NOT NULL DEFAULT true,
    mozhet_vozvrashchat boolean NOT NULL DEFAULT true,
    lichnye_uvedomleniya boolean NOT NULL DEFAULT true,
    prioritet_naznacheniya integer NOT NULL DEFAULT 100,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_menedzhery_tg_user
        CHECK (btrim(telegram_user_id) <> ''),
    CONSTRAINT ck_menedzhery_imya
        CHECK (btrim(otobrazhaemoe_imya) <> ''),
    CONSTRAINT ck_menedzhery_private_chat
        CHECK (
            (
                private_chat_podtverzhden = false
                AND private_chat_id IS NULL
                AND vremya_podtverzhdeniya IS NULL
            )
            OR
            (
                private_chat_podtverzhden = true
                AND private_chat_id IS NOT NULL
                AND btrim(private_chat_id) <> ''
                AND vremya_podtverzhdeniya IS NOT NULL
            )
        ),
    CONSTRAINT ck_menedzhery_prioritet
        CHECK (prioritet_naznacheniya >= 0)
);

CREATE UNIQUE INDEX uq_menedzhery_tg_user
    ON qbit_test.menedzhery_telegram (telegram_user_id);

CREATE UNIQUE INDEX uq_menedzhery_private_chat
    ON qbit_test.menedzhery_telegram (private_chat_id)
    WHERE private_chat_id IS NOT NULL;

CREATE INDEX ix_menedzhery_aktivnye
    ON qbit_test.menedzhery_telegram (
        prioritet_naznacheniya,
        id
    )
    WHERE aktiven = true;


CREATE TABLE qbit_test.operator_telegram_temy (
    dialog_id uuid PRIMARY KEY
        REFERENCES qbit_test.dialogi(id),
    sluzhebnyy_chat_id text NOT NULL,
    message_thread_id text,
    vneshniy_id_kartochki text,
    status text NOT NULL DEFAULT 'nuzhno_sozdat',
    operaciya_sozdaniya_id text,
    popytki integer NOT NULL DEFAULT 0,
    sleduyushchiy_zapusk timestamptz NOT NULL DEFAULT clock_timestamp(),
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_podtverzhdeniya timestamptz,
    vremya_posledney_sinhronizacii timestamptz,
    kod_oshibki text,
    opisanie_oshibki text,

    CONSTRAINT ck_operator_tema_chat
        CHECK (btrim(sluzhebnyy_chat_id) <> ''),
    CONSTRAINT ck_operator_tema_thread
        CHECK (
            message_thread_id IS NULL
            OR btrim(message_thread_id) <> ''
        ),
    CONSTRAINT ck_operator_tema_kartochka
        CHECK (
            vneshniy_id_kartochki IS NULL
            OR btrim(vneshniy_id_kartochki) <> ''
        ),
    CONSTRAINT ck_operator_tema_status
        CHECK (
            status IN (
                'nuzhno_sozdat',
                'sozdaetsya',
                'gotova',
                'neizvestno',
                'oshibka',
                'zakryta'
            )
        ),
    CONSTRAINT ck_operator_tema_operaciya
        CHECK (
            operaciya_sozdaniya_id IS NULL
            OR btrim(operaciya_sozdaniya_id) <> ''
        ),
    CONSTRAINT ck_operator_tema_popytki
        CHECK (popytki >= 0),
    CONSTRAINT ck_operator_tema_nomer_vladeniya
        CHECK (nomer_vladeniya >= 0),
    CONSTRAINT ck_operator_tema_arenda
        CHECK (
            status <> 'sozdaetsya'
            OR (
                operaciya_sozdaniya_id IS NOT NULL
                AND vladelec_arendy IS NOT NULL
                AND btrim(vladelec_arendy) <> ''
                AND arenda_do IS NOT NULL
            )
        ),
    CONSTRAINT ck_operator_tema_gotova
        CHECK (
            status NOT IN ('gotova', 'zakryta')
            OR (
                message_thread_id IS NOT NULL
                AND vremya_podtverzhdeniya IS NOT NULL
            )
        ),
    CONSTRAINT ck_operator_tema_neizvestno
        CHECK (
            status <> 'neizvestno'
            OR operaciya_sozdaniya_id IS NOT NULL
        )
);

CREATE UNIQUE INDEX uq_operator_tema_chat_thread
    ON qbit_test.operator_telegram_temy (
        sluzhebnyy_chat_id,
        message_thread_id
    )
    WHERE message_thread_id IS NOT NULL;

CREATE INDEX ix_operator_tema_status
    ON qbit_test.operator_telegram_temy (
        status,
        sleduyushchiy_zapusk
    );

CREATE INDEX ix_operator_tema_arenda
    ON qbit_test.operator_telegram_temy (arenda_do)
    WHERE status = 'sozdaetsya';


CREATE TABLE qbit_test.sobytiya_zerkala_operatora (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_test.dialogi(id),
    soobshchenie_id uuid
        REFERENCES qbit_test.soobshcheniya(id),
    vlozhenie_id uuid
        REFERENCES qbit_test.vlozheniya_soobshcheniy(id),
    tip_sobytiya text NOT NULL,
    klyuch_idempotentnosti text NOT NULL,
    prioritet integer NOT NULL DEFAULT 0,
    cel_chat_id text,
    cel_thread_id text,
    cel_menedzher_id uuid
        REFERENCES qbit_test.menedzhery_telegram(id),
    bezopasnaya_podpis_klienta text,
    tekst text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'zaplanirovano',
    popytki integer NOT NULL DEFAULT 0,
    sleduyushchiy_zapusk timestamptz NOT NULL DEFAULT clock_timestamp(),
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    vneshniy_message_id text,
    vremya_podtverzhdeniya timestamptz,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_zerkalo_tip
        CHECK (
            tip_sobytiya IN (
                'obespechit_temu',
                'soobshchenie_klienta',
                'otvet_bota',
                'media_klienta',
                'nuzhen_chelovek',
                'zabran',
                'vozvrashchen',
                'lichnoe_uvedomlenie',
                'obnovit_kartochku'
            )
        ),
    CONSTRAINT ck_zerkalo_klyuch
        CHECK (btrim(klyuch_idempotentnosti) <> ''),
    CONSTRAINT ck_zerkalo_cel_chat
        CHECK (
            cel_chat_id IS NULL
            OR btrim(cel_chat_id) <> ''
        ),
    CONSTRAINT ck_zerkalo_cel_thread
        CHECK (
            cel_thread_id IS NULL
            OR btrim(cel_thread_id) <> ''
        ),
    CONSTRAINT ck_zerkalo_payload
        CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT ck_zerkalo_status
        CHECK (
            status IN (
                'zaplanirovano',
                'v_rabote',
                'podtverzhdeno',
                'povtor',
                'neizvestno',
                'otmeneno',
                'oshibka'
            )
        ),
    CONSTRAINT ck_zerkalo_popytki
        CHECK (popytki >= 0),
    CONSTRAINT ck_zerkalo_nomer_vladeniya
        CHECK (nomer_vladeniya >= 0),
    CONSTRAINT ck_zerkalo_arenda
        CHECK (
            status <> 'v_rabote'
            OR (
                vladelec_arendy IS NOT NULL
                AND btrim(vladelec_arendy) <> ''
                AND arenda_do IS NOT NULL
            )
        ),
    CONSTRAINT ck_zerkalo_klient_text
        CHECK (
            tip_sobytiya <> 'soobshchenie_klienta'
            OR soobshchenie_id IS NOT NULL
        ),
    CONSTRAINT ck_zerkalo_bot_text
        CHECK (
            tip_sobytiya <> 'otvet_bota'
            OR soobshchenie_id IS NOT NULL
        ),
    CONSTRAINT ck_zerkalo_media
        CHECK (
            tip_sobytiya <> 'media_klienta'
            OR (
                soobshchenie_id IS NOT NULL
                AND vlozhenie_id IS NOT NULL
            )
        ),
    CONSTRAINT ck_zerkalo_lichnoe
        CHECK (
            tip_sobytiya <> 'lichnoe_uvedomlenie'
            OR cel_menedzher_id IS NOT NULL
        )
);

CREATE UNIQUE INDEX uq_zerkalo_klyuch
    ON qbit_test.sobytiya_zerkala_operatora (klyuch_idempotentnosti);

CREATE INDEX ix_zerkalo_gotovy
    ON qbit_test.sobytiya_zerkala_operatora (
        prioritet DESC,
        sleduyushchiy_zapusk,
        vremya_sozdaniya
    )
    WHERE status IN ('zaplanirovano', 'povtor');

CREATE INDEX ix_zerkalo_dialog
    ON qbit_test.sobytiya_zerkala_operatora (
        dialog_id,
        vremya_sozdaniya
    );

CREATE INDEX ix_zerkalo_arenda
    ON qbit_test.sobytiya_zerkala_operatora (arenda_do)
    WHERE status = 'v_rabote';

-- Complete the second DB-02 forward reference.
ALTER TABLE qbit_test.dialogi
    ADD CONSTRAINT fk_dialogi_tekushchiy_menedzher
    FOREIGN KEY (tekushchiy_menedzher_id)
    REFERENCES qbit_test.menedzhery_telegram(id);

-- ===========================================================================
-- 2. COMMENTS
-- ===========================================================================

COMMENT ON TABLE qbit_test.menedzhery_telegram IS
'Разрешённые менеджеры служебного Telegram с подтверждённым private chat и правами Take/Return.';

COMMENT ON TABLE qbit_test.operator_telegram_temy IS
'Долговечная связь одного клиентского диалога с одной темой закрытой служебной Telegram forum-группы.';

COMMENT ON TABLE qbit_test.sobytiya_zerkala_operatora IS
'Долговечная очередь зеркала и операторских уведомлений со стабильным ключом, lease и внешним message ID.';

COMMENT ON COLUMN qbit_test.menedzhery_telegram.id IS 'Внутренний UUID менеджера.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.telegram_user_id IS 'Разрешённый Telegram user ID менеджера; не берётся из клиентского текста.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.private_chat_id IS 'Private chat ID со служебным ботом после подтверждённого /start.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.private_chat_podtverzhden IS 'Подтверждён ли private chat служебным webhook.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.vremya_podtverzhdeniya IS 'Время подтверждения private chat.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.otobrazhaemoe_imya IS 'Безопасное отображаемое имя менеджера.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.aktiven IS 'Можно ли использовать менеджера в текущей конфигурации.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.mozhet_zabirat IS 'Разрешено ли менеджеру атомарно забирать диалог.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.mozhet_vozvrashchat IS 'Разрешено ли менеджеру явно возвращать диалог боту.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.lichnye_uvedomleniya IS 'Разрешены ли личные служебные уведомления этому менеджеру.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.prioritet_naznacheniya IS 'Меньшее значение означает более высокий приоритет назначения.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.vremya_sozdaniya IS 'Время создания записи менеджера.';
COMMENT ON COLUMN qbit_test.menedzhery_telegram.vremya_obnovleniya IS 'Время последнего изменения записи менеджера.';

COMMENT ON COLUMN qbit_test.operator_telegram_temy.dialog_id IS 'Диалог; одновременно PK и FK, поэтому один диалог имеет максимум одну операторскую тему.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.sluzhebnyy_chat_id IS 'Доверенный ID закрытой служебной forum-группы.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.message_thread_id IS 'Telegram message_thread_id подтверждённо созданной темы.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.vneshniy_id_kartochki IS 'Telegram message ID карточки темы при наличии.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.status IS 'nuzhno_sozdat, sozdaetsya, gotova, neizvestno, oshibka или zakryta.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.operaciya_sozdaniya_id IS 'Стабильный ID конкретной попытки создания forum topic.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.popytki IS 'Количество начатых попыток создания/сверки темы.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.sleduyushchiy_zapusk IS 'Не обрабатывать тему раньше этого времени.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.vladelec_arendy IS 'Worker, владеющий текущей арендой создания/сверки.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.arenda_do IS 'Срок текущей аренды.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.nomer_vladeniya IS 'Fencing номер владения для stale-worker защиты.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.vremya_sozdaniya IS 'Время создания intent-записи темы.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.vremya_podtverzhdeniya IS 'Время подтверждения реального message_thread_id.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.vremya_posledney_sinhronizacii IS 'Время последней надёжной сверки состояния темы.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.kod_oshibki IS 'Безопасный код ошибки.';
COMMENT ON COLUMN qbit_test.operator_telegram_temy.opisanie_oshibki IS 'Безопасное описание ошибки без токенов/секретов.';

COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.id IS 'UUID события операторского зеркала.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.dialog_id IS 'Клиентский диалог события.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.soobshchenie_id IS 'Логическое сообщение при зеркалировании текста/медиа.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vlozhenie_id IS 'Локально сохранённое вложение для media_klienta.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.tip_sobytiya IS 'Тип: тема, client/bot text, media, handoff, Take/Return, private alert или карточка.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.klyuch_idempotentnosti IS 'Стабильный ключ, не допускающий повтор одного зеркального действия.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.prioritet IS 'Приоритет обработки; handoff/private alert может иметь повышенное значение.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.cel_chat_id IS 'Доверенный целевой chat ID при групповой/личной отправке.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.cel_thread_id IS 'Целевой message_thread_id темы при наличии.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.cel_menedzher_id IS 'Разрешённый менеджер для личного уведомления.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.bezopasnaya_podpis_klienta IS 'Безопасная подпись клиента для операторского интерфейса.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.tekst IS 'Текст зеркального/служебного сообщения, разрешённый для конкретного event.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.payload IS 'Узкий безопасный JSON payload события.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.status IS 'zaplanirovano, v_rabote, podtverzhdeno, povtor, neizvestno, otmeneno или oshibka.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.popytki IS 'Количество начатых попыток обработки.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.sleduyushchiy_zapusk IS 'Не обрабатывать раньше этого времени.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vladelec_arendy IS 'Worker-владелец аренды.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.arenda_do IS 'Срок текущей аренды.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.nomer_vladeniya IS 'Fencing номер владения.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vneshniy_message_id IS 'Подтверждённый Telegram message ID зеркальной отправки.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vremya_podtverzhdeniya IS 'Время подтверждения Telegram-результата.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.kod_oshibki IS 'Безопасный код ошибки.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.opisanie_oshibki IS 'Безопасное описание ошибки.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vremya_sozdaniya IS 'Время создания события зеркала.';
COMMENT ON COLUMN qbit_test.sobytiya_zerkala_operatora.vremya_obnovleniya IS 'Время последнего изменения события зеркала.';

COMMENT ON CONSTRAINT fk_dialogi_tekushchiy_menedzher
    ON qbit_test.dialogi IS
'DB-03B: при vladelec=chelovek текущий UUID обязан ссылаться на разрешённого Telegram-менеджера.';

-- ===========================================================================
-- 3. ACCESS: DEFAULT-DENY
-- ===========================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA qbit_test FROM PUBLIC;

DO $db03b$
DECLARE
    v_role text;
BEGIN
    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_read',
        'qbit_test_dash_admin'
    ]
    LOOP
        EXECUTE pg_catalog.format(
            'REVOKE ALL ON ALL TABLES IN SCHEMA qbit_test FROM %I',
            v_role
        );
    END LOOP;
END
$db03b$;

-- ===========================================================================
-- 4. STATIC ASSERTIONS
-- ===========================================================================

DO $db03b$
DECLARE
    v_table_count integer;
    v_index_count integer;
BEGIN
    SELECT count(*)
      INTO v_table_count
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
     WHERE n.nspname = 'qbit_test'
       AND c.relkind = 'r'
       AND c.relname IN (
            'menedzhery_telegram',
            'operator_telegram_temy',
            'sobytiya_zerkala_operatora'
       );

    IF v_table_count <> 3 THEN
        RAISE EXCEPTION
            'DB-03B expected 3 tables, found %',
            v_table_count;
    END IF;

    SELECT count(*)
      INTO v_index_count
      FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = i.relnamespace
     WHERE n.nspname = 'qbit_test'
       AND i.relkind = 'i'
       AND i.relname IN (
            'uq_menedzhery_tg_user',
            'uq_menedzhery_private_chat',
            'ix_menedzhery_aktivnye',
            'uq_operator_tema_chat_thread',
            'ix_operator_tema_status',
            'ix_operator_tema_arenda',
            'uq_zerkalo_klyuch',
            'ix_zerkalo_gotovy',
            'ix_zerkalo_dialog',
            'ix_zerkalo_arenda'
       );

    IF v_index_count <> 10 THEN
        RAISE EXCEPTION
            'DB-03B expected 10 contract indexes, found %',
            v_index_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND rel.relname = 'dialogi'
           AND con.conname = 'fk_dialogi_tekushchiy_menedzher'
           AND con.contype = 'f'
           AND con.convalidated = true
    ) THEN
        RAISE EXCEPTION
            'DB-03B current-manager FK is missing or not validated';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
           AND pg_catalog.obj_description(c.oid, 'pg_class') IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-03B found a table without COMMENT';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
          JOIN pg_catalog.pg_attribute AS a
            ON a.attrelid = c.oid
           AND a.attnum > 0
           AND a.attisdropped = false
         WHERE n.nspname = 'qbit_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
           AND pg_catalog.col_description(c.oid, a.attnum) IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-03B found a column without COMMENT';
    END IF;
END
$db03b$;

-- ===========================================================================
-- 5. DISPOSABLE DATA PROBE
-- ===========================================================================

SAVEPOINT db03b_probe;

INSERT INTO qbit_test.menedzhery_telegram (
    id,
    telegram_user_id,
    private_chat_id,
    private_chat_podtverzhden,
    vremya_podtverzhdeniya,
    otobrazhaemoe_imya,
    aktiven,
    mozhet_zabirat,
    mozhet_vozvrashchat,
    lichnye_uvedomleniya,
    prioritet_naznacheniya
)
VALUES (
    '00000000-0000-4000-8000-000000000321',
    'db03b_manager_1',
    'db03b_private_1',
    true,
    '2026-09-24 16:00:00+00',
    'Менеджер DB-03B',
    true,
    true,
    true,
    true,
    10
);

INSERT INTO qbit_test.polzovateli (
    id,
    vremya_pervogo_obrashcheniya,
    vremya_poslednego_obrashcheniya,
    pervyy_kanal,
    testovyy
)
VALUES (
    '00000000-0000-4000-8000-000000000322',
    '2026-09-24 16:00:00+00',
    '2026-09-24 16:00:00+00',
    'telegram',
    true
);

INSERT INTO qbit_test.identifikatory_kanalov (
    id,
    polzovatel_id,
    kanal,
    akkaunt_kanala_id,
    vneshniy_polzovatel_id,
    vneshniy_dialog_id
)
VALUES (
    '00000000-0000-4000-8000-000000000323',
    '00000000-0000-4000-8000-000000000322',
    'telegram',
    'db03b_client_bot',
    'db03b_user_1',
    'db03b_chat_1'
);

INSERT INTO qbit_test.dialogi (
    id,
    polzovatel_id,
    identifikator_kanala_id,
    vremya_nachala,
    etap,
    status,
    versiya_workflow,
    versiya_prompta
)
VALUES (
    '00000000-0000-4000-8000-000000000324',
    '00000000-0000-4000-8000-000000000322',
    '00000000-0000-4000-8000-000000000323',
    '2026-09-24 16:00:00+00',
    'pervichnyy_kontakt',
    'aktivnyy',
    'db03b_probe',
    'db03b_probe'
);

INSERT INTO qbit_test.dialogi (
    id,
    polzovatel_id,
    identifikator_kanala_id,
    vremya_nachala,
    etap,
    status,
    versiya_workflow,
    versiya_prompta
)
VALUES (
    '00000000-0000-4000-8000-000000000327',
    '00000000-0000-4000-8000-000000000322',
    '00000000-0000-4000-8000-000000000323',
    '2026-09-24 16:00:30+00',
    'pervichnyy_kontakt',
    'aktivnyy',
    'db03b_probe',
    'db03b_probe'
);

INSERT INTO qbit_test.soobshcheniya (
    id,
    dialog_id,
    napravlenie,
    avtor,
    vid,
    tekst_ishodnyy,
    tekst_obezlichennyy,
    vneshnee_soobshchenie_id,
    vremya_priema
)
VALUES (
    '00000000-0000-4000-8000-000000000325',
    '00000000-0000-4000-8000-000000000324',
    'vhodyashchee',
    'klient',
    'text',
    'DB-03B test input',
    'DB-03B test input',
    'db03b_message_1',
    '2026-09-24 16:00:01+00'
);

INSERT INTO qbit_test.operator_telegram_temy (
    dialog_id,
    sluzhebnyy_chat_id,
    message_thread_id,
    vneshniy_id_kartochki,
    status,
    operaciya_sozdaniya_id,
    popytki,
    vremya_podtverzhdeniya,
    vremya_posledney_sinhronizacii
)
VALUES (
    '00000000-0000-4000-8000-000000000324',
    'db03b_service_group',
    'db03b_thread_1',
    'db03b_card_1',
    'gotova',
    'db03b_topic_operation_1',
    1,
    '2026-09-24 16:00:02+00',
    '2026-09-24 16:00:02+00'
);

INSERT INTO qbit_test.sobytiya_zerkala_operatora (
    id,
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
    '00000000-0000-4000-8000-000000000326',
    '00000000-0000-4000-8000-000000000324',
    '00000000-0000-4000-8000-000000000325',
    'soobshchenie_klienta',
    'db03b_mirror_1',
    10,
    'db03b_service_group',
    'db03b_thread_1',
    'Клиент DB-03B',
    'DB-03B test input',
    '{"probe":true}'::jsonb,
    'zaplanirovano'
);

-- Valid handoff reference: DB CHECK + new FK must both pass.
UPDATE qbit_test.dialogi
   SET vladelec = 'chelovek',
       tekushchiy_menedzher_id = '00000000-0000-4000-8000-000000000321',
       status = 'peredan_cheloveku',
       versiya_dialoga = versiya_dialoga + 1
 WHERE id = '00000000-0000-4000-8000-000000000324';

DO $db03b$
BEGIN
    -- Telegram user ID is unique.
    BEGIN
        INSERT INTO qbit_test.menedzhery_telegram (
            telegram_user_id,
            otobrazhaemoe_imya
        )
        VALUES (
            'db03b_manager_1',
            'Дубликат'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: duplicate Telegram manager user was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Confirmed private chat must be coherent.
    BEGIN
        INSERT INTO qbit_test.menedzhery_telegram (
            telegram_user_id,
            private_chat_podtverzhden,
            otobrazhaemoe_imya
        )
        VALUES (
            'db03b_manager_bad_private',
            true,
            'Bad private'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: confirmed private chat without ID/time was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- Private chat belongs to one allowed manager.
    BEGIN
        INSERT INTO qbit_test.menedzhery_telegram (
            telegram_user_id,
            private_chat_id,
            private_chat_podtverzhden,
            vremya_podtverzhdeniya,
            otobrazhaemoe_imya
        )
        VALUES (
            'db03b_manager_2',
            'db03b_private_1',
            true,
            '2026-09-24 16:01:00+00',
            'Manager 2'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: duplicate private chat was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- A human-owned dialog cannot point to an unknown manager.
    BEGIN
        UPDATE qbit_test.dialogi
           SET tekushchiy_menedzher_id =
               '00000000-0000-4000-8000-000000009999'
         WHERE id =
               '00000000-0000-4000-8000-000000000324';

        RAISE EXCEPTION
            'DB-03B probe failed: unknown manager UUID was accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN NULL;
    END;

    -- A ready topic requires a confirmed thread ID/time.
    BEGIN
        INSERT INTO qbit_test.operator_telegram_temy (
            dialog_id,
            sluzhebnyy_chat_id,
            status
        )
        VALUES (
            '00000000-0000-4000-8000-000000000327',
            'db03b_service_group',
            'gotova'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: ready topic without thread/time was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- The same service chat + thread cannot belong to a second dialog.
    BEGIN
        INSERT INTO qbit_test.operator_telegram_temy (
            dialog_id,
            sluzhebnyy_chat_id,
            message_thread_id,
            status,
            operaciya_sozdaniya_id,
            vremya_podtverzhdeniya
        )
        VALUES (
            '00000000-0000-4000-8000-000000000327',
            'db03b_service_group',
            'db03b_thread_1',
            'gotova',
            'db03b_topic_operation_2',
            '2026-09-24 16:02:00+00'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: duplicate service chat/thread was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Mirror stable key is unique.
    BEGIN
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
            dialog_id,
            soobshchenie_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            status
        )
        VALUES (
            '00000000-0000-4000-8000-000000000324',
            '00000000-0000-4000-8000-000000000325',
            'soobshchenie_klienta',
            'db03b_mirror_1',
            'zaplanirovano'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: duplicate mirror key was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- v_rabote mirror requires a lease.
    BEGIN
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
            dialog_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            status
        )
        VALUES (
            '00000000-0000-4000-8000-000000000324',
            'nuzhen_chelovek',
            'db03b_bad_lease',
            'v_rabote'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: v_rabote mirror without lease was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- Media mirror requires both message and attachment.
    BEGIN
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
            dialog_id,
            soobshchenie_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            status
        )
        VALUES (
            '00000000-0000-4000-8000-000000000324',
            '00000000-0000-4000-8000-000000000325',
            'media_klienta',
            'db03b_bad_media',
            'zaplanirovano'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: media mirror without attachment was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- Private alert requires an allowed manager target.
    BEGIN
        INSERT INTO qbit_test.sobytiya_zerkala_operatora (
            dialog_id,
            tip_sobytiya,
            klyuch_idempotentnosti,
            status
        )
        VALUES (
            '00000000-0000-4000-8000-000000000324',
            'lichnoe_uvedomlenie',
            'db03b_bad_private_alert',
            'zaplanirovano'
        );

        RAISE EXCEPTION
            'DB-03B probe failed: private alert without manager was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END
$db03b$;

DO $db03b$
DECLARE
    v_bad integer;
BEGIN
    SELECT count(*)
      INTO v_bad
      FROM (
            SELECT 'menedzhery_telegram' AS t, count(*) AS c
              FROM qbit_test.menedzhery_telegram
            UNION ALL
            SELECT 'operator_telegram_temy', count(*)
              FROM qbit_test.operator_telegram_temy
            UNION ALL
            SELECT 'sobytiya_zerkala_operatora', count(*)
              FROM qbit_test.sobytiya_zerkala_operatora
      ) AS x
     WHERE x.c <> 1;

    IF v_bad <> 0 THEN
        RAISE EXCEPTION
            'DB-03B probe expected one row in each new table; bad tables=%',
            v_bad;
    END IF;
END
$db03b$;

ROLLBACK TO SAVEPOINT db03b_probe;
RELEASE SAVEPOINT db03b_probe;

-- ===========================================================================
-- 6. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03b$
DECLARE
    v_role text;
    v_table record;
    v_owner text;
    v_probe_rows bigint;
BEGIN
    FOR v_table IN
        SELECT c.oid, c.relname
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
    LOOP
        SELECT r.rolname
          INTO v_owner
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = c.relowner
         WHERE c.oid = v_table.oid;

        IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
            RAISE EXCEPTION
                'DB-03B table qbit_test.% has wrong owner %',
                v_table.relname,
                v_owner;
        END IF;
    END LOOP;

    SELECT
          (SELECT count(*) FROM qbit_test.menedzhery_telegram)
        + (SELECT count(*) FROM qbit_test.operator_telegram_temy)
        + (SELECT count(*) FROM qbit_test.sobytiya_zerkala_operatora)
      INTO v_probe_rows;

    IF v_probe_rows <> 0 THEN
        RAISE EXCEPTION
            'DB-03B probe rows remain after SAVEPOINT rollback: %',
            v_probe_rows;
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_read',
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
               AND c.relname IN (
                    'menedzhery_telegram',
                    'operator_telegram_temy',
                    'sobytiya_zerkala_operatora'
               )
        LOOP
            IF pg_catalog.has_table_privilege(v_role, v_table.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % has direct DML on qbit_test.%',
                    v_role,
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'kompaniya_001_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
    ) THEN
        RAISE EXCEPTION
            'DB-03B unexpectedly created tables in kompaniya_001_test';
    END IF;
END
$db03b$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 7. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03b_status',
    'applied',
    'database',
    current_database(),
    'schema',
    'qbit_test',
    'owner',
    (
        SELECT r.rolname
          FROM pg_catalog.pg_namespace AS n
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = n.nspowner
         WHERE n.nspname = 'qbit_test'
    ),
    'tables_ok',
    (
        SELECT count(*) = 3
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
    ),
    'contract_indexes_ok',
    (
        SELECT count(*) = 10
          FROM pg_catalog.pg_class AS i
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = i.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND i.relkind = 'i'
           AND i.relname IN (
                'uq_menedzhery_tg_user',
                'uq_menedzhery_private_chat',
                'ix_menedzhery_aktivnye',
                'uq_operator_tema_chat_thread',
                'ix_operator_tema_status',
                'ix_operator_tema_arenda',
                'uq_zerkalo_klyuch',
                'ix_zerkalo_gotovy',
                'ix_zerkalo_dialog',
                'ix_zerkalo_arenda'
           )
    ),
    'manager_fk_ok',
    EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_test'
           AND rel.relname = 'dialogi'
           AND con.conname = 'fk_dialogi_tekushchiy_menedzher'
           AND con.contype = 'f'
           AND con.convalidated = true
    ),
    'probe_rows_remaining',
      (SELECT count(*) FROM qbit_test.menedzhery_telegram)
    + (SELECT count(*) FROM qbit_test.operator_telegram_temy)
    + (SELECT count(*) FROM qbit_test.sobytiya_zerkala_operatora),
    'runtime_direct_dml',
    false,
    'isolation_canary_untouched',
    NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'kompaniya_001_test'
           AND c.relkind = 'r'
           AND c.relname IN (
                'menedzhery_telegram',
                'operator_telegram_temy',
                'sobytiya_zerkala_operatora'
           )
    ),
    'functions_created',
    false,
    'result',
    'DB-03B SQL APPLIED: operator manager/topic/mirror tables and manager FK verified; probe data removed; production untouched.'
) AS db03b_result;
