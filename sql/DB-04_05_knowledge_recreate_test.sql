-- KB-01R3 v0.2: recreate experimental KB as normative DB-04/DB-05 in TEST only
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md + docs/specs/KNOWLEDGE_INGESTION.md
-- TARGET: qbit_bot_pervichnogo_obrascheniya ONLY; owner qbit_test_owner
-- IMPORTANT: PREPARED ONLY. Do not run until Pavel explicitly authorizes this exact server action.
-- Production schema qbit is never referenced by DDL/DML below.
-- Any error before COMMIT rolls back the whole recreate, including DROP statements.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '300s';
SET LOCAL search_path = pg_catalog;

DO $preflight$
DECLARE
    v_fn_md5 text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION 'KB-01R3 requires PostgreSQL 17+, current=%', current_setting('server_version');
    END IF;
    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION 'KB-01R3 must run from trusted postgres session; session_user=%', session_user;
    END IF;
    IF NOT pg_catalog.pg_has_role(session_user, 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'session_user % cannot SET ROLE qbit_test_owner', session_user;
    END IF;
    IF (
        SELECT r.rolname
        FROM pg_catalog.pg_namespace n
        JOIN pg_catalog.pg_roles r ON r.oid=n.nspowner
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
    ) IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'test schema owner changed; stop';
    END IF;
    IF pg_catalog.to_regprocedure('extensions.digest(bytea,text)') IS NULL THEN
        RAISE EXCEPTION 'extensions.digest(bytea,text) is required for SHA-256 verification';
    END IF;
    IF pg_catalog.to_regtype('extensions.vector') IS NULL THEN
        RAISE EXCEPTION 'extensions.vector type is required';
    END IF;
    IF pg_catalog.to_regprocedure('extensions.vector_dims(extensions.vector)') IS NULL THEN
        RAISE EXCEPTION 'extensions.vector_dims(vector) is required';
    END IF;
    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya') IS NULL THEN
        RAISE EXCEPTION 'Required DB-03 tables are missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya'::regclass
          AND a.attname='zagruzka_id' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN
        RAISE EXCEPTION 'ishodyashchie_deystviya.zagruzka_id is missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya
        WHERE zagruzka_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'ishodyashchie_deystviya.zagruzka_id already contains data; stop';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND c.relname = ANY (ARRAY[
            'zagruzki_znaniy','zadaniya_znaniy','dokumenty_znaniy',
            'versii_dokumentov_znaniy','profili_indeksa','fragmenty_znaniy',
            'kontrolnye_voprosy','proverki_znaniy'
          ])
    ) THEN
        RAISE EXCEPTION 'One or more normative DB-04 tables already exist; stop instead of overwriting';
    END IF;
    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_versii') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty') IS NULL THEN
        RAISE EXCEPTION 'Experimental KB tables do not match KB-01R2 snapshot';
    END IF;
    IF EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty)
       OR EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii)
       OR EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty) THEN
        RAISE EXCEPTION 'Experimental KB tables are no longer empty; stop before DROP';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND c.relkind IN ('r','p','v','m')
          AND (c.relname LIKE '%znani%' OR c.relname LIKE 'kb01%')
          AND c.relname NOT IN ('znaniya_dokumenty','znaniya_versii','znaniya_fragmenty')
    ) THEN
        RAISE EXCEPTION 'Unexpected KB table/view appeared after KB-01R2; stop';
    END IF;
    SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) INTO v_fn_md5
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
      AND p.proname='kb01_postavit_dokument'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p jsonb';
    IF v_fn_md5 IS DISTINCT FROM '56654d3112113f99acda41df4a53b8e8' THEN
        RAISE EXCEPTION 'kb01_postavit_dokument fingerprint changed; stop';
    END IF;
    SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) INTO v_fn_md5
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
      AND p.proname='kb01_zabrat_sleduyushchuyu_versiyu'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p jsonb';
    IF v_fn_md5 IS DISTINCT FROM '4ea8ce93b420723239fbe6fabec868ed' THEN
        RAISE EXCEPTION 'kb01_zabrat_sleduyushchuyu_versiyu fingerprint changed; stop';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND (p.proname LIKE 'kb01_%' OR p.proname LIKE '%znani%')
          AND p.proname NOT IN ('kb01_postavit_dokument','kb01_zabrat_sleduyushchuyu_versiyu')
    ) THEN
        RAISE EXCEPTION 'Unexpected KB functions appeared after KB-01R2; stop';
    END IF;
END
$preflight$;

SET LOCAL ROLE qbit_test_owner;

DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb);
DROP TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty
    DROP CONSTRAINT znaniya_dokumenty_aktivnaya_versiya_fk;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_versii;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty;

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.profili_indeksa (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    otpechatok_profilya text NOT NULL,
    embedding_model text NOT NULL,
    razmernost integer NOT NULL,
    metrika text NOT NULL,
    versiya_parsera text NOT NULL,
    versiya_ochistki text NOT NULL,
    versiya_chunkinga text NOT NULL,
    tokenizer text NOT NULL,
    cel_fragmenta_tokenov integer NOT NULL,
    maks_fragmenta_tokenov integer NOT NULL,
    overlap_tokenov integer NOT NULL,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_profili_otpechatok CHECK (otpechatok_profilya ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_profili_model CHECK (btrim(embedding_model)<>''),
    CONSTRAINT ck_profili_razmernost CHECK (razmernost=1024),
    CONSTRAINT ck_profili_metrika CHECK (metrika='cosine'),
    CONSTRAINT ck_profili_versii CHECK (btrim(versiya_parsera)<>'' AND btrim(versiya_ochistki)<>'' AND btrim(versiya_chunkinga)<>'' AND btrim(tokenizer)<>''),
    CONSTRAINT ck_profili_chunking CHECK (cel_fragmenta_tokenov>0 AND maks_fragmenta_tokenov>=cel_fragmenta_tokenov AND overlap_tokenov>=0 AND overlap_tokenov<cel_fragmenta_tokenov)
);
CREATE UNIQUE INDEX uq_profili_indeksa_otpechatok ON qbit_bot_pervichnogo_obrascheniya.profili_indeksa(otpechatok_profilya);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    identifikator_dokumenta text NOT NULL,
    aktivnaya_versiya_id uuid,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_dokumenty_identifikator CHECK (identifikator_dokumenta ~ '^[a-z][a-z0-9_]{0,79}$')
);
CREATE UNIQUE INDEX uq_dokumenty_identifikator ON qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(identifikator_dokumenta);
CREATE INDEX ix_dokumenty_aktivnaya ON qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(aktivnaya_versiya_id) WHERE aktivnaya_versiya_id IS NOT NULL;

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sobytie_integracii_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy(id),
    vneshnee_sobytie_id text NOT NULL,
    otpravitel_user_id text NOT NULL,
    chat_id text NOT NULL,
    vneshniy_file_id text NOT NULL,
    imya_fayla text NOT NULL,
    ishodnyy_fayl bytea NOT NULL,
    razmer_bayt bigint NOT NULL,
    hash_istochnika text NOT NULL,
    hash_soderzhaniya text,
    vremya_priema timestamptz NOT NULL,
    poryadok_priema bigint GENERATED ALWAYS AS IDENTITY,
    status text NOT NULL DEFAULT 'poluchena',
    kod_oshibki text,
    opisanie_oshibki text,
    dokument_id uuid,
    versiya_id uuid,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_zagruzki_text CHECK (btrim(vneshnee_sobytie_id)<>'' AND btrim(otpravitel_user_id)<>'' AND btrim(chat_id)<>'' AND btrim(vneshniy_file_id)<>'' AND btrim(imya_fayla)<>''),
    CONSTRAINT ck_zagruzki_razmer CHECK (razmer_bayt>=0 AND razmer_bayt<=5242880),
    CONSTRAINT ck_zagruzki_hash_istochnika CHECK (hash_istochnika ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_zagruzki_hash_soderzhaniya CHECK (hash_soderzhaniya IS NULL OR hash_soderzhaniya ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_zagruzki_status CHECK (status IN ('poluchena','proverka','obrabotka','ozhidaet_proverki','zavershena','dublikat','oshibka'))
);
CREATE UNIQUE INDEX uq_zagruzki_sobytie ON qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(sobytie_integracii_id);
CREATE INDEX ix_zagruzki_hash_istochnika ON qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(hash_istochnika);
CREATE INDEX ix_zagruzki_status ON qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(status,vremya_priema);
CREATE INDEX ix_zagruzki_dokument ON qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(dokument_id,poryadok_priema);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dokument_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(id),
    zagruzka_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(id),
    nomer_versii integer NOT NULL,
    nazvanie text NOT NULL,
    tip_dokumenta text NOT NULL,
    versiya_istochnika text,
    data_obnovleniya date,
    hash_soderzhaniya text NOT NULL,
    otpechatok_obrabotki text NOT NULL,
    profil_indeksa_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.profili_indeksa(id),
    status text NOT NULL DEFAULT 'chernovik',
    ozhidaemaya_aktivnaya_versiya_id uuid,
    vremya_proverki timestamptz,
    vremya_publikacii timestamptz,
    vremya_arhivirovaniya timestamptz,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_versii_nomer CHECK (nomer_versii>0),
    CONSTRAINT ck_versii_nazvanie CHECK (btrim(nazvanie)<>''),
    CONSTRAINT ck_versii_tip CHECK (tip_dokumenta IN ('opisanie','harakteristiki','instrukciya','faq','usloviya','politika')),
    CONSTRAINT ck_versii_hash CHECK (hash_soderzhaniya ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_versii_otpechatok CHECK (otpechatok_obrabotki ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_versii_status CHECK (status IN ('chernovik','gotova','opublikovana','arhiv','oshibka'))
);
CREATE UNIQUE INDEX uq_versii_dokument_nomer ON qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(dokument_id,nomer_versii);
CREATE INDEX ix_versii_dokument_status ON qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(dokument_id,status,nomer_versii DESC);
CREATE INDEX ix_versii_otpechatok ON qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(dokument_id,otpechatok_obrabotki);
CREATE INDEX ix_versii_profil ON qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(profil_indeksa_id);

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy ADD CONSTRAINT fk_dokumenty_aktivnaya_versiya FOREIGN KEY (aktivnaya_versiya_id) REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy ADD CONSTRAINT fk_versii_ozhidaemaya_aktivnaya FOREIGN KEY (ozhidaemaya_aktivnaya_versiya_id) REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy ADD CONSTRAINT fk_zagruzki_dokument FOREIGN KEY (dokument_id) REFERENCES qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(id);
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy ADD CONSTRAINT fk_zagruzki_versiya FOREIGN KEY (versiya_id) REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    zagruzka_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(id),
    dokument_id uuid REFERENCES qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(id),
    tip_zadaniya text NOT NULL,
    status text NOT NULL DEFAULT 'ozhidaet',
    prioritet integer NOT NULL DEFAULT 0,
    popytki integer NOT NULL DEFAULT 0,
    sleduyushchiy_zapusk timestamptz NOT NULL DEFAULT clock_timestamp(),
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint NOT NULL DEFAULT 0,
    ozhidaemaya_aktivnaya_versiya_id uuid REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    kod_oshibki text,
    opisanie_oshibki text,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    vremya_obnovleniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_zadaniya_znaniy_tip CHECK (btrim(tip_zadaniya)<>''),
    CONSTRAINT ck_zadaniya_znaniy_status CHECK (status IN ('ozhidaet','v_rabote','povtor','zaversheno','otmeneno','oshibka')),
    CONSTRAINT ck_zadaniya_znaniy_popytki CHECK (popytki>=0),
    CONSTRAINT ck_zadaniya_znaniy_vladenie CHECK (nomer_vladeniya>=0),
    CONSTRAINT ck_zadaniya_znaniy_payload CHECK (jsonb_typeof(payload)='object'),
    CONSTRAINT ck_zadaniya_znaniy_arenda CHECK (status<>'v_rabote' OR (vladelec_arendy IS NOT NULL AND btrim(vladelec_arendy)<>'' AND arenda_do IS NOT NULL))
);
CREATE UNIQUE INDEX uq_zadaniya_znaniy_zag_tip ON qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy(zagruzka_id,tip_zadaniya);
CREATE INDEX ix_zadaniya_znaniy_gotovy ON qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy(prioritet DESC,sleduyushchiy_zapusk,vremya_sozdaniya) WHERE status IN ('ozhidaet','povtor');
CREATE UNIQUE INDEX uq_zadaniya_znaniy_vrabote ON qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy(dokument_id) WHERE status='v_rabote' AND dokument_id IS NOT NULL;
CREATE INDEX ix_zadaniya_znaniy_arenda ON qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy(arenda_do) WHERE status='v_rabote';

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    versiya_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id) ON DELETE CASCADE,
    nomer_fragmenta integer NOT NULL,
    put_razdela text NOT NULL,
    tekst_fragmenta text NOT NULL,
    kolichestvo_tokenov integer NOT NULL,
    hash_fragmenta text NOT NULL,
    vektor extensions.vector(1024) NOT NULL,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_fragmenty_nomer CHECK (nomer_fragmenta>0),
    CONSTRAINT ck_fragmenty_put CHECK (btrim(put_razdela)<>''),
    CONSTRAINT ck_fragmenty_tekst CHECK (btrim(tekst_fragmenta)<>''),
    CONSTRAINT ck_fragmenty_tokeny CHECK (kolichestvo_tokenov>0 AND kolichestvo_tokenov<=800),
    CONSTRAINT ck_fragmenty_hash CHECK (hash_fragmenta ~ '^[0-9a-f]{64}$')
);
CREATE UNIQUE INDEX uq_fragmenty_versiya_nomer ON qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy(versiya_id,nomer_fragmenta);
CREATE INDEX ix_fragmenty_versiya ON qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy(versiya_id,nomer_fragmenta);
CREATE INDEX ix_fragmenty_hnsw_cos ON qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy USING hnsw (vektor extensions.vector_cosine_ops);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    versiya_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id) ON DELETE CASCADE,
    nomer integer NOT NULL,
    vopros text NOT NULL,
    ozhidaemyy_razdel text NOT NULL,
    ozhidaemyy_fakt text,
    istochnik text NOT NULL,
    vremya_sozdaniya timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_kontrolnye_nomer CHECK (nomer BETWEEN 1 AND 10),
    CONSTRAINT ck_kontrolnye_text CHECK (btrim(vopros)<>'' AND btrim(ozhidaemyy_razdel)<>'' AND btrim(istochnik)<>'')
);
CREATE UNIQUE INDEX uq_kontrolnye_versiya_nomer ON qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy(versiya_id,nomer);
CREATE INDEX ix_kontrolnye_versiya ON qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy(versiya_id);

