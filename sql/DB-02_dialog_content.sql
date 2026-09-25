-- DB-02 v0.1: users, dialogs, messages and business history
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_bot_pervichnogo_obrascheniya ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01 successfully applied.
--
-- CREATES 13 TABLES
--   polzovateli
--   identifikatory_kanalov
--   dialogi
--   soobshcheniya
--   vlozheniya_soobshcheniy
--   transkripcii_golosa
--   fakty_dialoga
--   sootvetstviya_pii
--   narusheniya_tematiky
--   sobytiya_dialogov
--   sobytiya_etapov
--   celevye_sobytiya
--   zayavki
--
-- FORWARD REFERENCES DEFERRED TO DB-03
--   dialogi.tekushchiy_menedzher_id -> menedzhery_telegram(id)
--   soobshcheniya.sobytie_id       -> sobytiya_integraciy(id)
--
-- IMPORTANT
--   * Run the WHOLE file as one query in self-hosted Supabase Studio SQL Editor.
--   * Production schema qbit is not touched.
--   * kompaniya_001_test remains an isolation canary; DB-02 creates no business tables there.
--   * Runtime roles receive no direct table DML here.
--   * No secrets, passwords or Credentials are created.
--   * No business rows remain after the built-in probe: probe data is rolled back to SAVEPOINT.
--   * On any error before COMMIT, the whole DB-02 migration is rolled back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db02$
DECLARE
    v_table text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-02 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-02 must be run from the trusted postgres administrative session. session_user=%',
            session_user;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_namespace
         WHERE nspname = 'qbit_bot_pervichnogo_obrascheniya'
    ) THEN
        RAISE EXCEPTION 'Required schema qbit_bot_pervichnogo_obrascheniya does not exist; DB-01 is not applied';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_roles
         WHERE rolname = 'qbit_test_owner'
           AND rolcanlogin = false
           AND rolsuper = false
           AND rolcreaterole = false
           AND rolcreatedb = false
           AND rolreplication = false
           AND rolbypassrls = false
    ) THEN
        RAISE EXCEPTION 'Required role qbit_test_owner is missing or unsafe';
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
        ) IS NOT NULL THEN
            RAISE EXCEPTION
                'DB-02 object qbit_bot_pervichnogo_obrascheniya.% already exists; stop instead of overwriting',
                v_table;
        END IF;
    END LOOP;
END
$db02$;

-- ===========================================================================
-- 1. CREATE TABLES AS THE DEDICATED NOLOGIN OWNER
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.polzovateli (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vremya_pervogo_obrashcheniya timestamptz NOT NULL,
    vremya_poslednego_obrashcheniya timestamptz NOT NULL,
    pervyy_kanal text NOT NULL,
    testovyy boolean NOT NULL DEFAULT false,
    sluzhebnyy boolean NOT NULL DEFAULT false,
    tekushchaya_metka text,
    byl_vozvrat boolean NOT NULL DEFAULT false,
    kolichestvo_vozvratov integer NOT NULL DEFAULT 0,
    vremya_poslednego_vozvrata timestamptz,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_polzovateli_vremya
        CHECK (
            vremya_poslednego_obrashcheniya >= vremya_pervogo_obrashcheniya
        ),
    CONSTRAINT ck_polzovateli_vozvraty
        CHECK (
            kolichestvo_vozvratov >= 0
            AND (
                (kolichestvo_vozvratov = 0
                 AND byl_vozvrat = false
                 AND vremya_poslednego_vozvrata IS NULL)
                OR
                (kolichestvo_vozvratov > 0
                 AND byl_vozvrat = true
                 AND vremya_poslednego_vozvrata IS NOT NULL)
            )
        ),
    CONSTRAINT ck_polzovateli_pervyy_kanal
        CHECK (btrim(pervyy_kanal) <> '')
);

CREATE INDEX ix_polzovateli_pervoe
    ON qbit_bot_pervichnogo_obrascheniya.polzovateli (vremya_pervogo_obrashcheniya);

CREATE INDEX ix_polzovateli_poslednee
    ON qbit_bot_pervichnogo_obrascheniya.polzovateli (vremya_poslednego_obrashcheniya);

CREATE INDEX ix_polzovateli_metka
    ON qbit_bot_pervichnogo_obrascheniya.polzovateli (tekushchaya_metka);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    kanal text NOT NULL,
    akkaunt_kanala_id text NOT NULL,
    vneshniy_polzovatel_id text NOT NULL,
    vneshniy_dialog_id text NOT NULL,
    sposob_vosstanovleniya text,
    dannye_vosstanovleniya jsonb,
    vozmozhna_otlozhennaya_otpravka boolean NOT NULL DEFAULT false,
    zapret_iniciativnyh_soobshcheniy boolean NOT NULL DEFAULT false,
    vremya_zapreta_iniciativy timestamptz,
    logicheski_zablokirovan boolean NOT NULL DEFAULT false,
    vremya_blokirovki timestamptz,
    prichina_blokirovki text,
    schetchik_narusheniy integer NOT NULL DEFAULT 0,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_idkanal_kanal
        CHECK (btrim(kanal) <> ''),
    CONSTRAINT ck_idkanal_akkaunt
        CHECK (btrim(akkaunt_kanala_id) <> ''),
    CONSTRAINT ck_idkanal_vnesh_polz
        CHECK (btrim(vneshniy_polzovatel_id) <> ''),
    CONSTRAINT ck_idkanal_vnesh_dialog
        CHECK (btrim(vneshniy_dialog_id) <> ''),
    CONSTRAINT ck_idkanal_narusheniya
        CHECK (schetchik_narusheniy >= 0),
    CONSTRAINT ck_idkanal_optout
        CHECK (
            zapret_iniciativnyh_soobshcheniy = false
            OR vremya_zapreta_iniciativy IS NOT NULL
        ),
    CONSTRAINT ck_idkanal_blok
        CHECK (
            logicheski_zablokirovan = false
            OR (
                vremya_blokirovki IS NOT NULL
                AND prichina_blokirovki IS NOT NULL
                AND btrim(prichina_blokirovki) <> ''
            )
        ),
    CONSTRAINT ck_idkanal_vosstanovlenie_json
        CHECK (
            dannye_vosstanovleniya IS NULL
            OR jsonb_typeof(dannye_vosstanovleniya) = 'object'
        )
);

CREATE UNIQUE INDEX uq_idkanal_kanal_akkaunt_polz
    ON qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
        kanal,
        akkaunt_kanala_id,
        vneshniy_polzovatel_id
    );

CREATE INDEX ix_idkanal_vnesh_dialog
    ON qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
        kanal,
        akkaunt_kanala_id,
        vneshniy_dialog_id
    );

CREATE INDEX ix_idkanal_polz
    ON qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (polzovatel_id);

