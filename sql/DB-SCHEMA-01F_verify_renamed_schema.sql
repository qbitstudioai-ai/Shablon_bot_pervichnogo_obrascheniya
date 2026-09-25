-- DB-SCHEMA-01F v0.3: finalize/verify already-renamed qBit project schema
-- Project: Shablon_bot_pervichnogo_obrascheniya
--
-- EXPECTED CURRENT STATE
--   old schema: qbit_test                          ABSENT
--   new schema: qbit_bot_pervichnogo_obrascheniya PRESENT
--   roles remain named qbit_test_* by explicit project decision
--   production schema qbit is NOT required in this test stage; DB-01 explicitly did not create it
--
-- PURPOSE
--   This file does NOT rename schemas and does NOT recreate functions.
--   It only verifies the state left by DB-SCHEMA-01 after the rename already
--   committed while an old post-COMMIT reporting SELECT failed.
--
-- SAFE TO RUN
--   * no DDL
--   * no DML
--   * no GRANT/REVOKE
--   * no production writes
--   * one read-only transaction

BEGIN;

SET TRANSACTION READ ONLY;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

DO $dbschema01f$
DECLARE
    v_owner text;
    v_table_count integer;
    v_function_count integer;
    v_old_ref_count integer;
    v_bad_search_path integer;
    v_bad_owner integer;
    v_bad_secdef integer;
    v_public_execute integer;
    v_bot_execute integer;
    v_service_execute integer;
    v_dash_admin_execute integer;
    v_runtime_direct_dml integer;
