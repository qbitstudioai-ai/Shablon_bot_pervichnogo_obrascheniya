-- DB-03A v0.1: core reliability, queues and memory tables
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_bot_pervichnogo_obrascheniya ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01 and DB-02 successfully applied.
--
-- CREATES 9 TABLES
--   sobytiya_integraciy
--   zadaniya_obrabotki
--   ishodyashchie_deystviya
--   napominaniya
--   pamyat_dialoga
--   analiz_dialogov
--   obratnaya_svyaz
--   sistemnye_sobytiya
--   zhurnal_administrirovaniya
--
-- ALSO ADDS
--   soobshcheniya.sobytie_id -> sobytiya_integraciy(id)
--
-- NOT INCLUDED
--   Operator Telegram tables/functions: DB-03B/DB-03D.
--   Client/queue/outgoing PostgreSQL API functions: DB-03C.
--   Knowledge upload FK ishodyashchie_deystviya.zagruzka_id: DB-04.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * kompaniya_001_test remains an isolation canary.
--   * Runtime roles receive no direct table DML.
--   * Probe rows are rolled back to a SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03A migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03a$
DECLARE
    v_table text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03A requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03A must run from trusted postgres session. session_user=%',
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
        RAISE EXCEPTION 'qbit_bot_pervichnogo_obrascheniya is not owned by qbit_test_owner';
    END IF;

    -- DB-02 prerequisites.
    FOREACH v_table IN ARRAY ARRAY[
        'polzovateli',
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'vlozheniya_soobshcheniy',
        'transkripcii_golosa',
        'fakty_dialoga',
        'sootvetstviya_pii',
        'narusheniya_tematiky',
        'sobytiya_dialogov',
        'sobytiya_etapov',
        'celevye_sobytiya',
        'zayavki'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I', v_table)
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required DB-02 table qbit_bot_pervichnogo_obrascheniya.% is missing',
                v_table;
        END IF;
    END LOOP;

    -- DB-03A must not overwrite a partial earlier installation.
    FOREACH v_table IN ARRAY ARRAY[
        'sobytiya_integraciy',
        'zadaniya_obrabotki',
        'ishodyashchie_deystviya',
        'napominaniya',
        'pamyat_dialoga',
        'analiz_dialogov',
        'obratnaya_svyaz',
        'sistemnye_sobytiya',
        'zhurnal_administrirovaniya'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I', v_table)
        ) IS NOT NULL THEN
            RAISE EXCEPTION
                'DB-03A object qbit_bot_pervichnogo_obrascheniya.% already exists; stop instead of overwriting',
                v_table;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND rel.relname = 'soobshcheniya'
           AND con.conname = 'fk_soobshcheniya_sobytie_integracii'
    ) THEN
        RAISE EXCEPTION
            'Forward FK fk_soobshcheniya_sobytie_integracii already exists';
    END IF;
END
$db03a$;

-- ===========================================================================
-- 1. CREATE CORE RELIABILITY TABLES
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    versiya_formata integer NOT NULL DEFAULT 1,
    operaciya_id text NOT NULL,
    istochnik text NOT NULL,
    akkaunt_istochnika_id text NOT NULL,
    vneshnee_sobytie_id text NOT NULL,
    tip_sobytiya text NOT NULL,
    klyuch_idempotentnosti text NOT NULL,
    hash_soderzhaniya text NOT NULL,
    payload_ishodnyy jsonb NOT NULL,
    vremya_istochnika timestamptz,
    vremya_priema timestamptz NOT NULL,
    vremya_zapisi timestamptz NOT NULL DEFAULT clock_timestamp(),
    status text NOT NULL,
    kod_oshibki text,
    trassirovka_id text,

    CONSTRAINT ck_sobint_versiya
        CHECK (versiya_formata >= 1),
    CONSTRAINT ck_sobint_operaciya
        CHECK (btrim(operaciya_id) <> ''),
    CONSTRAINT ck_sobint_istochnik
        CHECK (btrim(istochnik) <> ''),
    CONSTRAINT ck_sobint_akkaunt
        CHECK (btrim(akkaunt_istochnika_id) <> ''),
    CONSTRAINT ck_sobint_vnesh_sobytie
        CHECK (btrim(vneshnee_sobytie_id) <> ''),
    CONSTRAINT ck_sobint_tip
        CHECK (btrim(tip_sobytiya) <> ''),
    CONSTRAINT ck_sobint_idempotentnost
        CHECK (btrim(klyuch_idempotentnosti) <> ''),
    CONSTRAINT ck_sobint_hash
        CHECK (btrim(hash_soderzhaniya) <> ''),
    CONSTRAINT ck_sobint_payload
        CHECK (
            jsonb_typeof(payload_ishodnyy) IN ('object', 'array')
        ),
    CONSTRAINT ck_sobint_status
        CHECK (btrim(status) <> '')
);

CREATE UNIQUE INDEX uq_sobint_istochnik_sobytie
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (
        istochnik,
        akkaunt_istochnika_id,
        vneshnee_sobytie_id
    );

CREATE UNIQUE INDEX uq_sobint_idempotentnost
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (klyuch_idempotentnosti);

CREATE INDEX ix_sobint_priem
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (vremya_priema);

CREATE INDEX ix_sobint_account_time
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (
        istochnik,
        akkaunt_istochnika_id,
        vremya_priema DESC
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    sobytie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy(id),
    tip_zadaniya text NOT NULL,
    status text NOT NULL DEFAULT 'ozhidaet',
    prioritet integer NOT NULL DEFAULT 0,
    popytki integer NOT NULL DEFAULT 0,
    sleduyushchiy_zapusk timestamptz NOT NULL DEFAULT clock_timestamp(),
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    versiya_dialoga bigint NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_zadaniya_tip
        CHECK (btrim(tip_zadaniya) <> ''),
    CONSTRAINT ck_zadaniya_status
        CHECK (
            status IN (
                'ozhidaet',
                'v_rabote',
                'povtor',
                'zaversheno',
                'otmeneno',
                'oshibka'
            )
        ),
    CONSTRAINT ck_zadaniya_popytki
        CHECK (popytki >= 0),
    CONSTRAINT ck_zadaniya_nomer_vladeniya
        CHECK (nomer_vladeniya >= 0),
    CONSTRAINT ck_zadaniya_versiya_dialoga
        CHECK (versiya_dialoga >= 1),
    CONSTRAINT ck_zadaniya_payload
        CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT ck_zadaniya_arenda
        CHECK (
            status <> 'v_rabote'
            OR (
                vladelec_arendy IS NOT NULL
                AND btrim(vladelec_arendy) <> ''
                AND arenda_do IS NOT NULL
            )
        )
);