CREATE TABLE qbit_bot_pervichnogo_obrascheniya.proverki_znaniy (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    versiya_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(id) ON DELETE CASCADE,
    vopros_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy(id) ON DELETE CASCADE,
    profil_indeksa_id uuid NOT NULL REFERENCES qbit_bot_pervichnogo_obrascheniya.profili_indeksa(id),
    porog_shodstva numeric NOT NULL,
    limit_rezultatov integer NOT NULL,
    poluchennye_fragmenty uuid[] NOT NULL DEFAULT '{}'::uuid[],
    shodstva numeric[] NOT NULL DEFAULT '{}'::numeric[],
    rezultat text NOT NULL,
    opisanie text,
    vremya_proverki timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_proverki_porog CHECK (porog_shodstva>=0 AND porog_shodstva<=1),
    CONSTRAINT ck_proverki_limit CHECK (limit_rezultatov BETWEEN 1 AND 50),
    CONSTRAINT ck_proverki_rezultat CHECK (rezultat IN ('uspeshno','neuspeshno','oshibka')),
    CONSTRAINT ck_proverki_massivy CHECK (cardinality(poluchennye_fragmenty)=cardinality(shodstva))
);
CREATE INDEX ix_proverki_versiya_vremya ON qbit_bot_pervichnogo_obrascheniya.proverki_znaniy(versiya_id,vremya_proverki DESC);
CREATE INDEX ix_proverki_vopros ON qbit_bot_pervichnogo_obrascheniya.proverki_znaniy(vopros_id);

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya ADD CONSTRAINT fk_ishodyashchie_zagruzka_znaniy FOREIGN KEY (zagruzka_id) REFERENCES qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(id);

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_proverit_aktivnuyu_versiyu()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
DECLARE v record;
BEGIN
    IF NEW.aktivnaya_versiya_id IS NULL THEN RETURN NEW; END IF;
    SELECT dokument_id,status INTO v FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy WHERE id=NEW.aktivnaya_versiya_id;
    IF NOT FOUND OR v.dokument_id<>NEW.id OR v.status<>'opublikovana' THEN RAISE EXCEPTION 'aktivnaya_versiya_id must reference published version of the same document'; END IF;
    RETURN NEW;
END $fn$;
CREATE CONSTRAINT TRIGGER ct_dokumenty_aktivnaya_versiya AFTER INSERT OR UPDATE OF aktivnaya_versiya_id ON qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_proverit_aktivnuyu_versiyu();

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_zapretit_izmenenie_profilya()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya
AS $fn$
BEGIN
    IF EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy WHERE profil_indeksa_id=OLD.id) THEN RAISE EXCEPTION 'Used index profile is immutable'; END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER tr_profili_immutable BEFORE UPDATE OR DELETE ON qbit_bot_pervichnogo_obrascheniya.profili_indeksa FOR EACH ROW EXECUTE FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_zapretit_izmenenie_profilya();

-- CONTROL STRING: KB-01R3_FUNCTIONS_START

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(p_dannye jsonb,p_fayl bytea)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,zagruzka_id uuid,zadanie_id uuid,status_zagruzki text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions
AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_event uuid; v_existing record; v_upload uuid; v_job uuid; v_hash text; v_name text;
BEGIN
    IF p_dannye IS NULL OR jsonb_typeof(p_dannye)<>'object' OR p_fayl IS NULL THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Нужны JSON object и bytes файла',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    BEGIN v_event:=(p_dannye->>'sobytie_integracii_id')::uuid; EXCEPTION WHEN OTHERS THEN v_event:=NULL; END;
    v_name:=NULLIF(btrim(p_dannye->>'imya_fayla'),'');
    IF v_op IS NULL OR v_event IS NULL OR v_name IS NULL OR lower(v_name) !~ '\.md$' OR NULLIF(btrim(p_dannye->>'vneshnee_sobytie_id'),'') IS NULL OR NULLIF(btrim(p_dannye->>'otpravitel_user_id'),'') IS NULL OR NULLIF(btrim(p_dannye->>'chat_id'),'') IS NULL OR NULLIF(btrim(p_dannye->>'vneshniy_file_id'),'') IS NULL THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Разрешён только .md и обязательные trusted service/file поля',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    IF octet_length(p_fayl)>5242880 THEN RETURN QUERY SELECT v_op,'otkaz','fayl_slishkom_bolshoy','Лимит v1: 5 MiB фактических байтов',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    BEGIN PERFORM convert_from(p_fayl,'UTF8'); EXCEPTION WHEN OTHERS THEN RETURN QUERY SELECT v_op,'otkaz','ne_utf8','Файл не является корректным UTF-8',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END;
    v_hash:=encode(extensions.digest(p_fayl,'sha256'),'hex');
    IF NULLIF(lower(btrim(p_dannye->>'hash_istochnika')),'') IS NOT NULL AND lower(btrim(p_dannye->>'hash_istochnika'))<>v_hash THEN RETURN QUERY SELECT v_op,'konflikt','hash_ne_sovpadaet','SHA-256 не соответствует фактическим bytes',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.sobytiya_integraciy e WHERE e.id=v_event AND e.vneshnee_sobytie_id=p_dannye->>'vneshnee_sobytie_id') THEN RETURN QUERY SELECT v_op,'otkaz','sobytie_ne_zaregistrirovano','Нет соответствующего durable service event',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('kb_upload:'||v_event::text,0));
    SELECT z.id,z.status,z.hash_istochnika,z.vneshnee_sobytie_id,z.otpravitel_user_id,z.chat_id,z.vneshniy_file_id,z.imya_fayla,j.id AS job_id INTO v_existing FROM qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy z LEFT JOIN qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j ON j.zagruzka_id=z.id AND j.tip_zadaniya='obrabotka' WHERE z.sobytie_integracii_id=v_event;
    IF FOUND THEN
        IF v_existing.hash_istochnika IS DISTINCT FROM v_hash OR v_existing.vneshnee_sobytie_id IS DISTINCT FROM p_dannye->>'vneshnee_sobytie_id' OR v_existing.otpravitel_user_id IS DISTINCT FROM p_dannye->>'otpravitel_user_id' OR v_existing.chat_id IS DISTINCT FROM p_dannye->>'chat_id' OR v_existing.vneshniy_file_id IS DISTINCT FROM p_dannye->>'vneshniy_file_id' OR v_existing.imya_fayla IS DISTINCT FROM v_name THEN RETURN QUERY SELECT v_op,'konflikt','povtor_s_drugim_soderzhaniem','То же service event получило другое содержимое/metadata',NULL::timestamptz,v_existing.id,v_existing.job_id,v_existing.status; RETURN; END IF;
        RETURN QUERY SELECT v_op,'dublikat',NULL::text,'Событие уже зарегистрировано',NULL::timestamptz,v_existing.id,v_existing.job_id,v_existing.status; RETURN;
    END IF;
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy(sobytie_integracii_id,vneshnee_sobytie_id,otpravitel_user_id,chat_id,vneshniy_file_id,imya_fayla,ishodnyy_fayl,razmer_bayt,hash_istochnika,vremya_priema,status)
    VALUES(v_event,p_dannye->>'vneshnee_sobytie_id',p_dannye->>'otpravitel_user_id',p_dannye->>'chat_id',p_dannye->>'vneshniy_file_id',v_name,p_fayl,octet_length(p_fayl),v_hash,COALESCE(NULLIF(p_dannye->>'vremya_priema','')::timestamptz,clock_timestamp()),'poluchena') RETURNING id INTO v_upload;
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy(zagruzka_id,tip_zadaniya,status,prioritet,payload) VALUES(v_upload,'obrabotka','ozhidaet',COALESCE(NULLIF(p_dannye->>'prioritet','')::integer,0),'{}'::jsonb) RETURNING id INTO v_job;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_upload,v_job,'poluchena'::text;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,zadanie_id uuid,zagruzka_id uuid,dokument_id uuid,status_zadaniya text,popytki integer,vladelec_arendy text,arenda_do timestamptz,nomer_vladeniya bigint,imya_fayla text,ishodnyy_fayl bytea,hash_istochnika text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_worker text:=NULLIF(btrim(p_dannye->>'worker_id'),''); v_lease integer; v record;
BEGIN
    BEGIN v_lease:=COALESCE(NULLIF(p_dannye->>'arenda_sekund','')::integer,900); EXCEPTION WHEN OTHERS THEN v_lease:=NULL; END;
    IF v_op IS NULL OR v_worker IS NULL OR v_lease IS NULL OR v_lease<10 OR v_lease>3600 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Нужны operaciya_id, worker_id, arenda_sekund 10..3600',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::integer,NULL::text,NULL::timestamptz,NULL::bigint,NULL::text,NULL::bytea,NULL::text; RETURN; END IF;
    WITH candidate AS (
        SELECT j.id FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j
        WHERE (
            (j.status IN ('ozhidaet','povtor') AND j.sleduyushchiy_zapusk<=clock_timestamp() AND (j.dokument_id IS NULL OR NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy x WHERE x.dokument_id=j.dokument_id AND x.status='v_rabote' AND x.id<>j.id)))
            OR (j.status='v_rabote' AND j.arenda_do<clock_timestamp())
        )
        ORDER BY CASE WHEN j.status='v_rabote' THEN 0 ELSE 1 END,j.prioritet DESC,j.sleduyushchiy_zapusk,j.vremya_sozdaniya FOR UPDATE SKIP LOCKED LIMIT 1
    ) UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j SET status='v_rabote',popytki=j.popytki+1,vladelec_arendy=v_worker,nomer_vladeniya=j.nomer_vladeniya+1,arenda_do=clock_timestamp()+make_interval(secs=>v_lease),kod_oshibki=NULL,opisanie_oshibki=NULL,vremya_obnovleniya=clock_timestamp() FROM candidate c WHERE j.id=c.id RETURNING j.* INTO v;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'net_zadaniya',NULL::text,NULL::text,NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::integer,NULL::text,NULL::timestamptz,NULL::bigint,NULL::text,NULL::bytea,NULL::text; RETURN; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy SET status='obrabotka',vremya_obnovleniya=clock_timestamp() WHERE id=v.zagruzka_id AND status IN ('poluchena','proverka');
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v.id,v.zagruzka_id,v.dokument_id,v.status,v.popytki,v.vladelec_arendy,v.arenda_do,v.nomer_vladeniya,z.imya_fayla,z.ishodnyy_fayl,z.hash_istochnika FROM qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy z WHERE z.id=v.zagruzka_id;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,zadanie_id uuid,arenda_do timestamptz,nomer_vladeniya bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_id uuid; v_worker text:=NULLIF(btrim(p_dannye->>'worker_id'),''); v_fence bigint; v_lease integer; v record;
BEGIN
    BEGIN v_id:=(p_dannye->>'zadanie_id')::uuid; v_fence:=(p_dannye->>'nomer_vladeniya')::bigint; v_lease:=COALESCE(NULLIF(p_dannye->>'arenda_sekund','')::integer,900); EXCEPTION WHEN OTHERS THEN v_id:=NULL; END;
    IF v_op IS NULL OR v_id IS NULL OR v_worker IS NULL OR v_fence IS NULL OR v_lease<10 OR v_lease>3600 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Некорректные lease параметры',NULL::timestamptz,v_id,NULL::timestamptz,v_fence; RETURN; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j SET arenda_do=clock_timestamp()+make_interval(secs=>v_lease),vremya_obnovleniya=clock_timestamp() WHERE j.id=v_id AND j.status='v_rabote' AND j.vladelec_arendy=v_worker AND j.nomer_vladeniya=v_fence AND j.arenda_do>=clock_timestamp() RETURNING j.id,j.arenda_do,j.nomer_vladeniya INTO v;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'konflikt','stale_lease','Lease/worker/fencing больше не действуют',NULL::timestamptz,v_id,NULL::timestamptz,v_fence; RETURN; END IF;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v.id,v.arenda_do,v.nomer_vladeniya;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,zadanie_id uuid,status_zadaniya text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_id uuid; v_worker text:=NULLIF(btrim(p_dannye->>'worker_id'),''); v_fence bigint; v_status text:=NULLIF(btrim(p_dannye->>'status'),''); v_next timestamptz; v_upload uuid;