CREATE INDEX ix_idkanal_blok
    ON qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (vremya_blokirovki)
    WHERE logicheski_zablokirovan = true;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.dialogi (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    identifikator_kanala_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov(id),
    predydushchiy_dialog_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    vremya_nachala timestamptz NOT NULL,
    vremya_zaversheniya timestamptz,
    etap text NOT NULL,
    status text NOT NULL,
    rezultat text,
    prichina_zaversheniya text,
    poslednee_vhodyashchee_id uuid,
    poslednee_ishodyashchee_id uuid,
    versiya_dialoga bigint NOT NULL DEFAULT 1,
    ozhidaetsya_otvet boolean NOT NULL DEFAULT false,
    t0 timestamptz,
    pokolenie_ozhidaniya bigint NOT NULL DEFAULT 0,
    vladelec text NOT NULL DEFAULT 'bot',
    tekushchiy_menedzher_id uuid,
    versiya_workflow text NOT NULL,
    versiya_prompta text NOT NULL,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_dialogi_etap
        CHECK (btrim(etap) <> ''),
    CONSTRAINT ck_dialogi_status
        CHECK (
            status IN (
                'aktivnyy',
                'ozhidaet_otveta',
                'peredan_cheloveku',
                'zavershen'
            )
        ),
    CONSTRAINT ck_dialogi_rezultat
        CHECK (
            rezultat IS NULL
            OR rezultat IN (
                'zayavka_prinyata',
                'konsultaciya_zavershena',
                'otkaz',
                'net_otveta',
                'tehnicheski_prervan'
            )
        ),
    CONSTRAINT ck_dialogi_vremya
        CHECK (
            vremya_zaversheniya IS NULL
            OR vremya_zaversheniya >= vremya_nachala
        ),
    CONSTRAINT ck_dialogi_versiya
        CHECK (versiya_dialoga >= 1),
    CONSTRAINT ck_dialogi_pokolenie
        CHECK (pokolenie_ozhidaniya >= 0),
    CONSTRAINT ck_dialogi_vladelec
        CHECK (
            (vladelec = 'bot' AND tekushchiy_menedzher_id IS NULL)
            OR
            (vladelec = 'chelovek' AND tekushchiy_menedzher_id IS NOT NULL)
        ),
    CONSTRAINT ck_dialogi_zavershenie
        CHECK (
            status <> 'zavershen'
            OR vremya_zaversheniya IS NOT NULL
        ),
    CONSTRAINT ck_dialogi_workflow
        CHECK (btrim(versiya_workflow) <> ''),
    CONSTRAINT ck_dialogi_prompt
        CHECK (btrim(versiya_prompta) <> '')
);

CREATE INDEX ix_dialogi_polz_nachalo
    ON qbit_bot_pervichnogo_obrascheniya.dialogi (polzovatel_id, vremya_nachala DESC);

CREATE INDEX ix_dialogi_idkanal_status
    ON qbit_bot_pervichnogo_obrascheniya.dialogi (identifikator_kanala_id, status);

CREATE INDEX ix_dialogi_menedzher
    ON qbit_bot_pervichnogo_obrascheniya.dialogi (
        tekushchiy_menedzher_id,
        vremya_obnovleniya
    )
    WHERE vladelec = 'chelovek';

CREATE INDEX ix_dialogi_ozhidanie
    ON qbit_bot_pervichnogo_obrascheniya.dialogi (t0, pokolenie_ozhidaniya)
    WHERE ozhidaetsya_otvet = true;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    sobytie_id uuid,
    napravlenie text NOT NULL,
    avtor text NOT NULL,
    vid text NOT NULL,
    tekst_ishodnyy text,
    tekst_obezlichennyy text,
    vneshnee_soobshchenie_id text,
    otvet_na_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    redakciya_dlya_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    vremya_istochnika timestamptz,
    vremya_priema timestamptz NOT NULL,
    vremya_otpravki timestamptz,
    vremya_dostavki timestamptz,
    status_otpravki text,
    ozhidaetsya_otvet boolean NOT NULL DEFAULT false,
    tip_zaversheniya text,
    prichina_resheniya text,
    trassirovka_id text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_soobshcheniya_napravlenie
        CHECK (napravlenie IN ('vhodyashchee', 'ishodyashchee')),
    CONSTRAINT ck_soobshcheniya_avtor
        CHECK (avtor IN ('klient', 'bot', 'menedzher', 'sistema')),
    CONSTRAINT ck_soobshcheniya_vid
        CHECK (
            vid IN (
                'text',
                'voice',
                'photo',
                'video',
                'document',
                'sticker',
                'system'
            )
        ),
    CONSTRAINT ck_soobshcheniya_status_otpravki
        CHECK (
            status_otpravki IS NULL
            OR status_otpravki IN (
                'zaplanirovano',
                'v_rabote',
                'podtverzhdeno',
                'povtor',
                'neizvestno',
                'otmeneno',
                'oshibka'
            )
        ),
    CONSTRAINT ck_soobshcheniya_ozhidanie
        CHECK (
            ozhidaetsya_otvet = false
            OR napravlenie = 'ishodyashchee'
        ),
    CONSTRAINT ck_soobshcheniya_vremya_dostavki
        CHECK (
            vremya_dostavki IS NULL
            OR vremya_otpravki IS NULL
            OR vremya_dostavki >= vremya_otpravki
        ),
    CONSTRAINT ck_soobshcheniya_ne_sam_otvet
        CHECK (otvet_na_id IS NULL OR otvet_na_id <> id),
    CONSTRAINT ck_soobshcheniya_ne_sam_red
        CHECK (redakciya_dlya_id IS NULL OR redakciya_dlya_id <> id)
);

CREATE INDEX ix_soobshcheniya_dialog_vremya
    ON qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
        dialog_id,
        vremya_priema,
        id
    );

CREATE INDEX ix_soobshcheniya_sobytie
    ON qbit_bot_pervichnogo_obrascheniya.soobshcheniya (sobytie_id);

CREATE UNIQUE INDEX ix_soobshcheniya_vnesh
    ON qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
        dialog_id,
        vneshnee_soobshchenie_id
    )
    WHERE vneshnee_soobshchenie_id IS NOT NULL;

CREATE INDEX ix_soobshcheniya_redakciya
    ON qbit_bot_pervichnogo_obrascheniya.soobshcheniya (redakciya_dlya_id);

-- Circular DB-02 references become possible only after soobshcheniya exists.
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.dialogi
    ADD CONSTRAINT fk_dialogi_poslednee_vhodyashchee
    FOREIGN KEY (poslednee_vhodyashchee_id)
    REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id);

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.dialogi
    ADD CONSTRAINT fk_dialogi_poslednee_ishodyashchee
    FOREIGN KEY (poslednee_ishodyashchee_id)
    REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    soobshchenie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    tip_vlozheniya text NOT NULL,
    vneshniy_file_id text,
    vneshniy_file_unique_id text,
    imya_fayla text,
    mime text,
    razmer_bayt bigint,
    dlitelnost_sekund integer,
    shirina integer,
    vysota integer,
    sha256 text,
    status_sohraneniya text NOT NULL,
    hranilishche_tip text,
    soderzhimoe bytea,
    hranilishche_klyuch text,
    razresheno_ai boolean NOT NULL DEFAULT false,
    bezopasnye_metadannye jsonb NOT NULL DEFAULT '{}'::jsonb,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_vlozheniya_tip
        CHECK (btrim(tip_vlozheniya) <> ''),
    CONSTRAINT ck_vlozheniya_status
        CHECK (
            status_sohraneniya IN (
                'tolko_metadannye',
                'sohraneno',
                'oshibka',
                'udaleno'
            )
        ),
    CONSTRAINT ck_vlozheniya_razmer
        CHECK (razmer_bayt IS NULL OR razmer_bayt >= 0),
    CONSTRAINT ck_vlozheniya_dlitelnost
        CHECK (dlitelnost_sekund IS NULL OR dlitelnost_sekund >= 0),
    CONSTRAINT ck_vlozheniya_shirina
        CHECK (shirina IS NULL OR shirina > 0),
    CONSTRAINT ck_vlozheniya_vysota
        CHECK (vysota IS NULL OR vysota > 0),
    CONSTRAINT ck_vlozheniya_sohraneno
        CHECK (
            status_sohraneniya <> 'sohraneno'
            OR soderzhimoe IS NOT NULL
            OR hranilishche_klyuch IS NOT NULL
        ),
    CONSTRAINT ck_vlozheniya_ai_media
        CHECK (
            tip_vlozheniya NOT IN ('photo', 'video')
            OR razresheno_ai = false
        ),
    CONSTRAINT ck_vlozheniya_meta_json
        CHECK (jsonb_typeof(bezopasnye_metadannye) = 'object')
);

