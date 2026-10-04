-- KB-01R3 verifier v0.3: normative DB-04/DB-05 structural/access/compile verification
-- READ ONLY. Run only AFTER DB-04_05_knowledge_recreate_test.sql reports applied.
-- No production objects are referenced.
-- Runtime-role permissions are verified from catalogs; compile probes run from the trusted
-- SQL session and enter the SECURITY DEFINER functions as qbit_test_owner.
-- This intentionally does NOT SET ROLE: the trusted postgres SQL session is not required
-- to be a member of qbit_test_bot/qbit_test_sluzhebnyy/qbit_test_dash_admin.

BEGIN READ ONLY;
SET LOCAL statement_timeout='180s';
SET LOCAL search_path=pg_catalog;

DO $verify$
DECLARE
    v_name text;
    v_owner text;
BEGIN
    IF session_user<>'postgres' THEN
        RAISE EXCEPTION 'Verifier must run from trusted postgres session; session_user=%',session_user;
    END IF;

    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty') IS NOT NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_versii') IS NOT NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty') IS NOT NULL
       OR pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)') IS NOT NULL
       OR pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'Experimental KB objects remain';
    END IF;

    FOREACH v_name IN ARRAY ARRAY[
        'zagruzki_znaniy','zadaniya_znaniy','dokumenty_znaniy','versii_dokumentov_znaniy',
        'profili_indeksa','fragmenty_znaniy','kontrolnye_voprosy','proverki_znaniy'
    ] LOOP
        IF pg_catalog.to_regclass(pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name)) IS NULL THEN
            RAISE EXCEPTION 'Missing DB-04 table %',v_name;
        END IF;
        SELECT pg_catalog.pg_get_userbyid(c.relowner) INTO v_owner
        FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya' AND c.relname=v_name AND c.relkind IN('r','p');
        IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
            RAISE EXCEPTION 'Wrong owner for %: %',v_name,v_owner;
        END IF;

        IF pg_catalog.has_table_privilege('qbit_test_bot',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'SELECT')
           OR pg_catalog.has_table_privilege('qbit_test_bot',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'INSERT')
           OR pg_catalog.has_table_privilege('qbit_test_bot',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'UPDATE')
           OR pg_catalog.has_table_privilege('qbit_test_bot',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'DELETE')
           OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'SELECT')
           OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'INSERT')
           OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'UPDATE')
           OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'DELETE')
           OR pg_catalog.has_table_privilege('qbit_test_dash_admin',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'SELECT')
           OR pg_catalog.has_table_privilege('qbit_test_dash_admin',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'INSERT')
           OR pg_catalog.has_table_privilege('qbit_test_dash_admin',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'UPDATE')
           OR pg_catalog.has_table_privilege('qbit_test_dash_admin',pg_catalog.format('qbit_bot_pervichnogo_obrascheniya.%I',v_name),'DELETE') THEN
            RAISE EXCEPTION 'Direct runtime DML leaked on %',v_name;
        END IF;
    END LOOP;

    IF pg_catalog.format_type(
        (SELECT a.atttypid FROM pg_catalog.pg_attribute a WHERE a.attrelid='qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy'::regclass AND a.attname='vektor' AND a.attnum>0 AND NOT a.attisdropped),
        (SELECT a.atttypmod FROM pg_catalog.pg_attribute a WHERE a.attrelid='qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy'::regclass AND a.attname='vektor' AND a.attnum>0 AND NOT a.attisdropped)
    ) NOT IN ('extensions.vector(1024)','vector(1024)') THEN
        RAISE EXCEPTION 'fragmenty_znaniy.vektor is not vector(1024)';
    END IF;

    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.ix_fragmenty_hnsw_cos') IS NULL THEN
        RAISE EXCEPTION 'HNSW cosine index is missing';
    END IF;
    IF NOT EXISTS(
        SELECT 1 FROM pg_catalog.pg_constraint con
        JOIN pg_catalog.pg_class c ON c.oid=con.conrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND c.relname='ishodyashchie_deystviya'
          AND con.conname='fk_ishodyashchie_zagruzka_znaniy'
          AND con.contype='f'
    ) THEN
        RAISE EXCEPTION 'DB-04 outgoing upload FK is missing';
    END IF;

    FOREACH v_name IN ARRAY ARRAY[
        'zabrat_zadanie_znaniy','prodlit_arendu_zadaniya_znaniy','zavershit_zadanie_znaniy',
        'podgotovit_versiyu_znaniy','sohranit_fragmenty_znaniy','sohranit_kontrolnye_voprosy',
        'sohranit_proverki_znaniy','poisk_chernovika_znaniy','poisk_aktivnyh_znaniy',
        'opublikovat_versiyu_znaniy','otozvat_dokument_znaniy'
    ] LOOP
        IF NOT EXISTS(
            SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya' AND p.proname=v_name
              AND p.prosecdef AND pg_catalog.pg_get_userbyid(p.proowner)='qbit_test_owner'
        ) THEN
            RAISE EXCEPTION 'Missing/unsafe function %',v_name;
        END IF;
        IF EXISTS(
            SELECT 1
            FROM pg_catalog.pg_proc p
            JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL pg_catalog.aclexplode(
                COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))
            ) x
            WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
              AND p.proname=v_name
              AND x.grantee=0
              AND x.privilege_type='EXECUTE'
        ) THEN
            RAISE EXCEPTION 'PUBLIC EXECUTE leaked on %',v_name;
        END IF;
    END LOOP;

    IF pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea)') IS NULL THEN
        RAISE EXCEPTION 'Missing zaregistrirovat_zagruzku_znaniy(jsonb,bytea)';
    END IF;
    IF EXISTS(
        SELECT 1
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))
        ) x
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND p.proname='zaregistrirovat_zagruzku_znaniy'
          AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_fayl bytea'
          AND x.grantee=0
          AND x.privilege_type='EXECUTE'
    ) THEN
        RAISE EXCEPTION 'PUBLIC EXECUTE leaked on upload registration';
    END IF;

    -- Exact runtime role matrix is verified from PostgreSQL ACL catalogs.
    IF NOT pg_catalog.has_function_privilege('qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'bot lacks active RAG'; END IF;
    IF pg_catalog.has_function_privilege('qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb)','EXECUTE')
       OR pg_catalog.has_function_privilege('qbit_test_bot','qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'bot can access draft/publish'; END IF;

    IF NOT pg_catalog.has_function_privilege('qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb,bytea)','EXECUTE')
       OR NOT pg_catalog.has_function_privilege('qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb)','EXECUTE')
       OR NOT pg_catalog.has_function_privilege('qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'service role lacks ingestion/draft/publish'; END IF;
    IF pg_catalog.has_function_privilege('qbit_test_sluzhebnyy','qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'service role unexpectedly has active RAG'; END IF;

    IF NOT pg_catalog.has_function_privilege('qbit_test_dash_admin','qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'dash_admin lacks revoke'; END IF;
    IF pg_catalog.has_function_privilege('qbit_test_dash_admin','qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'dash_admin unexpectedly has publish'; END IF;
END
$verify$;

-- Compile/runtime-entry probes.
-- The caller remains the trusted postgres SQL session because that session is not
-- intentionally a member of the runtime roles. ACL correctness for those roles was
-- checked above. Every function is SECURITY DEFINER and the invalid input below exits
-- before an application write; the whole verifier is READ ONLY and ends in ROLLBACK.
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy('{}'::jsonb,NULL::bytea) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy('{}'::jsonb) LIMIT 1;
SELECT rezultat FROM qbit_bot_pervichnogo_obrascheniya.otozvat_dokument_znaniy('{}'::jsonb) LIMIT 1;

SELECT jsonb_build_object(
    'db04_05_verifier_result',jsonb_build_object(
        'status','verified',
        'verifier_version','KB-01R3_VERIFIER_v0.3',
        'schema','qbit_bot_pervichnogo_obrascheniya',
        'experimental_objects_absent',true,
        'normative_tables_present',true,
        'owners_ok',true,
        'security_definer_ok',true,
        'public_execute_denied',true,
        'runtime_direct_dml_denied',true,
        'execute_matrix_ok',true,
        'vector_1024_hnsw_ok',true,
        'compile_probes_trusted_session_ok',true,
        'role_switch_required',false,
        'production_untouched_informational',true
    )
) AS db04_05_verifier_result;

ROLLBACK;
