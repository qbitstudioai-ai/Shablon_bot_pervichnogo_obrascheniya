-- DB-01 v0.3: test schemas and restricted roles
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- Verified target environment (read-only diagnostics, 2026-09-24):
--   PostgreSQL 17.6
--   session_user/current_user = postgres
--   postgres: rolsuper=false, rolcreaterole=true, rolcreatedb=true,
--             rolinherit=true, rolreplication=true, rolbypassrls=true
--   CREATE on current database = true
--   CREATE for PUBLIC on schema public = false
--   vector = 0.8.2
--
-- PURPOSE
--   Create ONLY two isolated TEST schemas:
--     1) qbit_test
--     2) kompaniya_001_test (fictional isolation canary)
--   and their restricted PostgreSQL roles.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * This file DOES NOT create qbit production schema or production roles.
--   * This file DOES NOT create/change passwords or n8n Credentials.
--   * LOGIN roles are created with PASSWORD NULL.
--   * This file DOES NOT install extensions; it only verifies vector exists.
--   * The migration is transactional. Any error before COMMIT rolls DB-01 back.
--   * It contains no DROP SCHEMA, DROP ROLE, DELETE, TRUNCATE, or business-data changes.
--
-- OWNERSHIP MODEL
--   postgres is a trusted infrastructure/deployment administrator, not an application role.
--   Company objects are owned by dedicated NOLOGIN *_owner roles.
--   Runtime roles receive schema USAGE only here; DB-02...DB-05 later grant narrow EXECUTE.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK: target environment and concrete privileges
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
            'DB-01 requires CREATEROLE. session_user=%',
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

    -- The shared public schema is not modified here.
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
            'Schema public grants CREATE to PUBLIC. Stop for separate infrastructure review.';
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
    v_session_oid oid;
    v_is_superuser boolean;
BEGIN
    SELECT r.oid, r.rolsuper
      INTO v_session_oid, v_is_superuser
      FROM pg_catalog.pg_roles AS r
     WHERE r.rolname = session_user;

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
            r.oid,
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

            SELECT
                r.oid,
                r.rolname,
                r.rolsuper,
                r.rolinherit,
                r.rolcreaterole,
                r.rolcreatedb,
                r.rolcanlogin,
                r.rolreplication,
                r.rolbypassrls
              INTO STRICT v_existing
              FROM pg_catalog.pg_roles AS r
             WHERE r.rolname = v_role.rolname;
        END IF;

        IF v_existing.rolsuper
           OR v_existing.rolinherit
           OR v_existing.rolcreaterole
           OR v_existing.rolcreatedb
           OR v_existing.rolreplication
           OR v_existing.rolbypassrls
           OR v_existing.rolcanlogin IS DISTINCT FROM v_role.can_login
        THEN
            RAISE EXCEPTION
                'Role % has incompatible/unsafe attributes; DB-01 will not alter it silently.',
                v_role.rolname;
        END IF;

        -- A non-superuser postgres must have ADMIN OPTION over roles it manages.
        IF COALESCE(v_is_superuser, false) IS NOT TRUE
           AND NOT EXISTS (
                SELECT 1
                  FROM pg_catalog.pg_auth_members AS m
                 WHERE m.roleid = v_existing.oid
                   AND m.member = v_session_oid
                   AND m.admin_option = true
           )
        THEN
            RAISE EXCEPTION
                'session_user % lacks ADMIN OPTION for role %',
                session_user,
                v_role.rolname;
        END IF;
    END LOOP;
END
$db01$;

-- PostgreSQL 17 gives a non-superuser CREATEROLE creator ADMIN OPTION on roles it creates,
-- but the automatic membership has SET FALSE and INHERIT FALSE.
-- CREATE SCHEMA ... AUTHORIZATION <owner> requires SET ROLE ability to that owner.
-- Grant trusted postgres SET-only access to the two NOLOGIN owner roles.

GRANT qbit_test_owner TO postgres
    WITH INHERIT FALSE, SET TRUE;

GRANT kompaniya_001_test_owner TO postgres
    WITH INHERIT FALSE, SET TRUE;