CREATE INDEX ix_zadaniya_gotovy
    ON qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
        prioritet DESC,
        sleduyushchiy_zapusk,
        vremya_sozdaniya
    )
    WHERE status IN ('ozhidaet', 'povtor');

CREATE INDEX ix_zadaniya_dialog
    ON qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
        dialog_id,
        vremya_sozdaniya
    );

CREATE INDEX ix_zadaniya_arenda
    ON qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (arenda_do)
    WHERE status = 'v_rabote';

CREATE UNIQUE INDEX uq_zadaniya_dialog_vrabote
    ON qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (dialog_id)
    WHERE status = 'v_rabote';


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    zagruzka_id uuid,
    soobshchenie_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    vid_deystviya text NOT NULL,
    istochnik text NOT NULL,
    klyuch_povtora text NOT NULL,
    kanal text,
    akkaunt_kanala_id text,
    vneshniy_dialog_id text,
    vneshnee_otvet_na_id text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'zaplanirovano',
    popytki integer NOT NULL DEFAULT 0,
    sleduyushchiy_zapusk timestamptz NOT NULL DEFAULT clock_timestamp(),
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    versiya_dialoga bigint,
    vneshniy_id text,
    vremya_zaprosa timestamptz,
    vremya_podtverzhdeniya timestamptz,
    povtor_posle timestamptz,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_ishod_vid
        CHECK (
            vid_deystviya IN (
                'soobshchenie',
                'crm',
                'uvedomlenie',
                'otchet'
            )
        ),
    CONSTRAINT ck_ishod_istochnik
        CHECK (istochnik IN ('bot', 'menedzher', 'sistema')),
    CONSTRAINT ck_ishod_klyuch
        CHECK (btrim(klyuch_povtora) <> ''),
    CONSTRAINT ck_ishod_osnovanie
        CHECK (
            dialog_id IS NOT NULL
            OR zagruzka_id IS NOT NULL
        ),
    CONSTRAINT ck_ishod_soobshchenie
        CHECK (
            vid_deystviya <> 'soobshchenie'
            OR (
                dialog_id IS NOT NULL
                AND soobshchenie_id IS NOT NULL
                AND kanal IS NOT NULL
                AND btrim(kanal) <> ''
                AND akkaunt_kanala_id IS NOT NULL
                AND btrim(akkaunt_kanala_id) <> ''
                AND vneshniy_dialog_id IS NOT NULL
                AND btrim(vneshniy_dialog_id) <> ''
            )
        ),
    CONSTRAINT ck_ishod_status
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
    CONSTRAINT ck_ishod_popytki
        CHECK (popytki >= 0),
    CONSTRAINT ck_ishod_nomer_vladeniya
        CHECK (nomer_vladeniya >= 0),
    CONSTRAINT ck_ishod_versiya_dialoga
        CHECK (
            (dialog_id IS NULL AND versiya_dialoga IS NULL)
            OR
            (dialog_id IS NOT NULL
             AND versiya_dialoga IS NOT NULL
             AND versiya_dialoga >= 1)
        ),
    CONSTRAINT ck_ishod_payload
        CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT ck_ishod_arenda
        CHECK (
            status <> 'v_rabote'
            OR (
                vladelec_arendy IS NOT NULL
                AND btrim(vladelec_arendy) <> ''
                AND arenda_do IS NOT NULL
            )
        ),
    CONSTRAINT ck_ishod_podtverzhdenie
        CHECK (
            status <> 'podtverzhdeno'
            OR vremya_podtverzhdeniya IS NOT NULL
        )
);

CREATE UNIQUE INDEX uq_ishod_klyuch_povtora
    ON qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (klyuch_povtora);

CREATE INDEX ix_ishod_gotovy
    ON qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
        sleduyushchiy_zapusk,
        vremya_sozdaniya
    )
    WHERE status IN ('zaplanirovano', 'povtor');

CREATE INDEX ix_ishod_dialog_status
    ON qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
        dialog_id,
        status,
        vremya_sozdaniya
    );

CREATE INDEX ix_ishod_arenda
    ON qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (arenda_do)
    WHERE status = 'v_rabote';

CREATE INDEX ix_ishod_vnesh
    ON qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
        kanal,
        akkaunt_kanala_id,
        vneshniy_id
    )
    WHERE vneshniy_id IS NOT NULL;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.napominaniya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    tip text NOT NULL,
    t0 timestamptz NOT NULL,
    soobshchenie_osnovanie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    pokolenie_ozhidaniya bigint NOT NULL,
    srok timestamptz NOT NULL,
    aktualno_do timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'zaplanirovano',
    prichina text,
    ishodyashchee_deystvie_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya(id),
    vremya_fakticheskoy_otpravki timestamptz,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_napominaniya_tip
        CHECK (
            tip IN (
                'napominanie_1',
                'napominanie_2',
                'proverka_poteri'
            )
        ),
    CONSTRAINT ck_napominaniya_pokolenie
        CHECK (pokolenie_ozhidaniya >= 0),
    CONSTRAINT ck_napominaniya_okno
        CHECK (aktualno_do >= srok),
    CONSTRAINT ck_napominaniya_status
        CHECK (
            status IN (
                'zaplanirovano',
                'v_rabote',
                'podtverzhdeno',
                'propushcheno',
                'otmeneno',
                'neizvestno',
                'oshibka'
            )
        ),
    CONSTRAINT ck_napominaniya_fakt
        CHECK (
            status <> 'podtverzhdeno'
            OR tip = 'proverka_poteri'
            OR vremya_fakticheskoy_otpravki IS NOT NULL
        )
);

CREATE UNIQUE INDEX uq_napominaniya_dialog_pok_tip
    ON qbit_bot_pervichnogo_obrascheniya.napominaniya (
        dialog_id,
        pokolenie_ozhidaniya,
        tip
    );

