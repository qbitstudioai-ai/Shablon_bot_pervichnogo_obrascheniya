-- DB-01: test schema and restricted roles
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
--   * Run in the target Supabase PostgreSQL database as the trusted postgres role.
--     Supabase postgres is intentionally not SUPERUSER; DB-01 checks required capabilities.
--   * This file does NOT create qbit production schema or any production role.
--   * This file does NOT create or change passwords. LOGIN roles are created with PASSWORD NULL.
--   * This file does NOT install extensions. It only verifies that vector is already installed.
--   * This file is transactional and contains no DROP of business objects or data.
--   * If an object with the expected name already exists but has unsafe/incompatible attributes,
--     the transaction stops instead of silently rewriting it.
--
-- AFTER SUCCESS
--   DB-02/DB-03 migrations must create objects as the corresponding *_owner role
--   (directly via SET ROLE from *_deploy or by an equivalent controlled deployment path).
--   Runtime roles receive per-function EXECUTE later; they do not receive direct table DML here.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL search_path = pg_catalog;

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------

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
     WHERE r.rolname = current_user;

    -- Supabase intentionally runs Studio as postgres without SUPERUSER.
    -- DB-01 therefore checks the concrete capabilities it needs instead of rolsuper=true.
    IF current_user <> 'postgres'
       AND COALESCE(v_is_superuser, false) IS NOT TRUE
    THEN
        RAISE EXCEPTION
            'DB-01 must be executed by the trusted postgres role (or a real superuser). current_user=%',
            current_user;
    END IF;

    IF COALESCE(v_is_superuser, false) IS NOT TRUE
       AND COALESCE(v_can_create_roles, false) IS NOT TRUE
    THEN
        RAISE EXCEPTION
            'DB-01 requires CREATEROLE when postgres is not a superuser. current_user=%',
            current_user;
    END IF;

    IF NOT pg_catalog.has_database_privilege(
        current_user,
        current_database(),
        'CREATE'
    ) THEN
        RAISE EXCEPTION
            'DB-01 requires CREATE on database %. current_user=%',
            current_database(),
            current_user;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_extension
         WHERE extname = 'vector'
    ) THEN
        RAISE EXCEPTION
            'Extension vector is not installed. DB-01 does not install extensions.';
    END IF;

    -- Application roles must not be able to create objects in public through PUBLIC.
    -- On PostgreSQL 15+ this is normally already false, but upgraded/custom databases
    -- can retain CREATE for PUBLIC. DB-01 refuses to make a cluster-wide change silently.
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
            'Schema public grants CREATE to PUBLIC. Stop: this shared-database setting needs a separate reviewed change.';
    END IF;
END
$db01$;

-- ---------------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------------
-- All roles are cluster-wide PostgreSQL roles, but their names include company + environment.
-- Runtime/deploy LOGIN roles intentionally have no password after creation.

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

-- PostgreSQL 17 gives a non-superuser CREATEROLE creator ADMIN on a newly created role,
-- but not SET ROLE by default. Supabase postgres is intentionally not SUPERUSER, so grant
-- this trusted infrastructure role SET-only access to the two NOLOGIN owner roles.
-- INHERIT stays false: postgres does not silently inherit company-owner privileges.
DO $db01$
DECLARE
    v_owner text;
BEGIN
    FOREACH v_owner IN ARRAY ARRAY[
        'qbit_test_owner',
        'kompaniya_001_test_owner'
    ]
    LOOP
        IF NOT pg_catalog.pg_has_role(current_user, v_owner, 'SET') THEN
            EXECUTE pg_catalog.format(
                'GRANT %I TO %I WITH INHERIT FALSE',
                v_owner,
                current_user
            );
            EXECUTE pg_catalog.format(
                'GRANT %I TO %I WITH SET TRUE',
                v_owner,
                current_user
            );
        END IF;

        IF NOT pg_catalog.pg_has_role(current_user, v_owner, 'SET') THEN
            RAISE EXCEPTION
                'DB-01 cannot SET ROLE %. current_user=%',
                v_owner,
                current_user;
        END IF;

        IF pg_catalog.pg_has_role(current_user, v_owner, 'USAGE') THEN
            RAISE EXCEPTION
                'DB-01 infrastructure role must not inherit owner %. current_user=%',
                v_owner,
                current_user;
        END IF;
    END LOOP;
END
$db01$;

-- Deploy can explicitly SET ROLE to owner, but does not inherit owner privileges automatically.
GRANT qbit_test_owner TO qbit_test_deploy WITH INHERIT FALSE;
GRANT qbit_test_owner TO qbit_test_deploy WITH SET TRUE;
GRANT qbit_test_owner TO qbit_test_deploy WITH ADMIN FALSE;

GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH INHERIT FALSE;
GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH SET TRUE;
GRANT kompaniya_001_test_owner TO kompaniya_001_test_deploy WITH ADMIN FALSE;

