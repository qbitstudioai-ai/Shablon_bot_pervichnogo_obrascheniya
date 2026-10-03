-- EVIDENCE ONLY / НЕ КАНОНИЧЕСКАЯ МИГРАЦИЯ.
-- Команды ниже были выполнены по частям в test 03.10.2026 и дали успешные проверки.
-- Они НЕ соответствуют полностью нормативному DB-04 и НЕ должны запускаться повторно.
-- Следовать docs/KB-01_RECONCILIATION_PLAN.md.

-- Bootstrap, подтверждён отдельно:
GRANT USAGE ON SCHEMA extensions TO qbit_test_owner;

SET ROLE qbit_test_owner;

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    kompaniya_kod text NOT NULL,
    sreda text NOT NULL,
    put_logicheskiy text NOT NULL,
    nazvanie text NOT NULL,
    aktivnaya_versiya_id uuid,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    CONSTRAINT znaniya_dokumenty_put_unique
        UNIQUE (kompaniya_kod, sreda, put_logicheskiy)
);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_versii (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    dokument_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty(id)
        ON DELETE CASCADE,
    nomer_versii integer NOT NULL,
    status text NOT NULL DEFAULT 'ozhidaet'
        CHECK (status IN ('ozhidaet','v_rabote','opublikovana','arhiv','oshibka')),
    klyuch_idempotentnosti text NOT NULL UNIQUE,
    telegram_update_id text,
    telegram_chat_id text NOT NULL,
    telegram_from_id text,
    telegram_file_id text NOT NULL,
    telegram_file_unique_id text,
    imya_fayla text NOT NULL,
    mime_type text,
    file_size bigint,
    model_embedding text NOT NULL,
    razmernost_embedding integer NOT NULL CHECK (razmernost_embedding = 1024),
    ozhidaemoe_fragmentov integer,
    kolichestvo_fragmentov integer,
    vladelec_arendy text,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    arenda_do timestamptz,
    popytki integer NOT NULL DEFAULT 0,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    vremya_nachala_obrabotki timestamptz,
    vremya_zaversheniya timestamptz,
    vremya_publikacii timestamptz,
    CONSTRAINT znaniya_versii_nomer_unique UNIQUE (dokument_id, nomer_versii)
);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    versiya_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.znaniya_versii(id)
        ON DELETE CASCADE,
    nomer_fragmenta integer NOT NULL CHECK (nomer_fragmenta > 0),
    put_razdela text NOT NULL DEFAULT '',
    soderzhanie text NOT NULL,
    embedding extensions.vector(1024) NOT NULL,
    metadannye jsonb NOT NULL DEFAULT '{}'::jsonb,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    CONSTRAINT znaniya_fragmenty_nomer_unique UNIQUE (versiya_id, nomer_fragmenta)
);

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty
    ADD CONSTRAINT znaniya_dokumenty_aktivnaya_versiya_fk
    FOREIGN KEY (aktivnaya_versiya_id)
    REFERENCES qbit_bot_pervichnogo_obrascheniya.znaniya_versii(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX znaniya_versii_status_idx
    ON qbit_bot_pervichnogo_obrascheniya.znaniya_versii(status, vremya_sozdaniya);

CREATE INDEX znaniya_fragmenty_versiya_idx
    ON qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty(versiya_id, nomer_fragmenta);

RESET ROLE;