CREATE INDEX ix_vlozheniya_soobshchenie
    ON qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (soobshchenie_id);

CREATE INDEX ix_vlozheniya_file_unique
    ON qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (vneshniy_file_unique_id)
    WHERE vneshniy_file_unique_id IS NOT NULL;

CREATE INDEX ix_vlozheniya_sha256
    ON qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (sha256)
    WHERE sha256 IS NOT NULL;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    soobshchenie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    status text NOT NULL,
    tekst_transkripcii text,
    tekst_obezlichennyy text,
    dvizhok text,
    versiya_dvizhka text,
    popytki integer NOT NULL DEFAULT 0,
    vremya_nachala timestamptz,
    vremya_zaversheniya timestamptz,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_transkripcii_status
        CHECK (
            status IN (
                'zaplanirovana',
                'v_rabote',
                'gotova',
                'oshibka'
            )
        ),
    CONSTRAINT ck_transkripcii_popytki
        CHECK (popytki >= 0),
    CONSTRAINT ck_transkripcii_vremya
        CHECK (
            vremya_zaversheniya IS NULL
            OR vremya_nachala IS NULL
            OR vremya_zaversheniya >= vremya_nachala
        ),
    CONSTRAINT ck_transkripcii_gotova
        CHECK (
            status <> 'gotova'
            OR tekst_transkripcii IS NOT NULL
        ),
    CONSTRAINT ck_transkripcii_oshibka
        CHECK (
            status <> 'oshibka'
            OR kod_oshibki IS NOT NULL
        )
);

CREATE UNIQUE INDEX uq_transkripcii_soobshchenie
    ON qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa (soobshchenie_id);

CREATE INDEX ix_transkripcii_status
    ON qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa (status, vremya_obnovleniya);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    kod_polya text NOT NULL,
    znachenie_zashchishchennoe jsonb,
    znachenie_dlya_ai jsonb,
    eto_pii boolean NOT NULL DEFAULT false,
    podtverzhden boolean NOT NULL DEFAULT false,
    istochnik text NOT NULL,
    soobshchenie_dokazatelstvo_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    vremya_fakta timestamptz NOT NULL,
    deystvitelno_do timestamptz,
    zamenen_faktom_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.fakty_dialoga(id),
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_fakty_kod
        CHECK (btrim(kod_polya) <> ''),
    CONSTRAINT ck_fakty_istochnik
        CHECK (btrim(istochnik) <> ''),
    CONSTRAINT ck_fakty_srok
        CHECK (
            deystvitelno_do IS NULL
            OR deystvitelno_do >= vremya_fakta
        ),
    CONSTRAINT ck_fakty_ne_sam
        CHECK (
            zamenen_faktom_id IS NULL
            OR zamenen_faktom_id <> id
        )
);

CREATE INDEX ix_fakty_dialog_kod
    ON qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (
        dialog_id,
        kod_polya,
        vremya_fakta DESC
    );

CREATE INDEX ix_fakty_polz_kod
    ON qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (
        polzovatel_id,
        kod_polya,
        vremya_fakta DESC
    );

CREATE INDEX ix_fakty_dokazatelstvo
    ON qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (soobshchenie_dokazatelstvo_id);

CREATE INDEX ix_fakty_tekushchie
    ON qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (dialog_id, kod_polya)
    WHERE zamenen_faktom_id IS NULL;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    soobshchenie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    tip_pii text NOT NULL,
    psevdometka text NOT NULL,
    znachenie_zashchishchennoe text NOT NULL,
    hash_normalizovannogo_znacheniya text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    deystvitelno_do timestamptz,

    CONSTRAINT ck_pii_tip
        CHECK (btrim(tip_pii) <> ''),
    CONSTRAINT ck_pii_metka
        CHECK (btrim(psevdometka) <> ''),
    CONSTRAINT ck_pii_znachenie
        CHECK (znachenie_zashchishchennoe <> ''),
    CONSTRAINT ck_pii_srok
        CHECK (
            deystvitelno_do IS NULL
            OR deystvitelno_do >= vremya_sozdaniya
        )
);

CREATE UNIQUE INDEX uq_pii_dialog_metka
    ON qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (dialog_id, psevdometka);

CREATE INDEX ix_pii_soobshchenie
    ON qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (soobshchenie_id);

CREATE INDEX ix_pii_hash
    ON qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (
        tip_pii,
        hash_normalizovannogo_znacheniya
    )
    WHERE hash_normalizovannogo_znacheniya IS NOT NULL;


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    identifikator_kanala_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov(id),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    soobshchenie_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),
    klassifikaciya text NOT NULL,
    nomer_narusheniya integer NOT NULL,
    istochnik text NOT NULL,
    uverennost numeric,
    prichina text,
    vremya_sobytiya timestamptz NOT NULL,
    privelo_k_blokirovke boolean NOT NULL DEFAULT false,

    CONSTRAINT ck_narusheniya_klass
        CHECK (
            klassifikaciya IN (
                'ne_po_teme',
                'ataka_ili_injection'
            )
        ),
    CONSTRAINT ck_narusheniya_nomer
        CHECK (nomer_narusheniya >= 1),
    CONSTRAINT ck_narusheniya_istochnik
        CHECK (btrim(istochnik) <> ''),
    CONSTRAINT ck_narusheniya_uverennost
        CHECK (
            uverennost IS NULL
            OR (uverennost >= 0 AND uverennost <= 1)
        )
);

CREATE INDEX ix_narusheniya_idkanal_vremya
    ON qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (
        identifikator_kanala_id,
        vremya_sobytiya DESC
    );

CREATE UNIQUE INDEX uq_narusheniya_soobshchenie
    ON qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (soobshchenie_id);


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    tip_sobytiya text NOT NULL,
    vremya_sobytiya timestamptz NOT NULL,
    vremya_zapisi timestamptz NOT NULL DEFAULT clock_timestamp(),
    prichina text,
    rezultat text,
    predydushchaya_poterya_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov(id),
    istochnik text NOT NULL,
    trassirovka_id text,

    CONSTRAINT ck_sobdialog_tip
        CHECK (btrim(tip_sobytiya) <> ''),
    CONSTRAINT ck_sobdialog_istochnik
        CHECK (btrim(istochnik) <> ''),
    CONSTRAINT ck_sobdialog_ne_sam
        CHECK (
            predydushchaya_poterya_id IS NULL
            OR predydushchaya_poterya_id <> id
        )
);