CREATE INDEX ix_napominaniya_srok
    ON qbit_bot_pervichnogo_obrascheniya.napominaniya (srok)
    WHERE status = 'zaplanirovano';

CREATE INDEX ix_napominaniya_dialog
    ON qbit_bot_pervichnogo_obrascheniya.napominaniya (
        dialog_id,
        pokolenie_ozhidaniya
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga (
    dialog_id uuid PRIMARY KEY
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    rezyume text,
    poslednie_soobshcheniya jsonb NOT NULL DEFAULT '[]'::jsonb,
    podtverzhdennye_fakty jsonb NOT NULL DEFAULT '{}'::jsonb,
    obrabotano_do_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    versiya_pamyati bigint NOT NULL DEFAULT 1,
    kolichestvo_tokenov integer NOT NULL DEFAULT 0,
    predydushchiy_dialog_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_pamyat_poslednie
        CHECK (
            jsonb_typeof(poslednie_soobshcheniya) = 'array'
        ),
    CONSTRAINT ck_pamyat_fakty
        CHECK (
            jsonb_typeof(podtverzhdennye_fakty) = 'object'
        ),
    CONSTRAINT ck_pamyat_versiya
        CHECK (versiya_pamyati >= 1),
    CONSTRAINT ck_pamyat_tokeny
        CHECK (kolichestvo_tokenov >= 0)
);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.analiz_dialogov (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    rezyume text,
    tema text,
    reakciya text,
    predpolagaemye_oshibki jsonb NOT NULL DEFAULT '[]'::jsonb,
    probely_znaniy jsonb NOT NULL DEFAULT '[]'::jsonb,
    dokazatelstva uuid[] NOT NULL DEFAULT '{}'::uuid[],
    uverennost numeric,
    versiya_modeli text NOT NULL,
    versiya_prompta text NOT NULL,
    podtverzhdeno_chelovekom boolean NOT NULL DEFAULT false,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_analiz_oshibki
        CHECK (
            jsonb_typeof(predpolagaemye_oshibki) = 'array'
        ),
    CONSTRAINT ck_analiz_probely
        CHECK (
            jsonb_typeof(probely_znaniy) = 'array'
        ),
    CONSTRAINT ck_analiz_uverennost
        CHECK (
            uverennost IS NULL
            OR (uverennost >= 0 AND uverennost <= 1)
        ),
    CONSTRAINT ck_analiz_model
        CHECK (btrim(versiya_modeli) <> ''),
    CONSTRAINT ck_analiz_prompt
        CHECK (btrim(versiya_prompta) <> '')
);

CREATE INDEX ix_analiz_dialog_vremya
    ON qbit_bot_pervichnogo_obrascheniya.analiz_dialogov (
        dialog_id,
        vremya_sozdaniya DESC
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    ocenka smallint NOT NULL,
    tekst text,
    vremya timestamptz NOT NULL,
    kanal text NOT NULL,
    predydushchaya_redakciya_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz(id),

    CONSTRAINT ck_feedback_ocenka
        CHECK (ocenka BETWEEN 1 AND 5),
    CONSTRAINT ck_feedback_kanal
        CHECK (btrim(kanal) <> ''),
    CONSTRAINT ck_feedback_ne_sam
        CHECK (
            predydushchaya_redakciya_id IS NULL
            OR predydushchaya_redakciya_id <> id
        )
);

CREATE INDEX ix_feedback_dialog
    ON qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz (
        dialog_id,
        vremya DESC
    );

CREATE INDEX ix_feedback_vremya
    ON qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz (vremya DESC);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kompaniya_kod text NOT NULL,
    sreda text NOT NULL,
    komponent text NOT NULL,
    operaciya_id text,
    trassirovka_id text,
    vremya_sobytiya timestamptz NOT NULL,
    uroven text NOT NULL,
    kod text NOT NULL,
    opisanie text NOT NULL,
    klyuch_gruppirovki text NOT NULL,
    status_uvedomleniya text NOT NULL DEFAULT 'ne_trebuetsya',
    kolichestvo_povtorov integer NOT NULL DEFAULT 0,
    poslednee_povtorenie timestamptz,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_sissob_kompaniya
        CHECK (btrim(kompaniya_kod) <> ''),
    CONSTRAINT ck_sissob_sreda
        CHECK (btrim(sreda) <> ''),
    CONSTRAINT ck_sissob_komponent
        CHECK (btrim(komponent) <> ''),
    CONSTRAINT ck_sissob_uroven
        CHECK (
            uroven IN (
                'info',
                'preduprezhdenie',
                'oshibka',
                'kritichno'
            )
        ),
    CONSTRAINT ck_sissob_kod
        CHECK (btrim(kod) <> ''),
    CONSTRAINT ck_sissob_opisanie
        CHECK (btrim(opisanie) <> ''),
    CONSTRAINT ck_sissob_gruppa
        CHECK (btrim(klyuch_gruppirovki) <> ''),
    CONSTRAINT ck_sissob_status_uvedomleniya
        CHECK (
            status_uvedomleniya IN (
                'ne_trebuetsya',
                'ozhidaet',
                'otpravleno',
                'povtor',
                'oshibka',
                'zakryto'
            )
        ),
    CONSTRAINT ck_sissob_povtory
        CHECK (kolichestvo_povtorov >= 0)
);

CREATE INDEX ix_sissob_vremya_uroven
    ON qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
        vremya_sobytiya DESC,
        uroven
    );

CREATE INDEX ix_sissob_gruppa
    ON qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
        klyuch_gruppirovki,
        vremya_sobytiya DESC
    );