DO $db01$
BEGIN
    IF NOT pg_catalog.pg_has_role('postgres', 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'postgres cannot SET ROLE qbit_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('postgres', 'qbit_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'postgres unexpectedly inherits qbit_test_owner privileges';
    END IF;

    IF NOT pg_catalog.pg_has_role('postgres', 'kompaniya_001_test_owner', 'SET') THEN
        RAISE EXCEPTION 'postgres cannot SET ROLE kompaniya_001_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('postgres', 'kompaniya_001_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'postgres unexpectedly inherits kompaniya_001_test_owner privileges';
    END IF;
END
$db01$;

-- Deploy roles may explicitly become only their own NOLOGIN owner.
GRANT qbit_test_owner TO qbit_test_deploy
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

-- ===========================================================================
-- 2. CREATE / VALIDATE TEST SCHEMAS
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS qbit_test
    AUTHORIZATION qbit_test_owner;

CREATE SCHEMA IF NOT EXISTS kompaniya_001_test
    AUTHORIZATION kompaniya_001_test_owner;

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

-- ===========================================================================
-- 3. qBit test schema: owner-controlled privileges/defaults
-- ===========================================================================

SET LOCAL ROLE qbit_test_owner;

COMMENT ON SCHEMA qbit_test IS
'Тестовая schema первой эталонной установки qBit. Production-данные здесь запрещены.';

REVOKE ALL ON SCHEMA qbit_test FROM PUBLIC;

GRANT USAGE ON SCHEMA qbit_test
    TO qbit_test_bot,
       qbit_test_sluzhebnyy,
       qbit_test_dash_read,
       qbit_test_dash_admin;

-- No qBit deploy/runtime access to the fictional company schema is granted anywhere.
-- Remove accidental foreign grants if DB-01 is re-run.
REVOKE ALL ON SCHEMA qbit_test
    FROM kompaniya_001_test_deploy,
         kompaniya_001_test_bot,
         kompaniya_001_test_sluzhebnyy,
         kompaniya_001_test_dash_read,
         kompaniya_001_test_dash_admin;

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
        END IF;
    END LOOP;
END
$db01$;

-- Existing objects (normally none at DB-01) are kept default-deny for PUBLIC.
REVOKE ALL ON ALL TABLES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA qbit_test FROM PUBLIC;

-- PostgreSQL grants PUBLIC EXECUTE on new functions and PUBLIC USAGE on new types
-- by global default. These owner-wide defaults intentionally omit IN SCHEMA.
ALTER DEFAULT PRIVILEGES
    REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE USAGE ON TYPES FROM PUBLIC;

RESET ROLE;

-- ===========================================================================
-- 4. Fictional isolation schema: owner-controlled privileges/defaults
-- ===========================================================================

SET LOCAL ROLE kompaniya_001_test_owner;

COMMENT ON SCHEMA kompaniya_001_test IS
'Вымышленная test schema для проверки межкомпанейской изоляции DB-01.';

REVOKE ALL ON SCHEMA kompaniya_001_test FROM PUBLIC;

GRANT USAGE ON SCHEMA kompaniya_001_test
    TO kompaniya_001_test_bot,
       kompaniya_001_test_sluzhebnyy,
       kompaniya_001_test_dash_read,
       kompaniya_001_test_dash_admin;

REVOKE ALL ON SCHEMA kompaniya_001_test
    FROM qbit_test_deploy,
         qbit_test_bot,
         qbit_test_sluzhebnyy,
         qbit_test_dash_read,
         qbit_test_dash_admin;

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
                'REVOKE ALL ON SCHEMA kompaniya_001_test FROM %I',
                v_shared_role
            );
        END IF;
    END LOOP;
END
$db01$;

REVOKE ALL ON ALL TABLES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA kompaniya_001_test FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
    REVOKE USAGE ON TYPES FROM PUBLIC;

RESET ROLE;

-- ===========================================================================
-- 5. SAFE search_path FOR LOGIN ROLES
-- ===========================================================================
-- public is intentionally absent. Future migrations/functions still use qualified names.

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
-- 6. ROLE COMMENTS
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
-- 7. DISPOSABLE OWNER-CREATED PROBES
-- ===========================================================================
-- These prove that future owner-created tables/functions are default-deny.
-- They are removed before COMMIT.

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION qbit_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$
    SELECT 1
$probe$;

RESET ROLE;

SET LOCAL ROLE kompaniya_001_test_owner;

CREATE TABLE kompaniya_001_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION kompaniya_001_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$
    SELECT 1
$probe$;

RESET ROLE;

-- ===========================================================================
-- 8. SECURITY ASSERTIONS
-- ===========================================================================

DO $db01$
DECLARE
    v_role text;
    v_shared_role text;