CREATE INDEX ix_sobdialog_dialog_vremya
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        dialog_id,
        vremya_sobytiya DESC
    );

CREATE INDEX ix_sobdialog_polz_tip
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
        polzovatel_id,
        tip_sobytiya
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    staryy_etap text,
    novyy_etap text NOT NULL,
    vremya_sobytiya timestamptz NOT NULL,
    prichina text,
    istochnik text NOT NULL,
    uverennost numeric,
    soobshchenie_dokazatelstvo_id uuid
        REFERENCES qbit_bot_pervichnogo_obrascheniya.soobshcheniya(id),

    CONSTRAINT ck_sobetap_staryy
        CHECK (
            staryy_etap IS NULL
            OR btrim(staryy_etap) <> ''
        ),
    CONSTRAINT ck_sobetap_novyy
        CHECK (btrim(novyy_etap) <> ''),
    CONSTRAINT ck_sobetap_istochnik
        CHECK (btrim(istochnik) <> ''),
    CONSTRAINT ck_sobetap_uverennost
        CHECK (
            uverennost IS NULL
            OR (uverennost >= 0 AND uverennost <= 1)
        )
);

CREATE INDEX ix_sobetap_dialog_vremya
    ON qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov (
        dialog_id,
        vremya_sobytiya
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    kod_celi text NOT NULL,
    vremya_sobytiya timestamptz NOT NULL,
    istochnik text NOT NULL,
    podtverzhdenie_id uuid,
    dokazatelnye_soobshcheniya uuid[] NOT NULL DEFAULT '{}'::uuid[],
    podtverzhdeno boolean NOT NULL DEFAULT false,

    CONSTRAINT ck_celi_kod
        CHECK (btrim(kod_celi) <> ''),
    CONSTRAINT ck_celi_istochnik
        CHECK (btrim(istochnik) <> '')
);

CREATE INDEX ix_celi_dialog_kod
    ON qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya (
        dialog_id,
        kod_celi
    );

CREATE INDEX ix_celi_polz_vremya
    ON qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya (
        polzovatel_id,
        vremya_sobytiya
    );


CREATE TABLE qbit_bot_pervichnogo_obrascheniya.zayavki (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dialog_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.dialogi(id),
    polzovatel_id uuid NOT NULL
        REFERENCES qbit_bot_pervichnogo_obrascheniya.polzovateli(id),
    kontakt_zashchishchennyy jsonb,
    potrebnost jsonb,
    vneshniy_klyuch text NOT NULL,
    otvetstvennyy text,
    lokalnyy_status text NOT NULL,
    crm_tip text,
    crm_id text,
    status_sinhronizacii text NOT NULL,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_zayavki_klyuch
        CHECK (btrim(vneshniy_klyuch) <> ''),
    CONSTRAINT ck_zayavki_status
        CHECK (btrim(lokalnyy_status) <> ''),
    CONSTRAINT ck_zayavki_sync
        CHECK (btrim(status_sinhronizacii) <> ''),
    CONSTRAINT ck_zayavki_kontakt_json
        CHECK (
            kontakt_zashchishchennyy IS NULL
            OR jsonb_typeof(kontakt_zashchishchennyy) = 'object'
        ),
    CONSTRAINT ck_zayavki_potrebnost_json
        CHECK (
            potrebnost IS NULL
            OR jsonb_typeof(potrebnost) = 'object'
        )
);

CREATE UNIQUE INDEX uq_zayavki_vnesh_klyuch
    ON qbit_bot_pervichnogo_obrascheniya.zayavki (vneshniy_klyuch);

CREATE INDEX ix_zayavki_dialog
    ON qbit_bot_pervichnogo_obrascheniya.zayavki (dialog_id);

CREATE INDEX ix_zayavki_crm
    ON qbit_bot_pervichnogo_obrascheniya.zayavki (crm_tip, crm_id)
    WHERE crm_id IS NOT NULL;

-- ===========================================================================
-- 2. RUSSIAN COMMENTS: TABLES
-- ===========================================================================

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.polzovateli IS
'Люди, впервые и повторно обратившиеся в компанию; основа метрик по пользователям.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov IS
'Связь внутреннего пользователя с конкретным каналом, аккаунтом и адресом диалога.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.dialogi IS
'Отдельные бизнес-диалоги пользователя с версией состояния, ожиданием и владельцем bot/chelovek.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.soobshcheniya IS
'Неизменяемые логические входящие и исходящие сообщения диалога, включая сырой и обезличенный текст.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy IS
'Метаданные и при необходимости локальные байты вложений сообщений.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa IS
'Результаты локальной транскрипции голосовых сообщений и их обезличенная версия.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.fakty_dialoga IS
'Долговечные подтверждённые или рабочие факты диалога с доказательством и сроком действия.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii IS
'Локальное обратное соответствие PII-псевдометок; не предназначено для внешнего AI и служебного workflow.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky IS
'Подтверждённые нарушения тематики или injection, используемые для счётчика логической блокировки.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov IS
'История жизненного цикла диалога: начало, закрытие, потеря, возврат и передача управления.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov IS
'История переходов между бизнес-этапами с источником и доказательством.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya IS
'Достижения бизнес-целей пользователя/диалога с доказательными сообщениями.';

COMMENT ON TABLE qbit_bot_pervichnogo_obrascheniya.zayavki IS
'Локальные заявки и состояние их последующей синхронизации с CRM.';

