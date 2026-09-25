-- DB-03V v0.2: integration probe for late confirmed bot send after operator Take
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- TARGET: qbit_test ONLY, self-hosted PostgreSQL 17.6
--
-- PURPOSE
--   Prove the critical crossing scenario:
--     bot outgoing already v_rabote
--     -> manager Take changes dialog to human owner/version
--     -> late external podtverzhdeno arrives for that already-started bot send
--   The external confirmed fact MUST be persisted, but stale dependent effects
--   MUST NOT restore bot ownership, wait/t0/reminders, stage or goal.
--
-- IMPORTANT
--   * This file creates NO permanent functions/tables/indexes.
--   * All probe rows are inside SAVEPOINT and rolled back before COMMIT.
--   * The direct UPDATE to v_rabote below intentionally simulates the exact
--     state produced by C4 claim for THIS probe action only. It avoids consuming
--     unrelated due actions that may already exist in qbit_test.
--   * Production schema qbit is never referenced for writes.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

-- ===========================================================================
-- 0. PRECHECK
-- ===========================================================================

DO $db03v$
DECLARE
    v_required text;
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION
            'DB-03V requires PostgreSQL 17+, current=%',
            current_setting('server_version');
    END IF;

    IF session_user <> 'postgres'
       OR NOT pg_catalog.pg_has_role(
            session_user,
            'qbit_test_owner',
            'SET'
       ) THEN
        RAISE EXCEPTION
            'DB-03V requires trusted postgres session with SET qbit_test_owner';
    END IF;

    FOREACH v_required IN ARRAY ARRAY[
        'zaregistrirovat_vhod_klienta(jsonb)',
        'sozdat_ishodyashchee_deystvie(jsonb)',
        'zafiksirovat_rezultat_ishodyashchego(jsonb)',
        'zaregistrirovat_sluzhebnoe_sobytie(jsonb)',
        'zabrat_dialog_operatorom(jsonb)'
    ]
    LOOP
        IF pg_catalog.to_regprocedure(
            pg_catalog.format('qbit_test.%s', v_required)
        ) IS NULL THEN
            RAISE EXCEPTION
                'Required function qbit_test.% is missing',
                v_required;
        END IF;
    END LOOP;

    IF pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(
            'qbit_test.zafiksirovat_rezultat_ishodyashchego(jsonb)'::regprocedure
        ),
        'v_action.istochnik = ''menedzher'''
    ) = 0 THEN
        RAISE EXCEPTION
            'DB-03D2 upgraded outgoing-result function is not installed';
    END IF;

END
$db03v$;

SET LOCAL ROLE qbit_test_owner;

SAVEPOINT db03v_probe;

-- ===========================================================================
-- 1. CROSSING-SCENARIO PROBE
-- ===========================================================================

DO $db03v$
DECLARE
    v_manager_id uuid;

    v_ingress record;
    v_action_create record;
    v_take_event record;
    v_take record;
    v_late_confirm record;

    v_dialog_before record;
    v_dialog_after_take record;
    v_dialog_after_confirm record;
    v_action_after_take record;
    v_action_after_confirm record;
    v_message_after_take record;
    v_message_after_confirm record;

    v_fencing bigint;
    v_worker text := 'db03v_bot_worker';
    v_stage_before text;
    v_reminder_count bigint;
    v_goal_count bigint;
    v_stage_event_count bigint;
    v_bot_mirror_count bigint;
    v_bot_mirror_effects_applied boolean;