BEGIN
    BEGIN v_id:=(p_dannye->>'zadanie_id')::uuid; v_fence:=(p_dannye->>'nomer_vladeniya')::bigint; v_next:=NULLIF(p_dannye->>'sleduyushchiy_zapusk','')::timestamptz; EXCEPTION WHEN OTHERS THEN v_id:=NULL; END;
    IF v_op IS NULL OR v_id IS NULL OR v_worker IS NULL OR v_fence IS NULL OR v_status NOT IN ('zaversheno','povtor','otmeneno','oshibka') OR (v_status='povtor' AND (v_next IS NULL OR v_next<=clock_timestamp())) THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Некорректное завершение knowledge job',NULL::timestamptz,v_id,NULL::text; RETURN; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j SET status=v_status,sleduyushchiy_zapusk=COALESCE(v_next,j.sleduyushchiy_zapusk),vladelec_arendy=NULL,arenda_do=NULL,kod_oshibki=NULLIF(p_dannye->>'kod_oshibki',''),opisanie_oshibki=NULLIF(p_dannye->>'opisanie_oshibki',''),vremya_obnovleniya=clock_timestamp() WHERE j.id=v_id AND j.status='v_rabote' AND j.vladelec_arendy=v_worker AND j.nomer_vladeniya=v_fence AND j.arenda_do>=clock_timestamp() RETURNING j.zagruzka_id INTO v_upload;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'konflikt','stale_lease','Job уже не принадлежит worker/fencing',NULL::timestamptz,v_id,NULL::text; RETURN; END IF;
    IF v_status='oshibka' THEN UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy SET status='oshibka',kod_oshibki=NULLIF(p_dannye->>'kod_oshibki',''),opisanie_oshibki=NULLIF(p_dannye->>'opisanie_oshibki',''),vremya_obnovleniya=clock_timestamp() WHERE id=v_upload AND status<>'zavershena'; END IF;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,CASE WHEN v_status='povtor' THEN v_next ELSE NULL END,v_id,v_status;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,dokument_id uuid,versiya_id uuid,nomer_versii integer,profil_indeksa_id uuid,ozhidaemaya_aktivnaya_versiya_id uuid,status_versii text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_job uuid; v_worker text:=NULLIF(btrim(p_dannye->>'worker_id'),''); v_fence bigint; v_ident text:=NULLIF(btrim(p_dannye->>'identifikator_dokumenta'),''); v_name text:=NULLIF(btrim(p_dannye->>'nazvanie'),''); v_tip text:=NULLIF(btrim(p_dannye->>'tip_dokumenta'),''); v_hash text:=lower(NULLIF(btrim(p_dannye->>'hash_soderzhaniya'),'')); v_proc text:=lower(NULLIF(btrim(p_dannye->>'otpechatok_obrabotki'),'')); v_prof text:=lower(NULLIF(btrim(p_dannye->>'otpechatok_profilya'),'')); v_model text:=NULLIF(btrim(p_dannye->>'embedding_model'),''); v_parser text:=NULLIF(btrim(p_dannye->>'versiya_parsera'),''); v_clean text:=NULLIF(btrim(p_dannye->>'versiya_ochistki'),''); v_chunk text:=NULLIF(btrim(p_dannye->>'versiya_chunkinga'),''); v_tokenizer text:=NULLIF(btrim(p_dannye->>'tokenizer'),''); v_target integer; v_max integer; v_overlap integer; v_dim integer; v_profile uuid; v_doc uuid; v_active uuid; v_version uuid; v_num integer; v_upload uuid; v_existing record; v_jobrow record;