-- ===========================================================================
-- 3. RUSSIAN COMMENTS: COLUMNS
-- ===========================================================================

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.id IS 'Внутренний UUID пользователя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.vremya_pervogo_obrashcheniya IS 'Время первого обращения; возвраты его не меняют.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.vremya_poslednego_obrashcheniya IS 'Время последнего принятого обращения пользователя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.pervyy_kanal IS 'Код первого известного канала пользователя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.testovyy IS 'Признак тестовой идентичности.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.sluzhebnyy IS 'Признак служебной идентичности.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.tekushchaya_metka IS 'Текущая бизнес-метка пользователя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.byl_vozvrat IS 'Был ли подтверждён хотя бы один возврат.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.kolichestvo_vozvratov IS 'Количество подтверждённых возвратов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.vremya_poslednego_vozvrata IS 'Время последнего подтверждённого возврата.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.vremya_sozdaniya IS 'Время создания строки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.polzovateli.vremya_obnovleniya IS 'Время последнего изменения строки.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.id IS 'UUID идентичности канала.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.polzovatel_id IS 'Ссылка на внутреннего пользователя.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.kanal IS 'Код канала: telegram, site и т.п.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.akkaunt_kanala_id IS 'Доверенный код конкретного бота или аккаунта канала.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vneshniy_polzovatel_id IS 'ID пользователя у внешнего провайдера.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vneshniy_dialog_id IS 'Адрес внешнего диалога для ответа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.sposob_vosstanovleniya IS 'Подтверждённый способ восстановления сессии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.dannye_vosstanovleniya IS 'Безопасные структурированные данные восстановления без секретов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vozmozhna_otlozhennaya_otpravka IS 'Разрешает ли канал отложенную отправку.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.zapret_iniciativnyh_soobshcheniy IS 'Устойчивый запрет инициативных сообщений.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vremya_zapreta_iniciativy IS 'Время установки opt-out.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.logicheski_zablokirovan IS 'Логическая блокировка CORE без запрета хранения входа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vremya_blokirovki IS 'Время логической блокировки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.prichina_blokirovki IS 'Безопасный код причины блокировки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.schetchik_narusheniy IS 'Число подтверждённых тематических нарушений.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vremya_sozdaniya IS 'Время создания идентичности.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov.vremya_obnovleniya IS 'Время последнего изменения идентичности.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.id IS 'UUID бизнес-диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.polzovatel_id IS 'Пользователь диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.identifikator_kanala_id IS 'Конкретная идентичность канала диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.predydushchiy_dialog_id IS 'Предыдущий диалог того же бизнес-цикла/пользователя при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.vremya_nachala IS 'Время начала диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.vremya_zaversheniya IS 'Время завершения диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.etap IS 'Конфигурируемый бизнес-код текущего этапа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.status IS 'Технический статус жизненного цикла диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.rezultat IS 'Финальный результат завершённого диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.prichina_zaversheniya IS 'Безопасная причина завершения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.poslednee_vhodyashchee_id IS 'Последнее логическое входящее сообщение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.poslednee_ishodyashchee_id IS 'Последнее подтверждённое логическое исходящее сообщение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.versiya_dialoga IS 'CAS-версия состояния диалога, начиная с 1.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.ozhidaetsya_otvet IS 'Есть ли актуальное ожидание ответа клиента.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.t0 IS 'Время подтверждённого основного сообщения, от которого считаются напоминания.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.pokolenie_ozhidaniya IS 'Поколение ожидания для отмены устаревших напоминаний.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.vladelec IS 'Текущий владелец ответа: bot или chelovek.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.tekushchiy_menedzher_id IS 'UUID текущего менеджера; FK на menedzhery_telegram добавляет DB-03.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.versiya_workflow IS 'Версия CORE/workflow, обрабатывающего диалог.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.versiya_prompta IS 'Версия prompt/config, применённая к диалогу.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.vremya_sozdaniya IS 'Время создания диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.dialogi.vremya_obnovleniya IS 'Время последнего изменения состояния диалога.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.id IS 'UUID логического сообщения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.dialog_id IS 'Диалог сообщения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.sobytie_id IS 'UUID входного integration event; FK на sobytiya_integraciy добавляет DB-03.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.napravlenie IS 'Направление: vhodyashchee или ishodyashchee.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.avtor IS 'Автор: klient, bot, menedzher или sistema.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vid IS 'Вид: text, voice, photo, video, document, sticker или system.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.tekst_ishodnyy IS 'Неизменяемый исходный текст; защищённое чтение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.tekst_obezlichennyy IS 'Обезличенный текст для памяти и внешнего AI.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vneshnee_soobshchenie_id IS 'ID сообщения у провайдера канала.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.otvet_na_id IS 'Логическое сообщение, на которое дан ответ.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.redakciya_dlya_id IS 'Предыдущее логическое сообщение, редакцией которого является эта строка.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vremya_istochnika IS 'Время сообщения по данным канала.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vremya_priema IS 'Локальное время приёма/формирования логического сообщения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vremya_otpravki IS 'Время подтверждённого принятия исходящего сообщения каналом.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vremya_dostavki IS 'Время доставки, только если канал предоставляет подтверждение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.status_otpravki IS 'Состояние связанного исходящего действия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.ozhidaetsya_otvet IS 'Требует ли это исходящее сообщение ответа клиента.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.tip_zaversheniya IS 'Решение CORE по ожиданию/завершению.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.prichina_resheniya IS 'Безопасная причина решения CORE.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.trassirovka_id IS 'Безопасный ID трассировки выполнения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.soobshcheniya.vremya_sozdaniya IS 'Время создания строки сообщения.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.id IS 'UUID вложения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.soobshchenie_id IS 'Исходное сообщение вложения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.tip_vlozheniya IS 'Тип вложения: voice, photo, video, document, sticker и т.п.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.vneshniy_file_id IS 'Provider file_id конкретного бота/аккаунта.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.vneshniy_file_unique_id IS 'Стабильный внешний unique file ID, если провайдер его даёт.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.imya_fayla IS 'Безопасное имя файла.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.mime IS 'Проверенный или заявленный MIME.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.razmer_bayt IS 'Фактический размер содержимого в байтах.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.dlitelnost_sekund IS 'Длительность медиа в секундах.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.shirina IS 'Ширина изображения/видео.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.vysota IS 'Высота изображения/видео.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.sha256 IS 'SHA-256 скачанных байтов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.status_sohraneniya IS 'Состояние локального хранения вложения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.hranilishche_tip IS 'Тип локального хранилища; v1 обычно postgres_bytea.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.soderzhimoe IS 'Локальные байты вложения после проверки лимитов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.hranilishche_klyuch IS 'Ключ будущего защищённого object storage.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.razresheno_ai IS 'Разрешено ли содержимое политикой для AI; фото/видео v1 запрещены.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.bezopasnye_metadannye IS 'Безопасные структурированные метаданные без секретов.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy.vremya_sozdaniya IS 'Время создания записи вложения.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.id IS 'UUID записи транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.soobshchenie_id IS 'Голосовое логическое сообщение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.status IS 'Состояние локальной транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.tekst_transkripcii IS 'Исходный локально полученный текст транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.tekst_obezlichennyy IS 'Обезличенный текст транскрипции для дальнейшей обработки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.dvizhok IS 'Локальный STT-движок.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.versiya_dvizhka IS 'Версия локального STT-движка/модели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.popytki IS 'Количество попыток локальной транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.vremya_nachala IS 'Время начала обработки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.vremya_zaversheniya IS 'Время завершения обработки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.kod_oshibki IS 'Безопасный код ошибки транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.opisanie_oshibki IS 'Безопасное описание ошибки транскрипции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.vremya_sozdaniya IS 'Время создания записи.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa.vremya_obnovleniya IS 'Время последнего изменения записи.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.id IS 'UUID долговечного факта.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.dialog_id IS 'Диалог, в котором факт получен/подтверждён.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.polzovatel_id IS 'Пользователь, к которому относится факт.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.kod_polya IS 'Нормализованный код факта/поля.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.znachenie_zashchishchennoe IS 'Защищённое локальное значение факта.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.znachenie_dlya_ai IS 'Безопасная версия значения, допустимая для AI.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.eto_pii IS 'Содержит ли исходное значение персональные данные.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.podtverzhden IS 'Подтверждён ли факт по правилам CORE.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.istochnik IS 'Источник факта: правило, LLM, клиент, менеджер и т.п.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.soobshchenie_dokazatelstvo_id IS 'Сообщение-доказательство факта.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.vremya_fakta IS 'Время, к которому относится факт.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.deystvitelno_do IS 'Срок действия факта при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.zamenen_faktom_id IS 'Более новый факт, заменивший эту запись.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.fakty_dialoga.vremya_sozdaniya IS 'Время создания факта.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.id IS 'UUID локального PII-соответствия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.dialog_id IS 'Диалог псевдонимизации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.polzovatel_id IS 'Пользователь псевдонимизации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.soobshchenie_id IS 'Исходное сообщение, породившее соответствие.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.tip_pii IS 'Тип персональных данных.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.psevdometka IS 'Псевдометка, используемая вместо исходного значения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.znachenie_zashchishchennoe IS 'Локальное защищённое исходное значение.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.hash_normalizovannogo_znacheniya IS 'Хэш нормализованного значения для локального сопоставления.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.vremya_sozdaniya IS 'Время создания соответствия.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii.deystvitelno_do IS 'Срок действия соответствия при наличии.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.id IS 'UUID подтверждённого нарушения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.identifikator_kanala_id IS 'Канальная идентичность, по которой считается блокировка.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.dialog_id IS 'Диалог нарушения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.soobshchenie_id IS 'Сообщение, признанное нарушением.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.klassifikaciya IS 'ne_po_teme или ataka_ili_injection.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.nomer_narusheniya IS 'Порядковый номер подтверждённого нарушения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.istochnik IS 'Источник классификации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.uverennost IS 'Уверенность классификации от 0 до 1.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.prichina IS 'Безопасная причина классификации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.vremya_sobytiya IS 'Время фиксации нарушения.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky.privelo_k_blokirovke IS 'Привело ли это нарушение к логической блокировке.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.id IS 'UUID события жизненного цикла.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.dialog_id IS 'Диалог события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.polzovatel_id IS 'Пользователь события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.tip_sobytiya IS 'Код исторического события диалога.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.vremya_sobytiya IS 'Бизнес-время события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.vremya_zapisi IS 'Время записи события в БД.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.prichina IS 'Безопасная причина события.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.rezultat IS 'Связанный результат при наличии.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.predydushchaya_poterya_id IS 'Предыдущее событие потери, к которому относится возврат.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.istochnik IS 'Источник события: правило, LLM, менеджер, система.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov.trassirovka_id IS 'Безопасный ID трассировки.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.id IS 'UUID перехода этапа.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.dialog_id IS 'Диалог перехода.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.staryy_etap IS 'Предыдущий этап; NULL допустим для начального состояния.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.novyy_etap IS 'Новый бизнес-этап.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.vremya_sobytiya IS 'Время перехода.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.prichina IS 'Безопасная причина перехода.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.istochnik IS 'Источник перехода: правило, LLM, человек и т.п.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.uverennost IS 'Уверенность от 0 до 1 для вероятностного источника.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov.soobshchenie_dokazatelstvo_id IS 'Сообщение-доказательство перехода.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.id IS 'UUID события достижения цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.polzovatel_id IS 'Пользователь цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.dialog_id IS 'Диалог цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.kod_celi IS 'Конфигурируемый бизнес-код цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.vremya_sobytiya IS 'Время достижения/фиксации цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.istochnik IS 'Источник фиксации цели.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.podtverzhdenie_id IS 'UUID объекта подтверждения; конкретная связь определяется операцией CORE.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.dokazatelnye_soobshcheniya IS 'Массив UUID доказательных сообщений; проверяется прикладной операцией.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya.podtverzhdeno IS 'Прошла ли цель подтверждение по правилам CORE.';

COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.id IS 'UUID локальной заявки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.dialog_id IS 'Диалог, в котором создана заявка.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.polzovatel_id IS 'Пользователь заявки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.kontakt_zashchishchennyy IS 'Защищённые локальные контактные данные.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.potrebnost IS 'Структурированная потребность клиента.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.vneshniy_klyuch IS 'Стабильный ключ заявки для идемпотентности внешней синхронизации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.otvetstvennyy IS 'Безопасный код/идентификатор ответственного.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.lokalnyy_status IS 'Локальный статус заявки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.crm_tip IS 'Тип CRM при подключённой интеграции.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.crm_id IS 'ID записи заявки в CRM после подтверждённой синхронизации.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.status_sinhronizacii IS 'Состояние синхронизации заявки с внешней системой.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.vremya_sozdaniya IS 'Время создания заявки.';
COMMENT ON COLUMN qbit_bot_pervichnogo_obrascheniya.zayavki.vremya_obnovleniya IS 'Время последнего изменения заявки.';

-- ===========================================================================
-- 4. ACCESS: KEEP RUNTIME ROLES DEFAULT-DENY
-- ===========================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA qbit_bot_pervichnogo_obrascheniya FROM PUBLIC;

DO $db02$
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
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_roles
             WHERE rolname = v_role
        ) THEN
            EXECUTE pg_catalog.format(
                'REVOKE ALL ON ALL TABLES IN SCHEMA qbit_bot_pervichnogo_obrascheniya FROM %I',
                v_role
            );
        END IF;
    END LOOP;
END
$db02$;

-- ===========================================================================
-- 5. STATIC ASSERTIONS BEFORE DATA PROBE
-- ===========================================================================

DO $db02$
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
       );

    IF v_table_count <> 13 THEN
        RAISE EXCEPTION
            'DB-02 expected 13 tables, found %',
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
            'ix_polzovateli_pervoe',
            'ix_polzovateli_poslednee',
            'ix_polzovateli_metka',
            'uq_idkanal_kanal_akkaunt_polz',
            'ix_idkanal_vnesh_dialog',
            'ix_idkanal_polz',
            'ix_idkanal_blok',
            'ix_dialogi_polz_nachalo',
            'ix_dialogi_idkanal_status',
            'ix_dialogi_menedzher',
            'ix_dialogi_ozhidanie',
            'ix_soobshcheniya_dialog_vremya',
            'ix_soobshcheniya_sobytie',
            'ix_soobshcheniya_vnesh',
            'ix_soobshcheniya_redakciya',
            'ix_vlozheniya_soobshchenie',
            'ix_vlozheniya_file_unique',
            'ix_vlozheniya_sha256',
            'uq_transkripcii_soobshchenie',
            'ix_transkripcii_status',
            'ix_fakty_dialog_kod',
            'ix_fakty_polz_kod',
            'ix_fakty_dokazatelstvo',
            'ix_fakty_tekushchie',
            'uq_pii_dialog_metka',
            'ix_pii_soobshchenie',
            'ix_pii_hash',
            'ix_narusheniya_idkanal_vremya',
            'uq_narusheniya_soobshchenie',
            'ix_sobdialog_dialog_vremya',
            'ix_sobdialog_polz_tip',
            'ix_sobetap_dialog_vremya',
            'ix_celi_dialog_kod',
            'ix_celi_polz_vremya',
            'uq_zayavki_vnesh_klyuch',
            'ix_zayavki_dialog',
            'ix_zayavki_crm'
       );

    IF v_index_count <> 37 THEN
        RAISE EXCEPTION
            'DB-02 expected 37 contract indexes, found %',
            v_index_count;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
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
           )
           AND pg_catalog.obj_description(c.oid, 'pg_class') IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-02 found a table without Russian COMMENT';
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
           )
           AND pg_catalog.col_description(c.oid, a.attnum) IS NULL
    ) THEN
        RAISE EXCEPTION 'DB-02 found a column without Russian COMMENT';
    END IF;
END
$db02$;

-- ===========================================================================
-- 6. DISPOSABLE DATA PROBE
-- ===========================================================================
-- All probe rows are rolled back to this SAVEPOINT before the migration commits.

SAVEPOINT db02_probe;

