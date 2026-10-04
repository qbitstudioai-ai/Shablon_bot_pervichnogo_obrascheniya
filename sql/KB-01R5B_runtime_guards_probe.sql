-- KB-01R5B guards probe v0.1
-- RUN ONLY from n8n Postgres node using Credential: qbit_test_sluzhebnyy.
-- REQUIRES: KB-01R5B_PATCH_v0.1 applied.
-- Synthetic data only. Final KB-01R5B_GUARDS_PASS is intentional and rolls back everything.
-- Tests negative guards only; no publish, client RAG or production access.

DO $kb01r5b_guards$
DECLARE
    v_suffix text := pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
    v_vec1024 jsonb;
    v_bad_hash_seen boolean := false;
    v_bad_dim_seen boolean := false;
    v_bad_tokens_seen boolean := false;
    v_active_search_denied boolean := false;
    v_profile_fp text := pg_catalog.repeat('d',64);
    v_text text := 'KB-01R5B guard fragment';
    v_hash text := '12621089387f5071525a59cb9db45fae195ad4d67ce1ea6620c77a08d2f06397';
    r_event1 record;
    r_upload1 record;
    r_claim1 record;
    r_version1 record;
    r_event2 record;
    r_upload2 record;
    r_claim2 record;
    r_profile_conflict record;
