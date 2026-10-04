-- KB-01R5B runtime probe v0.1
-- RUN ONLY from an n8n Postgres node using Credential: qbit_test_sluzhebnyy.
-- REQUIRES: KB-01R5B_PATCH_v0.1 applied in test Supabase first.
-- Synthetic vectors only; this does NOT prove OpenAI embedding behavior (PRE-02E remains separate).
-- The final KB-01R5B_PASS is an intentional exception and rolls back all synthetic rows.
-- No publish, active RAG, admin revoke or production access.

DO $kb01r5b$
DECLARE
    v_suffix text := pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
    v_external_event text := 'kb01r5b-event-' || v_suffix;
    v_idem text := 'kb01r5b-idem-' || v_suffix;
    v_file_id text := 'kb01r5b-file-' || v_suffix;
    v_doc_ident text := 'kb01r5b_' || pg_catalog.left(v_suffix, 24);
    v_payload jsonb := pg_catalog.jsonb_build_object('probe','KB-01R5B','synthetic',true,'suffix',v_suffix);
    v_bytes bytea := pg_catalog.convert_to('# KB-01R5B synthetic' || E'\n\n' || 'draft knowledge probe' || E'\n','UTF8');
    v_vec1 jsonb;
    v_vec2 jsonb;
    v_fragments jsonb;
    v_checks jsonb;
    r_event record;
    r_upload record;
    r_claim record;
    r_version record;
    r_frag record;
    r_frag_dup record;
    r_search record;
    r_questions record;
    r_checks record;
    r_search_ready record;
