-- KB-01R3 rollback v0.1: remove newly created normative DB-04/DB-05 from TEST only
-- Use ONLY if recreate committed but verifier failed BEFORE any real KB upload/runtime use.
-- This rollback intentionally restores the safe state "KB absent/disabled".
-- It does NOT restore the known-incompatible experimental B1/B2 model.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='180s';
SET LOCAL search_path=pg_catalog;

DO $preflight$
DECLARE v_table text;
BEGIN
    IF session_user<>'postgres' THEN
        RAISE EXCEPTION 'Rollback must run from trusted postgres session';
    END IF;
    IF NOT pg_catalog.pg_has_role(session_user,'qbit_test_owner','SET') THEN
        RAISE EXCEPTION 'Cannot SET ROLE qbit_test_owner';
    END IF;
    FOREACH v_table IN ARRAY ARRAY[
        'zagruzki_znaniy','zadaniya_znaniy','dokumenty_znaniy','versii_dokumentov_znaniy',
        'profili_indeksa','fragmenty_znaniy','kontrolnye_voprosy','proverki_znaniy'
    ] LOOP
        IF pg_catalog.to_regclass(pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_table)) IS NULL THEN
            RAISE EXCEPTION 'Expected new KB table % is missing; stop instead of partial rollback',v_table;
        END IF;
    END LOOP;

    IF EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.profili_indeksa)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy)
       OR EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.proverki_znaniy) THEN
        RAISE EXCEPTION 'Normative KB already contains data; automatic rollback is forbidden';
    END IF;
    IF EXISTS(SELECT 1 FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya WHERE zagruzka_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Outgoing action already references a knowledge upload; automatic rollback is forbidden';
    END IF;
END
$preflight$;

SET LOCAL ROLE qbit_test_owner;

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya
    DROP CONSTRAINT fk_ishodyashchie_zagruzka_znaniy;

DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(jsonb);
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea);

DROP TABLE qbit_bot_pervichnogo_obrascheniya.proverki_znaniy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy;

ALTER TABLE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy
    DROP CONSTRAINT fk_dokumenty_aktivnaya_versiya;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy
    DROP CONSTRAINT fk_versii_ozhidaemaya_aktivnaya;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy
    DROP CONSTRAINT fk_zagruzki_versiya;
ALTER TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy
    DROP CONSTRAINT fk_zagruzki_dokument;

DROP TABLE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy;
DROP TABLE qbit_bot_pervichnogo_obrascheniya.profili_indeksa;

DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_proverit_aktivnuyu_versiyu();
DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.kb_zapretit_izmenenie_profilya();

RESET ROLE;

DO $verify$
BEGIN
    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy') IS NOT NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.dokumenty_znaniy') IS NOT NULL
       OR pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback did not remove all normative KB objects';
    END IF;
END
$verify$;

COMMIT;

SELECT jsonb_build_object(
    'kb01r3_rollback_result',jsonb_build_object(
        'status','rolled_back_to_kb_absent',
        'rollback_version','KB-01R3_ROLLBACK_v0.1',
        'production_untouched',true,
        'experimental_model_restored',false
    )
) AS kb01r3_rollback_result;