CREATE INDEX ix_sissob_uvedomlenie
    ON qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
        status_uvedomleniya,
        vremya_sobytiya
    )
    WHERE status_uvedomleniya IN (
        'ozhidaet',
        'povtor',
        'oshibka'
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tip_avtora text NOT NULL,
    avtor_id text NOT NULL,
    deystvie text NOT NULL,
    tip_obekta text NOT NULL,
    obekt_id text,
    vremya timestamptz NOT NULL,
    izmeneniya jsonb NOT NULL DEFAULT '{}'::jsonb,
    rezultat text NOT NULL,
    trassirovka_id text,

    CONSTRAINT ck_admin_tip_avtora
        CHECK (btrim(tip_avtora) <> ''),
    CONSTRAINT ck_admin_avtor
        CHECK (btrim(avtor_id) <> ''),
    CONSTRAINT ck_admin_deystvie
        CHECK (btrim(deystvie) <> ''),
    CONSTRAINT ck_admin_tip_obekta
        CHECK (btrim(tip_obekta) <> ''),
    CONSTRAINT ck_admin_izmeneniya
        CHECK (jsonb_typeof(izmeneniya) = 'object'),
    CONSTRAINT ck_admin_rezultat
        CHECK (btrim(rezultat) <> '')
);

CREATE INDEX ix_admin_objekt
    ON qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
        tip_obekta,
        obekt_id,
        vremya DESC
    );

CREATE INDEX ix_admin_avtor_vremya
    ON qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
        tip_avtora,
        avtor_id,
        vremya DESC
    );

CREATE INDEX ix_admin_vremya
    ON qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (vremya DESC);

-- Complete the DB-02 forward reference now that integration events exist.
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.soobshcheniya
    ADD CONSTRAINT fk_soobshcheniya_sobytie_integracii
    FOREIGN KEY (sobytie_id)
    REFERENCES qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy(id);

