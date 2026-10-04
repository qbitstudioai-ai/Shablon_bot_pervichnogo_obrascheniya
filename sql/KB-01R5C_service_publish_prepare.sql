-- KB-01R5C service publish prepare v0.1
-- RUN ONLY from n8n Postgres node using Credential: qbit_test_sluzhebnyy.
-- TEST schema only. This probe intentionally COMMITS synthetic rows so qbit_test_bot and
-- qbit_test_dash_admin can verify the same published state in separate real credentials.
-- Cleanup is mandatory after all R5C role probes; use the exact IDs returned by this file.
-- No OpenAI embedding and no production access.

BEGIN;
SET LOCAL statement_timeout = '180s';
SET LOCAL lock_timeout = '5s';
DROP TABLE IF EXISTS pg_temp.kb01r5c_result;
CREATE TEMP TABLE kb01r5c_result(payload jsonb);

DO $kb01r5c$
DECLARE
    v_suffix text := pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-','');
    v_doc_ident text := 'kb01r5c_' || pg_catalog.left(v_suffix,24);
    v_profile_fp text := pg_catalog.encode(extensions.digest(pg_catalog.convert_to('kb01r5c-profile-'||v_suffix,'UTF8'),'sha256'),'hex');
    v_vec1 jsonb; v_vec2 jsonb; v_vec3 jsonb;
    v_text1 text := 'KB-01R5C published version one';
    v_text2 text := 'KB-01R5C published version two';
    v_text3 text := 'KB-01R5C unpublished competing version three';
    r_event1 record; r_upload1 record; r_claim1 record; r_ver1 record; r_frag1 record; r_search1 record; r_q1 record; r_chk1 record; r_pub1 record;
    r_event2 record; r_upload2 record; r_claim2 record; r_ver2 record; r_frag2 record; r_search2 record; r_q2 record; r_chk2 record; r_finish2 record;
    r_event3 record; r_upload3 record; r_claim3 record; r_ver3 record; r_frag3 record; r_search3 record; r_q3 record; r_chk3 record; r_finish3 record;
    r_pub2 record; r_pub3_stale record;
    v_checks jsonb;