BEGIN
    BEGIN v_job:=(p_dannye->>'zadanie_id')::uuid; v_fence:=(p_dannye->>'nomer_vladeniya')::bigint; v_dim:=(p_dannye->>'razmernost')::integer; v_target:=COALESCE(NULLIF(p_dannye->>'cel_fragmenta_tokenov','')::integer,600); v_max:=COALESCE(NULLIF(p_dannye->>'maks_fragmenta_tokenov','')::integer,800); v_overlap:=COALESCE(NULLIF(p_dannye->>'overlap_tokenov','')::integer,100); EXCEPTION WHEN OTHERS THEN v_job:=NULL; END;
    IF v_op IS NULL OR v_job IS NULL OR v_worker IS NULL OR v_fence IS NULL OR v_ident !~ '^[a-z][a-z0-9_]{0,79}$' OR v_name IS NULL OR v_tip NOT IN ('opisanie','harakteristiki','instrukciya','faq','usloviya','politika') OR v_hash !~ '^[0-9a-f]{64}$' OR v_proc !~ '^[0-9a-f]{64}$' OR v_prof !~ '^[0-9a-f]{64}$' OR v_model IS NULL OR v_parser IS NULL OR v_clean IS NULL OR v_chunk IS NULL OR v_tokenizer IS NULL OR v_dim<>1024 OR v_target<=0 OR v_max<v_target OR v_overlap<0 OR v_overlap>=v_target THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Metadata/profile не соответствуют v1 contract',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    SELECT * INTO v_jobrow FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j WHERE j.id=v_job FOR UPDATE;
    IF NOT FOUND OR v_jobrow.status<>'v_rabote' OR v_jobrow.vladelec_arendy<>v_worker OR v_jobrow.nomer_vladeniya<>v_fence OR v_jobrow.arenda_do<clock_timestamp() THEN RETURN QUERY SELECT v_op,'konflikt','stale_lease','Job lease/fencing недействительны',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    v_upload:=v_jobrow.zagruzka_id;
    SELECT z.dokument_id,z.versiya_id,v.nomer_versii,v.profil_indeksa_id,v.ozhidaemaya_aktivnaya_versiya_id,v.status INTO v_existing FROM qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy z LEFT JOIN qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v ON v.id=z.versiya_id WHERE z.id=v_upload FOR UPDATE OF z;
    IF v_existing.versiya_id IS NOT NULL THEN RETURN QUERY SELECT v_op,'dublikat',NULL::text,'Версия для этой загрузки уже подготовлена',NULL::timestamptz,v_existing.dokument_id,v_existing.versiya_id,v_existing.nomer_versii,v_existing.profil_indeksa_id,v_existing.ozhidaemaya_aktivnaya_versiya_id,v_existing.status; RETURN; END IF;
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.profili_indeksa(otpechatok_profilya,embedding_model,razmernost,metrika,versiya_parsera,versiya_ochistki,versiya_chunkinga,tokenizer,cel_fragmenta_tokenov,maks_fragmenta_tokenov,overlap_tokenov) VALUES(v_prof,v_model,v_dim,'cosine',v_parser,v_clean,v_chunk,v_tokenizer,v_target,v_max,v_overlap) ON CONFLICT(otpechatok_profilya) DO NOTHING;
    SELECT p.id INTO v_profile FROM qbit_bot_pervichnogo_obrascheniya.profili_indeksa p WHERE p.otpechatok_profilya=v_prof;
    IF NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.profili_indeksa p WHERE p.id=v_profile AND p.embedding_model=v_model AND p.razmernost=v_dim AND p.metrika='cosine' AND p.versiya_parsera=v_parser AND p.versiya_ochistki=v_clean AND p.versiya_chunkinga=v_chunk AND p.tokenizer=v_tokenizer AND p.cel_fragmenta_tokenov=v_target AND p.maks_fragmenta_tokenov=v_max AND p.overlap_tokenov=v_overlap) THEN RETURN QUERY SELECT v_op,'konflikt','profil_ne_sovpadaet','Одинаковый fingerprint не может описывать другой профиль',NULL::timestamptz,NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::uuid,NULL::text; RETURN; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('kb_doc:'||v_ident,0));
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy(identifikator_dokumenta) VALUES(v_ident) ON CONFLICT(identifikator_dokumenta) DO NOTHING;
    SELECT d.id,d.aktivnaya_versiya_id INTO v_doc,v_active FROM qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy d WHERE d.identifikator_dokumenta=v_ident FOR UPDATE;
    IF EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j WHERE j.dokument_id=v_doc AND j.status='v_rabote' AND j.id<>v_job) THEN UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy SET status='povtor',sleduyushchiy_zapusk=clock_timestamp()+interval '30 seconds',vladelec_arendy=NULL,arenda_do=NULL,vremya_obnovleniya=clock_timestamp() WHERE id=v_job; RETURN QUERY SELECT v_op,'povtor','dokument_zanyat','Другой worker уже обрабатывает этот logical document',clock_timestamp()+interval '30 seconds',v_doc,NULL::uuid,NULL::integer,v_profile,v_active,NULL::text; RETURN; END IF;
    IF v_active IS NOT NULL AND EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v WHERE v.id=v_active AND v.otpechatok_obrabotki=v_proc AND v.status='opublikovana') THEN UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy SET dokument_id=v_doc,versiya_id=v_active,hash_soderzhaniya=v_hash,status='dublikat',vremya_obnovleniya=clock_timestamp() WHERE id=v_upload; UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy SET dokument_id=v_doc,ozhidaemaya_aktivnaya_versiya_id=v_active,status='zaversheno',vladelec_arendy=NULL,arenda_do=NULL,vremya_obnovleniya=clock_timestamp() WHERE id=v_job; SELECT v.nomer_versii,v.profil_indeksa_id,v.status INTO v_num,v_profile,v_tip FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v WHERE v.id=v_active; RETURN QUERY SELECT v_op,'dublikat',NULL::text,'Отпечаток совпадает с активной версией',NULL::timestamptz,v_doc,v_active,v_num,v_profile,v_active,v_tip; RETURN; END IF;
    SELECT COALESCE(max(v.nomer_versii),0)+1 INTO v_num FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v WHERE v.dokument_id=v_doc;
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy(dokument_id,zagruzka_id,nomer_versii,nazvanie,tip_dokumenta,versiya_istochnika,data_obnovleniya,hash_soderzhaniya,otpechatok_obrabotki,profil_indeksa_id,status,ozhidaemaya_aktivnaya_versiya_id) VALUES(v_doc,v_upload,v_num,v_name,v_tip,NULLIF(p_dannye->>'versiya_istochnika',''),NULLIF(p_dannye->>'data_obnovleniya','')::date,v_hash,v_proc,v_profile,'chernovik',v_active) RETURNING id INTO v_version;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy SET dokument_id=v_doc,versiya_id=v_version,hash_soderzhaniya=v_hash,status='obrabotka',vremya_obnovleniya=clock_timestamp() WHERE id=v_upload;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy SET dokument_id=v_doc,ozhidaemaya_aktivnaya_versiya_id=v_active,vremya_obnovleniya=clock_timestamp() WHERE id=v_job;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_doc,v_version,v_num,v_profile,v_active,'chernovik'::text;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,versiya_id uuid,sohraneno_fragmentov integer,vsego_fragmentov integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_ver uuid; v_job uuid; v_worker text:=NULLIF(btrim(p_dannye->>'worker_id'),''); v_fence bigint; v_items jsonb:=p_dannye->'fragmenty'; v_item jsonb; v_vec extensions.vector; v_profile record; v_count integer:=0; v_existing record; v_total integer; v_hash text;
BEGIN
    BEGIN v_ver:=(p_dannye->>'versiya_id')::uuid; v_job:=(p_dannye->>'zadanie_id')::uuid; v_fence:=(p_dannye->>'nomer_vladeniya')::bigint; EXCEPTION WHEN OTHERS THEN v_ver:=NULL; END;
    IF v_op IS NULL OR v_ver IS NULL OR v_job IS NULL OR v_worker IS NULL OR v_fence IS NULL OR jsonb_typeof(v_items)<>'array' OR jsonb_array_length(v_items)=0 OR jsonb_array_length(v_items)>100 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Нужны live job/version и batch 1..100 fragments',NULL::timestamptz,v_ver,0,0; RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j JOIN qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v ON v.zagruzka_id=j.zagruzka_id WHERE j.id=v_job AND v.id=v_ver AND j.status='v_rabote' AND j.vladelec_arendy=v_worker AND j.nomer_vladeniya=v_fence AND j.arenda_do>=clock_timestamp() AND v.status='chernovik') THEN RETURN QUERY SELECT v_op,'konflikt','stale_lease','Job/version больше не доступны для записи',NULL::timestamptz,v_ver,0,0; RETURN; END IF;
    SELECT p.* INTO v_profile FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v JOIN qbit_bot_pervichnogo_obrascheniya.profili_indeksa p ON p.id=v.profil_indeksa_id WHERE v.id=v_ver;
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
        IF jsonb_typeof(v_item)<>'object' OR jsonb_typeof(v_item->'vektor')<>'array' OR NULLIF(v_item->>'tekst_fragmenta','') IS NULL THEN RAISE EXCEPTION 'Invalid fragment payload'; END IF;
        v_vec:=(v_item->'vektor')::text::extensions.vector;
        IF extensions.vector_dims(v_vec)<>v_profile.razmernost THEN RAISE EXCEPTION 'Vector dimension mismatch'; END IF;
        v_hash:=encode(extensions.digest(convert_to(v_item->>'tekst_fragmenta','UTF8'),'sha256'),'hex');
        IF lower(COALESCE(v_item->>'hash_fragmenta',''))<>v_hash THEN RAISE EXCEPTION 'Fragment hash mismatch'; END IF;
        IF (v_item->>'kolichestvo_tokenov')::integer>v_profile.maks_fragmenta_tokenov THEN RAISE EXCEPTION 'Fragment exceeds profile max tokens'; END IF;
        SELECT f.hash_fragmenta,f.put_razdela,f.tekst_fragmenta,f.kolichestvo_tokenov INTO v_existing FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver AND f.nomer_fragmenta=(v_item->>'nomer_fragmenta')::integer;
        IF FOUND THEN IF v_existing.hash_fragmenta IS DISTINCT FROM v_hash OR v_existing.put_razdela IS DISTINCT FROM v_item->>'put_razdela' OR v_existing.tekst_fragmenta IS DISTINCT FROM v_item->>'tekst_fragmenta' OR v_existing.kolichestvo_tokenov IS DISTINCT FROM (v_item->>'kolichestvo_tokenov')::integer THEN RAISE EXCEPTION 'Fragment number conflict'; END IF; ELSE INSERT INTO qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy(versiya_id,nomer_fragmenta,put_razdela,tekst_fragmenta,kolichestvo_tokenov,hash_fragmenta,vektor) VALUES(v_ver,(v_item->>'nomer_fragmenta')::integer,v_item->>'put_razdela',v_item->>'tekst_fragmenta',(v_item->>'kolichestvo_tokenov')::integer,v_hash,v_vec); v_count:=v_count+1; END IF;
    END LOOP;
    SELECT count(*)::integer INTO v_total FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_ver,v_count,v_total;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,versiya_id uuid,kolichestvo_voprosov integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_ver uuid; v_q jsonb:=p_dannye->'voprosy'; v_item jsonb; v_n integer;
