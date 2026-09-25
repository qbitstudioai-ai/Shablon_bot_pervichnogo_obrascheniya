-- DB-03C3 v0.1: processing queue claim, lease heartbeat and fenced completion
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Contract: docs/specs/DB_CONTRACT.md
--
-- TARGET
--   self-hosted Supabase / PostgreSQL 17.6
--   schema: qbit_test ONLY
--   owner:  qbit_test_owner
--
-- REQUIRES
--   DB-01, DB-02, DB-03A, DB-03B, DB-03C1 v0.3, DB-03C2 v0.1 applied.
--
-- CREATES 3 SECURITY DEFINER FUNCTIONS
--   zabrat_zadanie_obrabotki(jsonb)    -> qbit_test_bot
--   prodlit_arendu_zadaniya(jsonb)     -> qbit_test_bot
--   zavershit_zadanie_obrabotki(jsonb) -> qbit_test_bot
--
-- RELIABILITY MODEL
--   * queue claim uses FOR UPDATE OF job,dialog SKIP LOCKED;
--   * dialog row lock serializes claims for the same dialog;
--   * uq_zadaniya_dialog_vrabote remains the database backstop;
--   * every claim/reclaim increments nomer_vladeniya (fencing token);
--   * expired lease can be reclaimed; old worker becomes stale immediately;
--   * heartbeat/completion require worker + fencing number + live lease;
--   * heartbeat also refuses stale dialog version/state and therefore cannot keep stale work alive;
--   * completion additionally requires current dialog version;
--   * stale/blocked/human/closed due jobs are cancelled by claim cleanup;
--   * no SQL transaction is held across LLM/channel calls.
--
-- IMPORTANT
--   * Run the WHOLE file in self-hosted Supabase Studio -> SQL Editor.
--   * Production schema qbit is not touched.
--   * Probe rows are rolled back to SAVEPOINT before COMMIT.
--   * Any error before COMMIT rolls the whole DB-03C3 migration back.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03c3$
DECLARE
    v_required_table text;
    v_required_fn text;
    v_new_fn text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03C3 requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'DB-03C3 must run from trusted postgres session. session_user=%',
            session_user;
    END IF;

    IF NOT pg_catalog.pg_has_role(
        session_user,
        'qbit_test_owner',
        'SET'
    ) THEN
        RAISE EXCEPTION
            'session_user % cannot SET ROLE qbit_test_owner',
            session_user;
    END IF;

    FOREACH v_required_table IN ARRAY ARRAY[
        'identifikatory_kanalov',
        'dialogi',
        'soobshcheniya',
        'sobytiya_integraciy',
        'zadaniya_obrabotki'
    ]
    LOOP
        IF pg_catalog.to_regclass(
            pg_catalog.format('qbit_test.%I', v_required_table)
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required table qbit_test.% is missing',
                v_required_table;
        END IF;
    END LOOP;

    IF pg_catalog.to_regclass(
        'qbit_test.uq_zadaniya_dialog_vrabote'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Required unique one-active-job index is missing';
    END IF;

    FOREACH v_required_fn IN ARRAY ARRAY[
        'zaregistrirovat_vhod_klienta',
        'poluchit_kontekst_dialoga',
        'sohranit_fakty_i_pamyat',
        'proverit_limit_chastoty',
        'zapisat_narushenie_tematiky'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_test'
               AND p.proname = v_required_fn
        ) THEN
            RAISE EXCEPTION
                'Required prior function qbit_test.% is missing',
                v_required_fn;
        END IF;
    END LOOP;

    FOREACH v_new_fn IN ARRAY ARRAY[
        'zabrat_zadanie_obrabotki',
        'prodlit_arendu_zadaniya',
        'zavershit_zadanie_obrabotki'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_proc AS p
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = p.pronamespace
             WHERE n.nspname = 'qbit_test'
               AND p.proname = v_new_fn
        ) THEN
            RAISE EXCEPTION
                'DB-03C3 function qbit_test.% already exists; stop instead of overwriting',
                v_new_fn;
        END IF;
    END LOOP;
END
$db03c3$;

SET LOCAL ROLE qbit_test_owner;

-- ===========================================================================
-- 1. ATOMIC CLAIM / EXPIRED-LEASE RECLAIM
-- ===========================================================================

CREATE FUNCTION qbit_test.zabrat_zadanie_obrabotki(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    zadanie_id uuid,
    dialog_id uuid,
    sobytie_id uuid,
    tip_zadaniya text,
    status_zadaniya text,
    prioritet integer,
    popytki integer,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga bigint,
    payload jsonb,
    byl_perehvachen boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_worker text;
    v_lease_seconds integer;
    v_now timestamptz;
    v_candidate record;
    v_claimed record;
    v_cleanup_reason text;
    v_was_reclaim boolean;
    v_iteration integer;
BEGIN
    IF p_dannye IS NULL
       OR jsonb_typeof(p_dannye) <> 'object' THEN
        RETURN QUERY SELECT
            NULL::text, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Ожидается JSON object.'::text, NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
            NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint, NULL::jsonb, false;
        RETURN;
    END IF;

    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund', '')::integer;

    IF v_operaciya IS NULL
       OR v_worker IS NULL
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны operaciya_id, worker_id и trusted arenda_sekund 10..3600.'::text,
            NULL::timestamptz,
            NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
            NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint, NULL::jsonb, false;
        RETURN;
    END IF;

    -- A single call may clean a bounded number of stale due jobs before
    -- returning one usable job. It never waits on rows claimed elsewhere.
    FOR v_iteration IN 1..50 LOOP
        v_now := clock_timestamp();

        SELECT
            z.id AS job_id,
            z.dialog_id,
            z.sobytie_id,
            z.tip_zadaniya,
            z.status AS job_status,
            z.prioritet,
            z.popytki,
            z.vladelec_arendy,
            z.arenda_do,
            z.nomer_vladeniya,
            z.versiya_dialoga AS job_dialog_version,
            z.payload,
            d.versiya_dialoga AS current_dialog_version,
            d.vladelec AS dialog_owner,
            d.status AS dialog_status,
            i.logicheski_zablokirovan AS identity_blocked
          INTO v_candidate
          FROM qbit_test.zadaniya_obrabotki AS z
          JOIN qbit_test.dialogi AS d
            ON d.id = z.dialog_id
          JOIN qbit_test.identifikatory_kanalov AS i
            ON i.id = d.identifikator_kanala_id
         WHERE (
                (
                    z.status IN ('ozhidaet', 'povtor')
                    AND z.sleduyushchiy_zapusk <= v_now
                    AND NOT EXISTS (
                        SELECT 1
                          FROM qbit_test.zadaniya_obrabotki AS active_job
                         WHERE active_job.dialog_id = z.dialog_id
                           AND active_job.status = 'v_rabote'
                    )
                )
                OR
                (
                    z.status = 'v_rabote'
                    AND z.arenda_do <= v_now
                )
         )
         ORDER BY
            z.prioritet DESC,
            CASE
                WHEN z.status = 'v_rabote' THEN z.arenda_do
                ELSE z.sleduyushchiy_zapusk
            END,
            z.vremya_sozdaniya,
            z.id
         FOR UPDATE OF z, d SKIP LOCKED
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                v_operaciya, 'net_zadaniya'::text, NULL::text,
                'Готового задания сейчас нет.'::text, NULL::timestamptz,
                NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
                NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
                NULL::bigint, NULL::bigint, NULL::jsonb, false;
            RETURN;
        END IF;

        v_cleanup_reason := CASE
            WHEN v_candidate.job_dialog_version
                 IS DISTINCT FROM v_candidate.current_dialog_version
            THEN 'stale_dialog_version'
            WHEN v_candidate.identity_blocked
            THEN 'logicheski_zablokirovan'
            WHEN v_candidate.dialog_owner <> 'bot'
            THEN 'vladelec_ne_bot'
            WHEN v_candidate.dialog_status IN ('peredan_cheloveku', 'zavershen')
            THEN 'dialog_ne_aktiven'
            ELSE NULL
        END;

        IF v_cleanup_reason IS NOT NULL THEN
            UPDATE qbit_test.zadaniya_obrabotki AS z_cancel
               SET status = 'otmeneno',
                   vladelec_arendy = NULL,
                   arenda_do = NULL,
                   kod_oshibki = v_cleanup_reason,
                   opisanie_oshibki = 'DB-03C3 claim cleanup: задание устарело или больше не разрешено состоянием диалога.',
                   vremya_obnovleniya = clock_timestamp()
             WHERE z_cancel.id = v_candidate.job_id;
            CONTINUE;
        END IF;

        v_was_reclaim := (
            v_candidate.job_status = 'v_rabote'
            AND v_candidate.arenda_do <= v_now
        );

        UPDATE qbit_test.zadaniya_obrabotki AS z_claim
           SET status = 'v_rabote',
               popytki = z_claim.popytki + 1,
               vladelec_arendy = v_worker,
               arenda_do = v_now + make_interval(secs => v_lease_seconds),
               nomer_vladeniya = z_claim.nomer_vladeniya + 1,
               kod_oshibki = NULL,
               opisanie_oshibki = NULL,
               vremya_obnovleniya = clock_timestamp()
         WHERE z_claim.id = v_candidate.job_id
         RETURNING
            z_claim.id,
            z_claim.dialog_id,
            z_claim.sobytie_id,
            z_claim.tip_zadaniya,
            z_claim.status,
            z_claim.prioritet,
            z_claim.popytki,
            z_claim.vladelec_arendy,
            z_claim.arenda_do,
            z_claim.nomer_vladeniya,
            z_claim.versiya_dialoga,
            z_claim.payload
          INTO v_claimed;

        RETURN QUERY SELECT
            v_operaciya, 'uspeshno'::text, NULL::text,
            CASE
                WHEN v_was_reclaim
                THEN 'Истёкшая аренда безопасно перехвачена с новым fencing number.'
                ELSE 'Готовое задание атомарно выдано worker.'
            END::text,
            NULL::timestamptz,
            v_claimed.id,
            v_claimed.dialog_id,
            v_claimed.sobytie_id,
            v_claimed.tip_zadaniya,
            v_claimed.status,
            v_claimed.prioritet,
            v_claimed.popytki,
            v_claimed.vladelec_arendy,
            v_claimed.arenda_do,
            v_claimed.nomer_vladeniya,
            v_claimed.versiya_dialoga,
            v_claimed.payload,
            v_was_reclaim;
        RETURN;
    END LOOP;

    RETURN QUERY SELECT
        v_operaciya, 'povtor'::text, 'ochistka_limit'::text,
        'За один claim очищено 50 неактуальных due jobs; безопасно повторить claim.'::text,
        clock_timestamp() + interval '1 second',
        NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text,
        NULL::integer, NULL::integer, NULL::text, NULL::timestamptz,
        NULL::bigint, NULL::bigint, NULL::jsonb, false;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zabrat_zadanie_obrabotki(jsonb) IS
'DB-03C3: atomic due-job claim via job+dialog row locks and SKIP LOCKED; reclaims expired lease with monotonic fencing number; cleans stale/blocked/human/closed due jobs before claim.';

-- ===========================================================================
-- 2. LEASE HEARTBEAT
-- ===========================================================================

CREATE FUNCTION qbit_test.prodlit_arendu_zadaniya(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    zadanie_id uuid,
    status_zadaniya text,
    vladelec_arendy text,
    arenda_do timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_lease_seconds integer;
    v_now timestamptz;
    v_job record;
    v_dialog_version bigint;
    v_dialog_owner text;
    v_dialog_status text;
    v_identity_blocked boolean;
    v_new_lease timestamptz;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_lease_seconds := NULLIF(p_dannye->>'arenda_sekund', '')::integer;
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_lease_seconds IS NULL
       OR v_lease_seconds < 10
       OR v_lease_seconds > 3600 THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Нужны job, worker, fencing number и trusted lease 10..3600.'::text,
            NULL::timestamptz,
            v_job_id, NULL::text, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT z.*
      INTO v_job
      FROM qbit_test.zadaniya_obrabotki AS z
     WHERE z.id = v_job_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'zadanie_ne_naydeno'::text,
            'Задание не найдено.'::text, NULL::timestamptz,
            v_job_id, NULL::text, NULL::text, NULL::timestamptz,
            NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker больше не является текущим владельцем этой аренды.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL
       OR v_job.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшую аренду нельзя продлить старым worker; нужен новый claim.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    SELECT
        d.versiya_dialoga,
        d.vladelec,
        d.status,
        i.logicheski_zablokirovan
      INTO
        v_dialog_version,
        v_dialog_owner,
        v_dialog_status,
        v_identity_blocked
      FROM qbit_test.dialogi AS d
      JOIN qbit_test.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
     WHERE d.id = v_job.dialog_id
     FOR UPDATE OF d;

    IF NOT FOUND
       OR v_dialog_version IS DISTINCT FROM v_job.versiya_dialoga THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Версия диалога изменилась; stale worker больше не может продлевать lease.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    IF v_identity_blocked
       OR v_dialog_owner <> 'bot'
       OR v_dialog_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Состояние identity/dialog больше не разрешает продление bot lease.'::text,
            NULL::timestamptz,
            v_job_id, v_job.status, v_job.vladelec_arendy,
            v_job.arenda_do, v_job.nomer_vladeniya, v_job.versiya_dialoga;
        RETURN;
    END IF;

    v_new_lease := GREATEST(
        v_job.arenda_do,
        v_now + make_interval(secs => v_lease_seconds)
    );

    UPDATE qbit_test.zadaniya_obrabotki AS z_upd
       SET arenda_do = v_new_lease,
           vremya_obnovleniya = clock_timestamp()
     WHERE z_upd.id = v_job_id;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        'Аренда текущего worker продлена без изменения fencing number.'::text,
        NULL::timestamptz,
        v_job_id, 'v_rabote'::text, v_worker,
        v_new_lease, v_ownership, v_job.versiya_dialoga;
END
$fn$;

COMMENT ON FUNCTION qbit_test.prodlit_arendu_zadaniya(jsonb) IS
'DB-03C3: heartbeat продлевает только живую аренду текущего worker с совпадающим monotonic fencing number; истёкшая/перехваченная аренда получает konflikt.';

-- ===========================================================================
-- 3. FENCED COMPLETION / RETRY / CANCEL / ERROR
-- ===========================================================================

CREATE FUNCTION qbit_test.zavershit_zadanie_obrabotki(
    p_dannye jsonb
)
RETURNS TABLE (
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    zadanie_id uuid,
    dialog_id uuid,
    status_zadaniya text,
    popytki integer,
    sleduyushchiy_zapusk timestamptz,
    nomer_vladeniya bigint,
    versiya_dialoga_zadaniya bigint,
    tekushchaya_versiya_dialoga bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_test
AS $fn$
#variable_conflict use_column
DECLARE
    v_operaciya text;
    v_job_id uuid;
    v_worker text;
    v_ownership bigint;
    v_expected_dialog bigint;
    v_target_status text;
    v_retry_at timestamptz;
    v_error_code text;
    v_error_description text;
    v_now timestamptz;

    v_job record;
    v_dialog_version bigint;
    v_dialog_owner text;
    v_dialog_status text;
    v_identity_blocked boolean;
    v_saved record;
BEGIN
    v_operaciya := NULLIF(btrim(p_dannye->>'operaciya_id'), '');
    v_job_id := NULLIF(p_dannye->>'zadanie_id', '')::uuid;
    v_worker := NULLIF(btrim(p_dannye->>'worker_id'), '');
    v_ownership := NULLIF(p_dannye->>'nomer_vladeniya', '')::bigint;
    v_expected_dialog := NULLIF(p_dannye->>'ozhidaemaya_versiya_dialoga', '')::bigint;
    v_target_status := NULLIF(btrim(p_dannye->>'status'), '');
    v_retry_at := NULLIF(p_dannye->>'sleduyushchiy_zapusk', '')::timestamptz;
    v_error_code := NULLIF(btrim(p_dannye->>'kod_oshibki'), '');
    v_error_description := NULLIF(btrim(p_dannye->>'opisanie_oshibki'), '');
    v_now := clock_timestamp();

    IF v_operaciya IS NULL
       OR v_job_id IS NULL
       OR v_worker IS NULL
       OR v_ownership IS NULL
       OR v_ownership < 1
       OR v_expected_dialog IS NULL
       OR v_expected_dialog < 1
       OR v_target_status NOT IN ('zaversheno', 'povtor', 'otmeneno', 'oshibka')
       OR (
            v_target_status = 'povtor'
            AND (
                v_retry_at IS NULL
                OR v_retry_at <= v_now
                OR v_error_code IS NULL
            )
       )
       OR (
            v_target_status = 'oshibka'
            AND v_error_code IS NULL
       ) THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'nekorrektnyy_vhod'::text,
            'Некорректные completion данные; retry требует future time+error, oshibka требует error code.'::text,
            NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::text, NULL::integer,
            NULL::timestamptz, NULL::bigint, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    SELECT z.*
      INTO v_job
      FROM qbit_test.zadaniya_obrabotki AS z
     WHERE z.id = v_job_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'otkaz'::text, 'zadanie_ne_naydeno'::text,
            'Задание не найдено.'::text, NULL::timestamptz,
            v_job_id, NULL::uuid, NULL::text, NULL::integer,
            NULL::timestamptz, NULL::bigint, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.status <> 'v_rabote'
       OR v_job.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_job.nomer_vladeniya IS DISTINCT FROM v_ownership THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_lease_owner'::text,
            'Worker/fencing number больше не владеет этим заданием.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.arenda_do IS NULL
       OR v_job.arenda_do <= v_now THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'arenda_istekla'::text,
            'Истёкшая аренда не имеет права записывать результат.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    SELECT
        d.versiya_dialoga,
        d.vladelec,
        d.status,
        i.logicheski_zablokirovan
      INTO
        v_dialog_version,
        v_dialog_owner,
        v_dialog_status,
        v_identity_blocked
      FROM qbit_test.dialogi AS d
      JOIN qbit_test.identifikatory_kanalov AS i
        ON i.id = d.identifikator_kanala_id
     WHERE d.id = v_job.dialog_id
     FOR UPDATE OF d;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_nayden'::text,
            'Диалог задания больше не существует.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, NULL::bigint;
        RETURN;
    END IF;

    IF v_job.versiya_dialoga IS DISTINCT FROM v_expected_dialog
       OR v_dialog_version IS DISTINCT FROM v_expected_dialog THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'stale_dialog_version'::text,
            'Результат вычислен для устаревшей версии диалога.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, v_dialog_version;
        RETURN;
    END IF;

    IF v_identity_blocked
       OR v_dialog_owner <> 'bot'
       OR v_dialog_status IN ('peredan_cheloveku', 'zavershen') THEN
        RETURN QUERY SELECT
            v_operaciya, 'konflikt'::text, 'dialog_ne_razreshaet_bot'::text,
            'Состояние identity/dialog больше не разрешает bot completion.'::text,
            NULL::timestamptz,
            v_job_id, v_job.dialog_id, v_job.status, v_job.popytki,
            v_job.sleduyushchiy_zapusk, v_job.nomer_vladeniya,
            v_job.versiya_dialoga, v_dialog_version;
        RETURN;
    END IF;

    UPDATE qbit_test.zadaniya_obrabotki AS z_done
       SET status = v_target_status,
           sleduyushchiy_zapusk = CASE
               WHEN v_target_status = 'povtor' THEN v_retry_at
               ELSE z_done.sleduyushchiy_zapusk
           END,
           vladelec_arendy = NULL,
           arenda_do = NULL,
           kod_oshibki = CASE
               WHEN v_target_status = 'zaversheno' THEN NULL
               ELSE v_error_code
           END,
           opisanie_oshibki = CASE
               WHEN v_target_status = 'zaversheno' THEN NULL
               ELSE v_error_description
           END,
           vremya_obnovleniya = clock_timestamp()
     WHERE z_done.id = v_job_id
     RETURNING
        z_done.id,
        z_done.dialog_id,
        z_done.status,
        z_done.popytki,
        z_done.sleduyushchiy_zapusk,
        z_done.nomer_vladeniya,
        z_done.versiya_dialoga
      INTO v_saved;

    RETURN QUERY SELECT
        v_operaciya, 'uspeshno'::text, NULL::text,
        CASE v_target_status
            WHEN 'zaversheno' THEN 'Задание завершено текущим владельцем.'
            WHEN 'povtor' THEN 'Безопасный retry запланирован; аренда освобождена.'
            WHEN 'otmeneno' THEN 'Задание отменено текущим владельцем; аренда освобождена.'
            ELSE 'Задание завершено постоянной ошибкой; аренда освобождена.'
        END::text,
        CASE WHEN v_target_status = 'povtor' THEN v_retry_at ELSE NULL END,
        v_saved.id,
        v_saved.dialog_id,
        v_saved.status,
        v_saved.popytki,
        v_saved.sleduyushchiy_zapusk,
        v_saved.nomer_vladeniya,
        v_saved.versiya_dialoga,
        v_dialog_version;
END
$fn$;

COMMENT ON FUNCTION qbit_test.zavershit_zadanie_obrabotki(jsonb) IS
'DB-03C3: fenced completion/retry/cancel/error требует live lease, current worker, ownership number и совпадающую dialog version; stale worker/version получает konflikt без записи результата.';

-- ===========================================================================
-- 4. PRIVILEGES
-- ===========================================================================

REVOKE ALL ON FUNCTION qbit_test.zabrat_zadanie_obrabotki(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.prodlit_arendu_zadaniya(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION qbit_test.zavershit_zadanie_obrabotki(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION qbit_test.zabrat_zadanie_obrabotki(jsonb)
TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.prodlit_arendu_zadaniya(jsonb)
TO qbit_test_bot;
GRANT EXECUTE ON FUNCTION qbit_test.zavershit_zadanie_obrabotki(jsonb)
TO qbit_test_bot;

-- ===========================================================================
-- 5. STATIC SECURITY ASSERTIONS
-- ===========================================================================

DO $db03c3$
DECLARE
    v_fn record;
BEGIN
    FOR v_fn IN
        SELECT
            p.oid,
            p.proname,
            p.prosecdef,
            p.proconfig,
            r.rolname AS owner_name
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
          JOIN pg_catalog.pg_roles AS r
            ON r.oid = p.proowner
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki'
           )
    LOOP
        IF NOT v_fn.prosecdef THEN
            RAISE EXCEPTION
                'Function % is not SECURITY DEFINER',
                v_fn.proname;
        END IF;

        IF v_fn.owner_name IS DISTINCT FROM 'qbit_test_owner' THEN
            RAISE EXCEPTION
                'Function % has wrong owner %',
                v_fn.proname,
                v_fn.owner_name;
        END IF;

        IF NOT (
            COALESCE(v_fn.proconfig, ARRAY[]::text[])
            @> ARRAY['search_path=pg_catalog, qbit_test']::text[]
        ) THEN
            RAISE EXCEPTION
                'Function % has unsafe search_path %',
                v_fn.proname,
                v_fn.proconfig;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM pg_catalog.aclexplode(
                    COALESCE(
                        (SELECT p2.proacl
                           FROM pg_catalog.pg_proc AS p2
                          WHERE p2.oid = v_fn.oid),
                        pg_catalog.acldefault(
                            'f',
                            (SELECT p2.proowner
                               FROM pg_catalog.pg_proc AS p2
                              WHERE p2.oid = v_fn.oid)
                        )
                    )
              ) AS a
             WHERE a.grantee = 0
               AND a.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'PUBLIC unexpectedly has EXECUTE on %',
                v_fn.proname;
        END IF;

        IF NOT pg_catalog.has_function_privilege(
            'qbit_test_bot',
            v_fn.oid,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_bot lacks EXECUTE on %',
                v_fn.proname;
        END IF;

        IF pg_catalog.has_function_privilege(
            'qbit_test_sluzhebnyy',
            v_fn.oid,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'qbit_test_sluzhebnyy unexpectedly has queue EXECUTE on %',
                v_fn.proname;
        END IF;
    END LOOP;

    IF (
        SELECT count(*)
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki'
           )
    ) <> 3 THEN
        RAISE EXCEPTION
            'DB-03C3 expected exactly 3 API functions';
    END IF;
END
$db03c3$;

-- ===========================================================================
-- 6. DISPOSABLE BEHAVIOR PROBE
-- ===========================================================================

SAVEPOINT db03c3_probe;

DO $db03c3$
DECLARE
    r1 record;
    r2 record;
    r3 record;
    r4 record;

    c1 record;
    c_none record;
    hb_wrong record;
    hb_ok record;
    hb_stale_dialog record;
    stale_finish record;
    c2 record;
    c3 record;
    hb_stale record;
    finish_stale_owner record;
    retry_done record;
    c4 record;
    done_ok record;
    c5 record;
    err_ok record;
    c6 record;
    cancel_ok record;

    v_r1_status text;
    v_r1_code text;
BEGIN
    -- Message 1 / job version 1.
    SELECT *
      INTO r1
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c3_ingress_1',
            'klyuch_idempotentnosti', 'db03c3_idem_1',
            'hash_soderzhaniya', 'db03c3_hash_1',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c3_client_bot',
            'vneshnee_sobytie_id', 'db03c3_event_1',
            'vneshniy_polzovatel_id', 'db03c3_user',
            'vneshniy_dialog_id', 'db03c3_chat',
            'vneshnee_soobshchenie_id', 'db03c3_msg_1',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'DB-03C3 message 1',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03c3_probe',
            'versiya_prompta', 'db03c3_probe',
            'sluzhebnyy_chat_id', 'db03c3_service_group'
        )
      );

    IF r1.rezultat <> 'uspeshno'
       OR r1.versiya_dialoga <> 1 THEN
        RAISE EXCEPTION
            'DB-03C3 setup ingress1 failed: %',
            row_to_json(r1);
    END IF;

    SELECT *
      INTO c1
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_a',
            'worker_id', 'worker_a',
            'arenda_sekund', 120
        )
      );

    IF c1.rezultat <> 'uspeshno'
       OR c1.zadanie_id IS DISTINCT FROM r1.zadanie_id
       OR c1.nomer_vladeniya <> 1
       OR c1.popytki <> 1
       OR c1.byl_perehvachen THEN
        RAISE EXCEPTION
            'DB-03C3 first claim failed: %',
            row_to_json(c1);
    END IF;

    -- No second worker may get another active job for this dialog.
    SELECT *
      INTO c_none
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_while_active',
            'worker_id', 'worker_b',
            'arenda_sekund', 120
        )
      );

    IF c_none.rezultat <> 'net_zadaniya' THEN
        RAISE EXCEPTION
            'DB-03C3 one-active-job guard failed: %',
            row_to_json(c_none);
    END IF;

    SELECT *
      INTO hb_wrong
      FROM qbit_test.prodlit_arendu_zadaniya(
        jsonb_build_object(
            'operaciya_id', 'db03c3_hb_wrong',
            'zadanie_id', c1.zadanie_id,
            'worker_id', 'worker_wrong',
            'nomer_vladeniya', c1.nomer_vladeniya,
            'arenda_sekund', 120
        )
      );

    IF hb_wrong.rezultat <> 'konflikt'
       OR hb_wrong.kod_oshibki <> 'stale_lease_owner' THEN
        RAISE EXCEPTION
            'DB-03C3 wrong-worker heartbeat was not fenced: %',
            row_to_json(hb_wrong);
    END IF;

    SELECT *
      INTO hb_ok
      FROM qbit_test.prodlit_arendu_zadaniya(
        jsonb_build_object(
            'operaciya_id', 'db03c3_hb_ok',
            'zadanie_id', c1.zadanie_id,
            'worker_id', 'worker_a',
            'nomer_vladeniya', c1.nomer_vladeniya,
            'arenda_sekund', 180
        )
      );

    IF hb_ok.rezultat <> 'uspeshno'
       OR hb_ok.nomer_vladeniya <> c1.nomer_vladeniya
       OR hb_ok.arenda_do <= c1.arenda_do THEN
        RAISE EXCEPTION
            'DB-03C3 valid heartbeat failed: %',
            row_to_json(hb_ok);
    END IF;

    -- New client input while worker A is computing: dialog version becomes 2,
    -- second job is pending but cannot be claimed while job1 lease is active.
    SELECT *
      INTO r2
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c3_ingress_2',
            'klyuch_idempotentnosti', 'db03c3_idem_2',
            'hash_soderzhaniya', 'db03c3_hash_2',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c3_client_bot',
            'vneshnee_sobytie_id', 'db03c3_event_2',
            'vneshniy_polzovatel_id', 'db03c3_user',
            'vneshniy_dialog_id', 'db03c3_chat',
            'vneshnee_soobshchenie_id', 'db03c3_msg_2',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'DB-03C3 message 2',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03c3_probe',
            'versiya_prompta', 'db03c3_probe',
            'sluzhebnyy_chat_id', 'db03c3_service_group'
        )
      );

    IF r2.rezultat <> 'uspeshno'
       OR r2.versiya_dialoga <> 2 THEN
        RAISE EXCEPTION
            'DB-03C3 setup ingress2 failed: %',
            row_to_json(r2);
    END IF;

    SELECT *
      INTO hb_stale_dialog
      FROM qbit_test.prodlit_arendu_zadaniya(
        jsonb_build_object(
            'operaciya_id', 'db03c3_hb_stale_dialog',
            'zadanie_id', c1.zadanie_id,
            'worker_id', 'worker_a',
            'nomer_vladeniya', c1.nomer_vladeniya,
            'arenda_sekund', 180
        )
      );

    IF hb_stale_dialog.rezultat <> 'konflikt'
       OR hb_stale_dialog.kod_oshibki <> 'stale_dialog_version' THEN
        RAISE EXCEPTION
            'DB-03C3 stale dialog heartbeat extended lease: %',
            row_to_json(hb_stale_dialog);
    END IF;

    SELECT *
      INTO c_none
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_pending_same_dialog',
            'worker_id', 'worker_b',
            'arenda_sekund', 120
        )
      );

    IF c_none.rezultat <> 'net_zadaniya' THEN
        RAISE EXCEPTION
            'DB-03C3 pending same-dialog job bypassed active lease: %',
            row_to_json(c_none);
    END IF;

    -- Worker A still owns a live lease but its dialog version is stale.
    SELECT *
      INTO stale_finish
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_finish_stale_dialog',
            'zadanie_id', c1.zadanie_id,
            'worker_id', 'worker_a',
            'nomer_vladeniya', c1.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 1,
            'status', 'zaversheno'
        )
      );

    IF stale_finish.rezultat <> 'konflikt'
       OR stale_finish.kod_oshibki <> 'stale_dialog_version'
       OR stale_finish.tekushchaya_versiya_dialoga <> 2 THEN
        RAISE EXCEPTION
            'DB-03C3 stale dialog completion was not rejected: %',
            row_to_json(stale_finish);
    END IF;

    -- Simulate lease expiry. Next claim must cancel stale job1 and claim job2.
    UPDATE qbit_test.zadaniya_obrabotki AS z_probe
       SET arenda_do = clock_timestamp() - interval '1 second'
     WHERE z_probe.id = c1.zadanie_id;

    SELECT *
      INTO c2
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_b',
            'worker_id', 'worker_b',
            'arenda_sekund', 120
        )
      );

    SELECT z.status, z.kod_oshibki
      INTO v_r1_status, v_r1_code
      FROM qbit_test.zadaniya_obrabotki AS z
     WHERE z.id = r1.zadanie_id;

    IF c2.rezultat <> 'uspeshno'
       OR c2.zadanie_id IS DISTINCT FROM r2.zadanie_id
       OR c2.nomer_vladeniya <> 1
       OR c2.popytki <> 1
       OR v_r1_status <> 'otmeneno'
       OR v_r1_code <> 'stale_dialog_version' THEN
        RAISE EXCEPTION
            'DB-03C3 stale cleanup / next job claim failed: claim=%, old_status=%, old_code=%',
            row_to_json(c2),
            v_r1_status,
            v_r1_code;
    END IF;

    -- Expired current-version job2 is reclaimed as the SAME job with fencing+1.
    UPDATE qbit_test.zadaniya_obrabotki AS z_probe
       SET arenda_do = clock_timestamp() - interval '1 second'
     WHERE z_probe.id = c2.zadanie_id;

    SELECT *
      INTO c3
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_c_reclaim',
            'worker_id', 'worker_c',
            'arenda_sekund', 120
        )
      );

    IF c3.rezultat <> 'uspeshno'
       OR c3.zadanie_id IS DISTINCT FROM c2.zadanie_id
       OR c3.nomer_vladeniya <> 2
       OR c3.popytki <> 2
       OR NOT c3.byl_perehvachen THEN
        RAISE EXCEPTION
            'DB-03C3 expired lease reclaim/fencing failed: old=%, new=%',
            row_to_json(c2),
            row_to_json(c3);
    END IF;

    SELECT *
      INTO hb_stale
      FROM qbit_test.prodlit_arendu_zadaniya(
        jsonb_build_object(
            'operaciya_id', 'db03c3_hb_stale_after_reclaim',
            'zadanie_id', c2.zadanie_id,
            'worker_id', 'worker_b',
            'nomer_vladeniya', c2.nomer_vladeniya,
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO finish_stale_owner
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_finish_stale_owner',
            'zadanie_id', c2.zadanie_id,
            'worker_id', 'worker_b',
            'nomer_vladeniya', c2.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 2,
            'status', 'zaversheno'
        )
      );

    IF hb_stale.rezultat <> 'konflikt'
       OR finish_stale_owner.rezultat <> 'konflikt'
       OR hb_stale.kod_oshibki <> 'stale_lease_owner'
       OR finish_stale_owner.kod_oshibki <> 'stale_lease_owner' THEN
        RAISE EXCEPTION
            'DB-03C3 old worker was not fenced after reclaim: hb=%, finish=%',
            row_to_json(hb_stale),
            row_to_json(finish_stale_owner);
    END IF;

    -- Current owner schedules a safe retry.
    SELECT *
      INTO retry_done
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_retry',
            'zadanie_id', c3.zadanie_id,
            'worker_id', 'worker_c',
            'nomer_vladeniya', c3.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 2,
            'status', 'povtor',
            'sleduyushchiy_zapusk', clock_timestamp() + interval '10 minutes',
            'kod_oshibki', 'temporary_probe',
            'opisanie_oshibki', 'DB-03C3 retry probe'
        )
      );

    IF retry_done.rezultat <> 'uspeshno'
       OR retry_done.status_zadaniya <> 'povtor' THEN
        RAISE EXCEPTION
            'DB-03C3 retry completion failed: %',
            row_to_json(retry_done);
    END IF;

    -- Make the retry due, claim again: same job, ownership=3, attempts=3.
    UPDATE qbit_test.zadaniya_obrabotki AS z_probe
       SET sleduyushchiy_zapusk = clock_timestamp() - interval '1 second'
     WHERE z_probe.id = c3.zadanie_id;

    SELECT *
      INTO c4
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_d_retry',
            'worker_id', 'worker_d',
            'arenda_sekund', 120
        )
      );

    IF c4.rezultat <> 'uspeshno'
       OR c4.zadanie_id IS DISTINCT FROM c3.zadanie_id
       OR c4.nomer_vladeniya <> 3
       OR c4.popytki <> 3
       OR c4.byl_perehvachen THEN
        RAISE EXCEPTION
            'DB-03C3 retry re-claim failed: %',
            row_to_json(c4);
    END IF;

    SELECT *
      INTO done_ok
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_done',
            'zadanie_id', c4.zadanie_id,
            'worker_id', 'worker_d',
            'nomer_vladeniya', c4.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 2,
            'status', 'zaversheno'
        )
      );

    IF done_ok.rezultat <> 'uspeshno'
       OR done_ok.status_zadaniya <> 'zaversheno'
       OR EXISTS (
            SELECT 1
              FROM qbit_test.zadaniya_obrabotki AS z
             WHERE z.id = c4.zadanie_id
               AND (
                    z.vladelec_arendy IS NOT NULL
                    OR z.arenda_do IS NOT NULL
                    OR z.kod_oshibki IS NOT NULL
               )
       ) THEN
        RAISE EXCEPTION
            'DB-03C3 final success completion failed: %',
            row_to_json(done_ok);
    END IF;

    -- Version 3: permanent error path.
    SELECT *
      INTO r3
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c3_ingress_3',
            'klyuch_idempotentnosti', 'db03c3_idem_3',
            'hash_soderzhaniya', 'db03c3_hash_3',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c3_client_bot',
            'vneshnee_sobytie_id', 'db03c3_event_3',
            'vneshniy_polzovatel_id', 'db03c3_user',
            'vneshniy_dialog_id', 'db03c3_chat',
            'vneshnee_soobshchenie_id', 'db03c3_msg_3',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'DB-03C3 message 3',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03c3_probe',
            'versiya_prompta', 'db03c3_probe',
            'sluzhebnyy_chat_id', 'db03c3_service_group'
        )
      );

    SELECT *
      INTO c5
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_e',
            'worker_id', 'worker_e',
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO err_ok
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_error',
            'zadanie_id', c5.zadanie_id,
            'worker_id', 'worker_e',
            'nomer_vladeniya', c5.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 3,
            'status', 'oshibka',
            'kod_oshibki', 'permanent_probe',
            'opisanie_oshibki', 'DB-03C3 permanent error probe'
        )
      );

    IF r3.versiya_dialoga <> 3
       OR c5.zadanie_id IS DISTINCT FROM r3.zadanie_id
       OR err_ok.rezultat <> 'uspeshno'
       OR err_ok.status_zadaniya <> 'oshibka' THEN
        RAISE EXCEPTION
            'DB-03C3 permanent error path failed: ingress=%, claim=%, finish=%',
            row_to_json(r3),
            row_to_json(c5),
            row_to_json(err_ok);
    END IF;

    -- Version 4: explicit cancel path.
    SELECT *
      INTO r4
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03c3_ingress_4',
            'klyuch_idempotentnosti', 'db03c3_idem_4',
            'hash_soderzhaniya', 'db03c3_hash_4',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03c3_client_bot',
            'vneshnee_sobytie_id', 'db03c3_event_4',
            'vneshniy_polzovatel_id', 'db03c3_user',
            'vneshniy_dialog_id', 'db03c3_chat',
            'vneshnee_soobshchenie_id', 'db03c3_msg_4',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'DB-03C3 message 4',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03c3_probe',
            'versiya_prompta', 'db03c3_probe',
            'sluzhebnyy_chat_id', 'db03c3_service_group'
        )
      );

    SELECT *
      INTO c6
      FROM qbit_test.zabrat_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_claim_f',
            'worker_id', 'worker_f',
            'arenda_sekund', 120
        )
      );

    SELECT *
      INTO cancel_ok
      FROM qbit_test.zavershit_zadanie_obrabotki(
        jsonb_build_object(
            'operaciya_id', 'db03c3_cancel',
            'zadanie_id', c6.zadanie_id,
            'worker_id', 'worker_f',
            'nomer_vladeniya', c6.nomer_vladeniya,
            'ozhidaemaya_versiya_dialoga', 4,
            'status', 'otmeneno',
            'kod_oshibki', 'cancelled_by_probe',
            'opisanie_oshibki', 'DB-03C3 cancel probe'
        )
      );

    IF r4.versiya_dialoga <> 4
       OR c6.zadanie_id IS DISTINCT FROM r4.zadanie_id
       OR cancel_ok.rezultat <> 'uspeshno'
       OR cancel_ok.status_zadaniya <> 'otmeneno' THEN
        RAISE EXCEPTION
            'DB-03C3 cancel path failed: ingress=%, claim=%, finish=%',
            row_to_json(r4),
            row_to_json(c6),
            row_to_json(cancel_ok);
    END IF;