BEGIN
    -- One allowed manager for this disposable Take.
    INSERT INTO qbit_test.menedzhery_telegram AS new_manager (
        telegram_user_id,
        otobrazhaemoe_imya,
        aktiven,
        mozhet_zabirat,
        mozhet_vozvrashchat,
        lichnye_uvedomleniya,
        prioritet_naznacheniya
    )
    VALUES (
        'db03v_manager',
        'Менеджер DB-03V',
        true,
        true,
        true,
        false,
        10
    )
    RETURNING new_manager.id
    INTO v_manager_id;

    -- New client dialog. DB-03C1 also creates the durable topic intent and
    -- initial processing job; Take must later cancel that internal job.
    SELECT *
      INTO v_ingress
      FROM qbit_test.zaregistrirovat_vhod_klienta(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03v_client_ingress',
            'klyuch_idempotentnosti', 'db03v_client_idem',
            'hash_soderzhaniya', 'db03v_client_hash',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03v_client_bot',
            'vneshnee_sobytie_id', 'db03v_client_event',
            'vneshniy_polzovatel_id', 'db03v_client_user',
            'vneshniy_dialog_id', 'db03v_client_chat',
            'vneshnee_soobshchenie_id', 'db03v_client_msg',
            'tip_sobytiya', 'message',
            'tip_soobshcheniya', 'text',
            'tekst_ishodnyy', 'Хочу уточнить условия',
            'vremya_priema', clock_timestamp(),
            'versiya_workflow', 'db03v_probe',
            'versiya_prompta', 'db03v_probe',
            'sluzhebnyy_chat_id', 'db03v_service_group',
            'bezopasnaya_podpis_klienta', 'Клиент DB-03V'
        )
      );

    IF v_ingress.rezultat <> 'uspeshno' THEN
        RAISE EXCEPTION
            'DB-03V setup ingress failed: %',
            row_to_json(v_ingress);
    END IF;

    SELECT d.*
      INTO v_dialog_before
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_ingress.dialog_id
     FOR UPDATE;

    v_stage_before := v_dialog_before.etap;

    -- Create a waiting bot message with deliberately visible dependent effects.
    -- If stale effects accidentally run after Take, stage/goal/t0/reminders
    -- will expose the bug.
    SELECT *
      INTO v_action_create
      FROM qbit_test.sozdat_ishodyashchee_deystvie(
        jsonb_build_object(
            'operaciya_id', 'db03v_bot_action_create',
            'klyuch_povtora', 'db03v_bot_action',
            'dialog_id', v_ingress.dialog_id,
            'ozhidaemaya_versiya_dialoga', v_dialog_before.versiya_dialoga,
            'istochnik', 'bot',
            'kanal', 'telegram',
            'akkaunt_kanala_id', 'db03v_client_bot',
            'vneshniy_dialog_id', 'db03v_client_chat',
            'tekst_ishodnyy', 'Это сообщение уже ушло во внешний Telegram API',
            'tekst_obezlichennyy', 'Это сообщение уже ушло во внешний Telegram API',
            'ozhidaetsya_otvet', true,
            'effekty_posle_podtverzhdeniya',
                jsonb_build_object(
                    'novyy_etap', 'db03v_stale_stage_must_not_apply',
                    'kod_celi', 'db03v_stale_goal_must_not_apply',
                    'napominanie_1_sekund', 10800,
                    'napominanie_2_sekund', 43200,
                    'okno_napominaniya_sekund', 3600,
                    'poterya_posle_sekund', 86400
                )
        )
      );

    IF v_action_create.rezultat <> 'uspeshno'
       OR v_action_create.status_deystviya <> 'zaplanirovano' THEN
        RAISE EXCEPTION
            'DB-03V bot action creation failed: %',
            row_to_json(v_action_create);
    END IF;

    -- Simulate the exact state produced by C4 claim for THIS action only.
    -- This intentionally avoids a queue-wide claim that could consume unrelated
    -- qbit_test work.
    UPDATE qbit_test.ishodyashchie_deystviya AS a_claim
       SET status = 'v_rabote',
           popytki = a_claim.popytki + 1,
           vladelec_arendy = v_worker,
           arenda_do = clock_timestamp() + interval '600 seconds',
           nomer_vladeniya = a_claim.nomer_vladeniya + 1,
           vremya_zaprosa = clock_timestamp(),
           povtor_posle = NULL,
           kod_oshibki = NULL,
           opisanie_oshibki = NULL,
           vremya_obnovleniya = clock_timestamp()
     WHERE a_claim.id = v_action_create.deystvie_id
       AND a_claim.status = 'zaplanirovano'
    RETURNING a_claim.nomer_vladeniya
      INTO v_fencing;

    IF v_fencing IS NULL THEN
        RAISE EXCEPTION
            'DB-03V could not transition probe action to v_rabote';
    END IF;

    UPDATE qbit_test.soobshcheniya AS m_claim
       SET status_otpravki = 'v_rabote'
     WHERE m_claim.id = v_action_create.soobshchenie_id;

    -- Register the real service callback that will Take the dialog while
    -- the bot external call is still in flight.
    SELECT *
      INTO v_take_event
      FROM qbit_test.zaregistrirovat_sluzhebnoe_sobytie(
        jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'db03v_take_event',
            'akkaunt_istochnika_id', 'db03v_service_bot',
            'vneshnee_sobytie_id', 'db03v_take_update',
            'tip_sobytiya', 'callback_take',
            'klyuch_idempotentnosti', 'db03v_take_idem',
            'hash_soderzhaniya', 'db03v_take_hash',
            'payload_ishodnyy', jsonb_build_object(
                'dialog_id', v_ingress.dialog_id,
                'telegram_user_id', 'db03v_manager'
            ),
            'vremya_priema', clock_timestamp()
        )
      );

    IF v_take_event.rezultat <> 'uspeshno' THEN
        RAISE EXCEPTION
            'DB-03V service Take event registration failed: %',
            row_to_json(v_take_event);
    END IF;

    SELECT *
      INTO v_take
      FROM qbit_test.zabrat_dialog_operatorom(
        jsonb_build_object(
            'operaciya_id', 'db03v_take',
            'sobytie_id', v_take_event.sobytie_id,
            'dialog_id', v_ingress.dialog_id,
            'telegram_user_id', 'db03v_manager',
            'ozhidaemaya_versiya_dialoga', v_dialog_before.versiya_dialoga
        )
      );

    IF v_take.rezultat <> 'uspeshno'
       OR v_take.vladelec <> 'chelovek'
       OR v_take.menedzher_id IS DISTINCT FROM v_manager_id THEN
        RAISE EXCEPTION
            'DB-03V Take failed: %',
            row_to_json(v_take);
    END IF;

    SELECT d.*
      INTO v_dialog_after_take
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_ingress.dialog_id;

    SELECT a.*
      INTO v_action_after_take
      FROM qbit_test.ishodyashchie_deystviya AS a
     WHERE a.id = v_action_create.deystvie_id;

    SELECT m.*
      INTO v_message_after_take
      FROM qbit_test.soobshcheniya AS m
     WHERE m.id = v_action_create.soobshchenie_id;

    -- This is the key precondition: Take must NOT erase an already-started
    -- external attempt.
    IF v_dialog_after_take.vladelec <> 'chelovek'
       OR v_dialog_after_take.status <> 'peredan_cheloveku'
       OR v_dialog_after_take.tekushchiy_menedzher_id IS DISTINCT FROM v_manager_id
       OR v_dialog_after_take.versiya_dialoga
            <> v_dialog_before.versiya_dialoga + 1
       OR v_dialog_after_take.pokolenie_ozhidaniya
            <> v_dialog_before.pokolenie_ozhidaniya + 1
       OR v_dialog_after_take.ozhidaetsya_otvet
       OR v_dialog_after_take.t0 IS NOT NULL
       OR v_action_after_take.status <> 'v_rabote'
       OR v_action_after_take.vladelec_arendy IS DISTINCT FROM v_worker
       OR v_action_after_take.nomer_vladeniya IS DISTINCT FROM v_fencing
       OR v_action_after_take.versiya_dialoga
            IS DISTINCT FROM v_dialog_before.versiya_dialoga
       OR v_message_after_take.status_otpravki <> 'v_rabote' THEN
        RAISE EXCEPTION
            'DB-03V pre-late-confirm state is wrong: dialog=%, action=%, message=%',
            row_to_json(v_dialog_after_take),
            row_to_json(v_action_after_take),
            row_to_json(v_message_after_take);
    END IF;

    -- External Telegram API now reports success AFTER Take.
    SELECT *
      INTO v_late_confirm
      FROM qbit_test.zafiksirovat_rezultat_ishodyashchego(
        jsonb_build_object(
            'operaciya_id', 'db03v_late_confirm',
            'deystvie_id', v_action_create.deystvie_id,
            'worker_id', v_worker,
            'nomer_vladeniya', v_fencing,
            'status', 'podtverzhdeno',
            'vneshniy_id', 'db03v_external_message',
            'vremya_podtverzhdeniya', clock_timestamp()
        )
      );

    SELECT d.*
      INTO v_dialog_after_confirm
      FROM qbit_test.dialogi AS d
     WHERE d.id = v_ingress.dialog_id;

    SELECT a.*
      INTO v_action_after_confirm
      FROM qbit_test.ishodyashchie_deystviya AS a
     WHERE a.id = v_action_create.deystvie_id;

    SELECT m.*
      INTO v_message_after_confirm
      FROM qbit_test.soobshcheniya AS m
     WHERE m.id = v_action_create.soobshchenie_id;

    SELECT count(*)
      INTO v_reminder_count
      FROM qbit_test.napominaniya AS n
     WHERE n.dialog_id = v_ingress.dialog_id;

    SELECT count(*)
      INTO v_goal_count
      FROM qbit_test.celevye_sobytiya AS g
     WHERE g.dialog_id = v_ingress.dialog_id
       AND g.kod_celi = 'db03v_stale_goal_must_not_apply';

    SELECT count(*)
      INTO v_stage_event_count
      FROM qbit_test.sobytiya_etapov AS se
     WHERE se.dialog_id = v_ingress.dialog_id
       AND se.novyy_etap = 'db03v_stale_stage_must_not_apply';

    SELECT
        count(*),
        COALESCE(
            bool_or(
                COALESCE((z.payload->>'effekty_primeneny')::boolean, true)
            ),
            true
        )
      INTO v_bot_mirror_count, v_bot_mirror_effects_applied
      FROM qbit_test.sobytiya_zerkala_operatora AS z
     WHERE z.klyuch_idempotentnosti =
        'bot_confirmed:' || v_action_create.soobshchenie_id::text;

    IF v_late_confirm.rezultat <> 'uspeshno'
       OR v_late_confirm.status_deystviya <> 'podtverzhdeno'
       OR v_late_confirm.opisanie IS DISTINCT FROM
            'Внешний confirmed-факт сохранён, но устаревшие зависимые эффекты подавлены.'
       OR v_action_after_confirm.status <> 'podtverzhdeno'
       OR v_action_after_confirm.vneshniy_id <> 'db03v_external_message'
       OR v_action_after_confirm.vremya_podtverzhdeniya IS NULL
       OR v_message_after_confirm.status_otpravki <> 'podtverzhdeno'
       OR v_message_after_confirm.vneshnee_soobshchenie_id
            <> 'db03v_external_message'
       OR v_dialog_after_confirm.vladelec <> 'chelovek'
       OR v_dialog_after_confirm.status <> 'peredan_cheloveku'
       OR v_dialog_after_confirm.tekushchiy_menedzher_id
            IS DISTINCT FROM v_manager_id
       OR v_dialog_after_confirm.versiya_dialoga
            IS DISTINCT FROM v_dialog_after_take.versiya_dialoga
       OR v_dialog_after_confirm.pokolenie_ozhidaniya
            IS DISTINCT FROM v_dialog_after_take.pokolenie_ozhidaniya
       OR v_dialog_after_confirm.ozhidaetsya_otvet
       OR v_dialog_after_confirm.t0 IS NOT NULL
       OR v_dialog_after_confirm.etap IS DISTINCT FROM v_stage_before
       OR v_reminder_count <> 0
       OR v_goal_count <> 0
       OR v_stage_event_count <> 0
       OR v_bot_mirror_count <> 1
       OR v_bot_mirror_effects_applied THEN
        RAISE EXCEPTION
            'DB-03V late-confirm invariant failed: result=%, dialog=%, action=%, message=%, reminders=%, goals=%, stage_events=%, mirror_count=%, mirror_effects_applied=%',
            row_to_json(v_late_confirm),
            row_to_json(v_dialog_after_confirm),
            row_to_json(v_action_after_confirm),
            row_to_json(v_message_after_confirm),
            v_reminder_count,
            v_goal_count,
            v_stage_event_count,
            v_bot_mirror_count,
            v_bot_mirror_effects_applied;
    END IF;

    -- Take must also have canceled the original processing job from ingress.
    IF EXISTS (
        SELECT 1
          FROM qbit_test.zadaniya_obrabotki AS j
         WHERE j.dialog_id = v_ingress.dialog_id
           AND j.status IN ('ozhidaet', 'povtor', 'v_rabote')
    ) THEN
        RAISE EXCEPTION
            'DB-03V Take left active internal processing job';
    END IF;