BEGIN
    IF current_database() <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-SCHEMA-01F expected database postgres, actual %',
            current_database();
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-SCHEMA-01F must run from trusted postgres session; session_user=%',
            session_user;
    END IF;

    IF pg_catalog.to_regnamespace('qbit_test') IS NOT NULL THEN
        RAISE EXCEPTION
            'Old schema qbit_test still exists; finalizer expects already-renamed state';
    END IF;

    IF pg_catalog.to_regnamespace('qbit_bot_pervichnogo_obrascheniya') IS NULL THEN
        RAISE EXCEPTION
            'New schema qbit_bot_pervichnogo_obrascheniya does not exist';
    END IF;

    SELECT r.rolname
      INTO v_owner
      FROM pg_catalog.pg_namespace AS n
      JOIN pg_catalog.pg_roles AS r
        ON r.oid = n.nspowner
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya';

    IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION
            'Schema owner mismatch: expected qbit_test_owner, actual %',
            v_owner;
    END IF;

    IF pg_catalog.has_database_privilege(
        'qbit_test_owner',
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'Temporary CREATE ON DATABASE is still present on qbit_test_owner';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_namespace AS n
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(
                n.nspacl,
                pg_catalog.acldefault('n',n.nspowner)
            )
          ) AS a
         WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
           AND a.grantee=0
           AND a.privilege_type IN ('USAGE','CREATE')
    ) THEN
        RAISE EXCEPTION
            'PUBLIC unexpectedly has schema privilege on qbit_bot_pervichnogo_obrascheniya';
    END IF;

    IF NOT pg_catalog.has_schema_privilege(
        'qbit_test_bot',
        'qbit_bot_pervichnogo_obrascheniya',
        'USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya',
        'USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_dash_read',
        'qbit_bot_pervichnogo_obrascheniya',
        'USAGE'
    )
    OR NOT pg_catalog.has_schema_privilege(
        'qbit_test_dash_admin',
        'qbit_bot_pervichnogo_obrascheniya',
        'USAGE'
    ) THEN
        RAISE EXCEPTION
            'Expected runtime USAGE on renamed schema is missing';
    END IF;

    SELECT count(*)
      INTO v_table_count
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND c.relkind = 'r';

    IF v_table_count <> 25 THEN
        RAISE EXCEPTION
            'Table count mismatch: expected 25, actual %',
            v_table_count;
    END IF;

    WITH expected(name, execute_role) AS (
        VALUES
            ('zaregistrirovat_vhod_klienta','bot'),
            ('sohranit_vlozhenie','bot'),
            ('sohranit_transkripciyu_golosa','bot'),
            ('sohranit_obezlichivanie','bot'),
            ('poluchit_kontekst_dialoga','bot'),
            ('sohranit_fakty_i_pamyat','bot'),
            ('proverit_limit_chastoty','bot'),
            ('zapisat_narushenie_tematiky','bot'),
            ('razblokirovat_polzovatelya','dash_admin'),
            ('zabrat_zadanie_obrabotki','bot'),
            ('prodlit_arendu_zadaniya','bot'),
            ('zavershit_zadanie_obrabotki','bot'),
            ('sozdat_ishodyashchee_deystvie','bot'),
            ('zabrat_ishodyashchee_deystvie','bot'),
            ('zafiksirovat_rezultat_ishodyashchego','bot'),
            ('podgotovit_napominanie','bot'),
            ('zafiksirovat_poteryu_bez_otveta','bot'),
            ('zaregistrirovat_sluzhebnoe_sobytie','service'),
            ('podtverdit_lichnyy_chat_menedzhera','service'),
            ('zabrat_sozdanie_operator_temy','service'),
            ('podtverdit_operator_temu','service'),
            ('otmetit_temu_neizvestnoy','service'),
            ('zabrat_sobytie_zerkala','service'),
            ('zafiksirovat_rezultat_zerkala','service'),
            ('zabrat_dialog_operatorom','service'),
            ('vernut_dialog_botu','service'),
            ('sozdat_ruchnoe_ishodyashchee','service'),
            ('sozdat_lichnoe_uvedomlenie','bot')
    ),
    actual AS MATERIALIZED (
        SELECT
            p.oid,
            p.proname,
            p.proowner,
            p.proacl,
            p.prosecdef,
            p.proconfig,
            e.execute_role
        FROM expected AS e
        JOIN pg_catalog.pg_proc AS p
          ON p.proname = e.name
        JOIN pg_catalog.pg_namespace AS n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
          AND p.prokind = 'f'
          AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
    )
    SELECT count(*)
      INTO v_function_count
      FROM actual;

    IF v_function_count <> 28 THEN
        RAISE EXCEPTION
            'Expected function count mismatch: expected 28, actual %',
            v_function_count;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.prokind = 'f'
           AND p.proname IN (
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie',
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya',
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki',
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta',
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie'
           )
         GROUP BY p.proname
        HAVING count(*) <> 1
    ) THEN
        RAISE EXCEPTION
            'Duplicate/overloaded expected function name detected';
    END IF;

    WITH target AS MATERIALIZED (
        SELECT p.oid
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.prokind = 'f'
           AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
           AND p.proname IN (
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie',
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya',
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki',
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta',
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie'
           )
    )
    SELECT count(*)
      INTO v_old_ref_count
      FROM target AS t
     WHERE pg_catalog.strpos(
            pg_catalog.pg_get_functiondef(t.oid),
            'qbit_test.'
           ) > 0;

    IF v_old_ref_count <> 0 THEN
        RAISE EXCEPTION
            'Old qbit_test qualified refs remain in % expected functions',
            v_old_ref_count;
    END IF;

    SELECT count(*)
      INTO v_bad_search_path
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND p.prokind = 'f'
       AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
       AND p.proname IN (
            'zaregistrirovat_vhod_klienta',
            'sohranit_vlozhenie',
            'sohranit_transkripciyu_golosa',
            'sohranit_obezlichivanie',
            'poluchit_kontekst_dialoga',
            'sohranit_fakty_i_pamyat',
            'proverit_limit_chastoty',
            'zapisat_narushenie_tematiky',
            'razblokirovat_polzovatelya',
            'zabrat_zadanie_obrabotki',
            'prodlit_arendu_zadaniya',
            'zavershit_zadanie_obrabotki',
            'sozdat_ishodyashchee_deystvie',
            'zabrat_ishodyashchee_deystvie',
            'zafiksirovat_rezultat_ishodyashchego',
            'podgotovit_napominanie',
            'zafiksirovat_poteryu_bez_otveta',
            'zaregistrirovat_sluzhebnoe_sobytie',
            'podtverdit_lichnyy_chat_menedzhera',
            'zabrat_sozdanie_operator_temy',
            'podtverdit_operator_temu',
            'otmetit_temu_neizvestnoy',
            'zabrat_sobytie_zerkala',
            'zafiksirovat_rezultat_zerkala',
            'zabrat_dialog_operatorom',
            'vernut_dialog_botu',
            'sozdat_ruchnoe_ishodyashchee',
            'sozdat_lichnoe_uvedomlenie'
       )
       AND NOT (
            COALESCE(p.proconfig, ARRAY[]::text[])
            @> ARRAY[
                'search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya'
            ]::text[]
       );

    IF v_bad_search_path <> 0 THEN
        RAISE EXCEPTION
            'Expected functions with wrong fixed search_path: %',
            v_bad_search_path;
    END IF;

    SELECT count(*)
      INTO v_bad_owner
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
      JOIN pg_catalog.pg_roles AS r
        ON r.oid = p.proowner
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND p.prokind = 'f'
       AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
       AND p.proname IN (
            'zaregistrirovat_vhod_klienta',
            'sohranit_vlozhenie',
            'sohranit_transkripciyu_golosa',
            'sohranit_obezlichivanie',
            'poluchit_kontekst_dialoga',
            'sohranit_fakty_i_pamyat',
            'proverit_limit_chastoty',
            'zapisat_narushenie_tematiky',
            'razblokirovat_polzovatelya',
            'zabrat_zadanie_obrabotki',
            'prodlit_arendu_zadaniya',
            'zavershit_zadanie_obrabotki',
            'sozdat_ishodyashchee_deystvie',
            'zabrat_ishodyashchee_deystvie',
            'zafiksirovat_rezultat_ishodyashchego',
            'podgotovit_napominanie',
            'zafiksirovat_poteryu_bez_otveta',
            'zaregistrirovat_sluzhebnoe_sobytie',
            'podtverdit_lichnyy_chat_menedzhera',
            'zabrat_sozdanie_operator_temy',
            'podtverdit_operator_temu',
            'otmetit_temu_neizvestnoy',
            'zabrat_sobytie_zerkala',
            'zafiksirovat_rezultat_zerkala',
            'zabrat_dialog_operatorom',
            'vernut_dialog_botu',
            'sozdat_ruchnoe_ishodyashchee',
            'sozdat_lichnoe_uvedomlenie'
       )
       AND r.rolname <> 'qbit_test_owner';

    IF v_bad_owner <> 0 THEN
        RAISE EXCEPTION
            'Expected functions with wrong owner: %',
            v_bad_owner;
    END IF;

    SELECT count(*)
      INTO v_bad_secdef
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND p.prokind = 'f'
       AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
       AND p.proname IN (
            'zaregistrirovat_vhod_klienta',
            'sohranit_vlozhenie',
            'sohranit_transkripciyu_golosa',
            'sohranit_obezlichivanie',
            'poluchit_kontekst_dialoga',
            'sohranit_fakty_i_pamyat',
            'proverit_limit_chastoty',
            'zapisat_narushenie_tematiky',
            'razblokirovat_polzovatelya',
            'zabrat_zadanie_obrabotki',
            'prodlit_arendu_zadaniya',
            'zavershit_zadanie_obrabotki',
            'sozdat_ishodyashchee_deystvie',
            'zabrat_ishodyashchee_deystvie',
            'zafiksirovat_rezultat_ishodyashchego',
            'podgotovit_napominanie',
            'zafiksirovat_poteryu_bez_otveta',
            'zaregistrirovat_sluzhebnoe_sobytie',
            'podtverdit_lichnyy_chat_menedzhera',
            'zabrat_sozdanie_operator_temy',
            'podtverdit_operator_temu',
            'otmetit_temu_neizvestnoy',
            'zabrat_sobytie_zerkala',
            'zafiksirovat_rezultat_zerkala',
            'zabrat_dialog_operatorom',
            'vernut_dialog_botu',
            'sozdat_ruchnoe_ishodyashchee',
            'sozdat_lichnoe_uvedomlenie'
       )
       AND NOT p.prosecdef;

    IF v_bad_secdef <> 0 THEN
        RAISE EXCEPTION
            'Expected functions without SECURITY DEFINER: %',
            v_bad_secdef;
    END IF;

    WITH target AS MATERIALIZED (
        SELECT p.oid,p.proacl,p.proowner
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.prokind = 'f'
           AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
           AND p.proname IN (
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie',
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya',
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki',
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta',
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie'
           )
    )
    SELECT count(DISTINCT t.oid)
      INTO v_public_execute
      FROM target AS t
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
            t.proacl,
            pg_catalog.acldefault('f',t.proowner)
        )
      ) AS a
     WHERE a.grantee=0
       AND a.privilege_type='EXECUTE';

    IF v_public_execute <> 0 THEN
        RAISE EXCEPTION
            'PUBLIC EXECUTE remains on % expected functions',
            v_public_execute;
    END IF;

    WITH target AS MATERIALIZED (
        SELECT p.oid
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND p.prokind = 'f'
           AND (
                (
                    p.proname='zaregistrirovat_vhod_klienta'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                )
                OR (
                    p.proname='sohranit_vlozhenie'
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                )
                OR (
                    p.proname NOT IN (
                        'zaregistrirovat_vhod_klienta',
                        'sohranit_vlozhenie'
                    )
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                )
           )
           AND p.proname IN (
                'zaregistrirovat_vhod_klienta',
                'sohranit_vlozhenie',
                'sohranit_transkripciyu_golosa',
                'sohranit_obezlichivanie',
                'poluchit_kontekst_dialoga',
                'sohranit_fakty_i_pamyat',
                'proverit_limit_chastoty',
                'zapisat_narushenie_tematiky',
                'razblokirovat_polzovatelya',
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki',
                'sozdat_ishodyashchee_deystvie',
                'zabrat_ishodyashchee_deystvie',
                'zafiksirovat_rezultat_ishodyashchego',
                'podgotovit_napominanie',
                'zafiksirovat_poteryu_bez_otveta',
                'zaregistrirovat_sluzhebnoe_sobytie',
                'podtverdit_lichnyy_chat_menedzhera',
                'zabrat_sozdanie_operator_temy',
                'podtverdit_operator_temu',
                'otmetit_temu_neizvestnoy',
                'zabrat_sobytie_zerkala',
                'zafiksirovat_rezultat_zerkala',
                'zabrat_dialog_operatorom',
                'vernut_dialog_botu',
                'sozdat_ruchnoe_ishodyashchee',
                'sozdat_lichnoe_uvedomlenie'
           )
    )
    SELECT
        count(*) FILTER (
            WHERE pg_catalog.has_function_privilege(
                'qbit_test_bot', t.oid, 'EXECUTE'
            )
        ),
        count(*) FILTER (
            WHERE pg_catalog.has_function_privilege(
                'qbit_test_sluzhebnyy', t.oid, 'EXECUTE'
            )
        ),
        count(*) FILTER (
            WHERE pg_catalog.has_function_privilege(
                'qbit_test_dash_admin', t.oid, 'EXECUTE'
            )
        )
      INTO
        v_bot_execute,
        v_service_execute,
        v_dash_admin_execute
      FROM target AS t;

    IF v_bot_execute <> 17
       OR v_service_execute <> 10
       OR v_dash_admin_execute <> 1 THEN
        RAISE EXCEPTION
            'EXECUTE distribution mismatch: bot %, service %, dash_admin %; expected 17/10/1',
            v_bot_execute,
            v_service_execute,
            v_dash_admin_execute;
    END IF;

    WITH runtime_roles(role_name) AS (
        VALUES
            ('qbit_test_bot'),
            ('qbit_test_sluzhebnyy'),
            ('qbit_test_dash_read'),
            ('qbit_test_dash_admin')
    ),
    target_tables AS MATERIALIZED (
        SELECT c.oid
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
         WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
           AND c.relkind = 'r'
    )
    SELECT count(*)
      INTO v_runtime_direct_dml
      FROM runtime_roles AS rr
      CROSS JOIN target_tables AS t
     WHERE pg_catalog.has_table_privilege(
                rr.role_name,
                t.oid,
                'INSERT'
           )
        OR pg_catalog.has_table_privilege(
                rr.role_name,
                t.oid,
                'UPDATE'
           )
        OR pg_catalog.has_table_privilege(
                rr.role_name,
                t.oid,
                'DELETE'
           );

    IF v_runtime_direct_dml <> 0 THEN
        RAISE EXCEPTION
            'Runtime direct DML privilege remains on % role/table pairs',
            v_runtime_direct_dml;
    END IF;

    IF NOT pg_catalog.pg_has_role(
        'postgres',
        'qbit_test_owner',
        'SET'
    ) THEN
        RAISE EXCEPTION
            'postgres can no longer SET ROLE qbit_test_owner';
    END IF;

    IF pg_catalog.has_schema_privilege(
        'qbit_test_bot',
        'kompaniya_001_test',
        'USAGE'
    )
    OR pg_catalog.has_schema_privilege(
        'qbit_test_sluzhebnyy',
        'kompaniya_001_test',
        'USAGE'
    ) THEN
        RAISE EXCEPTION
            'qBit runtime role unexpectedly has USAGE on kompaniya_001_test';
    END IF;

    IF pg_catalog.to_regnamespace('kompaniya_001_test') IS NULL THEN
        RAISE EXCEPTION
            'Canary schema kompaniya_001_test unexpectedly missing';
    END IF;
