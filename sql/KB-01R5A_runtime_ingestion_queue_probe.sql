-- KB-01R5A runtime probe v0.1
-- RUN ONLY from an n8n Postgres node using Credential: qbit_test_sluzhebnyy.
-- DO NOT run as postgres/Supabase SQL Editor: the purpose is to prove the real runtime credential.
-- Synthetic data only. The final KB-01R5A_PASS is an intentional exception that rolls back
-- the whole DO statement, so no test service event/upload/job remains persisted.
-- No embeddings, version preparation, fragments, publish, client RAG or production access.

DO $kb01r5a$
DECLARE
    v_suffix text := pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
    v_external_event text := 'kb01r5a-event-' || v_suffix;
    v_idem text := 'kb01r5a-idem-' || v_suffix;
    v_trace text := 'kb01r5a-trace-' || v_suffix;
    v_file_id text := 'kb01r5a-file-' || v_suffix;
    v_payload jsonb := pg_catalog.jsonb_build_object(
        'probe', 'KB-01R5A',
        'synthetic', true,
        'suffix', v_suffix
    );
    v_bytes bytea := pg_catalog.convert_to(
        '# KB-01R5A synthetic' || E'\n\n' || 'runtime ingestion and queue probe' || E'\n',
        'UTF8'
    );
    v_bytes_changed bytea := pg_catalog.convert_to(
        '# KB-01R5A synthetic' || E'\n\n' || 'CHANGED runtime ingestion and queue probe' || E'\n',
        'UTF8'
    );
    v_upload_json jsonb;
    r_event record;
    r_event_dup record;
    r_upload record;
    r_upload_dup record;
    r_upload_conflict record;
    r_claim1 record;
    r_heartbeat1 record;
    r_stale_heartbeat record;
    r_retry record;
    r_claim2 record;
    r_stale_finish record;
    r_finish2 record;
    r_empty record;
