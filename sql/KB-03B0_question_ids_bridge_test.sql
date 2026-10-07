-- KB-03B0 v0.1 — bridge для ID контрольных вопросов, TEST only
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Purpose: после sohranit_kontrolnye_voprosy дать служебному worker узкое
--          чтение ID/metadata вопросов только своей live fenced job/version.
-- TARGET ONLY: qbit_bot_pervichnogo_obrascheniya
-- PRODUCTION: не затрагивается.
--
-- Порядок:
-- 1) выполнить весь файл одной командой trusted postgres session;
-- 2) транзакция сама проверит owner/required objects/grants;
-- 3) в конце должны появиться:
--    - smoke_result = otkaz / nekorrektnyy_vhod (ожидаемо для пустого smoke input);
--    - kb03b0_status = verified.
--
-- Rollback, только если понадобится ДО KB-03B1:
-- BEGIN;
-- SET LOCAL ROLE qbit_test_owner;
-- DROP FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb);
-- COMMIT;

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

DO $preflight$
BEGIN
    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION 'KB-03B0 must run from trusted postgres session; session_user=%', session_user;
    END IF;

    IF NOT pg_catalog.pg_has_role(session_user, 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'session_user % cannot SET ROLE qbit_test_owner', session_user;
    END IF;

    IF (
        SELECT r.rolname
        FROM pg_catalog.pg_namespace n
        JOIN pg_catalog.pg_roles r ON r.oid = n.nspowner
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
    ) IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'test schema owner changed; stop';
    END IF;

    IF pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy') IS NULL
       OR pg_catalog.to_regclass('qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy') IS NULL THEN
        RAISE EXCEPTION 'Required DB-04 tables are missing';
    END IF;

    IF pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(jsonb)'
    ) IS NULL
       OR pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb)'
    ) IS NULL
       OR pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(jsonb)'
    ) IS NULL THEN
        RAISE EXCEPTION 'Required normative KB functions are missing';
    END IF;

    IF pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)'
    ) IS NOT NULL
       AND (
           SELECT r.rolname
           FROM pg_catalog.pg_proc p
           JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
           JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
           WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
             AND p.proname = 'poluchit_kontrolnye_voprosy_znaniy'
             AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_dannye jsonb'
       ) IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'Existing bridge function has unexpected owner; stop';
    END IF;
END
$preflight$;

SET LOCAL ROLE qbit_test_owner;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(
    p_dannye jsonb
)
RETURNS TABLE(
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    versiya_id uuid,
    vopros_id uuid,
    nomer integer,
    vopros text,
    ozhidaemyy_razdel text,
    ozhidaemyy_fakt text,
    istochnik text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya
AS $fn$
#variable_conflict use_column
DECLARE
    v_op text := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_ver uuid;
    v_job uuid;
    v_worker text := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_fence bigint;
    v_count integer;
BEGIN
    BEGIN
        v_ver := (p_dannye->>'versiya_id')::uuid;
        v_job := (p_dannye->>'zadanie_id')::uuid;
        v_fence := (p_dannye->>'nomer_vladeniya')::bigint;
    EXCEPTION WHEN OTHERS THEN
        v_ver := NULL;
        v_job := NULL;
        v_fence := NULL;
    END;

    IF v_op IS NULL
       OR v_ver IS NULL
       OR v_job IS NULL
       OR v_worker IS NULL
       OR v_fence IS NULL THEN
        RETURN QUERY
        SELECT
            v_op,
            'otkaz'::text,
            'nekorrektnyy_vhod'::text,
            'Нужны operaciya_id, versiya_id и live fenced job'::text,
            v_ver,
            NULL::uuid,
            NULL::integer,
            NULL::text,
            NULL::text,
            NULL::text,
            NULL::text;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM qbit_bot_pervichnogo_obrascheniya.zadaniya_znaniy j
        JOIN qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v
          ON v.zagruzka_id = j.zagruzka_id
        WHERE j.id = v_job
          AND v.id = v_ver
          AND j.status = 'v_rabote'
          AND j.vladelec_arendy = v_worker
          AND j.nomer_vladeniya = v_fence
          AND j.arenda_do >= clock_timestamp()
          AND v.status IN ('chernovik', 'gotova')
    ) THEN
        RETURN QUERY
        SELECT
            v_op,
            'konflikt'::text,
            'stale_lease'::text,
            'Job/version больше не доступны текущему worker/fencing'::text,
            v_ver,
            NULL::uuid,
            NULL::integer,
            NULL::text,
            NULL::text,
            NULL::text,
            NULL::text;
        RETURN;
    END IF;

    SELECT count(*)::integer
      INTO v_count
      FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k
     WHERE k.versiya_id = v_ver;

    IF v_count < 3 OR v_count > 10 THEN
        RETURN QUERY
        SELECT
            v_op,
            'otkaz'::text,
            'nekorrektnoe_chislo_voprosov'::text,
            pg_catalog.format(
                'Для автоматической проверки нужно 3..10 вопросов; найдено %s',
                v_count
            )::text,
            v_ver,
            NULL::uuid,
            NULL::integer,
            NULL::text,
            NULL::text,
            NULL::text,
            NULL::text;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        v_op,
        'uspeshno'::text,
        NULL::text,
        NULL::text,
        v_ver,
        k.id,
        k.nomer,
        k.vopros,
        k.ozhidaemyy_razdel,
        k.ozhidaemyy_fakt,
        k.istochnik
    FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k
    WHERE k.versiya_id = v_ver
    ORDER BY k.nomer;