BEGIN
    BEGIN v_ver:=(p_dannye->>'versiya_id')::uuid; EXCEPTION WHEN OTHERS THEN v_ver:=NULL; END;
    IF v_op IS NULL OR v_ver IS NULL OR jsonb_typeof(v_q)<>'array' OR jsonb_array_length(v_q)<3 OR jsonb_array_length(v_q)>10 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Требуется 3..10 контрольных вопросов',NULL::timestamptz,v_ver,0; RETURN; END IF;
    PERFORM 1 FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v WHERE v.id=v_ver AND v.status='chernovik' FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'konflikt','versiya_ne_chernovik','Вопросы меняются только у draft version',NULL::timestamptz,v_ver,0; RETURN; END IF;
    DELETE FROM qbit_bot_pervichnogo_obrascheniya.proverki_znaniy p WHERE p.versiya_id=v_ver; DELETE FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k WHERE k.versiya_id=v_ver; v_n:=0;
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_q) LOOP v_n:=v_n+1; IF NULLIF(btrim(v_item->>'vopros'),'') IS NULL OR NULLIF(btrim(v_item->>'ozhidaemyy_razdel'),'') IS NULL THEN RAISE EXCEPTION 'Invalid control question'; END IF; INSERT INTO qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy(versiya_id,nomer,vopros,ozhidaemyy_razdel,ozhidaemyy_fakt,istochnik) VALUES(v_ver,v_n,v_item->>'vopros',v_item->>'ozhidaemyy_razdel',NULLIF(v_item->>'ozhidaemyy_fakt',''),COALESCE(NULLIF(v_item->>'istochnik',''),'yaml')); END LOOP;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_ver,v_n;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,versiya_id uuid,status_versii text,uspeshnyh integer,vsego integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_ver uuid; v_profile uuid; v_arr jsonb:=p_dannye->'proverki'; v_item jsonb; v_q uuid; v_ok integer; v_all integer; v_frag integer; v_dim integer; v_status text; v_limit integer;
BEGIN
    BEGIN v_ver:=(p_dannye->>'versiya_id')::uuid; v_profile:=(p_dannye->>'profil_indeksa_id')::uuid; EXCEPTION WHEN OTHERS THEN v_ver:=NULL; END;
    IF v_op IS NULL OR v_ver IS NULL OR v_profile IS NULL OR jsonb_typeof(v_arr)<>'array' OR jsonb_array_length(v_arr)=0 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Некорректный набор проверок',NULL::timestamptz,v_ver,NULL::text,0,0; RETURN; END IF;
    SELECT p.razmernost INTO v_dim FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v JOIN qbit_bot_pervichnogo_obrascheniya.profili_indeksa p ON p.id=v.profil_indeksa_id WHERE v.id=v_ver AND v.profil_indeksa_id=v_profile AND v.status='chernovik' FOR UPDATE OF v;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'konflikt','versiya_ili_profil','Draft version/profile не совпадают',NULL::timestamptz,v_ver,NULL::text,0,0; RETURN; END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_arr) LOOP
        v_q:=(v_item->>'vopros_id')::uuid; v_limit:=(v_item->>'limit_rezultatov')::integer;
        IF NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k WHERE k.id=v_q AND k.versiya_id=v_ver) THEN RAISE EXCEPTION 'Question does not belong to version'; END IF;
        IF jsonb_array_length(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb))>v_limit THEN RAISE EXCEPTION 'Stored result count exceeds top-k limit'; END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb)) x WHERE NOT EXISTS (SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.id=x::uuid AND f.versiya_id=v_ver)) THEN RAISE EXCEPTION 'Check references fragment outside version'; END IF;
        INSERT INTO qbit_bot_pervichnogo_obrascheniya.proverki_znaniy(versiya_id,vopros_id,profil_indeksa_id,porog_shodstva,limit_rezultatov,poluchennye_fragmenty,shodstva,rezultat,opisanie) VALUES(v_ver,v_q,v_profile,(v_item->>'porog_shodstva')::numeric,v_limit,ARRAY(SELECT x::uuid FROM jsonb_array_elements_text(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb)) x),ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(COALESCE(v_item->'shodstva','[]'::jsonb)) x),v_item->>'rezultat',NULLIF(v_item->>'opisanie',''));
    END LOOP;
    SELECT count(*)::integer INTO v_all FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k WHERE k.versiya_id=v_ver;
    WITH latest AS (SELECT DISTINCT ON (p.vopros_id) p.vopros_id,p.rezultat FROM qbit_bot_pervichnogo_obrascheniya.proverki_znaniy p WHERE p.versiya_id=v_ver ORDER BY p.vopros_id,p.vremya_proverki DESC,p.id DESC) SELECT count(*) FILTER(WHERE rezultat='uspeshno')::integer INTO v_ok FROM latest;
    SELECT count(*)::integer INTO v_frag FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver AND extensions.vector_dims(f.vektor)=v_dim;
    IF v_all BETWEEN 3 AND 10 AND v_ok=v_all AND v_frag>0 THEN v_status:='gotova'; ELSE v_status:='chernovik'; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy SET status=v_status,vremya_proverki=clock_timestamp() WHERE id=v_ver;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy z SET status=CASE WHEN v_status='gotova' THEN 'ozhidaet_proverki' ELSE z.status END,vremya_obnovleniya=clock_timestamp() FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v WHERE v.id=v_ver AND z.id=v.zagruzka_id;
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_ver,v_status,v_ok,v_all;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,versiya_id uuid,fragment_id uuid,nomer_fragmenta integer,put_razdela text,tekst_fragmenta text,shodstvo numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_ver uuid; v_profile uuid; v_limit integer; v_thr numeric; v_query extensions.vector; v_dim integer;
BEGIN
    BEGIN v_ver:=(p_dannye->>'versiya_id')::uuid; v_profile:=(p_dannye->>'profil_indeksa_id')::uuid; v_limit:=COALESCE(NULLIF(p_dannye->>'limit','')::integer,5); v_thr:=COALESCE(NULLIF(p_dannye->>'porog_shodstva','')::numeric,0); v_query:=(p_dannye->'vektor')::text::extensions.vector; EXCEPTION WHEN OTHERS THEN v_ver:=NULL; END;
    SELECT p.razmernost INTO v_dim FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v JOIN qbit_bot_pervichnogo_obrascheniya.profili_indeksa p ON p.id=v.profil_indeksa_id WHERE v.id=v_ver AND v.profil_indeksa_id=v_profile AND v.status IN ('chernovik','gotova');
    IF v_op IS NULL OR v_ver IS NULL OR v_dim IS NULL OR v_query IS NULL OR extensions.vector_dims(v_query)<>v_dim OR v_limit<1 OR v_limit>50 OR v_thr<0 OR v_thr>1 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Draft/version/profile/vector не совпадают',v_ver,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::numeric; RETURN; END IF;
    RETURN QUERY WITH ranked AS (SELECT f.id,f.nomer_fragmenta,f.put_razdela,f.tekst_fragmenta,(1-(f.vektor OPERATOR(extensions.<=>) v_query))::numeric AS sim FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver ORDER BY f.vektor OPERATOR(extensions.<=>) v_query LIMIT v_limit) SELECT v_op,'uspeshno',NULL::text,NULL::text,v_ver,r.id,r.nomer_fragmenta,r.put_razdela,r.tekst_fragmenta,r.sim FROM ranked r WHERE r.sim>=v_thr;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,dokument_id uuid,identifikator_dokumenta text,versiya_id uuid,fragment_id uuid,nomer_fragmenta integer,put_razdela text,tekst_fragmenta text,shodstvo numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_profile uuid; v_limit integer; v_thr numeric; v_query extensions.vector; v_dim integer;
