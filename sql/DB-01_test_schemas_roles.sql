-- DB-01 v0.2: test schemas and restricted roles
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- PURPOSE
--   Create ONLY two isolated TEST schemas:
--     1) qbit_test
--     2) kompaniya_001_test (fictional isolation canary)
--   and their restricted PostgreSQL roles.
--
-- IMPORTANT
--   * Run the WHOLE file in Supabase Studio -> SQL Editor as the trusted postgres role.
--   * Supabase postgres is intentionally not SUPERUSER; this file checks concrete privileges.
--   * This file DOES NOT create qbit production schema or production roles.
--   * This file DOES NOT create/change passwords or Credentials.
--   * LOGIN roles are created with PASSWORD NULL.
--   * This file DOES NOT install extensions; it only verifies vector is already installed.
--   * The migration is transactional. On any error before COMMIT, DB-01 changes roll back.
--   * It contains no DROP SCHEMA, DROP ROLE, DELETE, TRUNCATE, or business-data changes.
--
-- NOTE ABOUT FUTURE MIGRATIONS
--   DB-02...DB-05 must create company objects as the matching *_owner role
--   (normally via controlled SET ROLE from *_deploy) and use schema-qualified names.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db01$
DECLARE
    v_server_num integer;
    v_is_superuser boolean;
    v_can_create_roles boolean;
BEGIN
    v_server_num := current_setting('server_version_num')::integer;

    IF v_server_num < 170000 THEN
        RAISE EXCEPTION
            'DB-01 requires PostgreSQL 17+, current server_version_num=%',
            v_server_num;
    END IF;

    SELECT r.rolsuper, r.rolcreaterole
      INTO v_is_superuser, v_can_create_roles
      FROM pg_catalog.pg_roles AS r
     WHERE r.rolname = session_user;

    IF session_user <> 'postgres'
       AND COALESCE(v_is_superuser, false) IS NOT TRUE
    THEN
        RAISE EXCEPTION
            'DB-01 must be run as trusted postgres (or a real superuser). session_user=%',
            session_user;
    END IF;

    IF COALESCE(v_is_superuser, false) IS NOT TRUE
       AND COALESCE(v_can_create_roles, false) IS NOT TRUE
    THEN
        RAISE EXCEPTION
            'DB-01 requires CREATEROLE when postgres is not SUPERUSER. session_user=%',
            session_user;
    END IF;

    IF NOT pg_catalog.has_database_privilege(
        session_user,
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'DB-01 requires CREATE on database %. session_user=%',
            current_database(),
            session_user;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_extension
         WHERE extname = 'vector'
    ) THEN
        RAISE EXCEPTION
            'Extension vector is not installed. DB-01 does not install extensions.';
    END IF;

    -- Do not silently change shared schema "public".
    -- If PUBLIC can CREATE there, stop for a separate reviewed infrastructure change.
    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_namespace AS n
          CROSS JOIN LATERAL pg_catalog.aclexplode(
              COALESCE(
                  n.nspacl,
                  pg_catalog.acldefault('n', n.nspowner)
              )
          ) AS a
         WHERE n.nspname = 'public'
           AND a.grantee = 0
           AND a.privilege_type = 'CREATE'
    ) THEN
        RAISE EXCEPTION
            'Schema public grants CREATE to PUBLIC. Stop: shared setting requires separate review.';
    END IF;
END
$db01$;

-- ===========================================================================
-- 1. CREATE / VALIDATE TEST ROLES
-- ===========================================================================

DO $db01$
DECLARE
    v_role record;
    v_existing record;