-- ---------------------------------------------------------------------------
-- 2. Schemas
-- ---------------------------------------------------------------------------

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
            'Schema qbit_test exists with wrong owner: expected qbit_test_owner, actual %',
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
            'Schema kompaniya_001_test exists with wrong owner: expected kompaniya_001_test_owner, actual %',
            COALESCE(v_owner, '<missing>');
    END IF;
END
$db01$;

COMMENT ON SCHEMA qbit_test IS
'Тестовая schema первой эталонной установки qBit. Production-данные здесь запрещены.';

COMMENT ON SCHEMA kompaniya_001_test IS
'Вымышленная тестовая schema для проверки межкомпанейской изоляции DB-01.';

-- ---------------------------------------------------------------------------
-- 3. Schema privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON SCHEMA kompaniya_001_test FROM PUBLIC;

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

-- Explicitly remove custom-schema access from standard/shared Supabase roles if they exist.
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

-- If this script is safely re-run after later migrations, keep PUBLIC away from existing
-- table/sequence/function objects too. Runtime roles are not affected by these PUBLIC revokes.
REVOKE ALL ON ALL TABLES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA qbit_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA qbit_test FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA kompaniya_001_test FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA kompaniya_001_test FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 4. Default privileges for future objects created by *_owner
-- ---------------------------------------------------------------------------
-- Important: PostgreSQL normally grants PUBLIC EXECUTE on new functions and PUBLIC USAGE
-- on new types. Revoke both in advance. Per-function EXECUTE is granted later by DB-02…DB-05.

ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner IN SCHEMA qbit_test
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner IN SCHEMA qbit_test
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner IN SCHEMA qbit_test
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE qbit_test_owner IN SCHEMA qbit_test
    REVOKE USAGE ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner IN SCHEMA kompaniya_001_test
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner IN SCHEMA kompaniya_001_test
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner IN SCHEMA kompaniya_001_test
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kompaniya_001_test_owner IN SCHEMA kompaniya_001_test
    REVOKE USAGE ON TYPES FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 5. Safe search_path for login roles in this database only
-- ---------------------------------------------------------------------------
-- public is intentionally absent. pg_catalog is first.

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

-- ---------------------------------------------------------------------------
-- 6. Russian role comments
-- ---------------------------------------------------------------------------

COMMENT ON ROLE qbit_test_owner IS
'DB-01: владелец объектов qbit_test; NOLOGIN; используется только через контролируемый deployment.';
COMMENT ON ROLE qbit_test_deploy IS
'DB-01: тестовая роль миграций qBit; LOGIN без пароля; SET ROLE qbit_test_owner разрешён явно.';
COMMENT ON ROLE qbit_test_bot IS
'DB-01: тестовый клиентский workflow qBit; только USAGE schema и будущие точечные EXECUTE.';
COMMENT ON ROLE qbit_test_sluzhebnyy IS
'DB-01: тестовый служебный workflow qBit; только USAGE schema и будущие точечные EXECUTE.';
COMMENT ON ROLE qbit_test_dash_read IS
'DB-01: тестовый сервер дашборда qBit, чтение только через будущие разрешённые функции/представления.';
COMMENT ON ROLE qbit_test_dash_admin IS
'DB-01: тестовый административный сервер qBit; только будущие узкие административные функции.';

COMMENT ON ROLE kompaniya_001_test_owner IS
'DB-01: владелец объектов вымышленной schema kompaniya_001_test; NOLOGIN.';
COMMENT ON ROLE kompaniya_001_test_deploy IS
'DB-01: роль миграций вымышленной test-компании; LOGIN без пароля; явный SET ROLE owner.';
COMMENT ON ROLE kompaniya_001_test_bot IS
'DB-01: клиентский workflow вымышленной test-компании; изоляционный canary.';
COMMENT ON ROLE kompaniya_001_test_sluzhebnyy IS
'DB-01: служебный workflow вымышленной test-компании; изоляционный canary.';
COMMENT ON ROLE kompaniya_001_test_dash_read IS
'DB-01: read-роль дашборда вымышленной test-компании; изоляционный canary.';
COMMENT ON ROLE kompaniya_001_test_dash_admin IS
'DB-01: admin-роль дашборда вымышленной test-компании; изоляционный canary.';

-- ---------------------------------------------------------------------------
-- 7. Disposable probes: prove default-deny before commit
-- ---------------------------------------------------------------------------
-- Probe objects are created by owner roles, checked through ACL inspection, then removed.
-- No probe object remains after the migration.

SET LOCAL ROLE qbit_test_owner;

CREATE TABLE qbit_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION qbit_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$SELECT 1$probe$;

RESET ROLE;

SET LOCAL ROLE kompaniya_001_test_owner;

CREATE TABLE kompaniya_001_test.db01_probe_table (
    id integer NOT NULL
);

CREATE FUNCTION kompaniya_001_test.db01_probe_function()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $probe$SELECT 1$probe$;

RESET ROLE;

DO $db01$
DECLARE
    v_role text;
    v_shared_role text;