BEGIN
    BEGIN v_profile:=(p_dannye->>'profil_indeksa_id')::uuid; v_limit:=COALESCE(NULLIF(p_dannye->>'limit','')::integer,5); v_thr:=COALESCE(NULLIF(p_dannye->>'porog_shodstva','')::numeric,0); v_query:=(p_dannye->'vektor')::text::extensions.vector; EXCEPTION WHEN OTHERS THEN v_profile:=NULL; END;
    SELECT p.razmernost INTO v_dim FROM qbit_bot_pervichnogo_obrascheniya.profili_indeksa p WHERE p.id=v_profile;
    IF v_op IS NULL OR v_profile IS NULL OR v_dim IS NULL OR v_query IS NULL OR extensions.vector_dims(v_query)<>v_dim OR v_limit<1 OR v_limit>50 OR v_thr<0 OR v_thr>1 THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Profile/vector/search параметры некорректны',NULL::uuid,NULL::text,NULL::uuid,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::numeric; RETURN; END IF;
    RETURN QUERY WITH ranked AS (SELECT d.id AS did,d.identifikator_dokumenta,v.id AS vid,f.id AS fid,f.nomer_fragmenta,f.put_razdela,f.tekst_fragmenta,(1-(f.vektor OPERATOR(extensions.<=>) v_query))::numeric AS sim FROM qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy d JOIN qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v ON v.id=d.aktivnaya_versiya_id AND v.dokument_id=d.id AND v.status='opublikovana' AND v.profil_indeksa_id=v_profile JOIN qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f ON f.versiya_id=v.id ORDER BY f.vektor OPERATOR(extensions.<=>) v_query LIMIT v_limit) SELECT v_op,'uspeshno',NULL::text,NULL::text,r.did,r.identifikator_dokumenta,r.vid,r.fid,r.nomer_fragmenta,r.put_razdela,r.tekst_fragmenta,r.sim FROM ranked r WHERE r.sim>=v_thr;
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,dokument_id uuid,versiya_id uuid,predydushchaya_aktivnaya_versiya_id uuid,status_versii text,status_zagruzki text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_ver uuid; v_expected uuid; v record; v_current uuid; v_q integer; v_ok integer; v_frag integer; v_bad integer;
BEGIN
    BEGIN v_ver:=(p_dannye->>'versiya_id')::uuid; v_expected:=NULLIF(p_dannye->>'ozhidaemaya_aktivnaya_versiya_id','')::uuid; EXCEPTION WHEN OTHERS THEN v_ver:=NULL; END;
    IF v_op IS NULL OR v_ver IS NULL THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Нужны operaciya_id и versiya_id',NULL::timestamptz,NULL::uuid,v_ver,NULL::uuid,NULL::text,NULL::text; RETURN; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('kb_publish_op:'||v_op,0));
    SELECT vv.*,p.razmernost INTO v FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy vv JOIN qbit_bot_pervichnogo_obrascheniya.profili_indeksa p ON p.id=vv.profil_indeksa_id WHERE vv.id=v_ver FOR UPDATE OF vv;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'otkaz','versiya_ne_naydena','Version not found',NULL::timestamptz,NULL::uuid,v_ver,NULL::uuid,NULL::text,NULL::text; RETURN; END IF;
    SELECT d.aktivnaya_versiya_id INTO v_current FROM qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy d WHERE d.id=v.dokument_id FOR UPDATE;
    IF v_current=v_ver AND v.status='opublikovana' THEN RETURN QUERY SELECT v_op,'dublikat',NULL::text,'Версия уже активна',NULL::timestamptz,v.dokument_id,v_ver,v_expected,'opublikovana','zavershena'; RETURN; END IF;
    IF v_current IS DISTINCT FROM v_expected OR v.ozhidaemaya_aktivnaya_versiya_id IS DISTINCT FROM v_expected THEN RETURN QUERY SELECT v_op,'konflikt','stale_expected_active','Активная версия изменилась после начала обработки',NULL::timestamptz,v.dokument_id,v_ver,v_current,v.status,NULL::text; RETURN; END IF;
    IF v.status<>'gotova' THEN RETURN QUERY SELECT v_op,'otkaz','versiya_ne_gotova','Публикация разрешена только status=gotova',NULL::timestamptz,v.dokument_id,v_ver,v_current,v.status,NULL::text; RETURN; END IF;
    SELECT count(*)::integer INTO v_frag FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver;
    SELECT count(*)::integer INTO v_bad FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f WHERE f.versiya_id=v_ver AND extensions.vector_dims(f.vektor)<>v.razmernost;
    SELECT count(*)::integer INTO v_q FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k WHERE k.versiya_id=v_ver;
    WITH latest AS (SELECT DISTINCT ON(p.vopros_id) p.vopros_id,p.rezultat FROM qbit_bot_pervichnogo_obrascheniya.proverki_znaniy p WHERE p.versiya_id=v_ver ORDER BY p.vopros_id,p.vremya_proverki DESC,p.id DESC) SELECT count(*) FILTER(WHERE rezultat='uspeshno')::integer INTO v_ok FROM latest;
    IF v_frag=0 OR v_bad<>0 OR v_q NOT BETWEEN 3 AND 10 OR v_ok<>v_q THEN RETURN QUERY SELECT v_op,'otkaz','proverki_ne_proydeny','Fragments/vectors/reference checks incomplete',NULL::timestamptz,v.dokument_id,v_ver,v_current,v.status,NULL::text; RETURN; END IF;
    IF v_current IS NOT NULL THEN UPDATE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy SET status='arhiv',vremya_arhivirovaniya=clock_timestamp() WHERE id=v_current AND dokument_id=v.dokument_id AND status='opublikovana'; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy SET status='opublikovana',vremya_publikacii=clock_timestamp() WHERE id=v_ver;
    UPDATE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy SET aktivnaya_versiya_id=v_ver,vremya_obnovleniya=clock_timestamp() WHERE id=v.dokument_id;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy SET status='zavershena',vremya_obnovleniya=clock_timestamp() WHERE id=v.zagruzka_id;
    UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy SET status='zaversheno',vladelec_arendy=NULL,arenda_do=NULL,vremya_obnovleniya=clock_timestamp() WHERE zagruzka_id=v.zagruzka_id AND status IN ('v_rabote','ozhidaet','povtor');
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v.dokument_id,v_ver,v_current,'opublikovana','zavershena';
END $fn$;