END
$dbschema01f$;

COMMIT;

SELECT jsonb_build_object(
    'db_schema_01f_status','verified',
    'database',current_database(),
    'old_schema_absent',
        pg_catalog.to_regnamespace('qbit_test') IS NULL,
    'new_schema',
        'qbit_bot_pervichnogo_obrascheniya',
    'new_schema_present',
        pg_catalog.to_regnamespace(
            'qbit_bot_pervichnogo_obrascheniya'
        ) IS NOT NULL,
    'schema_owner',
        (
            SELECT r.rolname
              FROM pg_catalog.pg_namespace AS n
              JOIN pg_catalog.pg_roles AS r
                ON r.oid=n.nspowner
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
        ),
    'tables_ok',
        (
            SELECT count(*)=25
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid=c.relnamespace
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
               AND c.relkind='r'
        ),
    'functions_ok',
        (
            SELECT count(*)=28
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid=p.pronamespace
             WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
               AND p.prokind='f'
               AND (
                    (
                        p.proname='zaregistrirovat_vhod_klienta'
                        AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_vhod jsonb'
                    )
                    OR (
                        p.proname='sohranit_vlozhenie'
                        AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb, p_soderzhimoe bytea'
                    )
                    OR (
                        p.proname NOT IN (
                            'zaregistrirovat_vhod_klienta',
                            'sohranit_vlozhenie'
                        )
                        AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_dannye jsonb'
                    )
               )
               AND p.proname IN (
                    'zaregistrirovat_vhod_klienta',
                    'sohranit_vlozhenie',
                    'sohranit_transkripciyu_golosa',
                    'sohranit_obezlichivanie',
                    'poluchit_kontekst_dialoga',
                    'sohranit_fakty_i_pamyat',
                    'proverit_limit_chastoty',
                    'zapisat_narushenie_tematiky',
                    'razblokirovat_polzovatelya',
                    'zabrat_zadanie_obrabotki',
                    'prodlit_arendu_zadaniya',
                    'zavershit_zadanie_obrabotki',
                    'sozdat_ishodyashchee_deystvie',
                    'zabrat_ishodyashchee_deystvie',
                    'zafiksirovat_rezultat_ishodyashchego',
                    'podgotovit_napominanie',
                    'zafiksirovat_poteryu_bez_otveta',
                    'zaregistrirovat_sluzhebnoe_sobytie',
                    'podtverdit_lichnyy_chat_menedzhera',
                    'zabrat_sozdanie_operator_temy',
                    'podtverdit_operator_temu',
                    'otmetit_temu_neizvestnoy',
                    'zabrat_sobytie_zerkala',
                    'zafiksirovat_rezultat_zerkala',
                    'zabrat_dialog_operatorom',
                    'vernut_dialog_botu',
                    'sozdat_ruchnoe_ishodyashchee',
                    'sozdat_lichnoe_uvedomlenie'
               )
        ),
    'temporary_database_create_revoked',
        NOT pg_catalog.has_database_privilege(
            'qbit_test_owner',
            current_database(),
            'CREATE'
        ),
    'runtime_direct_dml_denied',true,
    'execute_distribution','bot=17/service=10/dash_admin=1',
    'production_schema_qbit_present_informational',
        pg_catalog.to_regnamespace('qbit') IS NOT NULL,
    'production_schema_qbit_required',false,
    'canary_schema_present',
        pg_catalog.to_regnamespace('kompaniya_001_test') IS NOT NULL,
    'supabase_stage_complete',true,
    'next_stage','PRE-02_n8n_openrouter',
    'result',
    'DB-SCHEMA-01F VERIFIED: qbit_bot_pervichnogo_obrascheniya is the canonical qBit project schema; old qbit_test is absent; 25 tables and 28 SECURITY DEFINER functions use the new schema/search_path with preserved runtime isolation; temporary database CREATE is revoked; canary schema remains present. Production schema qbit is not required in this test stage and its current presence is reported only. Current Supabase stage is complete; proceed to PRE-02 in n8n.'
) AS db_schema_01f_result;