-- ===========================================================================
-- 2. COMMENTS
-- ===========================================================================

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy IS
'Долговечные входные integration events с ключом идемпотентности, хэшем и сырым локальным payload.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki IS
'PostgreSQL-очередь последовательной обработки диалогов с арендой, номером владения и версией состояния.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya IS
'Долговечные намерения внешних действий: сообщение, CRM, уведомление или отчёт; подтверждение отделено от запроса.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.napominaniya IS
'План и фактическое состояние напоминаний и проверки потери, привязанные к t0 и поколению ожидания.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga IS
'Короткая сохраняемая память диалога: резюме, обезличенное окно и кэш подтверждённых фактов.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.analiz_dialogov IS
'Необязательный структурированный анализ качества диалога с доказательствами и версиями модели/prompt.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz IS
'Оценка и текст обратной связи пользователя с сохранением истории редакций.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya IS
'Безопасные технические события, группировка инцидентов и состояние внешнего уведомления.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya IS
'Аудит административных действий: автор, объект, безопасное изменение, результат и трассировка.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.id IS 'UUID integration event.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.versiya_formata IS 'Версия нормализованного формата входного события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.operaciya_id IS 'ID прикладной операции регистрации события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.istochnik IS 'Код источника/канала входного события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.akkaunt_istochnika_id IS 'Доверенный код конкретного аккаунта/бота источника.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.vneshnee_sobytie_id IS 'Устойчивый внешний ID события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.tip_sobytiya IS 'Нормализованный тип события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.klyuch_idempotentnosti IS 'Стабильный локальный ключ идемпотентности.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.hash_soderzhaniya IS 'Хэш нормализованного содержания для обнаружения конфликта same-key/different-content.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.payload_ishodnyy IS 'Исходный локально сохранённый payload без публикации наружу.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.vremya_istochnika IS 'Время события по данным источника.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.vremya_priema IS 'Время приёма webhook/события приложением.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.vremya_zapisi IS 'Время долговечной записи в PostgreSQL.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.status IS 'Техническое состояние входного события; переходами управляют функции DB-03C/DB-03D.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.kod_oshibki IS 'Безопасный код ошибки обработки события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy.trassirovka_id IS 'Безопасный ID трассировки выполнения.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.id IS 'UUID задания очереди.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.dialog_id IS 'Диалог, обрабатываемый заданием.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.sobytie_id IS 'Integration event, породивший задание.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.tip_zadaniya IS 'Технический тип задания CORE.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.status IS 'ozhidaet, v_rabote, povtor, zaversheno, otmeneno или oshibka.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.prioritet IS 'Приоритет claim: большее значение забирается раньше при прочих равных.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.popytki IS 'Число начатых попыток выполнения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.sleduyushchiy_zapusk IS 'Не выполнять раньше этого времени.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.vladelec_arendy IS 'Идентификатор текущего worker-владельца аренды.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.arenda_do IS 'Срок действия текущей аренды.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.nomer_vladeniya IS 'Монотонный fencing/ownership номер для защиты от устаревшего worker.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.versiya_dialoga IS 'Ожидаемая CAS-версия диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.payload IS 'Безопасная структурированная полезная нагрузка задания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.kod_oshibki IS 'Безопасный код последней ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.opisanie_oshibki IS 'Безопасное описание последней ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.vremya_sozdaniya IS 'Время создания задания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki.vremya_obnovleniya IS 'Время последнего изменения задания.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.id IS 'UUID долговечного исходящего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.dialog_id IS 'Диалог действия при клиентской/CRM операции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.zagruzka_id IS 'UUID загрузки знаний для будущих служебных действий; FK добавляет DB-04.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.soobshchenie_id IS 'Одно логическое сообщение; повторы действия не создают новую реплику.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vid_deystviya IS 'soobshchenie, crm, uvedomlenie или otchet.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.istochnik IS 'Источник намерения: bot, menedzher или sistema.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.klyuch_povtora IS 'Стабильный ключ действия для защиты от дубля.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.kanal IS 'Доверенный код канала внешнего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.akkaunt_kanala_id IS 'Доверенный код аккаунта/бота канала.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vneshniy_dialog_id IS 'Доверенный внешний адрес получателя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vneshnee_otvet_na_id IS 'Внешний message/reply ID при необходимости.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.payload IS 'Безопасный структурированный payload внешнего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.status IS 'zaplanirovano, v_rabote, podtverzhdeno, povtor, neizvestno, otmeneno или oshibka.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.popytki IS 'Количество начатых попыток внешнего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.sleduyushchiy_zapusk IS 'Не выполнять раньше этого времени.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vladelec_arendy IS 'Текущий worker-владелец аренды.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.arenda_do IS 'Срок текущей аренды.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.nomer_vladeniya IS 'Fencing номер владения для CAS.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.versiya_dialoga IS 'Версия диалога, при которой действие было разрешено.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vneshniy_id IS 'Подтверждённый ID внешнего объекта/сообщения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vremya_zaprosa IS 'Время фактического внешнего запроса.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vremya_podtverzhdeniya IS 'Время подтверждения результата внешнего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.povtor_posle IS 'Время повторной попытки из Retry-After/политики.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.kod_oshibki IS 'Безопасный код ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.opisanie_oshibki IS 'Безопасное описание ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vremya_sozdaniya IS 'Время сохранения намерения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya.vremya_obnovleniya IS 'Время последнего изменения действия.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.id IS 'UUID напоминания/проверки потери.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.dialog_id IS 'Диалог ожидания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.tip IS 'napominanie_1, napominanie_2 или proverka_poteri.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.t0 IS 'Подтверждённое основное сообщение, от которого считаются сроки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.soobshchenie_osnovanie_id IS 'Логическое исходящее сообщение-основание ожидания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.pokolenie_ozhidaniya IS 'Поколение ожидания для отмены устаревших напоминаний.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.srok IS 'Плановый момент запуска проверки/напоминания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.aktualno_do IS 'Последний момент, когда действие ещё актуально.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.status IS 'Состояние напоминания/проверки потери.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.prichina IS 'Безопасная причина отмены, пропуска или ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.ishodyashchee_deystvie_id IS 'Исходящее действие, созданное для отправки напоминания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.vremya_fakticheskoy_otpravki IS 'Фактическое подтверждённое время отправки reminder1/reminder2.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.vremya_sozdaniya IS 'Время создания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.napominaniya.vremya_obnovleniya IS 'Время последнего изменения.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.dialog_id IS 'Диалог; одновременно PK и FK.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.rezyume IS 'Краткое обезличенное резюме состояния разговора.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.poslednie_soobshcheniya IS 'Массив последних 3–5 обезличенных сообщений по настройке компании.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.podtverzhdennye_fakty IS 'Производный кэш подтверждённых фактов; источник истины — fakty_dialoga.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.obrabotano_do_id IS 'Последнее логическое сообщение, включённое в память.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.versiya_pamyati IS 'CAS-версия рабочей памяти.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.kolichestvo_tokenov IS 'Сохранённая оценка размера контекста в токенах.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.predydushchiy_dialog_id IS 'Предыдущий диалог, из которого взяты релевантные сведения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga.vremya_obnovleniya IS 'Время последнего обновления памяти.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.id IS 'UUID записи анализа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.dialog_id IS 'Анализируемый диалог.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.rezyume IS 'Резюме анализа качества.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.tema IS 'Определённая тема диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.reakciya IS 'Оценка реакции/настроения в безопасной форме.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.predpolagaemye_oshibki IS 'Массив предполагаемых ошибок; это вывод анализа, не установленный факт.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.probely_znaniy IS 'Массив предполагаемых пробелов знаний.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.dokazatelstva IS 'UUID сообщений-доказательств; проверяются прикладным слоем.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.uverennost IS 'Уверенность анализа от 0 до 1.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.versiya_modeli IS 'Версия/код модели анализа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.versiya_prompta IS 'Версия prompt анализа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.podtverzhdeno_chelovekom IS 'Подтверждён ли вывод человеком.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.analiz_dialogov.vremya_sozdaniya IS 'Время создания анализа.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.id IS 'UUID обратной связи.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.dialog_id IS 'Диалог, к которому относится отзыв.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.polzovatel_id IS 'Пользователь, оставивший отзыв.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.ocenka IS 'Оценка от 1 до 5.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.tekst IS 'Текст отзыва при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.vremya IS 'Время отзыва.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.kanal IS 'Канал получения обратной связи.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz.predydushchaya_redakciya_id IS 'Предыдущая редакция отзыва, если текущая является новой версией.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.id IS 'UUID системного события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.kompaniya_kod IS 'Доверенный код компании.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.sreda IS 'Доверенный код среды.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.komponent IS 'Компонент, создавший событие.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.operaciya_id IS 'Прикладной ID операции при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.trassirovka_id IS 'Безопасный ID трассировки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.vremya_sobytiya IS 'Время технического события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.uroven IS 'info, preduprezhdenie, oshibka или kritichno.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.kod IS 'Стабильный безопасный код события/ошибки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.opisanie IS 'Безопасное описание без секретов и сырых переписок.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.klyuch_gruppirovki IS 'Ключ группировки повторяющегося инцидента.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.status_uvedomleniya IS 'ne_trebuetsya, ozhidaet, otpravleno, povtor, oshibka или zakryto.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.kolichestvo_povtorov IS 'Количество повторов сгруппированного события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.poslednee_povtorenie IS 'Время последнего повтора инцидента.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya.vremya_sozdaniya IS 'Время создания строки.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.id IS 'UUID административной записи.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.tip_avtora IS 'Тип автора: пользователь/система/служебный процесс.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.avtor_id IS 'Безопасный идентификатор автора.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.deystvie IS 'Код административного действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.tip_obekta IS 'Тип изменённого объекта.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.obekt_id IS 'Идентификатор объекта при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.vremya IS 'Время административного действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.izmeneniya IS 'Безопасное описание изменений без секретов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.rezultat IS 'Результат административного действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya.trassirovka_id IS 'Безопасный ID трассировки.';

COMMENT ON CONSTRAINT fk_soobshcheniya_sobytie_integracii
    ON qbit_bot_pervichnogo_obrascheniya.soobshcheniya IS
'DB-03A: каждое заполненное soobshcheniya.sobytie_id обязано ссылаться на долговечное integration event.';

-- ===========================================================================
-- 3. ACCESS: DEFAULT-DENY
-- ===========================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA qbit_bot_pervichnogo_obrascheniya FROM PUBLIC;

DO $db03a$
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
            'REVOKE ALL ON ALL TABLES IN SCHEMA qbit_bot_pervichnogo_obrascheniya FROM %I',
            v_role
        );
    END LOOP;
END
$db03a$;

-- ===========================================================================
-- 4. STATIC ASSERTIONS
-- ===========================================================================

DO $db03a$
DECLARE
    v_table_count integer;
    v_index_count integer;