INSERT INTO qbit_bot_pervichnogo_obrascheniya.polzovateli (
    id,
    vremya_pervogo_obrashcheniya,
    vremya_poslednego_obrashcheniya,
    pervyy_kanal,
    testovyy
)
VALUES (
    '00000000-0000-4000-8000-000000000201',
    '2026-09-24 12:00:00+00',
    '2026-09-24 12:00:00+00',
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
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000201',
    'telegram',
    'db02_test_bot',
    'db02_user_1',
    'db02_chat_1'
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
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '2026-09-24 12:00:00+00',
    'pervichnyy_kontakt',
    'aktivnyy',
    'db02_probe',
    'db02_probe'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
    id,
    dialog_id,
    napravlenie,
    avtor,
    vid,
    tekst_ishodnyy,
    tekst_obezlichennyy,
    vneshnee_soobshchenie_id,
    vremya_istochnika,
    vremya_priema
)
VALUES (
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000203',
    'vhodyashchee',
    'klient',
    'voice',
    'Тестовое сообщение DB-02',
    'Тестовое сообщение DB-02',
    'db02_external_message_1',
    '2026-09-24 12:00:00+00',
    '2026-09-24 12:00:01+00'
);

UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi
   SET poslednee_vhodyashchee_id =
       '00000000-0000-4000-8000-000000000204'
 WHERE id =
       '00000000-0000-4000-8000-000000000203';