BEGIN
    -- 1. Durable service event through the real service API.
    SELECT * INTO r_event
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        pg_catalog.jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'kb01r5a-event-create-' || v_suffix,
            'akkaunt_istochnika_id', 'kb01r5a_test_account',
            'vneshnee_sobytie_id', v_external_event,
            'tip_sobytiya', 'document',
            'klyuch_idempotentnosti', v_idem,
            'hash_soderzhaniya', 'synthetic-' || v_suffix,
            'payload_ishodnyy', v_payload,
            'vremya_priema', pg_catalog.clock_timestamp(),
            'trassirovka_id', v_trace
        )
    );

    IF r_event.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_event.sobytie_id IS NULL THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=service_event_create result=% code=%',
            r_event.rezultat, r_event.kod_oshibki;
    END IF;

    -- Service-event idempotency itself must also work.
    SELECT * INTO r_event_dup
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        pg_catalog.jsonb_build_object(
            'versiya_formata', 1,
            'operaciya_id', 'kb01r5a-event-duplicate-' || v_suffix,
            'akkaunt_istochnika_id', 'kb01r5a_test_account',
            'vneshnee_sobytie_id', v_external_event,
            'tip_sobytiya', 'document',
            'klyuch_idempotentnosti', v_idem,
            'hash_soderzhaniya', 'synthetic-' || v_suffix,
            'payload_ishodnyy', v_payload,
            'vremya_priema', pg_catalog.clock_timestamp(),
            'trassirovka_id', v_trace
        )
    );

    IF r_event_dup.rezultat IS DISTINCT FROM 'dublikat'
       OR r_event_dup.sobytie_id IS DISTINCT FROM r_event.sobytie_id THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=service_event_duplicate result=% code=%',
            r_event_dup.rezultat, r_event_dup.kod_oshibki;
    END IF;

    v_upload_json := pg_catalog.jsonb_build_object(
        'operaciya_id', 'kb01r5a-upload-' || v_suffix,
        'sobytie_integracii_id', r_event.sobytie_id,
        'vneshnee_sobytie_id', v_external_event,
        'otpravitel_user_id', 'kb01r5a_user',
        'chat_id', 'kb01r5a_chat',
        'vneshniy_file_id', v_file_id,
        'imya_fayla', 'kb01r5a_test.md',
        'prioritet', 0,
        'vremya_priema', pg_catalog.clock_timestamp()
    );

    -- 2. First knowledge upload.
    SELECT * INTO r_upload
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        v_upload_json,
        v_bytes
    );

    IF r_upload.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_upload.zagruzka_id IS NULL
       OR r_upload.zadanie_id IS NULL
       OR r_upload.status_zagruzki IS DISTINCT FROM 'poluchena' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=upload_create result=% code=% status=%',
            r_upload.rezultat, r_upload.kod_oshibki, r_upload.status_zagruzki;
    END IF;

    -- 3. Same service event + same bytes/metadata => duplicate with same IDs.
    SELECT * INTO r_upload_dup
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        v_upload_json || pg_catalog.jsonb_build_object('operaciya_id', 'kb01r5a-upload-duplicate-' || v_suffix),
        v_bytes
    );

    IF r_upload_dup.rezultat IS DISTINCT FROM 'dublikat'
       OR r_upload_dup.zagruzka_id IS DISTINCT FROM r_upload.zagruzka_id
       OR r_upload_dup.zadanie_id IS DISTINCT FROM r_upload.zadanie_id THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=upload_duplicate result=% code=%',
            r_upload_dup.rezultat, r_upload_dup.kod_oshibki;
    END IF;

    -- 4. Same service event + changed bytes => conflict.
    SELECT * INTO r_upload_conflict
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        v_upload_json || pg_catalog.jsonb_build_object('operaciya_id', 'kb01r5a-upload-conflict-' || v_suffix),
        v_bytes_changed
    );

    IF r_upload_conflict.rezultat IS DISTINCT FROM 'konflikt'
       OR r_upload_conflict.kod_oshibki IS DISTINCT FROM 'povtor_s_drugim_soderzhaniem' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=upload_conflict result=% code=%',
            r_upload_conflict.rezultat, r_upload_conflict.kod_oshibki;
    END IF;

    -- 5. Claim by worker 1.
    SELECT * INTO r_claim1
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-claim1-' || v_suffix,
            'worker_id', 'kb01r5a_worker_1',
            'arenda_sekund', 10
        )
    );

    IF r_claim1.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_claim1.zadanie_id IS DISTINCT FROM r_upload.zadanie_id
       OR r_claim1.zagruzka_id IS DISTINCT FROM r_upload.zagruzka_id
       OR r_claim1.status_zadaniya IS DISTINCT FROM 'v_rabote'
       OR r_claim1.popytki IS DISTINCT FROM 1
       OR r_claim1.nomer_vladeniya IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=claim1 result=% attempts=% fence=%',
            r_claim1.rezultat, r_claim1.popytki, r_claim1.nomer_vladeniya;
    END IF;

    -- 6. Valid heartbeat keeps the same fencing number.
    SELECT * INTO r_heartbeat1
    FROM qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-heartbeat1-' || v_suffix,
            'zadanie_id', r_claim1.zadanie_id,
            'worker_id', 'kb01r5a_worker_1',
            'nomer_vladeniya', r_claim1.nomer_vladeniya,
            'arenda_sekund', 10
        )
    );

    IF r_heartbeat1.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_heartbeat1.nomer_vladeniya IS DISTINCT FROM r_claim1.nomer_vladeniya THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=heartbeat1 result=% code=% fence=%',
            r_heartbeat1.rezultat, r_heartbeat1.kod_oshibki, r_heartbeat1.nomer_vladeniya;
    END IF;

    -- 7. Wrong worker with the same fencing number must be stale.
    SELECT * INTO r_stale_heartbeat
    FROM qbit_bot_pervichnogo_obrascheniya.prodlit_arendu_zadaniya_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-stale-heartbeat-' || v_suffix,
            'zadanie_id', r_claim1.zadanie_id,
            'worker_id', 'kb01r5a_worker_stale',
            'nomer_vladeniya', r_claim1.nomer_vladeniya,
            'arenda_sekund', 10
        )
    );

    IF r_stale_heartbeat.rezultat IS DISTINCT FROM 'konflikt'
       OR r_stale_heartbeat.kod_oshibki IS DISTINCT FROM 'stale_lease' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=stale_heartbeat result=% code=%',
            r_stale_heartbeat.rezultat, r_stale_heartbeat.kod_oshibki;
    END IF;

    -- 8. Worker 1 schedules a very short retry.
    SELECT * INTO r_retry
    FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-retry-' || v_suffix,
            'zadanie_id', r_claim1.zadanie_id,
            'worker_id', 'kb01r5a_worker_1',
            'nomer_vladeniya', r_claim1.nomer_vladeniya,
            'status', 'povtor',
            'sleduyushchiy_zapusk', pg_catalog.clock_timestamp() + interval '150 milliseconds',
            'kod_oshibki', 'synthetic_retry',
            'opisanie_oshibki', 'KB-01R5A synthetic retry'
        )
    );

    IF r_retry.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_retry.status_zadaniya IS DISTINCT FROM 'povtor' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=retry result=% code=% status=%',
            r_retry.rezultat, r_retry.kod_oshibki, r_retry.status_zadaniya;
    END IF;

    PERFORM pg_catalog.pg_sleep(0.25);

    -- 9. Worker 2 reclaims the same job; fencing must advance.
    SELECT * INTO r_claim2
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-claim2-' || v_suffix,
            'worker_id', 'kb01r5a_worker_2',
            'arenda_sekund', 10
        )
    );

    IF r_claim2.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_claim2.zadanie_id IS DISTINCT FROM r_claim1.zadanie_id
       OR r_claim2.popytki IS DISTINCT FROM 2
       OR r_claim2.nomer_vladeniya IS DISTINCT FROM (r_claim1.nomer_vladeniya + 1) THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=claim2 result=% attempts=% fence1=% fence2=%',
            r_claim2.rezultat, r_claim2.popytki, r_claim1.nomer_vladeniya, r_claim2.nomer_vladeniya;
    END IF;

    -- 10. Old worker/fence can no longer finish the reclaimed job.
    SELECT * INTO r_stale_finish
    FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-stale-finish-' || v_suffix,
            'zadanie_id', r_claim1.zadanie_id,
            'worker_id', 'kb01r5a_worker_1',
            'nomer_vladeniya', r_claim1.nomer_vladeniya,
            'status', 'zaversheno'
        )
    );

    IF r_stale_finish.rezultat IS DISTINCT FROM 'konflikt'
       OR r_stale_finish.kod_oshibki IS DISTINCT FROM 'stale_lease' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=stale_finish result=% code=%',
            r_stale_finish.rezultat, r_stale_finish.kod_oshibki;
    END IF;

    -- 11. Current worker finishes successfully.
    SELECT * INTO r_finish2
    FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-finish2-' || v_suffix,
            'zadanie_id', r_claim2.zadanie_id,
            'worker_id', 'kb01r5a_worker_2',
            'nomer_vladeniya', r_claim2.nomer_vladeniya,
            'status', 'zaversheno'
        )
    );

    IF r_finish2.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_finish2.status_zadaniya IS DISTINCT FROM 'zaversheno' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=finish2 result=% code=% status=%',
            r_finish2.rezultat, r_finish2.kod_oshibki, r_finish2.status_zadaniya;
    END IF;

    -- 12. Queue must now be empty for this rolled-back synthetic scenario.
    SELECT * INTO r_empty
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id', 'kb01r5a-empty-' || v_suffix,
            'worker_id', 'kb01r5a_worker_3',
            'arenda_sekund', 10
        )
    );

    IF r_empty.rezultat IS DISTINCT FROM 'net_zadaniya' THEN
        RAISE EXCEPTION 'KB-01R5A_FAIL step=queue_empty result=% code=% job=%',
            r_empty.rezultat, r_empty.kod_oshibki, r_empty.zadanie_id;
    END IF;

    -- INTENTIONAL: this exception is the PASS marker AND guarantees rollback of all
    -- synthetic rows created above. n8n should report this as an error text.
    RAISE EXCEPTION
        'KB-01R5A_PASS event=% upload=% job=% attempts=2 fence1=% fence2=% rollback=guaranteed',
        r_event.sobytie_id,
        r_upload.zagruzka_id,
        r_upload.zadanie_id,
        r_claim1.nomer_vladeniya,
        r_claim2.nomer_vladeniya;
END
$kb01r5a$;