END
$fn$;

REVOKE ALL
ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)
TO qbit_test_sluzhebnyy;

COMMENT ON FUNCTION qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)
IS 'KB-03B0: TEST service bridge. Returns IDs and canonical fields of 3..10 control questions only for the caller current live fenced knowledge job/version.';

RESET ROLE;

DO $verify$
DECLARE
    v_oid oid;
    v_owner text;
    v_secdef boolean;
    v_public_execute boolean;
BEGIN
    SELECT p.oid, r.rolname, p.prosecdef
      INTO v_oid, v_owner, v_secdef
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
     WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
       AND p.proname = 'poluchit_kontrolnye_voprosy_znaniy'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_dannye jsonb';

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'KB-03B0 function missing after CREATE';
    END IF;
    IF v_owner IS DISTINCT FROM 'qbit_test_owner' THEN
        RAISE EXCEPTION 'Unexpected function owner: %', v_owner;
    END IF;
    IF v_secdef IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Function must be SECURITY DEFINER';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
            COALESCE(
                (SELECT p.proacl FROM pg_catalog.pg_proc p WHERE p.oid = v_oid),
                pg_catalog.acldefault(
                    'f',
                    (SELECT p.proowner FROM pg_catalog.pg_proc p WHERE p.oid = v_oid)
                )
            )
        ) a
        WHERE a.grantee = 0
          AND a.privilege_type = 'EXECUTE'
    )
    INTO v_public_execute;

    IF v_public_execute THEN
        RAISE EXCEPTION 'PUBLIC EXECUTE leaked';
    END IF;

    IF NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        v_oid,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'qbit_test_sluzhebnyy EXECUTE missing';
    END IF;

    IF pg_catalog.has_function_privilege(
        'qbit_test_bot',
        v_oid,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'qbit_test_bot must not execute service bridge';
    END IF;

    IF pg_catalog.has_table_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'Direct SELECT on kontrolnye_voprosy leaked to service role';
    END IF;
END
$verify$;

-- Безопасный smoke: намеренно неполный input. Ожидается kontroliruemyy otkaz,
-- а не permission denied и не исключение.
SET LOCAL ROLE qbit_test_sluzhebnyy;

SELECT
    rezultat AS smoke_result,
    kod_oshibki AS smoke_kod
FROM qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(
    jsonb_build_object('operaciya_id', 'kb03b0:smoke')
);

RESET ROLE;

COMMIT;

SELECT jsonb_build_object(
    'kb03b0_status', 'verified',
    'schema', 'qbit_bot_pervichnogo_obrascheniya',
    'function', 'poluchit_kontrolnye_voprosy_znaniy(jsonb)',
    'owner', 'qbit_test_owner',
    'service_execute', true,
    'bot_execute', false,
    'public_execute', false,
    'direct_service_select_questions', false,
    'production_untouched', true,
    'next_stage', 'KB-03B1_workflow'
) AS kb03b0_result;