END
$db03v$;

ROLLBACK TO SAVEPOINT db03v_probe;
RELEASE SAVEPOINT db03v_probe;

-- ===========================================================================
-- 2. CLEANUP / NON-PERSISTENCE ASSERTIONS
-- ===========================================================================

DO $db03v$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM qbit_test.menedzhery_telegram AS m
         WHERE m.telegram_user_id = 'db03v_manager'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_test.sobytiya_integraciy AS e
         WHERE e.akkaunt_istochnika_id IN (
            'db03v_client_bot',
            'db03v_service_bot'
         )
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_test.identifikatory_kanalov AS i
         WHERE i.akkaunt_kanala_id = 'db03v_client_bot'
    )
    OR EXISTS (
        SELECT 1
          FROM qbit_test.ishodyashchie_deystviya AS a
         WHERE a.klyuch_povtora = 'db03v_bot_action'
    ) THEN
        RAISE EXCEPTION
            'DB-03V probe rows remain after SAVEPOINT rollback';
    END IF;
END
$db03v$;

RESET ROLE;

COMMIT;

-- ===========================================================================
-- 3. SINGLE RESULT SET FOR SUPABASE STUDIO
-- ===========================================================================

SELECT jsonb_build_object(
    'db03v_status', 'verified',
    'database', current_database(),
    'schema', 'qbit_test',
    'late_confirm_fact_preserved', true,
    'human_owner_preserved', true,
    'stale_effects_suppressed', true,
    'wait_t0_reminders_not_restored', true,
    'stage_goal_not_applied', true,
    'bot_mirror_marks_effects_false', true,
    'probe_rows_remaining', 0,
    'production_untouched', true,
    'parent_db03_ready_to_close', true,
    'result',
    'DB-03V VERIFIED: bot action v_rabote -> operator Take -> late confirmed preserves external send fact while human owner/version remain current and stale stage/goal/wait/t0/reminders stay suppressed; probe data rolled back; production untouched.'
) AS db03v_result;