BEGIN
    FOR v_role IN
        SELECT *
          FROM (
                VALUES
                    ('qbit_test_owner', false),
                    ('qbit_test_deploy', true),
                    ('qbit_test_bot', true),
                    ('qbit_test_sluzhebnyy', true),
                    ('qbit_test_dash_read', true),
                    ('qbit_test_dash_admin', true),

                    ('kompaniya_001_test_owner', false),
                    ('kompaniya_001_test_deploy', true),
                    ('kompaniya_001_test_bot', true),
                    ('kompaniya_001_test_sluzhebnyy', true),
                    ('kompaniya_001_test_dash_read', true),
                    ('kompaniya_001_test_dash_admin', true)
          ) AS x(rolname, can_login)
    LOOP
        SELECT
            r.rolname,
            r.rolsuper,
            r.rolinherit,
            r.rolcreaterole,
            r.rolcreatedb,
            r.rolcanlogin,
            r.rolreplication,
            r.rolbypassrls
          INTO v_existing
          FROM pg_catalog.pg_roles AS r
         WHERE r.rolname = v_role.rolname;

        IF NOT FOUND THEN
            IF v_role.can_login THEN
                EXECUTE pg_catalog.format(
                    'CREATE ROLE %I LOGIN PASSWORD NULL NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                    v_role.rolname
                );
            ELSE
                EXECUTE pg_catalog.format(
                    'CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                    v_role.rolname
                );
            END IF;
        ELSE
            IF v_existing.rolsuper
               OR v_existing.rolinherit
               OR v_existing.rolcreaterole
               OR v_existing.rolcreatedb
               OR v_existing.rolreplication
               OR v_existing.rolbypassrls
               OR v_existing.rolcanlogin IS DISTINCT FROM v_role.can_login
            THEN
                RAISE EXCEPTION
                    'Existing role % has incompatible/unsafe attributes. DB-01 will not alter it silently.',
                    v_role.rolname;
            END IF;
        END IF;
    END LOOP;
END
$db01$;

-- PostgreSQL 17: a non-superuser CREATEROLE creator gets ADMIN on roles it creates,
-- but SET ROLE is not automatically usable. Give only SET access to the two NOLOGIN
-- owner roles; do not inherit their privileges automatically.

DO $db01$
DECLARE
    v_owner text;
BEGIN
    FOREACH v_owner IN ARRAY ARRAY[
        'qbit_test_owner',
        'kompaniya_001_test_owner'
    ]
    LOOP
        IF NOT pg_catalog.pg_has_role(session_user, v_owner, 'SET') THEN
            EXECUTE pg_catalog.format(
                'GRANT %I TO %I WITH INHERIT FALSE',
                v_owner,
                session_user
            );
            EXECUTE pg_catalog.format(
                'GRANT %I TO %I WITH SET TRUE',
                v_owner,
                session_user
            );
        END IF;

        IF NOT pg_catalog.pg_has_role(session_user, v_owner, 'SET') THEN
            RAISE EXCEPTION
                'DB-01 cannot SET ROLE %. session_user=%',
                v_owner,
                session_user;
        END IF;

        IF pg_catalog.pg_has_role(session_user, v_owner, 'USAGE') THEN
            RAISE EXCEPTION
                'Infrastructure role unexpectedly inherits owner %. session_user=%',
                v_owner,
                session_user;
        END IF;
    END LOOP;
END
$db01$;

-- Deploy roles can explicitly SET ROLE to their own owner only.
GRANT qbit_test_owner TO qbit_test_deploy WITH INHERIT FALSE;
GRANT qbit_test_owner TO qbit_test_deploy WITH SET TRUE;
GRANT qbit_test_owner TO qbit_test_deploy WITH ADMIN FALSE;

GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH INHERIT FALSE;
GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH SET TRUE;
GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH ADMIN FALSE;

-- ===========================================================================
-- 2. CREATE / VALIDATE TEST SCHEMAS
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS qbit_test AUTHORIZATION qbit_test_owner;
CREATE SCHEMA IF NOT EXISTS kompaniya_001_test AUTHORIZATION kompaniya_001_test_owner;

DO $db01$
DECLARE
    v_owner text;
BEGIN
    SELECT r.rolname
      INTO v_owner
      FROM pg_catalog.pg_namespace AS n
      JOIN pg_catalog.pg_roles AS r
        ON r.oid = n.nspowner
     WHERE n.nspname = 'qbit_test';

    IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION
            'qbit_test owner mismatch: expected qbit_test_owner, actual %',
            COALESCE(v_owner, '<missing>');
    END IF;

    SELECT r.rolname
      INTO v_owner
      FROM pg_catalog.pg_namespace AS n
      JOIN pg_catalog.pg_roles AS r
        ON r.oid = n.nspowner
     WHERE n.nspname = 'kompaniya_001_test';

    IF v_owner IS DISTINCT FROM 'kompaniya_001_test_owner' THEN
        RAISE EXCEPTION
            'kompaniya_001_test owner mismatch: expected kompaniya_001_test_owner, actual %',
            COALESCE(v_owner, '<missing>');
    END IF;