END
$db03c3$;

ROLLBACK TO SAVEPOINT db03c3_probe;
RELEASE SAVEPOINT db03c3_probe;

-- ===========================================================================
-- 7. POST-PROBE ASSERTIONS
-- ===========================================================================

DO $db03c3$
DECLARE
    v_role text;
    v_table record;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03c3_client_bot'
            OR i.vneshniy_polzovatel_id = 'db03c3_user'
    ) THEN
        RAISE EXCEPTION
            'DB-03C3 probe rows remain after rollback';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'qbit_test_bot',
        'qbit_test_sluzhebnyy',
        'qbit_test_dash_admin'
    ]
    LOOP
        FOR v_table IN
            SELECT c.oid, c.relname
              FROM pg_catalog.pg_class AS c
              JOIN pg_catalog.pg_namespace AS n
                ON n.oid = c.relnamespace
             WHERE n.nspname = 'qbit_test'
               AND c.relkind = 'r'
        LOOP
            IF pg_catalog.has_table_privilege(v_role, v_table.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(v_role, v_table.oid, 'DELETE') THEN
                RAISE EXCEPTION
                    'Runtime role % unexpectedly has direct DML on qbit_test.%',
                    v_role,
                    v_table.relname;
            END IF;
        END LOOP;
    END LOOP;
END
$db03c3$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 8. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03c3_status',
    'applied',
    'database',
    current_database(),
    'schema',
    'qbit_test',
    'functions_ok',
    (
        SELECT count(*) = 3
          FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n
            ON n.oid = p.pronamespace
         WHERE n.nspname = 'qbit_test'
           AND p.proname IN (
                'zabrat_zadanie_obrabotki',
                'prodlit_arendu_zadaniya',
                'zavershit_zadanie_obrabotki'
           )
           AND p.prosecdef = true
    ),
    'bot_execute_ok',
    pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.zabrat_zadanie_obrabotki(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.prodlit_arendu_zadaniya(jsonb)',
        'EXECUTE'
    )
    AND pg_catalog.has_function_privilege(
        'qbit_test_bot',
        'qbit_test.zavershit_zadanie_obrabotki(jsonb)',
        'EXECUTE'
    ),
    'service_execute_denied',
    NOT pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_test.zabrat_zadanie_obrabotki(jsonb)',
        'EXECUTE'
    ),
    'one_active_job_index_ok',
    pg_catalog.to_regclass('qbit_test.uq_zadaniya_dialog_vrabote') IS NOT NULL,
    'probe_rows_remaining',
    (
        SELECT count(*)
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03c3_client_bot'
            OR i.vneshniy_polzovatel_id = 'db03c3_user'
    ),
    'runtime_direct_dml',
    false,
    'result',
    'DB-03C3 SQL APPLIED: queue claim/SKIP LOCKED/lease heartbeat/fencing/reclaim/dialog-version CAS verified; probe data removed; production untouched.'
) AS db03c3_result;
