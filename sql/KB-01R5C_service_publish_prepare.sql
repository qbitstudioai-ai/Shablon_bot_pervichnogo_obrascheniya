-- KB-01R5C service publish prepare v0.2
-- RUN ONLY from n8n Postgres node using Credential: qbit_test_sluzhebnyy.
-- TEST schema only. Intentionally COMMITS synthetic rows for later bot/dash_admin role probes.
-- No direct access to schema extensions; no OpenAI embedding; no production access.
-- Cleanup is mandatory after R5C and will use the IDs returned here.

ROLLBACK;
BEGIN;
SET LOCAL statement_timeout = '180s';
SET LOCAL lock_timeout = '5s';

DROP TABLE IF EXISTS pg_temp.kb01r5c_result;
CREATE TEMP TABLE kb01r5c_result(payload jsonb);

DO $kb01r5c$
DECLARE
    v_suffix text := pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-','');
    v_doc_ident text := 'kb01r5c_' || pg_catalog.left(v_suffix,24);
    v_profile_fp text := v_suffix || v_suffix;
    v_texts text[] := ARRAY[
        'KB-01R5C published version one',
        'KB-01R5C published version two',
        'KB-01R5C unpublished competing version three'
    ];
    v_hashes text[] := ARRAY[
        '0914c365fd6c1f228cc8cde539641aebaa0acba12ac22a02aa28f4eb002b1389',
        '9089febca79648dc0c5c330d1090b53a9cc0529d524e73e4e229809a2bf89f19',
        'c53d14320167e7113cc3aebe528609c643731523674a02a46affbd305bb40b86'
    ];
    v_event_ids uuid[] := ARRAY[]::uuid[];
    v_upload_ids uuid[] := ARRAY[]::uuid[];
    v_job_ids uuid[] := ARRAY[]::uuid[];
    v_version_ids uuid[] := ARRAY[]::uuid[];
    v_profile_id uuid;
    v_document_id uuid;
    v_vec jsonb;
    v_checks jsonb;
    n integer;
    r_event record;
    r_upload record;
    r_claim record;
    r_ver record;
    r_frag record;
    r_search record;
    r_questions record;
    r_checks record;
    r_finish record;
    r_pub1 record;
    r_pub2 record;
    r_pub3 record;