CREATE FUNCTION qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy(p_dannye jsonb)
RETURNS TABLE(operaciya_id text,rezultat text,kod_oshibki text,opisanie text,povtor_posle timestamptz,dokument_id uuid,predydushchaya_aktivnaya_versiya_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya AS $fn$
#variable_conflict use_column
DECLARE v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),''); v_doc uuid; v_expected uuid; v_reason text:=NULLIF(btrim(p_dannye->>'prichina'),''); v_actor text:=COALESCE(NULLIF(btrim(p_dannye->>'avtor_id'),''),session_user); v_current uuid;
BEGIN
    BEGIN v_doc:=(p_dannye->>'dokument_id')::uuid; v_expected:=NULLIF(p_dannye->>'ozhidaemaya_aktivnaya_versiya_id','')::uuid; EXCEPTION WHEN OTHERS THEN v_doc:=NULL; END;
    IF v_op IS NULL OR v_doc IS NULL OR v_reason IS NULL THEN RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Нужны operation/document/expected active/reason',NULL::timestamptz,v_doc,NULL::uuid; RETURN; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('kb_revoke_op:'||v_op,0));
    SELECT d.aktivnaya_versiya_id INTO v_current FROM qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy d WHERE d.id=v_doc FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT v_op,'otkaz','dokument_ne_nayden','Document not found',NULL::timestamptz,v_doc,NULL::uuid; RETURN; END IF;
    IF v_current IS NULL AND v_expected IS NULL THEN RETURN QUERY SELECT v_op,'dublikat',NULL::text,'Документ уже отозван',NULL::timestamptz,v_doc,NULL::uuid; RETURN; END IF;
    IF v_current IS DISTINCT FROM v_expected THEN RETURN QUERY SELECT v_op,'konflikt','stale_expected_active','Active version changed',NULL::timestamptz,v_doc,v_current; RETURN; END IF;
    UPDATE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy SET aktivnaya_versiya_id=NULL,vremya_obnovleniya=clock_timestamp() WHERE id=v_doc;
    IF v_current IS NOT NULL THEN UPDATE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy SET status='arhiv',vremya_arhivirovaniya=clock_timestamp() WHERE id=v_current AND dokument_id=v_doc; END IF;
    INSERT INTO qbit_bot_pervichnogo_obrascheniya.zhurnal_administrirovaniya(tip_avtora,avtor_id,deystvie,tip_obekta,obekt_id,vremya,izmeneniya,rezultat,trassirovka_id) VALUES('dash_admin',v_actor,'otozvat_dokument_znaniy','dokument_znaniy',v_doc::text,clock_timestamp(),jsonb_build_object('operaciya_id',v_op,'predydushchaya_aktivnaya_versiya_id',v_current,'prichina',v_reason),'uspeshno',NULLIF(p_dannye->>'trassirovka_id',''));
    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_doc,v_current;
END $fn$;

REVOKE ALL ON TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy,qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy,qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy,qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy,qbit_bot_pervichnogo_obrascheniya.profili_indeksa,qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy,qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy,qbit_bot_pervichnogo_obrascheniya.proverki_znaniy FROM PUBLIC,qbit_test_bot,qbit_test_sluzhebnyy,qbit_test_dash_read,qbit_test_dash_admin;
REVOKE ALL ON SEQUENCE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy_poryadok_priema_seq FROM PUBLIC,qbit_test_bot,qbit_test_sluzhebnyy,qbit_test_dash_read,qbit_test_dash_admin;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_proverit_aktivnuyu_versiyu() FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_zapretit_izmenenie_profilya() FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy(jsonb) FROM PUBLIC;

GRANT USAGE ON SCHEMA qbit_bot_pervichnogo_obrascheniya TO qbit_test_bot,qbit_test_sluzhebnyy,qbit_test_dash_admin;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb) TO qbit_test_sluzhebnyy;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb) TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy(jsonb) TO qbit_test_dash_admin;

RESET ROLE;
DO $check$
DECLARE v_table text; v_fn text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['zagruzki_znaniy','zadaniya_znaniy','dokumenty_znaniy','versii_dokumentov_znaniy','profili_indeksa','fragmenty_znaniy','kontrolnye_voprosy','proverki_znaniy'] LOOP IF pg_catalog.to_regclass(pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_table)) IS NULL THEN RAISE EXCEPTION 'Missing table %',v_table; END IF; END LOOP;
    FOREACH v_fn IN ARRAY ARRAY['zabrat_zadanie_znaniy','prodlit_arendu_zadaniya_znaniy','zavershit_zadanie_znaniy','podgotovit_versiyu_znaniy','sohranit_fragmenty_znaniy','sohranit_kontrolnye_voprosy','sohranit_proverki_znaniy','poisk_chernovika_znaniy','poisk_aktivnyh_znaniy','opublikovat_versiyu_znaniy','otozvat_dokument_znaniy'] LOOP IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya' AND p.proname=v_fn AND p.prosecdef) THEN RAISE EXCEPTION 'Missing/unsafe function %',v_fn; END IF; END LOOP;
    IF pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea)') IS NULL THEN RAISE EXCEPTION 'Missing upload registration function'; END IF;
    IF pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)') IS NOT NULL OR pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'Experimental functions remain'; END IF;
    IF pg_catalog.has_table_privilege('qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy','SELECT') OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy','SELECT') THEN RAISE EXCEPTION 'Direct table SELECT leaked to runtime role'; END IF;
END $check$;

COMMIT;

SELECT jsonb_build_object('kb01r3_result',jsonb_build_object('status','applied','migration','KB-01R3_v0.2','schema','qbit_bot_pervichnogo_obrascheniya','next','run sql/DB-04_05_knowledge_verifier.sql before any n8n import or client RAG')) AS kb01r3_result;