INSERT INTO qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (
    id,
    soobshchenie_id,
    tip_vlozheniya,
    vneshniy_file_id,
    status_sohraneniya,
    razresheno_ai
)
VALUES (
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000204',
    'voice',
    'db02_file_1',
    'tolko_metadannye',
    true
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa (
    id,
    soobshchenie_id,
    status
)
VALUES (
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000204',
    'zaplanirovana'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.fakty_dialoga (
    id,
    dialog_id,
    polzovatel_id,
    kod_polya,
    znachenie_zashchishchennoe,
    znachenie_dlya_ai,
    eto_pii,
    podtverzhden,
    istochnik,
    soobshchenie_dokazatelstvo_id,
    vremya_fakta
)
VALUES (
    '00000000-0000-4000-8000-000000000207',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000201',
    'gorod',
    '{"znachenie":"Тест"}'::jsonb,
    '{"znachenie":"<GOROD>"}'::jsonb,
    false,
    true,
    'db02_probe',
    '00000000-0000-4000-8000-000000000204',
    '2026-09-24 12:00:01+00'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (
    id,
    dialog_id,
    polzovatel_id,
    soobshchenie_id,
    tip_pii,
    psevdometka,
    znachenie_zashchishchennoe,
    hash_normalizovannogo_znacheniya
)
VALUES (
    '00000000-0000-4000-8000-000000000208',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000204',
    'telefon',
    '<TELEFON_1>',
    '+70000000000',
    'db02_hash'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (
    id,
    identifikator_kanala_id,
    dialog_id,
    soobshchenie_id,
    klassifikaciya,
    nomer_narusheniya,
    istochnik,
    uverennost,
    vremya_sobytiya
)
VALUES (
    '00000000-0000-4000-8000-000000000209',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204',
    'ne_po_teme',
    1,
    'db02_probe',
    0.90,
    '2026-09-24 12:00:02+00'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov (
    id,
    dialog_id,
    polzovatel_id,
    tip_sobytiya,
    vremya_sobytiya,
    istochnik
)
VALUES (
    '00000000-0000-4000-8000-000000000210',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000201',
    'nachalo',
    '2026-09-24 12:00:00+00',
    'db02_probe'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov (
    id,
    dialog_id,
    staryy_etap,
    novyy_etap,
    vremya_sobytiya,
    istochnik,
    uverennost,
    soobshchenie_dokazatelstvo_id
)
VALUES (
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000203',
    NULL,
    'pervichnyy_kontakt',
    '2026-09-24 12:00:01+00',
    'db02_probe',
    1,
    '00000000-0000-4000-8000-000000000204'
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya (
    id,
    polzovatel_id,
    dialog_id,
    kod_celi,
    vremya_sobytiya,
    istochnik,
    dokazatelnye_soobshcheniya,
    podtverzhdeno
)
VALUES (
    '00000000-0000-4000-8000-000000000212',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000203',
    'db02_test_goal',
    '2026-09-24 12:00:02+00',
    'db02_probe',
    ARRAY['00000000-0000-4000-8000-000000000204'::uuid],
    true
);

INSERT INTO qbit_bot_pervichnogo_obrascheniya.zayavki (
    id,
    dialog_id,
    polzovatel_id,
    kontakt_zashchishchennyy,
    potrebnost,
    vneshniy_klyuch,
    lokalnyy_status,
    status_sinhronizacii
)
VALUES (
    '00000000-0000-4000-8000-000000000213',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000201',
    '{"telefon":"<TELEFON_1>"}'::jsonb,
    '{"tip":"db02_probe"}'::jsonb,
    'db02_application_1',
    'sozdana',
    'ne_nachata'
);

-- Expected failures prove essential constraints.
DO $db02$
BEGIN
    -- Same external user in the same channel/account cannot create a second identity.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov (
            polzovatel_id,
            kanal,
            akkaunt_kanala_id,
            vneshniy_polzovatel_id,
            vneshniy_dialog_id
        )
        VALUES (
            '00000000-0000-4000-8000-000000000201',
            'telegram',
            'db02_test_bot',
            'db02_user_1',
            'another_chat'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: duplicate channel identity was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- Repeat of the same external message in one dialog must not create a second message.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
            dialog_id,
            napravlenie,
            avtor,
            vid,
            tekst_ishodnyy,
            vneshnee_soobshchenie_id,
            vremya_priema
        )
        VALUES (
            '00000000-0000-4000-8000-000000000203',
            'vhodyashchee',
            'klient',
            'text',
            'duplicate',
            'db02_external_message_1',
            '2026-09-24 12:00:03+00'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: duplicate external message was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- Message cannot point to a missing dialog.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.soobshcheniya (
            dialog_id,
            napravlenie,
            avtor,
            vid,
            vremya_priema
        )
        VALUES (
            '00000000-0000-4000-8000-000000009999',
            'vhodyashchee',
            'klient',
            'text',
            '2026-09-24 12:00:03+00'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: message with missing dialog was accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN
            NULL;
    END;

    -- Human owner requires a manager UUID even though the target FK is added in DB-03.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.dialogi (
            polzovatel_id,
            identifikator_kanala_id,
            vremya_nachala,
            etap,
            status,
            vladelec,
            tekushchiy_menedzher_id,
            versiya_workflow,
            versiya_prompta
        )
        VALUES (
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000202',
            '2026-09-24 12:00:03+00',
            'pervichnyy_kontakt',
            'peredan_cheloveku',
            'chelovek',
            NULL,
            'db02_probe',
            'db02_probe'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: human dialog without manager UUID was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    -- A saved attachment must have local bytes or protected storage key.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy (
            soobshchenie_id,
            tip_vlozheniya,
            status_sohraneniya
        )
        VALUES (
            '00000000-0000-4000-8000-000000000204',
            'document',
            'sohraneno'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: saved attachment without content/key was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    -- PII placeholder is unique inside a dialog.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii (
            dialog_id,
            polzovatel_id,
            soobshchenie_id,
            tip_pii,
            psevdometka,
            znachenie_zashchishchennoe
        )
        VALUES (
            '00000000-0000-4000-8000-000000000203',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000204',
            'telefon',
            '<TELEFON_1>',
            '+71111111111'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: duplicate PII placeholder was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- One message cannot count as two confirmed topic violations.
    BEGIN
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky (
            identifikator_kanala_id,
            dialog_id,
            soobshchenie_id,
            klassifikaciya,
            nomer_narusheniya,
            istochnik,
            vremya_sobytiya
        )
        VALUES (
            '00000000-0000-4000-8000-000000000202',
            '00000000-0000-4000-8000-000000000203',
            '00000000-0000-4000-8000-000000000204',
            'ataka_ili_injection',
            2,
            'db02_probe',
            '2026-09-24 12:00:04+00'
        );

        RAISE EXCEPTION
            'DB-02 probe failed: duplicate violation for one message was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;
END
$db02$;

-- The successful probe must contain exactly one row in every DB-02 table.
DO $db02$
DECLARE
    v_bad_count integer;
BEGIN
    SELECT count(*)
      INTO v_bad_count
      FROM (
            SELECT 'polzovateli' AS t, count(*) AS c FROM qbit_bot_pervichnogo_obrascheniya.polzovateli
            UNION ALL
            SELECT 'identifikatory_kanalov', count(*) FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov
            UNION ALL
            SELECT 'dialogi', count(*) FROM qbit_bot_pervichnogo_obrascheniya.dialogi
            UNION ALL
            SELECT 'soobshcheniya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya
            UNION ALL
            SELECT 'vlozheniya_soobshcheniy', count(*) FROM qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy
            UNION ALL
            SELECT 'transkripcii_golosa', count(*) FROM qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa
            UNION ALL
            SELECT 'fakty_dialoga', count(*) FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga
            UNION ALL
            SELECT 'sootvetstviya_pii', count(*) FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii
            UNION ALL
            SELECT 'narusheniya_tematiky', count(*) FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky
            UNION ALL
            SELECT 'sobytiya_dialogov', count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov
            UNION ALL
            SELECT 'sobytiya_etapov', count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov
            UNION ALL
            SELECT 'celevye_sobytiya', count(*) FROM qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya
            UNION ALL
            SELECT 'zayavki', count(*) FROM qbit_bot_pervichnogo_obrascheniya.zayavki
      ) AS x
     WHERE x.c <> 1;

    IF v_bad_count <> 0 THEN
        RAISE EXCEPTION
            'DB-02 probe expected exactly one row in each table; bad tables=%',
            v_bad_count;
    END IF;
END
$db02$;

ROLLBACK TO SAVEPOINT db02_probe;
RELEASE SAVEPOINT db02_probe;

-- ===========================================================================
-- 7. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db02$
DECLARE
    v_runtime_role text;
    v_table record;
    v_owner text;
    v_total_rows bigint;
BEGIN
    -- All DB-02 tables must be owned by qbit_test_owner.
    FOR v_table IN
        SELECT c.oid, c.relname
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
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
                'DB-02 table %.% has wrong owner %',
                'qbit_bot_pervichnogo_obrascheniya',
                v_table.relname,
                v_owner;
        END IF;
    END LOOP;

    -- Probe rollback must leave all DB-02 business tables empty.
    SELECT
          (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.polzovateli)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.dialogi)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zayavki)
      INTO v_total_rows;

    IF v_total_rows <> 0 THEN
        RAISE EXCEPTION
            'DB-02 probe rows remain after SAVEPOINT rollback: %',
            v_total_rows;
    END IF;

    -- Runtime roles must still have no direct DML on any DB-02 table.
    FOREACH v_runtime_role IN ARRAY ARRAY[
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
               )
        LOOP
            IF pg_catalog.has_table_privilege(
                v_runtime_role,
                v_table.oid,
                'SELECT'
            )
            OR pg_catalog.has_table_privilege(
                v_runtime_role,
                v_table.oid,
                'INSERT'
            )
            OR pg_catalog.has_table_privilege(
                v_runtime_role,
                v_table.oid,
                'UPDATE'
            )
            OR pg_catalog.has_table_privilege(
                v_runtime_role,
                v_table.oid,
                'DELETE'
            ) THEN
                RAISE EXCEPTION
                    'Runtime role % has direct DML on qbit_bot_pervichnogo_obrascheniya.%',
                    v_runtime_role,
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;

    -- The isolation canary must still contain no DB-02 business table.
    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'kompaniya_001_test'
           AND c.relkind = 'r'
           AND c.relname IN (
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
           )
    ) THEN
        RAISE EXCEPTION
            'DB-02 unexpectedly created business tables in kompaniya_001_test';
    END IF;
END
$db02$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 8. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db02_status',
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
        SELECT count(*) = 13
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
           AND c.relname IN (
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
           )
    ),
    'contract_indexes_ok',
    (
        SELECT count(*) = 37
          FROM pg_catalog.pg_class AS i
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = i.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND i.relkind = 'i'
           AND i.relname IN (
                'ix_polzovateli_pervoe',
                'ix_polzovateli_poslednee',
                'ix_polzovateli_metka',
                'uq_idkanal_kanal_akkaunt_polz',
                'ix_idkanal_vnesh_dialog',
                'ix_idkanal_polz',
                'ix_idkanal_blok',
                'ix_dialogi_polz_nachalo',
                'ix_dialogi_idkanal_status',
                'ix_dialogi_menedzher',
                'ix_dialogi_ozhidanie',
                'ix_soobshcheniya_dialog_vremya',
                'ix_soobshcheniya_sobytie',
                'ix_soobshcheniya_vnesh',
                'ix_soobshcheniya_redakciya',
                'ix_vlozheniya_soobshchenie',
                'ix_vlozheniya_file_unique',
                'ix_vlozheniya_sha256',
                'uq_transkripcii_soobshchenie',
                'ix_transkripcii_status',
                'ix_fakty_dialog_kod',
                'ix_fakty_polz_kod',
                'ix_fakty_dokazatelstvo',
                'ix_fakty_tekushchie',
                'uq_pii_dialog_metka',
                'ix_pii_soobshchenie',
                'ix_pii_hash',
                'ix_narusheniya_idkanal_vremya',
                'uq_narusheniya_soobshchenie',
                'ix_sobdialog_dialog_vremya',
                'ix_sobdialog_polz_tip',
                'ix_sobetap_dialog_vremya',
                'ix_celi_dialog_kod',
                'ix_celi_polz_vremya',
                'uq_zayavki_vnesh_klyuch',
                'ix_zayavki_dialog',
                'ix_zayavki_crm'
           )
    ),
    'probe_rows_remaining',
    (
          (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.polzovateli)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.identifikatory_kanalov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.dialogi)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.soobshcheniya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.vlozheniya_soobshcheniy)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.transkripcii_golosa)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.fakty_dialoga)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sootvetstviya_pii)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.narusheniya_tematiky)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_dialogov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_etapov)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.celevye_sobytiya)
        + (SELECT count(*) FROM qbit_bot_pervichnogo_obrascheniya.zayavki)
    ),
    'forward_fk_db03',
    jsonb_build_array(
        'dialogi.tekushchiy_menedzher_id -> menedzhery_telegram.id',
        'soobshcheniya.sobytie_id -> sobytiya_integraciy.id'
    ),
    'duplicate_message_guard',
    true,
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
           )
    ),
    'result',
    'DB-02 SQL APPLIED: 13 tables, links/comments/duplicate guard verified; probe data removed; production untouched.'
) AS db02_result;