BEGIN
    -- Owners/deploy membership must be explicit SET-only, without inherited owner privileges.
    IF NOT pg_catalog.pg_has_role('qbit_test_deploy', 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'qbit_test_deploy cannot SET ROLE qbit_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('qbit_test_deploy', 'qbit_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'qbit_test_deploy unexpectedly inherits qbit_test_owner privileges';
    END IF;

    IF NOT pg_catalog.pg_has_role('kompaniya_001_test_deploy', 'kompaniya_001_test_owner', 'SET') THEN
        RAISE EXCEPTION 'kompaniya_001_test_deploy cannot SET ROLE kompaniya_001_test_owner';
    END IF;

    IF pg_catalog.pg_has_role('kompaniya_001_test_deploy', 'kompaniya_001_test_owner', 'USAGE') THEN
        RAISE EXCEPTION 'kompaniya_001_test_deploy unexpectedly inherits kompaniya_001_test_owner privileges';
    END IF;

    -- qBit runtime roles: own schema USAGE only, no CREATE, no foreign schema access.
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
            RAISE EXCEPTION '% unexpectedly has direct DML on qbit_test owner-created table', v_role;
        END IF;

        IF pg_catalog.has_function_privilege(v_role, 'qbit_test.db01_probe_function()', 'EXECUTE') THEN
            RAISE EXCEPTION '% unexpectedly receives PUBLIC/default EXECUTE on qbit_test function', v_role;
        END IF;

        IF pg_catalog.pg_has_role(v_role, 'qbit_test_owner', 'MEMBER')
           OR pg_catalog.pg_has_role(v_role, 'kompaniya_001_test_owner', 'MEMBER')
        THEN
            RAISE EXCEPTION '% unexpectedly belongs to an owner role', v_role;
        END IF;
    END LOOP;

    -- Fictional-company runtime roles: mirror checks in the other direction.
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

        IF pg_catalog.has_table_privilege(v_role, 'kompaniya_001_test.db01_probe_table', 'SELECT')
           OR pg_catalog.has_table_privilege(v_role, 'kompaniya_001_test.db01_probe_table', 'INSERT')
           OR pg_catalog.has_table_privilege(v_role, 'kompaniya_001_test.db01_probe_table', 'UPDATE')
           OR pg_catalog.has_table_privilege(v_role, 'kompaniya_001_test.db01_probe_table', 'DELETE')
        THEN
            RAISE EXCEPTION '% unexpectedly has direct DML on kompaniya_001_test owner-created table', v_role;
        END IF;

        IF pg_catalog.has_function_privilege(v_role, 'kompaniya_001_test.db01_probe_function()', 'EXECUTE') THEN
            RAISE EXCEPTION '% unexpectedly receives PUBLIC/default EXECUTE on kompaniya_001_test function', v_role;
        END IF;

        IF pg_catalog.pg_has_role(v_role, 'qbit_test_owner', 'MEMBER')
           OR pg_catalog.pg_has_role(v_role, 'kompaniya_001_test_owner', 'MEMBER')
        THEN
            RAISE EXCEPTION '% unexpectedly belongs to an owner role', v_role;
        END IF;
    END LOOP;

    -- Shared Supabase roles must not see either company schema.
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
                RAISE EXCEPTION 'Shared role % can access a company schema', v_shared_role;
            END IF;
        END IF;
    END LOOP;
END
$db01$;

-- Remove probes before commit.
SET LOCAL ROLE qbit_test_owner;
DROP FUNCTION qbit_test.db01_probe_function();
DROP TABLE qbit_test.db01_probe_table;
RESET ROLE;

SET LOCAL ROLE kompaniya_001_test_owner;
DROP FUNCTION kompaniya_001_test.db01_probe_function();
DROP TABLE kompaniya_001_test.db01_probe_table;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 8. Final security assertions
-- ---------------------------------------------------------------------------

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

    IF pg_catalog.has_schema_privilege('qbit_test_bot', 'kompaniya_001_test', 'USAGE')
       OR pg_catalog.has_schema_privilege('kompaniya_001_test_bot', 'qbit_test', 'USAGE')
    THEN
        RAISE EXCEPTION 'Final cross-company isolation assertion failed';
    END IF;
END
$db01$;

COMMIT;

-- ---------------------------------------------------------------------------
-- 9. Human-readable evidence (read-only)
-- ---------------------------------------------------------------------------

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
    pg_catalog.has_schema_privilege(x.rolname, 'qbit_test', 'USAGE') AS qbit_test_usage,
    pg_catalog.has_schema_privilege(x.rolname, 'qbit_test', 'CREATE') AS qbit_test_create,
    pg_catalog.has_schema_privilege(x.rolname, 'kompaniya_001_test', 'USAGE') AS kompaniya_001_test_usage,
    pg_catalog.has_schema_privilege(x.rolname, 'kompaniya_001_test', 'CREATE') AS kompaniya_001_test_create
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
    'DB-01 SQL APPLIED: assertions passed; probe objects removed; production objects untouched.' AS result;
