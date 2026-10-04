-- KB-01R4 verifier v0.4 NO ROLE SWITCH
-- READ ONLY. This file contains no SET ROLE / SET SESSION AUTHORIZATION.
-- Use after DB-04_05_knowledge_recreate_test.sql reports KB-01R3_v0.2 applied.
-- It verifies structure, ownership and effective ACLs from PostgreSQL catalogs.
-- Runtime execution under actual n8n Credentials is a separate later test.

BEGIN READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

DO $verify$
DECLARE
    v_schema constant text := 'qbit_bot_pervichnogo_obrascheniya';
    v_table text;
    v_role text;
    v_sig text;
    v_oid oid;
    v_count bigint;
    v_indexdef text;
BEGIN
    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Verifier must run from trusted postgres SQL session; session_user=%', session_user;
    END IF;

    -- Experimental KB must be gone.
    IF pg_catalog.to_regclass(v_schema || '.znaniya_dokumenty') IS NOT NULL
       OR pg_catalog.to_regclass(v_schema || '.znaniya_versii') IS NOT NULL
       OR pg_catalog.to_regclass(v_schema || '.znaniya_fragmenty') IS NOT NULL
       OR pg_catalog.to_regprocedure(v_schema || '.kb01_postavit_dokument(jsonb)') IS NOT NULL
       OR pg_catalog.to_regprocedure(v_schema || '.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'Experimental KB objects remain';
    END IF;

    -- All 8 normative DB-04 tables must exist, belong to qbit_test_owner and still be empty.
    FOREACH v_table IN ARRAY ARRAY[
        'zagruzki_znaniy',
        'zadaniya_znaniy',
        'dokumenty_znaniy',
        'versii_dokumentov_znaniy',
        'profili_indeksa',
        'fragmenty_znaniy',
        'kontrolnye_voprosy',
        'proverki_znaniy'
    ] LOOP
        IF pg_catalog.to_regclass(pg_catalog.format('%I.%I', v_schema, v_table)) IS NULL THEN
            RAISE EXCEPTION 'Missing DB-04 table %.%', v_schema, v_table;
        END IF;

        IF (
            SELECT pg_catalog.pg_get_userbyid(c.relowner)
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = v_schema
              AND c.relname = v_table
              AND c.relkind IN ('r','p')
        ) IS DISTINCT FROM 'qbit_test_owner' THEN
            RAISE EXCEPTION 'Wrong owner for %.%', v_schema, v_table;
        END IF;

        EXECUTE pg_catalog.format('SELECT count(*) FROM %I.%I', v_schema, v_table)
        INTO v_count;
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'KB table %.% is not empty; expected 0 rows immediately after recreate, actual=%',
                v_schema, v_table, v_count;
        END IF;

        FOREACH v_role IN ARRAY ARRAY[
            'qbit_test_bot',
            'qbit_test_sluzhebnyy',
            'qbit_test_dash_read',
            'qbit_test_dash_admin'
        ] LOOP
            IF pg_catalog.has_table_privilege(v_role, pg_catalog.format('%I.%I', v_schema, v_table), 'SELECT')
               OR pg_catalog.has_table_privilege(v_role, pg_catalog.format('%I.%I', v_schema, v_table), 'INSERT')
               OR pg_catalog.has_table_privilege(v_role, pg_catalog.format('%I.%I', v_schema, v_table), 'UPDATE')
               OR pg_catalog.has_table_privilege(v_role, pg_catalog.format('%I.%I', v_schema, v_table), 'DELETE') THEN
                RAISE EXCEPTION 'Direct table DML leaked: role=% table=%.%', v_role, v_schema, v_table;
            END IF;
        END LOOP;
    END LOOP;

    -- vector(1024) and HNSW cosine index.
    IF pg_catalog.format_type(
        (SELECT a.atttypid FROM pg_catalog.pg_attribute a
          WHERE a.attrelid = (v_schema || '.fragmenty_znaniy')::regclass
            AND a.attname = 'vektor' AND a.attnum > 0 AND NOT a.attisdropped),
        (SELECT a.atttypmod FROM pg_catalog.pg_attribute a
          WHERE a.attrelid = (v_schema || '.fragmenty_znaniy')::regclass
            AND a.attname = 'vektor' AND a.attnum > 0 AND NOT a.attisdropped)
    ) NOT IN ('vector(1024)', 'extensions.vector(1024)') THEN
        RAISE EXCEPTION 'fragmenty_znaniy.vektor is not vector(1024)';
    END IF;

    IF pg_catalog.to_regclass(v_schema || '.ix_fragmenty_hnsw_cos') IS NULL THEN
        RAISE EXCEPTION 'HNSW cosine index is missing';
    END IF;
    SELECT pg_catalog.pg_get_indexdef(pg_catalog.to_regclass(v_schema || '.ix_fragmenty_hnsw_cos'))
      INTO v_indexdef;
    IF v_indexdef NOT ILIKE '%USING hnsw%'
       OR v_indexdef NOT ILIKE '%vector_cosine_ops%' THEN
        RAISE EXCEPTION 'ix_fragmenty_hnsw_cos is not HNSW cosine: %', v_indexdef;
    END IF;

    -- Required cross-stage FK and integrity triggers.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint con
        JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = v_schema
          AND c.relname = 'ishodyashchie_deystviya'
          AND con.conname = 'fk_ishodyashchie_zagruzka_znaniy'
          AND con.contype = 'f'
    ) THEN
        RAISE EXCEPTION 'DB-04 FK ishodyashchie_deystviya.zagruzka_id -> zagruzki_znaniy is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=v_schema AND c.relname='dokumenty_znaniy'
          AND t.tgname='ct_dokumenty_aktivnaya_versiya' AND NOT t.tgisinternal
    ) THEN
        RAISE EXCEPTION 'Active-version integrity trigger is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=v_schema AND c.relname='profili_indeksa'
          AND t.tgname='tr_profili_immutable' AND NOT t.tgisinternal
    ) THEN
        RAISE EXCEPTION 'Index-profile immutability trigger is missing';
    END IF;

    -- All public API functions: exact signature, owner, SECURITY DEFINER,
    -- fixed function-level search_path and no PUBLIC EXECUTE.
    FOREACH v_sig IN ARRAY ARRAY[
        'zaregistrirovat_zagruzku_znaniy(jsonb,bytea)',
        'zabrat_zadanie_znaniy(jsonb)',
        'prodlit_arendu_zadaniya_znaniy(jsonb)',
        'zavershit_zadanie_znaniy(jsonb)',
        'podgotovit_versiyu_znaniy(jsonb)',
        'sohranit_fragmenty_znaniy(jsonb)',
        'sohranit_kontrolnye_voprosy(jsonb)',
        'sohranit_proverki_znaniy(jsonb)',
        'poisk_chernovika_znaniy(jsonb)',
        'poisk_aktivnyh_znaniy(jsonb)',
        'opublikovat_versiyu_znaniy(jsonb)',
        'otozvat_dokument_znaniy(jsonb)'
    ] LOOP
        v_oid := pg_catalog.to_regprocedure(pg_catalog.format('%I.%s', v_schema, v_sig));
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'Missing function %.%', v_schema, v_sig;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND pg_catalog.pg_get_userbyid(p.proowner) = 'qbit_test_owner'
              AND EXISTS (
                  SELECT 1 FROM unnest(p.proconfig) cfg
                  WHERE cfg LIKE 'search_path=%'
              )
        ) THEN
            RAISE EXCEPTION 'Unsafe owner/SECURITY DEFINER/search_path for %.%', v_schema, v_sig;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(
                COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
            ) x
            WHERE p.oid = v_oid
              AND x.grantee = 0
              AND x.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'PUBLIC EXECUTE leaked on %.%', v_schema, v_sig;
        END IF;
    END LOOP;

    -- Exact effective runtime matrix. No role switching is used.
    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_bot',
        v_schema || '.poisk_aktivnyh_znaniy(jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'qbit_test_bot lacks active RAG';
    END IF;
    IF pg_catalog.has_function_privilege('qbit_test_bot', v_schema || '.poisk_chernovika_znaniy(jsonb)', 'EXECUTE')
       OR pg_catalog.has_function_privilege('qbit_test_bot', v_schema || '.opublikovat_versiyu_znaniy(jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'qbit_test_bot can access draft/publish';
    END IF;

    FOREACH v_sig IN ARRAY ARRAY[
        'zaregistrirovat_zagruzku_znaniy(jsonb,bytea)',
        'zabrat_zadanie_znaniy(jsonb)',
        'prodlit_arendu_zadaniya_znaniy(jsonb)',
        'zavershit_zadanie_znaniy(jsonb)',
        'podgotovit_versiyu_znaniy(jsonb)',
        'sohranit_fragmenty_znaniy(jsonb)',
        'sohranit_kontrolnye_voprosy(jsonb)',
        'sohranit_proverki_znaniy(jsonb)',
        'poisk_chernovika_znaniy(jsonb)',
        'opublikovat_versiyu_znaniy(jsonb)'
    ] LOOP
        IF NOT pg_catalog.has_function_privilege(
            'qbit_test_sluzhebnyy',
            pg_catalog.format('%I.%s', v_schema, v_sig),
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'qbit_test_sluzhebnyy lacks EXECUTE on %', v_sig;
        END IF;
    END LOOP;

    IF pg_catalog.has_function_privilege('qbit_test_sluzhebnyy', v_schema || '.poisk_aktivnyh_znaniy(jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'qbit_test_sluzhebnyy unexpectedly has active RAG';
    END IF;

    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_dash_admin',
        v_schema || '.otozvat_dokument_znaniy(jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'qbit_test_dash_admin lacks revoke';
    END IF;
    IF pg_catalog.has_function_privilege(
        'qbit_test_dash_admin',
        v_schema || '.opublikovat_versiyu_znaniy(jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'qbit_test_dash_admin unexpectedly has publish';
    END IF;
END
$verify$;

SELECT jsonb_build_object(
    'db04_05_verifier_result',
    jsonb_build_object(
        'status', 'verified',
        'verifier_version', 'KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH',
        'schema', 'qbit_bot_pervichnogo_obrascheniya',
        'experimental_objects_absent', true,
        'normative_tables_present_and_empty', true,
        'owners_ok', true,
        'security_definer_and_search_path_ok', true,
        'public_execute_denied', true,
        'runtime_direct_dml_denied', true,
        'execute_matrix_ok', true,
        'vector_1024_hnsw_ok', true,
        'integrity_triggers_ok', true,
        'role_switch_used', false,
        'runtime_execution_under_credentials_tested_here', false
    )
) AS db04_05_verifier_result;

ROLLBACK;
