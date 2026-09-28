-- DB-03E v0.3 read-only verifier
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Safe to run only AFTER DB-03E migration is explicitly authorized and applied.
-- Makes no changes.

WITH funcs AS (
    SELECT
        p.oid,
        p.proname,
        p.prosecdef,
        p.proconfig,
        r.rolname AS owner_name,
        pg_catalog.pg_get_functiondef(p.oid) AS def
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND p.proname IN (
            'poluchit_soderzhimoe_zadaniya',
            'poluchit_sostoyanie_operatora',
            'ustanovit_zapret_iniciativy',
            'zaprosit_cheloveka',
            'obrabotat_sleduyushchee_napominanie'
      )
), checks AS (
    SELECT
        count(*) = 5 AS functions_present,
        bool_and(prosecdef) AS security_definer_ok,
        bool_and(owner_name = 'qbit_test_owner') AS owner_ok,
        bool_and(
            COALESCE(proconfig, ARRAY[]::text[])
            @> ARRAY['search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya']::text[]
        ) AS search_path_ok,
        bool_and(
            NOT EXISTS (
                SELECT 1
                FROM pg_catalog.aclexplode(
                    COALESCE(
                        (SELECT p2.proacl FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=funcs.oid),
                        pg_catalog.acldefault(
                            'f',
                            (SELECT p2.proowner FROM pg_catalog.pg_proc AS p2 WHERE p2.oid=funcs.oid)
                        )
                    )
                ) AS a
                WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
            )
        ) AS public_execute_denied,
        bool_and(
            CASE
                WHEN proname='poluchit_sostoyanie_operatora' THEN
                    pg_catalog.has_function_privilege('qbit_test_sluzhebnyy',oid,'EXECUTE')
                    AND NOT pg_catalog.has_function_privilege('qbit_test_bot',oid,'EXECUTE')
                ELSE
                    pg_catalog.has_function_privilege('qbit_test_bot',oid,'EXECUTE')
                    AND NOT pg_catalog.has_function_privilege('qbit_test_sluzhebnyy',oid,'EXECUTE')
            END
        ) AS execute_split_ok,
        bool_and(
            CASE proname
                WHEN 'poluchit_soderzhimoe_zadaniya' THEN
                    pg_catalog.strpos(def,'stale_lease_owner')>0
                    AND pg_catalog.strpos(def,'arenda_istekla')>0
                    AND pg_catalog.strpos(def,'payload_ishodnyy')>0
                    AND pg_catalog.strpos(def,'FOR UPDATE OF z, d')>0
                WHEN 'poluchit_sostoyanie_operatora' THEN
                    pg_catalog.strpos(def,'operator_telegram_temy')>0
                    AND pg_catalog.strpos(def,'versiya_dialoga')>0
                    AND pg_catalog.strpos(def,'tekushchiy_menedzher_id')>0
                    AND pg_catalog.strpos(def,'soobshcheniya')=0
                    AND pg_catalog.strpos(def,'sootvetstviya_pii')=0
                WHEN 'ustanovit_zapret_iniciativy' THEN
                    pg_catalog.strpos(def,'zapret_iniciativnyh_soobshcheniy')>0
                    AND pg_catalog.strpos(def,'initiative_preference_changed')>0
                WHEN 'zaprosit_cheloveka' THEN
                    pg_catalog.strpos(def,'''nuzhen_chelovek''')>0
                    AND pg_catalog.strpos(def,'zabrat_dialog_operatorom')=0
                WHEN 'obrabotat_sleduyushchee_napominanie' THEN
                    pg_catalog.strpos(def,'FOR UPDATE SKIP LOCKED')>0
                    AND pg_catalog.strpos(def,'podgotovit_napominanie')>0
                    AND pg_catalog.strpos(def,'zafiksirovat_poteryu_bez_otveta')>0
                ELSE false
            END
        ) AS source_contract_ok
    FROM funcs
), dml AS (
    SELECT NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
        WHERE n.nspname='qbit_bot_pervichnogo_obrascheniya'
          AND c.relkind='r'
          AND (
               pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'SELECT')
            OR pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'INSERT')
            OR pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'UPDATE')
            OR pg_catalog.has_table_privilege('qbit_test_bot',c.oid,'DELETE')
            OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'SELECT')
            OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'INSERT')
            OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'UPDATE')
            OR pg_catalog.has_table_privilege('qbit_test_sluzhebnyy',c.oid,'DELETE')
          )
    ) AS runtime_direct_dml_denied
)
SELECT jsonb_build_object(
    'verifier_version','DB-03E_v0.3_read_only',
    'db03e_status',
    CASE
        WHEN c.functions_present
         AND c.security_definer_ok
         AND c.owner_ok
         AND c.search_path_ok
         AND c.public_execute_denied
         AND c.execute_split_ok
         AND c.source_contract_ok
         AND d.runtime_direct_dml_denied
        THEN 'verified' ELSE 'failed'
    END,
    'functions_present',c.functions_present,
    'security_definer_ok',c.security_definer_ok,
    'owner_ok',c.owner_ok,
    'search_path_ok',c.search_path_ok,
    'public_execute_denied',c.public_execute_denied,
    'execute_split_ok',c.execute_split_ok,
    'source_contract_ok',c.source_contract_ok,
    'runtime_direct_dml_denied',d.runtime_direct_dml_denied,
    'production_untouched_informational',true
) AS db03e_verifier_result
FROM checks AS c
CROSS JOIN dml AS d;