BEGIN
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=1 THEN 1.0 ELSE 0.0 END ORDER BY i) INTO v_vec1 FROM pg_catalog.generate_series(1,1024) g(i);
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=2 THEN 1.0 ELSE 0.0 END ORDER BY i) INTO v_vec2 FROM pg_catalog.generate_series(1,1024) g(i);
    SELECT pg_catalog.jsonb_agg(CASE WHEN i=3 THEN 1.0 ELSE 0.0 END ORDER BY i) INTO v_vec3 FROM pg_catalog.generate_series(1,1024) g(i);

    -- VERSION 1: create -> ready -> publish with expected active NULL.
    SELECT * INTO r_event1 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(
      pg_catalog.jsonb_build_object('versiya_formata',1,'operaciya_id','kb01r5c-e1-'||v_suffix,'akkaunt_istochnika_id','kb01r5c_test_account','vneshnee_sobytie_id','kb01r5c-event1-'||v_suffix,'tip_sobytiya','document','klyuch_idempotentnosti','kb01r5c-idem1-'||v_suffix,'hash_soderzhaniya','synthetic-r5c-1-'||v_suffix,'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5C','version',1),'vremya_priema',pg_catalog.clock_timestamp(),'trassirovka_id','kb01r5c-trace1-'||v_suffix));
    IF r_event1.rezultat IS DISTINCT FROM 'uspeshno' THEN RAISE EXCEPTION 'KB-01R5C_FAIL e1 result=% code=%',r_event1.rezultat,r_event1.kod_oshibki; END IF;
    SELECT * INTO r_upload1 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(
      pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-u1-'||v_suffix,'sobytie_integracii_id',r_event1.sobytie_id,'vneshnee_sobytie_id','kb01r5c-event1-'||v_suffix,'otpravitel_user_id','kb01r5c_user','chat_id','kb01r5c_chat','vneshniy_file_id','kb01r5c-file1-'||v_suffix,'imya_fayla','kb01r5c_v1.md','prioritet',1000,'vremya_priema',pg_catalog.clock_timestamp()),pg_catalog.convert_to('# KB-01R5C v1','UTF8'));
    IF r_upload1.rezultat IS DISTINCT FROM 'uspeshno' THEN RAISE EXCEPTION 'KB-01R5C_FAIL u1 result=% code=%',r_upload1.rezultat,r_upload1.kod_oshibki; END IF;
    SELECT * INTO r_claim1 FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-c1-'||v_suffix,'worker_id','kb01r5c_worker_1','arenda_sekund',120));
    IF r_claim1.rezultat IS DISTINCT FROM 'uspeshno' OR r_claim1.zadanie_id IS DISTINCT FROM r_upload1.zadanie_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL c1 result=% job=% expected=%',r_claim1.rezultat,r_claim1.zadanie_id,r_upload1.zadanie_id; END IF;
    SELECT * INTO r_ver1 FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(pg_catalog.jsonb_build_object(
      'operaciya_id','kb01r5c-v1-'||v_suffix,'zadanie_id',r_claim1.zadanie_id,'worker_id','kb01r5c_worker_1','nomer_vladeniya',r_claim1.nomer_vladeniya,'identifikator_dokumenta',v_doc_ident,'nazvanie','KB-01R5C synthetic','tip_dokumenta','faq','versiya_istochnika','r5c-v1','hash_soderzhaniya',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('content1-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_obrabotki',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('proc1-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_profilya',v_profile_fp,'embedding_model','synthetic-r5c','razmernost',1024,'versiya_parsera','r5c-parser','versiya_ochistki','r5c-clean','versiya_chunkinga','r5c-chunk','tokenizer','synthetic','cel_fragmenta_tokenov',20,'maks_fragmenta_tokenov',50,'overlap_tokenov',5));
    IF r_ver1.rezultat IS DISTINCT FROM 'uspeshno' OR r_ver1.ozhidaemaya_aktivnaya_versiya_id IS NOT NULL THEN RAISE EXCEPTION 'KB-01R5C_FAIL prepare1 result=% expected_active=%',r_ver1.rezultat,r_ver1.ozhidaemaya_aktivnaya_versiya_id; END IF;
    SELECT * INTO r_frag1 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-f1-'||v_suffix,'versiya_id',r_ver1.versiya_id,'zadanie_id',r_claim1.zadanie_id,'worker_id','kb01r5c_worker_1','nomer_vladeniya',r_claim1.nomer_vladeniya,'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('nomer_fragmenta',1,'put_razdela','R5C / V1','tekst_fragmenta',v_text1,'kolichestvo_tokenov',6,'hash_fragmenta',pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_text1,'UTF8'),'sha256'),'hex'),'vektor',v_vec1))));
    IF r_frag1.rezultat IS DISTINCT FROM 'uspeshno' THEN RAISE EXCEPTION 'KB-01R5C_FAIL fragments1'; END IF;
    SELECT * INTO r_search1 FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-s1-'||v_suffix,'versiya_id',r_ver1.versiya_id,'profil_indeksa_id',r_ver1.profil_indeksa_id,'limit',1,'porog_shodstva',0.99,'vektor',v_vec1));
    IF r_search1.rezultat IS DISTINCT FROM 'uspeshno' OR r_search1.fragment_id IS NULL THEN RAISE EXCEPTION 'KB-01R5C_FAIL search1'; END IF;
    SELECT * INTO r_q1 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-q1-'||v_suffix,'versiya_id',r_ver1.versiya_id,'voprosy',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('vopros','V1?','ozhidaemyy_razdel','R5C / V1','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V1 again?','ozhidaemyy_razdel','R5C / V1','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V1 third?','ozhidaemyy_razdel','R5C / V1','istochnik','synthetic'))));
    v_checks:=pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('nomer_voprosa',1,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search1.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',2,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search1.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',3,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search1.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'));
    SELECT * INTO r_chk1 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-k1-'||v_suffix,'versiya_id',r_ver1.versiya_id,'profil_indeksa_id',r_ver1.profil_indeksa_id,'proverki',v_checks));
    IF r_chk1.status_versii IS DISTINCT FROM 'gotova' THEN RAISE EXCEPTION 'KB-01R5C_FAIL checks1 status=%',r_chk1.status_versii; END IF;
    SELECT * INTO r_pub1 FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-pub1-'||v_suffix,'versiya_id',r_ver1.versiya_id));
    IF r_pub1.rezultat IS DISTINCT FROM 'uspeshno' OR r_pub1.status_versii IS DISTINCT FROM 'opublikovana' OR r_pub1.predydushchaya_aktivnaya_versiya_id IS NOT NULL THEN RAISE EXCEPTION 'KB-01R5C_FAIL publish1 result=% code=% previous=%',r_pub1.rezultat,r_pub1.kod_oshibki,r_pub1.predydushchaya_aktivnaya_versiya_id; END IF;

    -- VERSION 2: prepare ready while V1 active, then release worker without publishing yet.
    SELECT * INTO r_event2 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(pg_catalog.jsonb_build_object('versiya_formata',1,'operaciya_id','kb01r5c-e2-'||v_suffix,'akkaunt_istochnika_id','kb01r5c_test_account','vneshnee_sobytie_id','kb01r5c-event2-'||v_suffix,'tip_sobytiya','document','klyuch_idempotentnosti','kb01r5c-idem2-'||v_suffix,'hash_soderzhaniya','synthetic-r5c-2-'||v_suffix,'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5C','version',2),'vremya_priema',pg_catalog.clock_timestamp(),'trassirovka_id','kb01r5c-trace2-'||v_suffix));
    SELECT * INTO r_upload2 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-u2-'||v_suffix,'sobytie_integracii_id',r_event2.sobytie_id,'vneshnee_sobytie_id','kb01r5c-event2-'||v_suffix,'otpravitel_user_id','kb01r5c_user','chat_id','kb01r5c_chat','vneshniy_file_id','kb01r5c-file2-'||v_suffix,'imya_fayla','kb01r5c_v2.md','prioritet',1000,'vremya_priema',pg_catalog.clock_timestamp()),pg_catalog.convert_to('# KB-01R5C v2','UTF8'));
    SELECT * INTO r_claim2 FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-c2-'||v_suffix,'worker_id','kb01r5c_worker_2','arenda_sekund',120));
    IF r_event2.rezultat IS DISTINCT FROM 'uspeshno' OR r_upload2.rezultat IS DISTINCT FROM 'uspeshno' OR r_claim2.zadanie_id IS DISTINCT FROM r_upload2.zadanie_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL setup2'; END IF;
    SELECT * INTO r_ver2 FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-v2-'||v_suffix,'zadanie_id',r_claim2.zadanie_id,'worker_id','kb01r5c_worker_2','nomer_vladeniya',r_claim2.nomer_vladeniya,'identifikator_dokumenta',v_doc_ident,'nazvanie','KB-01R5C synthetic','tip_dokumenta','faq','versiya_istochnika','r5c-v2','hash_soderzhaniya',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('content2-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_obrabotki',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('proc2-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_profilya',v_profile_fp,'embedding_model','synthetic-r5c','razmernost',1024,'versiya_parsera','r5c-parser','versiya_ochistki','r5c-clean','versiya_chunkinga','r5c-chunk','tokenizer','synthetic','cel_fragmenta_tokenov',20,'maks_fragmenta_tokenov',50,'overlap_tokenov',5));
    IF r_ver2.rezultat IS DISTINCT FROM 'uspeshno' OR r_ver2.ozhidaemaya_aktivnaya_versiya_id IS DISTINCT FROM r_ver1.versiya_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL prepare2 result=% expected=%',r_ver2.rezultat,r_ver2.ozhidaemaya_aktivnaya_versiya_id; END IF;
    SELECT * INTO r_frag2 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-f2-'||v_suffix,'versiya_id',r_ver2.versiya_id,'zadanie_id',r_claim2.zadanie_id,'worker_id','kb01r5c_worker_2','nomer_vladeniya',r_claim2.nomer_vladeniya,'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('nomer_fragmenta',1,'put_razdela','R5C / V2','tekst_fragmenta',v_text2,'kolichestvo_tokenov',6,'hash_fragmenta',pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_text2,'UTF8'),'sha256'),'hex'),'vektor',v_vec2))));
    SELECT * INTO r_search2 FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-s2-'||v_suffix,'versiya_id',r_ver2.versiya_id,'profil_indeksa_id',r_ver2.profil_indeksa_id,'limit',1,'porog_shodstva',0.99,'vektor',v_vec2));
    SELECT * INTO r_q2 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-q2-'||v_suffix,'versiya_id',r_ver2.versiya_id,'voprosy',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('vopros','V2?','ozhidaemyy_razdel','R5C / V2','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V2 again?','ozhidaemyy_razdel','R5C / V2','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V2 third?','ozhidaemyy_razdel','R5C / V2','istochnik','synthetic'))));
    v_checks:=pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('nomer_voprosa',1,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search2.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',2,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search2.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',3,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search2.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'));
    SELECT * INTO r_chk2 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-k2-'||v_suffix,'versiya_id',r_ver2.versiya_id,'profil_indeksa_id',r_ver2.profil_indeksa_id,'proverki',v_checks));
    IF r_chk2.status_versii IS DISTINCT FROM 'gotova' THEN RAISE EXCEPTION 'KB-01R5C_FAIL checks2'; END IF;
    SELECT * INTO r_finish2 FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-finish2-'||v_suffix,'zadanie_id',r_claim2.zadanie_id,'worker_id','kb01r5c_worker_2','nomer_vladeniya',r_claim2.nomer_vladeniya,'status','zaversheno'));
    IF r_finish2.rezultat IS DISTINCT FROM 'uspeshno' THEN RAISE EXCEPTION 'KB-01R5C_FAIL finish2'; END IF;

    -- VERSION 3: another ready candidate remembers the SAME expected active V1.
    SELECT * INTO r_event3 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_sluzhebnoe_sobytie(pg_catalog.jsonb_build_object('versiya_formata',1,'operaciya_id','kb01r5c-e3-'||v_suffix,'akkaunt_istochnika_id','kb01r5c_test_account','vneshnee_sobytie_id','kb01r5c-event3-'||v_suffix,'tip_sobytiya','document','klyuch_idempotentnosti','kb01r5c-idem3-'||v_suffix,'hash_soderzhaniya','synthetic-r5c-3-'||v_suffix,'payload_ishodnyy',pg_catalog.jsonb_build_object('probe','KB-01R5C','version',3),'vremya_priema',pg_catalog.clock_timestamp(),'trassirovka_id','kb01r5c-trace3-'||v_suffix));
    SELECT * INTO r_upload3 FROM qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-u3-'||v_suffix,'sobytie_integracii_id',r_event3.sobytie_id,'vneshnee_sobytie_id','kb01r5c-event3-'||v_suffix,'otpravitel_user_id','kb01r5c_user','chat_id','kb01r5c_chat','vneshniy_file_id','kb01r5c-file3-'||v_suffix,'imya_fayla','kb01r5c_v3.md','prioritet',1000,'vremya_priema',pg_catalog.clock_timestamp()),pg_catalog.convert_to('# KB-01R5C v3','UTF8'));
    SELECT * INTO r_claim3 FROM qbit_bot_pervichnogo_obrascheniya.zabrat_zadanie_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-c3-'||v_suffix,'worker_id','kb01r5c_worker_3','arenda_sekund',120));
    IF r_event3.rezultat IS DISTINCT FROM 'uspeshno' OR r_upload3.rezultat IS DISTINCT FROM 'uspeshno' OR r_claim3.zadanie_id IS DISTINCT FROM r_upload3.zadanie_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL setup3'; END IF;
    SELECT * INTO r_ver3 FROM qbit_bot_pervichnogo_obrascheniya.podgotovit_versiyu_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-v3-'||v_suffix,'zadanie_id',r_claim3.zadanie_id,'worker_id','kb01r5c_worker_3','nomer_vladeniya',r_claim3.nomer_vladeniya,'identifikator_dokumenta',v_doc_ident,'nazvanie','KB-01R5C synthetic','tip_dokumenta','faq','versiya_istochnika','r5c-v3','hash_soderzhaniya',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('content3-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_obrabotki',pg_catalog.encode(extensions.digest(pg_catalog.convert_to('proc3-'||v_suffix,'UTF8'),'sha256'),'hex'),'otpechatok_profilya',v_profile_fp,'embedding_model','synthetic-r5c','razmernost',1024,'versiya_parsera','r5c-parser','versiya_ochistki','r5c-clean','versiya_chunkinga','r5c-chunk','tokenizer','synthetic','cel_fragmenta_tokenov',20,'maks_fragmenta_tokenov',50,'overlap_tokenov',5));
    IF r_ver3.rezultat IS DISTINCT FROM 'uspeshno' OR r_ver3.ozhidaemaya_aktivnaya_versiya_id IS DISTINCT FROM r_ver1.versiya_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL prepare3 result=% expected=%',r_ver3.rezultat,r_ver3.ozhidaemaya_aktivnaya_versiya_id; END IF;
    SELECT * INTO r_frag3 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_fragmenty_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-f3-'||v_suffix,'versiya_id',r_ver3.versiya_id,'zadanie_id',r_claim3.zadanie_id,'worker_id','kb01r5c_worker_3','nomer_vladeniya',r_claim3.nomer_vladeniya,'fragmenty',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('nomer_fragmenta',1,'put_razdela','R5C / V3','tekst_fragmenta',v_text3,'kolichestvo_tokenov',7,'hash_fragmenta',pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_text3,'UTF8'),'sha256'),'hex'),'vektor',v_vec3))));
    SELECT * INTO r_search3 FROM qbit_bot_pervichnogo_obrascheniya.poisk_chernovika_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-s3-'||v_suffix,'versiya_id',r_ver3.versiya_id,'profil_indeksa_id',r_ver3.profil_indeksa_id,'limit',1,'porog_shodstva',0.99,'vektor',v_vec3));
    SELECT * INTO r_q3 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_kontrolnye_voprosy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-q3-'||v_suffix,'versiya_id',r_ver3.versiya_id,'voprosy',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('vopros','V3?','ozhidaemyy_razdel','R5C / V3','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V3 again?','ozhidaemyy_razdel','R5C / V3','istochnik','synthetic'),pg_catalog.jsonb_build_object('vopros','V3 third?','ozhidaemyy_razdel','R5C / V3','istochnik','synthetic'))));
    v_checks:=pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('nomer_voprosa',1,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search3.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',2,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search3.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'),
      pg_catalog.jsonb_build_object('nomer_voprosa',3,'porog_shodstva',0.99,'limit_rezultatov',1,'poluchennye_fragmenty',pg_catalog.jsonb_build_array(r_search3.fragment_id),'shodstva',pg_catalog.jsonb_build_array(1.0),'rezultat','uspeshno'));
    SELECT * INTO r_chk3 FROM qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-k3-'||v_suffix,'versiya_id',r_ver3.versiya_id,'profil_indeksa_id',r_ver3.profil_indeksa_id,'proverki',v_checks));
    IF r_chk3.status_versii IS DISTINCT FROM 'gotova' THEN RAISE EXCEPTION 'KB-01R5C_FAIL checks3'; END IF;
    SELECT * INTO r_finish3 FROM qbit_bot_pervichnogo_obrascheniya.zavershit_zadanie_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-finish3-'||v_suffix,'zadanie_id',r_claim3.zadanie_id,'worker_id','kb01r5c_worker_3','nomer_vladeniya',r_claim3.nomer_vladeniya,'status','zaversheno'));
    IF r_finish3.rezultat IS DISTINCT FROM 'uspeshno' THEN RAISE EXCEPTION 'KB-01R5C_FAIL finish3'; END IF;

    -- Race simulation: V2 wins, V3 still carries expected V1 and must be rejected as stale.
    SELECT * INTO r_pub2 FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-pub2-'||v_suffix,'versiya_id',r_ver2.versiya_id,'ozhidaemaya_aktivnaya_versiya_id',r_ver1.versiya_id));
    IF r_pub2.rezultat IS DISTINCT FROM 'uspeshno' OR r_pub2.status_versii IS DISTINCT FROM 'opublikovana' OR r_pub2.predydushchaya_aktivnaya_versiya_id IS DISTINCT FROM r_ver1.versiya_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL publish2 result=% code=% previous=%',r_pub2.rezultat,r_pub2.kod_oshibki,r_pub2.predydushchaya_aktivnaya_versiya_id; END IF;
    SELECT * INTO r_pub3_stale FROM qbit_bot_pervichnogo_obrascheniya.opublikovat_versiyu_znaniy(pg_catalog.jsonb_build_object('operaciya_id','kb01r5c-pub3-stale-'||v_suffix,'versiya_id',r_ver3.versiya_id,'ozhidaemaya_aktivnaya_versiya_id',r_ver1.versiya_id));
    IF r_pub3_stale.rezultat IS DISTINCT FROM 'konflikt' OR r_pub3_stale.kod_oshibki IS DISTINCT FROM 'stale_expected_active' OR r_pub3_stale.predydushchaya_aktivnaya_versiya_id IS DISTINCT FROM r_ver2.versiya_id THEN RAISE EXCEPTION 'KB-01R5C_FAIL stale_publish result=% code=% current=%',r_pub3_stale.rezultat,r_pub3_stale.kod_oshibki,r_pub3_stale.predydushchaya_aktivnaya_versiya_id; END IF;

    INSERT INTO pg_temp.kb01r5c_result(payload) VALUES(pg_catalog.jsonb_build_object(
      'status','prepared_and_published',
      'probe','KB-01R5C_SERVICE_v0.1',
      'suffix',v_suffix,
      'document_identifier',v_doc_ident,
      'document_id',r_ver1.dokument_id,
      'profile_id',r_ver1.profil_indeksa_id,
      'version1_id',r_ver1.versiya_id,
      'version2_id',r_ver2.versiya_id,
      'version3_id',r_ver3.versiya_id,
      'event_ids',pg_catalog.jsonb_build_array(r_event1.sobytie_id,r_event2.sobytie_id,r_event3.sobytie_id),
      'upload_ids',pg_catalog.jsonb_build_array(r_upload1.zagruzka_id,r_upload2.zagruzka_id,r_upload3.zagruzka_id),
      'job_ids',pg_catalog.jsonb_build_array(r_upload1.zadanie_id,r_upload2.zadanie_id,r_upload3.zadanie_id),
      'active_version_id',r_ver2.versiya_id,
      'previous_active_id',r_pub2.predydushchaya_aktivnaya_versiya_id,
      'stale_candidate_id',r_ver3.versiya_id,
      'stale_publish_result',r_pub3_stale.rezultat,
      'stale_publish_code',r_pub3_stale.kod_oshibki,
      'next','run generated qbit_test_bot probe; then qbit_test_dash_admin revoke; then cleanup'
    ));
END
$kb01r5c$;

COMMIT;
SELECT payload AS kb01r5c_service_result FROM pg_temp.kb01r5c_result;