BEGIN
    SELECT count(*)
      INTO v_table_count
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND c.relkind = 'r'
       AND c.relname IN (
            'sobytiya_integraciy',
            'zadaniya_obrabotki',
            'ishodyashchie_deystviya',
            'napominaniya',
            'pamyat_dialoga',
            'analiz_dialogov',
            'obratnaya_svyaz',
            'sistemnye_sobytiya',
            'zhurnal_administrirovaniya'
       );

    IF v_table_count <> 9 THEN
        RAISE EXCEPTION
            'DB-03A expected 9 tables, found %',
            v_table_count;
    END IF;

    SELECT count(*)
      INTO v_index_count
      FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = i.relnamespace
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND i.relkind = 'i'
       AND i.relname IN (
            'uq_sobint_istochnik_sobytie',
            'uq_sobint_idempotentnost',
            'ix_sobint_priem',
            'ix_sobint_account_time',
            'ix_zadaniya_gotovy',
            'ix_zadaniya_dialog',
            'ix_zadaniya_arenda',
            'uq_zadaniya_dialog_vrabote',
            'uq_ishod_klyuch_povtora',
            'ix_ishod_gotovy',
            'ix_ishod_dialog_status',
            'ix_ishod_arenda',
            'ix_ishod_vnesh',
            'uq_napominaniya_dialog_pok_tip',
            'ix_napominaniya_srok',
            'ix_napominaniya_dialog',
            'ix_analiz_dialog_vremya',
            'ix_feedback_dialog',
            'ix_feedback_vremya',
            'ix_sissob_vremya_uroven',
            'ix_sissob_gruppa',
            'ix_sissob_uvedomlenie',
            'ix_admin_objekt',
            'ix_admin_avtor_vremya',
            'ix_admin_vremya'
       );

    IF v_index_count <> 25 THEN
        RAISE EXCEPTION
            'DB-03A expected 25 contract indexes, found %',
            v_index_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND rel.relname = 'soobshcheniya'
           AND con.conname = 'fk_soobshcheniya_sobytie_integracii'
           AND con.contype = 'f'
           AND con.convalidated = true
    ) THEN
        RAISE EXCEPTION
            'DB-03A integration-event FK is missing or not validated';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
           )
           AND pg_catalog.obj_description(c.oid, 'pg_class') IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-03A found a table without COMMENT';
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
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
           )
           AND pg_catalog.col_description(c.oid, a.attnum) IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-03A found a column without COMMENT';
    END IF;
END
$db03a$;

-- ===========================================================================
-- 5. DISPOSABLE DATA PROBE
-- ===========================================================================

SAVEPOINT db03a_probe;