END
$db01$;

COMMENT ON SCHEMA qbit_test IS
'Тестовая schema первой эталонной установки qBit. Production-данные здесь запрещены.';

COMMENT ON SCHEMA kompaniya_001_test IS
'Вымышленная test schema для проверки межкомпанейской изоляции DB-01.';

-- ===========================================================================
-- 3. SCHEMA ACCESS: DEFAULT DENY
-- ===========================================================================

REVOKE ALL ON SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON SCHEMA kompaniya_001_test FROM PUBLIC;

-- Runtime roles see only their own schema namespace.
GRANT USAGE ON SCHEMA qbit_test
    TO qbit_test_bot,
       qbit_test_sluzhebnyy,
       qbit_test_dash_read,
       qbit_test_dash_admin;

GRANT USAGE ON SCHEMA kompaniya_001_test
    TO kompaniya_001_test_bot,
       kompaniya_001_test_sluzhebnyy,
       kompaniya_001_test_dash_read,
       kompaniya_001_test_dash_admin;

-- Explicitly remove accidental cross-company schema grants if this file is re-run.
REVOKE ALL ON SCHEMA qbit_test
    FROM kompaniya_001_test_bot,
         kompaniya_001_test_sluzhebnyy,
         kompaniya_001_test_dash_read,
         kompaniya_001_test_dash_admin,
         kompaniya_001_test_deploy;

REVOKE ALL ON SCHEMA kompaniya_001_test
    FROM qbit_test_bot,
         qbit_test_sluzhebnyy,
         qbit_test_dash_read,
         qbit_test_dash_admin,
         qbit_test_deploy;

-- Standard/shared Supabase roles must not access company schemas.
DO $db01$
DECLARE
    v_shared_role text;
BEGIN
    FOREACH v_shared_role IN ARRAY ARRAY[
        'anon',
        'authenticated',
        'service_role',
        'authenticator'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_roles
             WHERE rolname = v_shared_role
        ) THEN
            EXECUTE pg_catalog.format(
                'REVOKE ALL ON SCHEMA qbit_test FROM %I',
                v_shared_role
            );
            EXECUTE pg_catalog.format(
                'REVOKE ALL ON SCHEMA kompaniya_001_test FROM %I',
                v_shared_role
            );
        END IF;
    END LOOP;
END
$db01$;

-- If DB-01 is safely re-run later, PUBLIC still must not receive direct object access.
REVOKE ALL ON ALL TABLES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA qbit_test FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA kompaniya_001_test FROM PUBLIC;

-- ===========================================================================
-- 4. GLOBAL DEFAULT PRIVILEGES OF COMPANY OWNERS
-- ===========================================================================
-- PostgreSQL default EXECUTE on functions is granted to PUBLIC globally.
-- A per-schema REVOKE cannot remove a global default grant.
-- Therefore these REVOKEs intentionally omit "IN SCHEMA".
-- The owner roles are dedicated to their one company/environment.

ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner
    REVOKE USAGE ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner
    REVOKE USAGE ON TYPES FROM PUBLIC;

-- ===========================================================================
-- 5. SAFE search_path FOR LOGIN ROLES
-- ===========================================================================
-- public is intentionally absent. Future migrations still use qualified names.

DO $db01$
DECLARE
    v_item record;
BEGIN
    FOR v_item IN
        SELECT *
          FROM (
                VALUES
                    ('qbit_test_deploy', 'qbit_test'),
                    ('qbit_test_bot', 'qbit_test'),
                    ('qbit_test_sluzhebnyy', 'qbit_test'),
                    ('qbit_test_dash_read', 'qbit_test'),
                    ('qbit_test_dash_admin', 'qbit_test'),

                    ('kompaniya_001_test_deploy', 'kompaniya_001_test'),
                    ('kompaniya_001_test_bot', 'kompaniya_001_test'),
                    ('kompaniya_001_test_sluzhebnyy', 'kompaniya_001_test'),
                    ('kompaniya_001_test_dash_read', 'kompaniya_001_test'),
                    ('kompaniya_001_test_dash_admin', 'kompaniya_001_test')
          ) AS x(rolname, nspname)
    LOOP
        EXECUTE pg_catalog.format(
            'ALTER ROLE %I IN DATABASE %I SET search_path = pg_catalog, %I',
            v_item.rolname,
            current_database(),
            v_item.nspname
        );
    END LOOP;