BEGIN
    -- Deploy roles: own-owner SET allowed, inheritance forbidden.
    IF NOT pg_catalog.pg_has_role(
        'qbit_test_deploy',
        'qbit_test_owner',
        'SET'
    ) THEN
        RAISE EXCEPTION
            'qbit_test_deploy cannot SET ROLE qbit_test_owner';
    END IF;

    IF pg_catalog.pg_has_role(
        'qbit_test_deploy',
        'qbit_test_owner',
        'USAGE'
    ) THEN
        RAISE EXCEPTION
            'qbit_test_deploy unexpectedly inherits qbit_test_owner';
    END IF;

    IF NOT pg_catalog.pg_has_role(
        'kompaniya_001_test_deploy',
        'kompaniya_001_test_owner',
        'SET'
    ) THEN
        RAISE EXCEPTION
            'kompaniya_001_test_deploy cannot SET ROLE kompaniya_001_test_owner';
    END IF;

    IF pg_catalog.pg_has_role(
        'kompaniya_001_test_deploy',
        'kompaniya_001_test_owner',
        'USAGE'
    ) THEN
        RAISE EXCEPTION
            'kompaniya_001_test_deploy unexpectedly inherits kompaniya_001_test_owner';
    END IF;

    IF pg_catalog.pg_has_role(
        'qbit_test_deploy',
        'kompaniya_001_test_owner',
        'MEMBER'
    ) THEN
        RAISE EXCEPTION
            'qbit_test_deploy unexpectedly belongs to foreign owner role';
    END IF;

    IF pg_catalog.pg_has_role(
        'kompaniya_001_test_deploy',
        'qbit_test_owner',
        'MEMBER'
    ) THEN
        RAISE EXCEPTION
            'kompaniya_001_test_deploy unexpectedly belongs to foreign owner role';
    END IF;

    -- qBit runtime roles.
    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_read',
        'qbit_test_dash_admin'
    ]
    LOOP
        IF NOT pg_catalog.has_schema_privilege(
            v_role,
            'qbit_test',
            'USAGE'
        ) THEN
            RAISE EXCEPTION
                '% lacks USAGE on qbit_test',
                v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(
            v_role,
            'qbit_test',
            'CREATE'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has CREATE on qbit_test',
                v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(
            v_role,
            'kompaniya_001_test',
            'USAGE'
        )
        OR pg_catalog.has_schema_privilege(
            v_role,
            'kompaniya_001_test',
            'CREATE'
        ) THEN
            RAISE EXCEPTION
                '% can access foreign schema kompaniya_001_test',
                v_role;
        END IF;

        IF pg_catalog.has_table_privilege(
            v_role,
            'qbit_test.db01_probe_table',
            'SELECT'
        )
        OR pg_catalog.has_table_privilege(
            v_role,
            'qbit_test.db01_probe_table',
            'INSERT'
        )
        OR pg_catalog.has_table_privilege(
            v_role,
            'qbit_test.db01_probe_table',
            'UPDATE'
        )
        OR pg_catalog.has_table_privilege(
            v_role,
            'qbit_test.db01_probe_table',
            'DELETE'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has direct DML on qbit_test probe table',
                v_role;
        END IF;

        IF pg_catalog.has_function_privilege(
            v_role,
            'qbit_test.db01_probe_function()',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has default EXECUTE on qbit_test probe function',
                v_role;
        END IF;

        IF pg_catalog.pg_has_role(
            v_role,
            'qbit_test_owner',
            'MEMBER'
        )
        OR pg_catalog.pg_has_role(
            v_role,
            'kompaniya_001_test_owner',
            'MEMBER'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly belongs to an owner role',
                v_role;
        END IF;
    END LOOP;

    -- Fictional-company runtime roles.
    FOREACH v_role IN ARRAY ARRAY[
        'kompaniya_001_test_bot',
        'kompaniya_001_test_sluzhebnyy',
        'kompaniya_001_test_dash_read',
        'kompaniya_001_test_dash_admin'
    ]
    LOOP
        IF NOT pg_catalog.has_schema_privilege(
            v_role,
            'kompaniya_001_test',
            'USAGE'
        ) THEN
            RAISE EXCEPTION
                '% lacks USAGE on kompaniya_001_test',
                v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(
            v_role,
            'kompaniya_001_test',
            'CREATE'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has CREATE on kompaniya_001_test',
                v_role;
        END IF;

        IF pg_catalog.has_schema_privilege(
            v_role,
            'qbit_test',
            'USAGE'
        )
        OR pg_catalog.has_schema_privilege(
            v_role,
            'qbit_test',
            'CREATE'
        ) THEN
            RAISE EXCEPTION
                '% can access foreign schema qbit_test',
                v_role;
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
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has direct DML on kompaniya_001_test probe table',
                v_role;
        END IF;

        IF pg_catalog.has_function_privilege(
            v_role,
            'kompaniya_001_test.db01_probe_function()',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly has default EXECUTE on kompaniya_001_test probe function',
                v_role;
        END IF;

        IF pg_catalog.pg_has_role(
            v_role,
            'qbit_test_owner',
            'MEMBER'
        )
        OR pg_catalog.pg_has_role(
            v_role,
            'kompaniya_001_test_owner',
            'MEMBER'
        ) THEN
            RAISE EXCEPTION
                '% unexpectedly belongs to an owner role',
                v_role;
        END IF;
    END LOOP;

    -- Shared Supabase roles must not have company-schema privileges.
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
            IF pg_catalog.has_schema_privilege(
                v_shared_role,
                'qbit_test',
                'USAGE'
            )
            OR pg_catalog.has_schema_privilege(
                v_shared_role,
                'qbit_test',
                'CREATE'
            )
            OR pg_catalog.has_schema_privilege(
                v_shared_role,
                'kompaniya_001_test',
                'USAGE'
            )
            OR pg_catalog.has_schema_privilege(
                v_shared_role,
                'kompaniya_001_test',
                'CREATE'
            ) THEN
                RAISE EXCEPTION
                    'Shared Supabase role % can access a company test schema',
                    v_shared_role;
            END IF;
        END IF;
    END LOOP;

    -- PUBLIC must not have schema USAGE/CREATE.
    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_namespace AS n
          CROSS JOIN LATERAL pg_catalog.aclexplode(
              COALESCE(
                  n.nspacl,
                  pg_catalog.acldefault('n', n.nspowner)
              )
          ) AS a
         WHERE n.nspname IN ('qbit_test', 'kompaniya_001_test')
           AND a.grantee = 0
           AND a.privilege_type IN ('USAGE', 'CREATE')
    ) THEN
        RAISE EXCEPTION
            'PUBLIC unexpectedly has USAGE/CREATE on a company test schema';
    END IF;
END
$db01$;

-- Remove disposable probes before COMMIT.
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
            RAISE EXCEPTION
                'Final role assertion failed for %',
                v_role.rolname;
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
    ) THEN
        RAISE EXCEPTION
            'Final cross-company isolation assertion failed';
    END IF;
END
$db01$;

COMMIT;

-- ===========================================================================
-- 10. READ-ONLY EVIDENCE AFTER COMMIT
-- ===========================================================================

SELECT
    jsonb_build_object(
        'db01_status',
        'applied',
        'database',
        current_database(),
        'postgres_version',
        current_setting('server_version'),
        'vector_version',
        (
            SELECT e.extversion
              FROM pg_catalog.pg_extension AS e
             WHERE e.extname = 'vector'
        ),
        'schemas',
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'schema', n.nspname,
                    'owner', r.rolname
                )
                ORDER BY n.nspname
            )
              FROM pg_catalog.pg_namespace AS n
              JOIN pg_catalog.pg_roles AS r
                ON r.oid = n.nspowner
             WHERE n.nspname IN (
                 'qbit_test',
                 'kompaniya_001_test'
             )
        ),
        'roles_ok',
        (
            SELECT count(*) = 12
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
        ),
        'qbit_bot_foreign_usage',
        pg_catalog.has_schema_privilege(
            'qbit_test_bot',
            'kompaniya_001_test',
            'USAGE'
        ),
        'fictional_bot_foreign_usage',
        pg_catalog.has_schema_privilege(
            'kompaniya_001_test_bot',
            'qbit_test',
            'USAGE'
        ),
        'probe_objects_remaining',
        EXISTS (
            SELECT 1
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = c.relnamespace
             WHERE n.nspname IN (
                 'qbit_test',
                 'kompaniya_001_test'
             )
               AND c.relname = 'db01_probe_table'
        )
        OR EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname IN (
                 'qbit_test',
                 'kompaniya_001_test'
             )
               AND p.proname = 'db01_probe_function'
        ),
        'result',
        'DB-01 SQL APPLIED: assertions passed; production objects untouched.'
    ) AS db01_result;