-- Minimal DB-02 graph.
INSERT INTO qbit_bot_pervichnogo_obrascheniya.polzovateli (
    id,
    vremya_pervogo_obrashcheniya,
    vremya_poslednego_obrashcheniya,
    pervyy_kanal,
    testovyy
)
VALUES (
    '00000000-0000-4000-8000-000000000301',
    '2026-09-24 15:00:00+00',
    '2026-09-24 15:00:00+00',
    'telegram',
    true
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
    id,
    polzovatel_id,
    kanal,
    akkaunt_kanala_id,
    vneshniy_polzovatel_id,
    vneshniy_dialog_id
)
VALUES (
    '00000000-0000-4000-8000-000000000302',
    '00000000-0000-4000-8000-000000000301',
    'telegram',
    'db03a_test_bot',
    'db03a_user',
    'db03a_chat'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.dialogi (
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
    '00000000-0000-4000-8000-000000000303',
    '00000000-0000-4000-8000-000000000301',
    '00000000-0000-4000-8000-000000000302',
    '2026-09-24 15:00:00+00',
    'pervichnyy_kontakt',
    'aktivnyy',
    'db03a_probe',
    'db03a_probe'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy (
    id,
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
    '00000000-0000-4000-8000-000000000304',
    1,
    'db03a_operation_1',
    'telegram',
    'db03a_test_bot',
    'db03a_event_1',
    'message',
    'db03a_idem_1',
    'db03a_hash_1',
    '{"update_id":"db03a_event_1"}'::jsonb,
    '2026-09-24 15:00:00+00',
    '2026-09-24 15:00:01+00',
    'prinyato',
    'db03a_trace'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
    id,
    dialog_id,
    sobytie_id,
    napravlenie,
    avtor,
    vid,
    tekst_ishodnyy,
    tekst_obezlichennyy,
    vneshnee_soobshchenie_id,
    vremya_priema
)
VALUES (
    '00000000-0000-4000-8000-000000000305',
    '00000000-0000-4000-8000-000000000303',
    '00000000-0000-4000-8000-000000000304',
    'vhodyashchee',
    'klient',
    'text',
    'DB-03A test input',
    'DB-03A test input',
    'db03a_message_1',
    '2026-09-24 15:00:01+00'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
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
    '00000000-0000-4000-8000-000000000306',
    '00000000-0000-4000-8000-000000000303',
    'ishodyashchee',
    'bot',
    'text',
    'DB-03A test outbound',
    'DB-03A test outbound',
    '2026-09-24 15:00:02+00',
    'zaplanirovano',
    true
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
    id,
    dialog_id,
    sobytie_id,
    tip_zadaniya,
    status,
    prioritet,
    sleduyushchiy_zapusk,
    versiya_dialoga
)
VALUES (
    '00000000-0000-4000-8000-000000000307',
    '00000000-0000-4000-8000-000000000303',
    '00000000-0000-4000-8000-000000000304',
    'obrabotat_vhod',
    'ozhidaet',
    10,
    '2026-09-24 15:00:01+00',
    1
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
    id,
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
    '00000000-0000-4000-8000-000000000308',
    '00000000-0000-4000-8000-000000000303',
    '00000000-0000-4000-8000-000000000306',
    'soobshchenie',
    'bot',
    'db03a_outgoing_1',
    'telegram',
    'db03a_test_bot',
    'db03a_chat',
    '{"text":"DB-03A test outbound"}'::jsonb,
    'zaplanirovano',
    '2026-09-24 15:00:02+00',
    1
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.napominaniya (
    id,
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
    '00000000-0000-4000-8000-000000000309',
    '00000000-0000-4000-8000-000000000303',
    'napominanie_1',
    '2026-09-24 15:00:02+00',
    '00000000-0000-4000-8000-000000000306',
    1,
    '2026-09-24 18:00:02+00',
    '2026-09-24 19:00:02+00',
    'zaplanirovano'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga (
    dialog_id,
    rezyume,
    poslednie_soobshcheniya,
    podtverzhdennye_fakty,
    obrabotano_do_id,
    versiya_pamyati,
    kolichestvo_tokenov
)
VALUES (
    '00000000-0000-4000-8000-000000000303',
    'DB-03A probe',
    '[{"role":"user","text":"DB-03A test input"}]'::jsonb,
    '{"telefon_poluchen":false}'::jsonb,
    '00000000-0000-4000-8000-000000000305',
    1,
    10
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.analiz_dialogov (
    id,
    dialog_id,
    rezyume,
    tema,
    reakciya,
    predpolagaemye_oshibki,
    probely_znaniy,
    dokazatelstva,
    uverennost,
    versiya_modeli,
    versiya_prompta
)
VALUES (
    '00000000-0000-4000-8000-000000000310',
    '00000000-0000-4000-8000-000000000303',
    'DB-03A probe analysis',
    'test',
    'neutral',
    '[]'::jsonb,
    '[]'::jsonb,
    ARRAY['00000000-0000-4000-8000-000000000305'::uuid],
    0.9,
    'db03a_model',
    'db03a_prompt'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz (
    id,
    dialog_id,
    polzovatel_id,
    ocenka,
    tekst,
    vremya,
    kanal
)
VALUES (
    '00000000-0000-4000-8000-000000000311',
    '00000000-0000-4000-8000-000000000303',
    '00000000-0000-4000-8000-000000000301',
    5,
    'DB-03A probe feedback',
    '2026-09-24 15:05:00+00',
    'telegram'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya (
    id,
    kompaniya_kod,
    sreda,
    komponent,
    operaciya_id,
    trassirovka_id,
    vremya_sobytiya,
    uroven,
    kod,
    opisanie,
    klyuch_gruppirovki,
    status_uvedomleniya
)
VALUES (
    '00000000-0000-4000-8000-000000000312',
    'qbit',
    'test',
    'db03a_probe',
    'db03a_operation_1',
    'db03a_trace',
    '2026-09-24 15:06:00+00',
    'info',
    'db03a_probe',
    'DB-03A safe probe event',
    'db03a_probe_group',
    'ne_trebuetsya'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya (
    id,
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
    '00000000-0000-4000-8000-000000000313',
    'sistema',
    'db03a_probe',
    'proverka',
    'db03a',
    '00000000-0000-4000-8000-000000000303',
    '2026-09-24 15:07:00+00',
    '{"probe":true}'::jsonb,
    'uspeshno',
    'db03a_trace'
);

-- Expected failures.
DO $db03a$
BEGIN
    -- External event uniqueness.
    BEGIN
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
            vremya_priema,
            status
        )
        VALUES (
            1,
            'db03a_operation_duplicate',
            'telegram',
            'db03a_test_bot',
            'db03a_event_1',
            'message',
            'db03a_idem_other',
            'db03a_hash_other',
            '{}'::jsonb,
            '2026-09-24 15:08:00+00',
            'prinyato'
        );

        RAISE EXCEPTION
            'DB-03A probe failed: duplicate source event was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Idempotency key uniqueness.
    BEGIN
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
            vremya_priema,
            status
        )
        VALUES (
            1,
            'db03a_operation_duplicate_2',
            'telegram',
            'db03a_test_bot',
            'db03a_event_2',
            'message',
            'db03a_idem_1',
            'db03a_hash_other',
            '{}'::jsonb,
            '2026-09-24 15:08:00+00',
            'prinyato'
        );

        RAISE EXCEPTION
            'DB-03A probe failed: duplicate idempotency key was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Forward FK from messages must reject unknown integration event.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
            dialog_id,
            sobytie_id,
            napravlenie,
            avtor,
            vid,
            vremya_priema
        )
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            '00000000-0000-4000-8000-000000009999',
            'vhodyashchee',
            'klient',
            'text',
            '2026-09-24 15:08:00+00'
        );

        RAISE EXCEPTION
            'DB-03A probe failed: message with missing integration event was accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN NULL;
    END;

    -- Only one in-progress job per dialog.
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki
       SET status = 'v_rabote',
           vladelec_arendy = 'worker_1',
           arenda_do = '2026-09-24 15:20:00+00',
           nomer_vladeniya = 1
     WHERE id = '00000000-0000-4000-8000-000000000307';

    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
            dialog_id,
            sobytie_id,
            tip_zadaniya,
            status,
            prioritet,
            sleduyushchiy_zapusk,
            vladelec_arendy,
            arenda_do,
            nomer_vladeniya,
            versiya_dialoga
        )
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            '00000000-0000-4000-8000-000000000304',
            'obrabotat_vhod',
            'v_rabote',
            9,
            '2026-09-24 15:08:00+00',
            'worker_2',
            '2026-09-24 15:20:00+00',
            1,
            1
        );

        RAISE EXCEPTION
            'DB-03A probe failed: two v_rabote jobs for one dialog were accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- v_rabote always needs a lease.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki (
            dialog_id,
            sobytie_id,
            tip_zadaniya,
            status,
            versiya_dialoga
        )
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            '00000000-0000-4000-8000-000000000304',
            'bad_lease',
            'v_rabote',
            1
        );

        RAISE EXCEPTION
            'DB-03A probe failed: v_rabote job without lease was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- Outgoing stable key uniqueness.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya (
            dialog_id,
            soobshchenie_id,
            vid_deystviya,
            istochnik,
            klyuch_povtora,
            kanal,
            akkaunt_kanala_id,
            vneshniy_dialog_id,
            status,
            versiya_dialoga
        )
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            '00000000-0000-4000-8000-000000000306',
            'soobshchenie',
            'bot',
            'db03a_outgoing_1',
            'telegram',
            'db03a_test_bot',
            'db03a_chat',
            'zaplanirovano',
            1
        );

        RAISE EXCEPTION
            'DB-03A probe failed: duplicate outgoing stable key was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Reminder generation/type uniqueness.
    BEGIN
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
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            'napominanie_1',
            '2026-09-24 15:00:02+00',
            '00000000-0000-4000-8000-000000000306',
            1,
            '2026-09-24 19:00:02+00',
            '2026-09-24 20:00:02+00',
            'zaplanirovano'
        );

        RAISE EXCEPTION
            'DB-03A probe failed: duplicate reminder generation/type was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    -- Feedback rating contract.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz (
            dialog_id,
            polzovatel_id,
            ocenka,
            vremya,
            kanal
        )
        VALUES (
            '00000000-0000-4000-8000-000000000303',
            '00000000-0000-4000-8000-000000000301',
            6,
            '2026-09-24 15:09:00+00',
            'telegram'
        );

        RAISE EXCEPTION
            'DB-03A probe failed: feedback rating outside 1..5 was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END
