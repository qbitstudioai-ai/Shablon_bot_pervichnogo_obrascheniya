-- KB-01R2 READ ONLY v0.1
-- CONTROL STRING: KB-01R2_READ_ONLY_v0.1
-- Назначение: только read-only инвентаризация experimental KB в test schema.
-- Не содержит DDL/DML, не вызывает прикладные функции и не читает содержимое документов.
-- Production schema не затрагивается.

WITH
row_counts AS (
    SELECT jsonb_build_object(
        'znaniya_dokumenty', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty
        ),
        'znaniya_versii', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
        ),
        'znaniya_fragmenty', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty
        )
    ) AS data
),
version_status_counts AS (
    SELECT COALESCE(
        jsonb_object_agg(status, cnt ORDER BY status),
        '{}'::jsonb
    ) AS data
    FROM (
        SELECT status, count(*)::bigint AS cnt
        FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
        GROUP BY status
    ) AS s
),
state_counts AS (
    SELECT jsonb_build_object(
        'dokumenty_s_aktivnoy_versiey', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty
            WHERE aktivnaya_versiya_id IS NOT NULL
        ),
        'versii_s_arendoy', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
            WHERE vladelec_arendy IS NOT NULL OR arenda_do IS NOT NULL
        ),
        'versii_s_oshibkoy', (
            SELECT count(*)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
            WHERE kod_oshibki IS NOT NULL OR opisanie_oshibki IS NOT NULL
        ),
        'versii_s_fragmentami', (
            SELECT count(DISTINCT versiya_id)::bigint
            FROM qbit_bot_pervichnogo_obrascheniya.znaniya_fragmenty
        )
    ) AS data
),
tables_found AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'name', c.relname,
                'kind', c.relkind,
                'owner', pg_catalog.pg_get_userbyid(c.relowner)
            ) ORDER BY c.relname
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND c.relkind IN ('r','p','v','m')
      AND (
          c.relname LIKE '%znani%'
          OR c.relname LIKE 'kb01%'
      )
),
columns_found AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'table', c.relname,
                'position', a.attnum,
                'column', a.attname,
                'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
                'not_null', a.attnotnull,
                'default', pg_catalog.pg_get_expr(ad.adbin, ad.adrelid)
            ) ORDER BY c.relname, a.attnum
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    JOIN pg_catalog.pg_attribute AS a
      ON a.attrelid = c.oid
     AND a.attnum > 0
     AND NOT a.attisdropped
    LEFT JOIN pg_catalog.pg_attrdef AS ad
      ON ad.adrelid = c.oid
     AND ad.adnum = a.attnum
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND c.relkind IN ('r','p')
      AND (
          c.relname LIKE '%znani%'
          OR c.relname LIKE 'kb01%'
      )
),
constraints_found AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'table', c.relname,
                'name', con.conname,
                'type', con.contype,
                'definition', pg_catalog.pg_get_constraintdef(con.oid, true)
            ) ORDER BY c.relname, con.conname
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND (
          c.relname LIKE '%znani%'
          OR c.relname LIKE 'kb01%'
      )
),
indexes_found AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'table', i.tablename,
                'name', i.indexname,
                'definition', i.indexdef
            ) ORDER BY i.tablename, i.indexname
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_indexes AS i
    WHERE i.schemaname = 'qbit_bot_pervichnogo_obrascheniya'
      AND (
          i.tablename LIKE '%znani%'
          OR i.tablename LIKE 'kb01%'
      )
),
functions_found AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'name', p.proname,
                'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
                'result_type', pg_catalog.pg_get_function_result(p.oid),
                'owner', pg_catalog.pg_get_userbyid(p.proowner),
                'security_definer', p.prosecdef,
                'config', COALESCE(to_jsonb(p.proconfig), '[]'::jsonb),
                'acl', COALESCE(to_jsonb(p.proacl::text), 'null'::jsonb),
                'service_execute', pg_catalog.has_function_privilege(
                    'qbit_test_sluzhebnyy', p.oid, 'EXECUTE'
                ),
                'public_execute', EXISTS (
                    SELECT 1
                    FROM pg_catalog.aclexplode(
                        COALESCE(
                            p.proacl,
                            pg_catalog.acldefault('f', p.proowner)
                        )
                    ) AS x
                    WHERE x.grantee = 0
                      AND x.privilege_type = 'EXECUTE'
                )
            ) ORDER BY p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND (
          p.proname LIKE 'kb01_%'
          OR p.proname LIKE '%znani%'
      )
),
service_table_privileges AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'table', c.relname,
                'select', pg_catalog.has_table_privilege(
                    'qbit_test_sluzhebnyy', c.oid, 'SELECT'
                ),
                'insert', pg_catalog.has_table_privilege(
                    'qbit_test_sluzhebnyy', c.oid, 'INSERT'
                ),
                'update', pg_catalog.has_table_privilege(
                    'qbit_test_sluzhebnyy', c.oid, 'UPDATE'
                ),
                'delete', pg_catalog.has_table_privilege(
                    'qbit_test_sluzhebnyy', c.oid, 'DELETE'
                )
            ) ORDER BY c.relname
        ),
        '[]'::jsonb
    ) AS data
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
      AND c.relkind IN ('r','p')
      AND (
          c.relname LIKE '%znani%'
          OR c.relname LIKE 'kb01%'
      )
)
SELECT pg_catalog.jsonb_pretty(
    jsonb_build_object(
        'kb01r2_read_only_result', jsonb_build_object(
            'verifier_version', 'KB-01R2_READ_ONLY_v0.1',
            'database', current_database(),
            'session_user', session_user,
            'schema', 'qbit_bot_pervichnogo_obrascheniya',
            'service_schema_usage', pg_catalog.has_schema_privilege(
                'qbit_test_sluzhebnyy',
                'qbit_bot_pervichnogo_obrascheniya',
                'USAGE'
            ),
            'row_counts', (SELECT data FROM row_counts),
            'version_status_counts', (SELECT data FROM version_status_counts),
            'state_counts', (SELECT data FROM state_counts),
            'tables', (SELECT data FROM tables_found),
            'columns', (SELECT data FROM columns_found),
            'constraints', (SELECT data FROM constraints_found),
            'indexes', (SELECT data FROM indexes_found),
            'functions', (SELECT data FROM functions_found),
            'service_table_privileges', (SELECT data FROM service_table_privileges)
        )
    )
) AS kb01r2_result;