END
$db01$;

-- ===========================================================================
-- 6. COMMENTS
-- ===========================================================================

COMMENT ON ROLE qbit_test_owner IS
'DB-01: NOLOGIN owner объектов qbit_test.';
COMMENT ON ROLE qbit_test_deploy IS
'DB-01: test deployment role qBit; explicit SET ROLE to qbit_test_owner.';
COMMENT ON ROLE qbit_test_bot IS
'DB-01: test client workflow qBit; schema USAGE plus future narrow EXECUTE only.';
COMMENT ON ROLE qbit_test_sluzhebnyy IS
'DB-01: test service workflow qBit; schema USAGE plus future narrow EXECUTE only.';
COMMENT ON ROLE qbit_test_dash_read IS
'DB-01: test dashboard read server role qBit; future narrow views/functions only.';
COMMENT ON ROLE qbit_test_dash_admin IS
'DB-01: test dashboard admin server role qBit; future narrow admin functions only.';

COMMENT ON ROLE kompaniya_001_test_owner IS
'DB-01: NOLOGIN owner fictional isolation schema kompaniya_001_test.';
COMMENT ON ROLE kompaniya_001_test_deploy IS
'DB-01: fictional test deployment role; explicit SET ROLE to own owner only.';
COMMENT ON ROLE kompaniya_001_test_bot IS
'DB-01: fictional client workflow role used as isolation canary.';
COMMENT ON ROLE kompaniya_001_test_sluzhebnyy IS
'DB-01: fictional service workflow role used as isolation canary.';
COMMENT ON ROLE kompaniya_001_test_dash_read IS
'DB-01: fictional dashboard read role used as isolation canary.';
COMMENT ON ROLE kompaniya_001_test_dash_admin IS
'DB-01: fictional dashboard admin role used as isolation canary.';

-- ===========================================================================
-- 7. DISPOSABLE PROBES
-- ===========================================================================
-- Prove future owner-created objects are default-deny, then remove them before COMMIT.

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION qbit_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$ SELECT 1 $probe$;

RESET ROLE;

SET LOCAL ROLE kompaniya_001_test_owner;

CREATE TABLE kompaniya_001_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION kompaniya_001_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$ SELECT 1 $probe$;

RESET ROLE;

-- ===========================================================================
-- 8. SECURITY ASSERTIONS
-- ===========================================================================

DO $db01$
DECLARE
    v_role text;
    v_shared_role text;