BEGIN
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=1 THEN 1.0 ELSE 0.0 END ORDER BY i)
      INTO v_vec1
      FROM pg_catalog.generate_series(1,1024) AS g(i);
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=2 THEN 1.0 ELSE 0.0 END ORDER BY i)
      INTO v_vec2
      FROM pg_catalog.generate_series(1,1024) AS g(i);

    -- 1. Durable synthetic service event.
    SELECT * INTO r_event
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
        pg_catalog.jsonb_build_object(
            'versiya_formata',1,
            'operaciya_id','kb01r5b-event-'||v_suffix,
            'akkaunt_istochnika_id','kb01r5b_test_account',
            'vneshnee_sobytie_id',v_external_event,
            'tip_sobytiya','document',
            'klyuch_idempotentnosti',v_idem,
            'hash_soderzhaniya','synthetic-'||v_suffix,
            'payload_ishodnyy',v_payload,
            'vremya_priema',pg_catalog.clock_timestamp(),
            'trassirovka_id','kb01r5b-trace-'||v_suffix
        )
    );
    IF r_event.rezultat IS DISTINCT FROM 'uspeshno' OR r_event.sobytie_id IS NULL THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=service_event result=% code=%',r_event.rezultat,r_event.kod_oshibki;
    END IF;

    -- 2. Register upload and claim its durable knowledge job.
    SELECT * INTO r_upload
    FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-upload-'||v_suffix,
            'sobytie_integracii_id',r_event.sobytie_id,
            'vneshnee_sobytie_id',v_external_event,
            'otpravitel_user_id','kb01r5b_user',
            'chat_id','kb01r5b_chat',
            'vneshniy_file_id',v_file_id,
            'imya_fayla','kb01r5b_test.md',
            'prioritet',0,
            'vremya_priema',pg_catalog.clock_timestamp()
        ),
        v_bytes
    );
    IF r_upload.rezultat IS DISTINCT FROM 'uspeshno' OR r_upload.zadanie_id IS NULL THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=upload result=% code=%',r_upload.rezultat,r_upload.kod_oshibki;
    END IF;

    SELECT * INTO r_claim
    FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-claim-'||v_suffix,
            'worker_id','kb01r5b_worker',
            'arenda_sekund',60
        )
    );
    IF r_claim.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_claim.zadanie_id IS DISTINCT FROM r_upload.zadanie_id
       OR r_claim.nomer_vladeniya IS NULL THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=claim result=% code=%',r_claim.rezultat,r_claim.kod_oshibki;
    END IF;

    -- 3. Prepare logical document/version and immutable index profile.
    SELECT * INTO r_version
    FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-version-'||v_suffix,
            'zadanie_id',r_claim.zadanie_id,
            'worker_id','kb01r5b_worker',
            'nomer_vladeniya',r_claim.nomer_vladeniya,
            'identifikator_dokumenta',v_doc_ident,
            'nazvanie','KB-01R5B synthetic document',
            'tip_dokumenta','faq',
            'versiya_istochnika','synthetic-v1',
            'hash_soderzhaniya',pg_catalog.repeat('a',64),
            'otpechatok_obrabotki',pg_catalog.repeat('b',64),
            'otpechatok_profilya',pg_catalog.repeat('c',64),
            'embedding_model','synthetic-r5b',
            'razmernost',1024,
            'versiya_parsera','r5b-parser-v1',
            'versiya_ochistki','r5b-clean-v1',
            'versiya_chunkinga','r5b-chunk-v1',
            'tokenizer','synthetic-tokenizer',
            'cel_fragmenta_tokenov',20,
            'maks_fragmenta_tokenov',50,
            'overlap_tokenov',5
        )
    );
    IF r_version.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_version.versiya_id IS NULL
       OR r_version.profil_indeksa_id IS NULL
       OR r_version.status_versii IS DISTINCT FROM 'chernovik'
       OR r_version.nomer_versii IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=prepare_version result=% code=% status=% number=%',
            r_version.rezultat,r_version.kod_oshibki,r_version.status_versii,r_version.nomer_versii;
    END IF;

    -- 4. Save two fragments with deterministic synthetic vectors.
    v_fragments := pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
            'nomer_fragmenta',1,
            'put_razdela','FAQ / Alpha',
            'tekst_fragmenta','KB-01R5B fragment alpha',
            'kolichestvo_tokenov',5,
            'hash_fragmenta','5be48e7eaef311107e7fb4b7d16e4f24187b9af23dc6b9f435191a9bd70ebde7',
            'vektor',v_vec1
        ),
        pg_catalog.jsonb_build_object(
            'nomer_fragmenta',2,
            'put_razdela','FAQ / Beta',
            'tekst_fragmenta','KB-01R5B fragment beta',
            'kolichestvo_tokenov',5,
            'hash_fragmenta','57a78cef72695090dc520414688d8e54965435a24158dd6494603a0926b3bbe4',
            'vektor',v_vec2
        )
    );

    SELECT * INTO r_frag
    FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-fragments-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'zadanie_id',r_claim.zadanie_id,
            'worker_id','kb01r5b_worker',
            'nomer_vladeniya',r_claim.nomer_vladeniya,
            'fragmenty',v_fragments
        )
    );
    IF r_frag.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_frag.sohraneno_fragmentov IS DISTINCT FROM 2
       OR r_frag.vsego_fragmentov IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=fragments result=% saved=% total=%',
            r_frag.rezultat,r_frag.sohraneno_fragmentov,r_frag.vsego_fragmentov;
    END IF;

    -- Idempotent repeat of the same batch must not create duplicates.
    SELECT * INTO r_frag_dup
    FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-fragments-dup-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'zadanie_id',r_claim.zadanie_id,
            'worker_id','kb01r5b_worker',
            'nomer_vladeniya',r_claim.nomer_vladeniya,
            'fragmenty',v_fragments
        )
    );
    IF r_frag_dup.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_frag_dup.sohraneno_fragmentov IS DISTINCT FROM 0
       OR r_frag_dup.vsego_fragmentov IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=fragment_idempotency result=% saved=% total=%',
            r_frag_dup.rezultat,r_frag_dup.sohraneno_fragmentov,r_frag_dup.vsego_fragmentov;
    END IF;

    -- 5. Draft-only vector search: vec1 must select fragment 1 with cosine similarity 1.
    SELECT * INTO r_search
    FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-search-draft-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'profil_indeksa_id',r_version.profil_indeksa_id,
            'limit',2,
            'porog_shodstva',0.99,
            'vektor',v_vec1
        )
    );
    IF r_search.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_search.fragment_id IS NULL
       OR r_search.nomer_fragmenta IS DISTINCT FROM 1
       OR r_search.tekst_fragmenta IS DISTINCT FROM 'KB-01R5B fragment alpha'
       OR r_search.shodstvo < 0.999 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=draft_search result=% fragment=% number=% similarity=%',
            r_search.rezultat,r_search.fragment_id,r_search.nomer_fragmenta,r_search.shodstvo;
    END IF;

    -- 6. Store the required 3 reference questions. Their internal UUIDs remain hidden.
    SELECT * INTO r_questions
    FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-questions-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'voprosy',pg_catalog.jsonb_build_array(
                pg_catalog.jsonb_build_object('vopros','Alpha?','ozhidaemyy_razdel','FAQ / Alpha','ozhidaemyy_fakt','alpha','istochnik','synthetic'),
                pg_catalog.jsonb_build_object('vopros','Alpha again?','ozhidaemyy_razdel','FAQ / Alpha','ozhidaemyy_fakt','alpha','istochnik','synthetic'),
                pg_catalog.jsonb_build_object('vopros','Alpha third?','ozhidaemyy_razdel','FAQ / Alpha','ozhidaemyy_fakt','alpha','istochnik','synthetic')
            )
        )
    );
    IF r_questions.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_questions.kolichestvo_voprosov IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=questions result=% count=%',
            r_questions.rezultat,r_questions.kolichestvo_voprosov;
    END IF;

    -- 7. Persist actual check results by stable question number, not hidden internal UUID.
    v_checks := pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
            'nomer_voprosa',1,'porog_shodstva',0.99,'limit_rezultatov',1,
            'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),
            'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno','opisanie','synthetic pass 1'
        ),
        pg_catalog.jsonb_build_object(
            'nomer_voprosa',2,'porog_shodstva',0.99,'limit_rezultatov',1,
            'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),
            'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno','opisanie','synthetic pass 2'
        ),
        pg_catalog.jsonb_build_object(
            'nomer_voprosa',3,'porog_shodstva',0.99,'limit_rezultatov',1,
            'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),
            'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno','opisanie','synthetic pass 3'
        )
    );

    SELECT * INTO r_checks
    FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-checks-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'profil_indeksa_id',r_version.profil_indeksa_id,
            'proverki',v_checks
        )
    );
    IF r_checks.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_checks.status_versii IS DISTINCT FROM 'gotova'
       OR r_checks.uspeshnyh IS DISTINCT FROM 3
       OR r_checks.vsego IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=checks result=% status=% ok=% total=% code=%',
            r_checks.rezultat,r_checks.status_versii,r_checks.uspeshnyh,r_checks.vsego,r_checks.kod_oshibki;
    END IF;

    -- Draft search remains explicitly version-scoped for a ready-but-unpublished version.
    SELECT * INTO r_search_ready
    FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5b-search-ready-'||v_suffix,
            'versiya_id',r_version.versiya_id,
            'profil_indeksa_id',r_version.profil_indeksa_id,
            'limit',1,
            'porog_shodstva',0.99,
            'vektor',v_vec1
        )
    );
    IF r_search_ready.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_search_ready.fragment_id IS DISTINCT FROM r_search.fragment_id
       OR r_search_ready.shodstvo < 0.999 THEN
        RAISE EXCEPTION 'KB-01R5B_FAIL step=ready_draft_search result=% fragment=% similarity=%',
            r_search_ready.rezultat,r_search_ready.fragment_id,r_search_ready.shodstvo;
    END IF;

    -- INTENTIONAL PASS marker: guarantees transaction rollback of all synthetic R5B rows.
    RAISE EXCEPTION
        'KB-01R5B_PASS version=% profile=% fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed',
        r_version.versiya_id,
        r_version.profil_indeksa_id;
END
$kb01r5b$;