$db03a$;

-- One successful row in every DB-03A table.
DO $db03a$
DECLARE
    v_bad integer;
BEGIN
    SELECT count(*)
      INTO v_bad
      FROM (
            SELECT 'sobytiya_integraciy' AS t, count(*) AS c FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy
            UNION ALL SELECT 'zadaniya_obrabotki', count(*) FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki
            UNION ALL SELECT 'ishodyashchie_deystviya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya
            UNION ALL SELECT 'napominaniya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.napominaniya
            UNION ALL SELECT 'pamyat_dialoga', count(*) FROM qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga
            UNION ALL SELECT 'analiz_dialogov', count(*) FROM qbit_bot_pervichnogo_obrascheniya.analiz_dialogov
            UNION ALL SELECT 'obratnaya_svyaz', count(*) FROM qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz
            UNION ALL SELECT 'sistemnye_sobytiya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya
            UNION ALL SELECT 'zhurnal_administrirovaniya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya
      ) AS x
     WHERE x.c <> 1;

    IF v_bad <> 0 THEN
        RAISE EXCEPTION
            'DB-03A probe expected one row in each new table; bad tables=%',
            v_bad;
    END IF;
END
$db03a$;

ROLLBACK TO SAVEPOINT db03a_probe;
RELEASE SAVEPOINT db03a_probe;

-- ===========================================================================
-- 6. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03a$
DECLARE
    v_role text;
    v_table record;
    v_owner text;
    v_probe_rows bigint;
BEGIN
    -- New tables must remain owned by qbit_test_owner.
    FOR v_table IN
        SELECT c.oid, c.relname
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
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
                'DB-03A table qbit_bot_pervichnogo_obrascheniya.% has wrong owner %',
                v_table.relname,
                v_owner;
        END IF;
    END LOOP;

    SELECT
          (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.napominaniya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.analiz_dialogov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya)
      INTO v_probe_rows;

    IF v_probe_rows <> 0 THEN
        RAISE EXCEPTION
            'DB-03A probe rows remain after SAVEPOINT rollback: %',
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
             WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
               AND c.relkind = 'r'
               AND c.relname IN (
                    'sobytiya_integraciy',
                    'zadaniya_obrabotki',
                    'ishodyashchie_deystviya',
                    'napominaniya',
                    'pamyat_dialoga',
                    'analiz_dialogov',
                    'obratnaya_svyaz',
                    'sistemnye_sobytiya',
                    'zhurnal_administrirovaniya'
               )
        LOOP
            IF pg_catalog.has_table_privilege(v_role, v_table.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % has direct DML on qbit_bot_pervichnogo_obrascheniya.%',
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
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
           )
    ) THEN
        RAISE EXCEPTION
            'DB-03A unexpectedly created tables in kompaniya_001_test';
    END IF;
END
$db03a$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 7. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03a_status',
    'applied',
    'database',
    current_database(),
    'schema',
    'qbit_bot_pervichnogo_obrascheniya',
    'owner',
    (
        SELECT r.rolname
          FROM pg_catalog.pg_namespace AS n
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = n.nspowner
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
    ),
    'tables_ok',
    (
        SELECT count(*) = 9
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
           )
    ),
    'contract_indexes_ok',
    (
        SELECT count(*) = 25
          FROM pg_catalog.pg_class AS i
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = i.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND i.relkind = 'i'
           AND i.relname IN (
                'uq_sobint_istochnik_sobytie',
                'uq_sobint_idempotentnost',
                'ix_sobint_priem',
                'ix_sobint_account_time',
                'ix_zadaniya_gotovy',
                'ix_zadaniya_dialog',
                'ix_zadaniya_arenda',
                'uq_zadaniya_dialog_vrabote',
                'uq_ishod_klyuch_povtora',
                'ix_ishod_gotovy',
                'ix_ishod_dialog_status',
                'ix_ishod_arenda',
                'ix_ishod_vnesh',
                'uq_napominaniya_dialog_pok_tip',
                'ix_napominaniya_srok',
                'ix_napominaniya_dialog',
                'ix_analiz_dialog_vremya',
                'ix_feedback_dialog',
                'ix_feedback_vremya',
                'ix_sissob_vremya_uroven',
                'ix_sissob_gruppa',
                'ix_sissob_uvedomlenie',
                'ix_admin_objekt',
                'ix_admin_avtor_vremya',
                'ix_admin_vremya'
           )
    ),
    'integration_fk_ok',
    EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS con
          JOIN pg_catalog.pg_class AS rel
            ON rel.oid = con.conrelid
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = rel.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND rel.relname = 'soobshcheniya'
           AND con.conname = 'fk_soobshcheniya_sobytie_integracii'
           AND con.contype = 'f'
           AND con.convalidated = true
    ),
    'probe_rows_remaining',
      (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.napominaniya)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.pamyat_dialoga)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.analiz_dialogov)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.obratnaya_svyaz)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sistemnye_sobytiya)
    + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya),
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
                'sobytiya_integraciy',
                'zadaniya_obrabotki',
                'ishodyashchie_deystviya',
                'napominaniya',
                'pamyat_dialoga',
                'analiz_dialogov',
                'obratnaya_svyaz',
                'sistemnye_sobytiya',
                'zhurnal_administrirovaniya'
           )
    ),
    'operator_tables_created',
    false,
    'result',
    'DB-03A SQL APPLIED: 9 core reliability tables and integration-event FK verified; probe data removed; production untouched.'
) AS db03a_result;