BEGIN
    -- Deploy roles: SET allowed, inheritance forbidden.
    IF NOT pg_catalog.pg_has_role('qbit_test_deploy', 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'qbit_test_deploy cannot SET ROLE qbit_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('qbit_test_deploy', 'qbit_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'qbit_test_deploy unexpectedly inherits qbit_test_owner';
    END IF;

    IF NOT pg_catalog.pg_has_role('kompaniya_001_test_deploy', 'kompaniya_001_test_owner', 'SET') THEN
        RAISE EXCEPTION 'kompaniya_001_test_deploy cannot SET ROLE kompaniya_001_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('kompaniya_001_test_deploy', 'kompaniya_001_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'kompaniya_001_test_deploy unexpectedly inherits kompaniya_001_test_owner';
    END IF;

    -- qBit runtime roles.
    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_read',
        'qbit_test_dash_admin'
    ]
    LOOP
        IF NOT pg_catalog.has_schema_privilege(v_role, 'qbit_test', 'USAGE') THEN
            RAISE EXCEPTION '% lacks USAGE on qbit_test', v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(v_role, 'qbit_test', 'CREATE') THEN
            RAISE EXCEPTION '% unexpectedly has CREATE on qbit_test', v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(v_role, 'kompaniya_001_test', 'USAGE')
           OR pg_catalog.has_schema_privilege(v_role, 'kompaniya_001_test', 'CREATE')
        THEN
            RAISE EXCEPTION '% can access foreign schema kompaniya_001_test', v_role;
        END IF;

        IF pg_catalog.has_table_privilege(v_role, 'qbit_test.db01_probe_table', 'SELECT')
           OR pg_catalog.has_table_privilege(v_role, 'qbit_test.db01_probe_table', 'INSERT')
           OR pg_catalog.has_table_privilege(v_role, 'qbit_test.db01_probe_table', 'UPDATE')
           OR pg_catalog.has_table_privilege(v_role, 'qbit_test.db01_probe_table', 'DELETE')
        THEN
            RAISE EXCEPTION '% unexpectedly has direct DML on qbit_test probe table', v_role;
        END IF;

        IF pg_catalog.has_function_privilege(
            v_role,
            'qbit_test.db01_probe_function()',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION '% unexpectedly has default EXECUTE on qbit_test probe function', v_role;
        END IF;

        IF pg_catalog.pg_has_role(v_role, 'qbit_test_owner', 'MEMBER')
           OR pg_catalog.pg_has_role(v_role, 'kompaniya_001_test_owner', 'MEMBER')
        THEN
            RAISE EXCEPTION '% unexpectedly belongs to an owner role', v_role;
        END IF;
    END LOOP;

    -- Fictional-company runtime roles, opposite direction.
    FOREACH v_role IN ARRAY ARRAY[
        'kompaniya_001_test_bot',
        'kompaniya_001_test_sluzhebnyy',
        'kompaniya_001_test_dash_read',
        'kompaniya_001_test_dash_admin'
    ]
    LOOP
        IF NOT pg_catalog.has_schema_privilege(v_role, 'kompaniya_001_test', 'USAGE') THEN
            RAISE EXCEPTION '% lacks USAGE on kompaniya_001_test', v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(v_role, 'kompaniya_001_test', 'CREATE') THEN
            RAISE EXCEPTION '% unexpectedly has CREATE on kompaniya_001_test', v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(v_role, 'qbit_test', 'USAGE')
           OR pg_catalog.has_schema_privilege(v_role, 'qbit_test', 'CREATE')
        THEN
            RAISE EXCEPTION '% can access foreign schema qbit_test', v_role;
        END IF;

        IF pg_catalog.has_table_privilege(
            v_role,
            'kompaniya_001_test.db01_probe_table',
            'SELECT'
        )
           OR pg_catalog.has_table_privilege(
               v_role,
               'kompaniya_001_test.db01_probe_table',
               'INSERT'
           )
           OR pg_catalog.has_table_privilege(
               v_role,
               'kompaniya_001_test.db01_probe_table',
               'UPDATE'
           )
           OR pg_catalog.has_table_privilege(
               v_role,
               'kompaniya_001_test.db01_probe_table',
               'DELETE'
           )
        THEN
            RAISE EXCEPTION '% unexpectedly has direct DML on kompaniya_001_test probe table', v_role;
        END IF;

        IF pg_catalog.has_function_privilege(
            v_role,
            'kompaniya_001_test.db01_probe_function()',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION '% unexpectedly has default EXECUTE on kompaniya_001_test probe function', v_role;
        END IF;

        IF pg_catalog.pg_has_role(v_role, 'qbit_test_owner', 'MEMBER')
           OR pg_catalog.pg_has_role(v_role, 'kompaniya_001_test_owner', 'MEMBER')
        THEN
            RAISE EXCEPTION '% unexpectedly belongs to an owner role', v_role;
        END IF;
    END LOOP;

    -- Shared Supabase roles.
    FOREACH v_shared_role IN ARRAY ARRAY[
        'anon',
        'authenticated',
        'service_role',
        'authenticator'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_roles
             WHERE rolname = v_shared_role
        ) THEN
            IF pg_catalog.has_schema_privilege(v_shared_role, 'qbit_test', 'USAGE')
               OR pg_catalog.has_schema_privilege(v_shared_role, 'qbit_test', 'CREATE')
               OR pg_catalog.has_schema_privilege(v_shared_role, 'kompaniya_001_test', 'USAGE')
               OR pg_catalog.has_schema_privilege(v_shared_role, 'kompaniya_001_test', 'CREATE')
            THEN
                RAISE EXCEPTION
                    'Shared Supabase role % can access a company test schema',
                    v_shared_role;
            END IF;
        END IF;
    END LOOP;
END
$db01$;

-- Remove disposable probes.
SET LOCAL ROLE qbit_test_owner;
DROP FUNCTION qbit_test.db01_probe_function();
DROP TABLE qbit_test.db01_probe_table;
RESET ROLE;

SET LOCAL ROLE kompaniya_001_test_owner;
DROP FUNCTION kompaniya_001_test.db01_probe_function();
DROP TABLE kompaniya_001_test.db01_probe_table;
RESET ROLE;

-- ===========================================================================
-- 9. FINAL ROLE ASSERTIONS
-- ===========================================================================

DO $db01$
DECLARE
    v_role record;
BEGIN
    FOR v_role IN
        SELECT *
          FROM (
                VALUES
                    ('qbit_test_owner', false),
                    ('qbit_test_deploy', true),
                    ('qbit_test_bot', true),
                    ('qbit_test_sluzhebnyy', true),
                    ('qbit_test_dash_read', true),
                    ('qbit_test_dash_admin', true),

                    ('kompaniya_001_test_owner', false),
                    ('kompaniya_001_test_deploy', true),
                    ('kompaniya_001_test_bot', true),
                    ('kompaniya_001_test_sluzhebnyy', true),
                    ('kompaniya_001_test_dash_read', true),
                    ('kompaniya_001_test_dash_admin', true)
          ) AS x(rolname, can_login)
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_roles AS r
             WHERE r.rolname = v_role.rolname
               AND r.rolcanlogin = v_role.can_login
               AND r.rolsuper = false
               AND r.rolinherit = false
               AND r.rolcreaterole = false
               AND r.rolcreatedb = false
               AND r.rolreplication = false
               AND r.rolbypassrls = false
        ) THEN
            RAISE EXCEPTION 'Final role assertion failed for %', v_role.rolname;
        END IF;
    END LOOP;

    IF pg_catalog.has_schema_privilege(
        'qbit_test_bot',
        'kompaniya_001_test',
        'USAGE'
    )
       OR pg_catalog.has_schema_privilege(
           'kompaniya_001_test_bot',
           'qbit_test',
           'USAGE'
       )
    THEN
        RAISE EXCEPTION 'Final cross-company isolation assertion failed';
    END IF;
END
$db01$;

COMMIT;

-- ===========================================================================
-- 10. READ-ONLY EVIDENCE AFTER COMMIT
-- ===========================================================================

SELECT
    n.nspname AS schema_name,
    r.rolname AS owner_role
FROM pg_catalog.pg_namespace AS n
JOIN pg_catalog.pg_roles AS r
  ON r.oid = n.nspowner
WHERE n.nspname IN ('qbit_test', 'kompaniya_001_test')
ORDER BY n.nspname;

SELECT
    r.rolname,
    r.rolcanlogin,
    r.rolinherit,
    r.rolsuper,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolreplication,
    r.rolbypassrls
FROM pg_catalog.pg_roles AS r
WHERE r.rolname IN (
    'qbit_test_owner',
    'qbit_test_deploy',
    'qbit_test_bot',
    'qbit_test_sluzhebnyy',
    'qbit_test_dash_read',
    'qbit_test_dash_admin',
    'kompaniya_001_test_owner',
    'kompaniya_001_test_deploy',
    'kompaniya_001_test_bot',
    'kompaniya_001_test_sluzhebnyy',
    'kompaniya_001_test_dash_read',
    'kompaniya_001_test_dash_admin'
)
ORDER BY r.rolname;

SELECT
    x.rolname,
    pg_catalog.has_schema_privilege(
        x.rolname,
        'qbit_test',
        'USAGE'
    ) AS qbit_test_usage,
    pg_catalog.has_schema_privilege(
        x.rolname,
        'qbit_test',
        'CREATE'
    ) AS qbit_test_create,
    pg_catalog.has_schema_privilege(
        x.rolname,
        'kompaniya_001_test',
        'USAGE'
    ) AS kompaniya_001_test_usage,
    pg_catalog.has_schema_privilege(
        x.rolname,
        'kompaniya_001_test',
        'CREATE'
    ) AS kompaniya_001_test_create
FROM (
    VALUES
        ('qbit_test_bot'),
        ('qbit_test_sluzhebnyy'),
        ('qbit_test_dash_read'),
        ('qbit_test_dash_admin'),
        ('kompaniya_001_test_bot'),
        ('kompaniya_001_test_sluzhebnyy'),
        ('kompaniya_001_test_dash_read'),
        ('kompaniya_001_test_dash_admin')
) AS x(rolname)
ORDER BY x.rolname;

SELECT
    'DB-01 SQL APPLIED: assertions passed; probe objects removed; production objects untouched.'
        AS result;