BEGIN
    FOR n IN 1..3 LOOP
        SELECT pg_catalog.jsonb_agg(CASE WHEN i=n THEN 1.0 ELSE 0.0 END ORDER BY i)
          INTO v_vec
          FROM pg_catalog.generate_series(1,1024) g(i);

        SELECT * INTO r_event
        FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
            pg_catalog.jsonb_build_object(
                'versiya_formata',1,
                'operaciya_id','kb01r5c-e'||n||'-'||v_suffix,
                'akkaunt_istochnika_id','kb01r5c_test_account',
                'vneshnee_sobytie_id','kb01r5c-event'||n||'-'||v_suffix,
                'tip_sobytiya','document',
                'klyuch_idempotentnosti','kb01r5c-idem'||n||'-'||v_suffix,
                'hash_soderzhaniya','synthetic-r5c-'||n||'-'||v_suffix,
                'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5C','version',n),
                'vremya_priema',pg_catalog.clock_timestamp(),
                'trassirovka_id','kb01r5c-trace'||n||'-'||v_suffix
            )
        );
        IF r_event.rezultat IS DISTINCT FROM 'uspeshno' OR r_event.sobytie_id IS NULL THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL event n=% result=% code=%',n,r_event.rezultat,r_event.kod_oshibki;
        END IF;

        SELECT * INTO r_upload
        FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-u'||n||'-'||v_suffix,
                'sobytie_integracii_id',r_event.sobytie_id,
                'vneshnee_sobytie_id','kb01r5c-event'||n||'-'||v_suffix,
                'otpravitel_user_id','kb01r5c_user',
                'chat_id','kb01r5c_chat',
                'vneshniy_file_id','kb01r5c-file'||n||'-'||v_suffix,
                'imya_fayla','kb01r5c_v'||n||'.md',
                'prioritet',2147483647,
                'vremya_priema',pg_catalog.clock_timestamp()
            ),
            pg_catalog.convert_to('# KB-01R5C v'||n,'UTF8')
        );
        IF r_upload.rezultat IS DISTINCT FROM 'uspeshno' OR r_upload.zadanie_id IS NULL THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL upload n=% result=% code=%',n,r_upload.rezultat,r_upload.kod_oshibki;
        END IF;

        SELECT * INTO r_claim
        FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-c'||n||'-'||v_suffix,
                'worker_id','kb01r5c_worker_'||n,
                'arenda_sekund',120
            )
        );
        IF r_claim.rezultat IS DISTINCT FROM 'uspeshno'
           OR r_claim.zadanie_id IS DISTINCT FROM r_upload.zadanie_id THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL claim n=% result=% job=% expected=%',
                n,r_claim.rezultat,r_claim.zadanie_id,r_upload.zadanie_id;
        END IF;

        SELECT * INTO r_ver
        FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-v'||n||'-'||v_suffix,
                'zadanie_id',r_claim.zadanie_id,
                'worker_id','kb01r5c_worker_'||n,
                'nomer_vladeniya',r_claim.nomer_vladeniya,
                'identifikator_dokumenta',v_doc_ident,
                'nazvanie','KB-01R5C synthetic',
                'tip_dokumenta','faq',
                'versiya_istochnika','r5c-v'||n,
                'hash_soderzhaniya',pg_catalog.repeat(n::text,32)||v_suffix,
                'otpechatok_obrabotki',pg_catalog.repeat(substr('abc',n,1),32)||v_suffix,
                'otpechatok_profilya',v_profile_fp,
                'embedding_model','synthetic-r5c',
                'razmernost',1024,
                'versiya_parsera','r5c-parser',
                'versiya_ochistki','r5c-clean',
                'versiya_chunkinga','r5c-chunk',
                'tokenizer','synthetic',
                'cel_fragmenta_tokenov',20,
                'maks_fragmenta_tokenov',50,
                'overlap_tokenov',5
            )
        );
        IF r_ver.rezultat IS DISTINCT FROM 'uspeshno' OR r_ver.versiya_id IS NULL THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL prepare n=% result=% code=%',n,r_ver.rezultat,r_ver.kod_oshibki;
        END IF;
        IF n=1 AND r_ver.ozhidaemaya_aktivnaya_versiya_id IS NOT NULL THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL v1 expected active must be null';
        END IF;
        IF n>1 AND r_ver.ozhidaemaya_aktivnaya_versiya_id IS DISTINCT FROM v_version_ids[1] THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL v% expected active=% wanted=%',
                n,r_ver.ozhidaemaya_aktivnaya_versiya_id,v_version_ids[1];
        END IF;

        SELECT * INTO r_frag
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-f'||n||'-'||v_suffix,
                'versiya_id',r_ver.versiya_id,
                'zadanie_id',r_claim.zadanie_id,
                'worker_id','kb01r5c_worker_'||n,
                'nomer_vladeniya',r_claim.nomer_vladeniya,
                'fragmenty',pg_catalog.jsonb_build_array(
                    pg_catalog.jsonb_build_object(
                        'nomer_fragmenta',1,
                        'put_razdela','R5C / V'||n,
                        'tekst_fragmenta',v_texts[n],
                        'kolichestvo_tokenov',7,
                        'hash_fragmenta',v_hashes[n],
                        'vektor',v_vec
                    )
                )
            )
        );
        IF r_frag.rezultat IS DISTINCT FROM 'uspeshno' THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL fragment n=% result=%',n,r_frag.rezultat;
        END IF;

        SELECT * INTO r_search
        FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-s'||n||'-'||v_suffix,
                'versiya_id',r_ver.versiya_id,
                'profil_indeksa_id',r_ver.profil_indeksa_id,
                'limit',1,
                'porog_shodstva',0.99,
                'vektor',v_vec
            )
        );
        IF r_search.rezultat IS DISTINCT FROM 'uspeshno' OR r_search.fragment_id IS NULL THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL draft search n=%',n;
        END IF;

        SELECT * INTO r_questions
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-q'||n||'-'||v_suffix,
                'versiya_id',r_ver.versiya_id,
                'voprosy',pg_catalog.jsonb_build_array(
                    pg_catalog.jsonb_build_object('vopros','V'||n||' A?','ozhidaemyy_razdel','R5C / V'||n,'istochnik','synthetic'),
                    pg_catalog.jsonb_build_object('vopros','V'||n||' B?','ozhidaemyy_razdel','R5C / V'||n,'istochnik','synthetic'),
                    pg_catalog.jsonb_build_object('vopros','V'||n||' C?','ozhidaemyy_razdel','R5C / V'||n,'istochnik','synthetic')
                )
            )
        );
        IF r_questions.rezultat IS DISTINCT FROM 'uspeshno' OR r_questions.kolichestvo_voprosov<>3 THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL questions n=%',n;
        END IF;

        v_checks:=pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object('nomer_voprosa',1,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
            pg_catalog.jsonb_build_object('nomer_voprosa',2,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
            pg_catalog.jsonb_build_object('nomer_voprosa',3,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno')
        );
        SELECT * INTO r_checks
        FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(
            pg_catalog.jsonb_build_object(
                'operaciya_id','kb01r5c-k'||n||'-'||v_suffix,
                'versiya_id',r_ver.versiya_id,
                'profil_indeksa_id',r_ver.profil_indeksa_id,
                'proverki',v_checks
            )
        );
        IF r_checks.rezultat IS DISTINCT FROM 'uspeshno' OR r_checks.status_versii IS DISTINCT FROM 'gotova' THEN
            RAISE EXCEPTION 'KB-01R5C_FAIL checks n=% result=% status=%',n,r_checks.rezultat,r_checks.status_versii;
        END IF;

        v_event_ids:=array_append(v_event_ids,r_event.sobytie_id);
        v_upload_ids:=array_append(v_upload_ids,r_upload.zagruzka_id);
        v_job_ids:=array_append(v_job_ids,r_upload.zadanie_id);
        v_version_ids:=array_append(v_version_ids,r_ver.versiya_id);
        v_profile_id:=r_ver.profil_indeksa_id;
        v_document_id:=r_ver.dokument_id;

        IF n=1 THEN
            SELECT * INTO r_pub1
            FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(
                pg_catalog.jsonb_build_object(
                    'operaciya_id','kb01r5c-pub1-'||v_suffix,
                    'versiya_id',r_ver.versiya_id
                )
            );
            IF r_pub1.rezultat IS DISTINCT FROM 'uspeshno'
               OR r_pub1.status_versii IS DISTINCT FROM 'opublikovana'
               OR r_pub1.predydushchaya_aktivnaya_versiya_id IS NOT NULL THEN
                RAISE EXCEPTION 'KB-01R5C_FAIL publish1 result=% code=%',r_pub1.rezultat,r_pub1.kod_oshibki;
            END IF;
        ELSE
            SELECT * INTO r_finish
            FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(
                pg_catalog.jsonb_build_object(
                    'operaciya_id','kb01r5c-finish'||n||'-'||v_suffix,
                    'zadanie_id',r_claim.zadanie_id,
                    'worker_id','kb01r5c_worker_'||n,
                    'nomer_vladeniya',r_claim.nomer_vladeniya,
                    'status','zaversheno'
                )
            );
            IF r_finish.rezultat IS DISTINCT FROM 'uspeshno' THEN
                RAISE EXCEPTION 'KB-01R5C_FAIL finish n=% result=%',n,r_finish.rezultat;
            END IF;
        END IF;
    END LOOP;

    SELECT * INTO r_pub2
    FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5c-pub2-'||v_suffix,
            'versiya_id',v_version_ids[2],
            'ozhidaemaya_aktivnaya_versiya_id',v_version_ids[1]
        )
    );
    IF r_pub2.rezultat IS DISTINCT FROM 'uspeshno'
       OR r_pub2.status_versii IS DISTINCT FROM 'opublikovana'
       OR r_pub2.predydushchaya_aktivnaya_versiya_id IS DISTINCT FROM v_version_ids[1] THEN
        RAISE EXCEPTION 'KB-01R5C_FAIL publish2 result=% code=%',r_pub2.rezultat,r_pub2.kod_oshibki;
    END IF;

    SELECT * INTO r_pub3
    FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(
        pg_catalog.jsonb_build_object(
            'operaciya_id','kb01r5c-pub3-stale-'||v_suffix,
            'versiya_id',v_version_ids[3],
            'ozhidaemaya_aktivnaya_versiya_id',v_version_ids[1]
        )
    );
    IF r_pub3.rezultat IS DISTINCT FROM 'konflikt'
       OR r_pub3.kod_oshibki IS DISTINCT FROM 'stale_expected_active'
       OR r_pub3.predydushchaya_aktivnaya_versiya_id IS DISTINCT FROM v_version_ids[2] THEN
        RAISE EXCEPTION 'KB-01R5C_FAIL stale publish result=% code=% current=%',
            r_pub3.rezultat,r_pub3.kod_oshibki,r_pub3.predydushchaya_aktivnaya_versiya_id;
    END IF;

    INSERT INTO pg_temp.kb01r5c_result(payload)
    VALUES(pg_catalog.jsonb_build_object(
        'status','prepared_and_published',
        'probe','KB-01R5C_SERVICE_v0.2',
        'suffix',v_suffix,
        'document_identifier',v_doc_ident,
        'document_id',v_document_id,
        'profile_id',v_profile_id,
        'version1_id',v_version_ids[1],
        'version2_id',v_version_ids[2],
        'version3_id',v_version_ids[3],
        'event_ids',to_jsonb(v_event_ids),
        'upload_ids',to_jsonb(v_upload_ids),
        'job_ids',to_jsonb(v_job_ids),
        'active_version_id',v_version_ids[2],
        'previous_active_id',v_version_ids[1],
        'stale_candidate_id',v_version_ids[3],
        'stale_publish_result',r_pub3.rezultat,
        'stale_publish_code',r_pub3.kod_oshibki,
        'next','run qbit_test_bot active search; then qbit_test_dash_admin revoke; then cleanup'
    ));
END
$kb01r5c$;

COMMIT;
SELECT payload AS kb01r5c_service_result FROM pg_temp.kb01r5c_result;