BEGIN
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=1 THEN 1.0 ELSE 0.0 END ORDER BY i)
      INTO v_vec1024
      FROM pg_catalog.generate_series(1,1024) AS g(i);

    -- First synthetic upload/job/version creates the profile used by guard tests.
    SELECT * INTO r_event1
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        pg_catalog.jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','kb01r5b-g-event1-'||v_suffix,
            'akkaunt_istochnika_id','kb01r5b_guard_account',
            'vneshnee_sobytie_id','kb01r5b-g-event1-'||v_suffix,
            'tip_sobytiya','document',
            'klyuch_idempotentnosti','kb01r5b-g-idem1-'||v_suffix,
            'hash_soderzhaniya','synthetic-guard-1-'||v_suffix,
            'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5B_GUARDS','n',1),
            'vremya_priema',pg_catalog.clock_timestamp(),
            'trassirovka_id','kb01r5b-g-trace1-'||v_suffix
        )
    );
    IF r_event1.rezultat IS DISTINCT FROM 'uspeshno' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=event1 result=% code=%',r_event1.rezultat,r_event1.kod_oshibki;
    END IF;

    SELECT * INTO r_upload1
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-upload1-'||v_suffix,
            'sobytie_integracii_id',r_event1.sobytie_id,
            'vneshnee_sobytie_id','kb01r5b-g-event1-'||v_suffix,
            'otpravitel_user_id','kb01r5b_guard_user',
            'chat_id','kb01r5b_guard_chat',
            'vneshniy_file_id','kb01r5b-g-file1-'||v_suffix,
            'imya_fayla','kb01r5b_guard_1.md',
            'vremya_priema',pg_catalog.clock_timestamp()
        ),
        pg_catalog.convert_to('# guard 1','UTF8')
    );
    IF r_upload1.rezultat IS DISTINCT FROM 'uspeshno' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=upload1 result=% code=%',r_upload1.rezultat,r_upload1.kod_oshibki;
    END IF;

    SELECT * INTO r_claim1
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-claim1-'||v_suffix,
            'worker_id','kb01r5b_guard_worker_1',
            'arenda_sekund',60
        )
    );
    IF r_claim1.rezultat IS DISTINCT FROM 'uspeshno' OR r_claim1.zadanie_id IS DISTINCT FROM r_upload1.zadanie_id THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=claim1 result=% code=%',r_claim1.rezultat,r_claim1.kod_oshibki;
    END IF;

    SELECT * INTO r_version1
    FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-version1-'||v_suffix,
            'zadanie_id',r_claim1.zadanie_id,
            'worker_id','kb01r5b_guard_worker_1',
            'nomer_vladeniya',r_claim1.nomer_vladeniya,
            'identifikator_dokumenta','kb01r5b_guard_'||pg_catalog.left(v_suffix,20),
            'nazvanie','KB-01R5B guard document 1',
            'tip_dokumenta','faq',
            'hash_soderzhaniya',pg_catalog.repeat('1',64),
            'otpechatok_obrabotki',pg_catalog.repeat('2',64),
            'otpechatok_profilya',v_profile_fp,
            'embedding_model','synthetic-r5b-guard',
            'razmernost',1024,
            'versiya_parsera','guard-parser-v1',
            'versiya_ochistki','guard-clean-v1',
            'versiya_chunkinga','guard-chunk-v1',
            'tokenizer','guard-tokenizer',
            'cel_fragmenta_tokenov',20,
            'maks_fragmenta_tokenov',50,
            'overlap_tokenov',5
        )
    );
    IF r_version1.rezultat IS DISTINCT FROM 'uspeshno' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=version1 result=% code=%',r_version1.rezultat,r_version1.kod_oshibki;
    END IF;

    -- Wrong fragment hash must be rejected.
    BEGIN
        PERFORM *
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5b-g-badhash-'||v_suffix,
                'versiya_id',r_version1.versiya_id,
                'zadanie_id',r_claim1.zadanie_id,
                'worker_id','kb01r5b_guard_worker_1',
                'nomer_vladeniya',r_claim1.nomer_vladeniya,
                'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                    'nomer_fragmenta',1,
                    'put_razdela','Guard / Hash',
                    'tekst_fragmenta',v_text,
                    'kolichestvo_tokenov',5,
                    'hash_fragmenta',pg_catalog.repeat('0',64),
                    'vektor',v_vec1024
                ))
            )
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Fragment hash mismatch%' THEN v_bad_hash_seen:=true; ELSE RAISE; END IF;
    END;
    IF NOT v_bad_hash_seen THEN RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=bad_hash_not_rejected'; END IF;

    -- Wrong vector dimension must be rejected.
    BEGIN
        PERFORM *
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5b-g-baddim-'||v_suffix,
                'versiya_id',r_version1.versiya_id,
                'zadanie_id',r_claim1.zadanie_id,
                'worker_id','kb01r5b_guard_worker_1',
                'nomer_vladeniya',r_claim1.nomer_vladeniya,
                'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                    'nomer_fragmenta',1,
                    'put_razdela','Guard / Dimension',
                    'tekst_fragmenta',v_text,
                    'kolichestvo_tokenov',5,
                    'hash_fragmenta',v_hash,
                    'vektor',pg_catalog.jsonb_build_array(1.0,0.0,0.0)
                ))
            )
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Vector dimension mismatch%' THEN v_bad_dim_seen:=true; ELSE RAISE; END IF;
    END;
    IF NOT v_bad_dim_seen THEN RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=bad_dimension_not_rejected'; END IF;

    -- Token count above profile max must be rejected.
    BEGIN
        PERFORM *
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5b-g-badtokens-'||v_suffix,
                'versiya_id',r_version1.versiya_id,
                'zadanie_id',r_claim1.zadanie_id,
                'worker_id','kb01r5b_guard_worker_1',
                'nomer_vladeniya',r_claim1.nomer_vladeniya,
                'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                    'nomer_fragmenta',1,
                    'put_razdela','Guard / Tokens',
                    'tekst_fragmenta',v_text,
                    'kolichestvo_tokenov',51,
                    'hash_fragmenta',v_hash,
                    'vektor',v_vec1024
                ))
            )
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Fragment exceeds profile max tokens%' THEN v_bad_tokens_seen:=true; ELSE RAISE; END IF;
    END;
    IF NOT v_bad_tokens_seen THEN RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=bad_tokens_not_rejected'; END IF;

    -- Second upload/job reuses the same profile fingerprint with different model.
    SELECT * INTO r_event2
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        pg_catalog.jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','kb01r5b-g-event2-'||v_suffix,
            'akkaunt_istochnika_id','kb01r5b_guard_account',
            'vneshnee_sobytie_id','kb01r5b-g-event2-'||v_suffix,
            'tip_sobytiya','document',
            'klyuch_idempotentnosti','kb01r5b-g-idem2-'||v_suffix,
            'hash_soderzhaniya','synthetic-guard-2-'||v_suffix,
            'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5B_GUARDS','n',2),
            'vremya_priema',pg_catalog.clock_timestamp(),
            'trassirovka_id','kb01r5b-g-trace2-'||v_suffix
        )
    );
    IF r_event2.rezultat IS DISTINCT FROM 'uspeshno' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=event2 result=% code=%',r_event2.rezultat,r_event2.kod_oshibki;
    END IF;

    SELECT * INTO r_upload2
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-upload2-'||v_suffix,
            'sobytie_integracii_id',r_event2.sobytie_id,
            'vneshnee_sobytie_id','kb01r5b-g-event2-'||v_suffix,
            'otpravitel_user_id','kb01r5b_guard_user',
            'chat_id','kb01r5b_guard_chat',
            'vneshniy_file_id','kb01r5b-g-file2-'||v_suffix,
            'imya_fayla','kb01r5b_guard_2.md',
            'vremya_priema',pg_catalog.clock_timestamp()
        ),
        pg_catalog.convert_to('# guard 2','UTF8')
    );
    IF r_upload2.rezultat IS DISTINCT FROM 'uspeshno' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=upload2 result=% code=%',r_upload2.rezultat,r_upload2.kod_oshibki;
    END IF;

    SELECT * INTO r_claim2
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-claim2-'||v_suffix,
            'worker_id','kb01r5b_guard_worker_2',
            'arenda_sekund',60
        )
    );
    IF r_claim2.rezultat IS DISTINCT FROM 'uspeshno' OR r_claim2.zadanie_id IS DISTINCT FROM r_upload2.zadanie_id THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=claim2 result=% code=%',r_claim2.rezultat,r_claim2.kod_oshibki;
    END IF;

    SELECT * INTO r_profile_conflict
    FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-g-profile-conflict-'||v_suffix,
            'zadanie_id',r_claim2.zadanie_id,
            'worker_id','kb01r5b_guard_worker_2',
            'nomer_vladeniya',r_claim2.nomer_vladeniya,
            'identifikator_dokumenta','kb01r5b_guard2_'||pg_catalog.left(v_suffix,20),
            'nazvanie','KB-01R5B guard document 2',
            'tip_dokumenta','faq',
            'hash_soderzhaniya',pg_catalog.repeat('3',64),
            'otpechatok_obrabotki',pg_catalog.repeat('4',64),
            'otpechatok_profilya',v_profile_fp,
            'embedding_model','DIFFERENT-MODEL',
            'razmernost',1024,
            'versiya_parsera','guard-parser-v1',
            'versiya_ochistki','guard-clean-v1',
            'versiya_chunkinga','guard-chunk-v1',
            'tokenizer','guard-tokenizer',
            'cel_fragmenta_tokenov',20,
            'maks_fragmenta_tokenov',50,
            'overlap_tokenov',5
        )
    );
    IF r_profile_conflict.rezultat IS DISTINCT FROM 'konflikt'
       OR r_profile_conflict.kod_oshibki IS DISTINCT FROM 'profil_ne_sovpadaet' THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=profile_fingerprint result=% code=%',r_profile_conflict.rezultat,r_profile_conflict.kod_oshibki;
    END IF;

    -- Actual service credential must not be allowed to call client active RAG API.
    BEGIN
        PERFORM * FROM qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5b-g-active-search-'||v_suffix,
                'profil_indeksa_id',r_version1.profil_indeksa_id,
                'limit',1,
                'porog_shodstva',0,
                'vektor',v_vec1024
            )
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_active_search_denied:=true;
    END;
    IF NOT v_active_search_denied THEN
        RAISE EXCEPTION 'KB-01R5B_GUARDS_FAIL step=service_active_search_was_allowed';
    END IF;

    RAISE EXCEPTION
        'KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed';
END
$kb01r5b_guards$;
