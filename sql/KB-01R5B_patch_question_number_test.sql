-- KB-01R5B PATCH v0.1: allow sohranit_proverki_znaniy to resolve a control question by nomer_voprosa
-- TEST ONLY: qbit_bot_pervichnogo_obrascheniya / qbit_test_owner.
-- Backward compatible: existing vopros_id input remains supported.
-- Purpose: qbit_test_sluzhebnyy has no direct table SELECT, so n8n cannot discover generated question UUIDs.
-- Production is not referenced.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog;

DO $preflight$
DECLARE
    v_oid oid;
    v_def text;
BEGIN
    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION 'KB-01R5B patch must run from trusted postgres session; session_user=%', session_user;
    END IF;
    IF NOT pg_catalog.pg_has_role(session_user, 'qbit_test_owner', 'SET') THEN
        RAISE EXCEPTION 'session_user % cannot SET ROLE qbit_test_owner', session_user;
    END IF;

    v_oid := pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb)'
    );
    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'Required function sohranit_proverki_znaniy(jsonb) is missing';
    END IF;

    IF pg_catalog.pg_get_userbyid((SELECT p.proowner FROM pg_catalog.pg_proc p WHERE p.oid=v_oid)) <> 'qbit_test_owner'
       OR NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=v_oid) THEN
        RAISE EXCEPTION 'Unexpected owner/security mode for sohranit_proverki_znaniy';
    END IF;

    v_def := pg_catalog.pg_get_functiondef(v_oid);
    IF v_def NOT LIKE '%v_q:=(v_item->>''vopros_id'')::uuid%'
       AND v_def NOT LIKE '%nomer_voprosa%' THEN
        RAISE EXCEPTION 'Unexpected current function body; stop before replacement';
    END IF;
END
$preflight$;

SET LOCAL ROLE qbit_test_owner;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(p_dannye jsonb)
RETURNS TABLE(
    operaciya_id text,
    rezultat text,
    kod_oshibki text,
    opisanie text,
    povtor_posle timestamptz,
    versiya_id uuid,
    status_versii text,
    uspeshnyh integer,
    vsego integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,qbit_bot_pervichnogo_obrascheniya,extensions
AS $fn$
#variable_conflict use_column
DECLARE
    v_op text:=NULLIF(btrim(p_dannye->>'operaciya_id'),'');
    v_ver uuid;
    v_profile uuid;
    v_arr jsonb:=p_dannye->'proverki';
    v_item jsonb;
    v_q uuid;
    v_nomer integer;
    v_ok integer;
    v_all integer;
    v_frag integer;
    v_dim integer;
    v_status text;
    v_limit integer;
BEGIN
    BEGIN
        v_ver:=(p_dannye->>'versiya_id')::uuid;
        v_profile:=(p_dannye->>'profil_indeksa_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_ver:=NULL;
    END;

    IF v_op IS NULL OR v_ver IS NULL OR v_profile IS NULL
       OR jsonb_typeof(v_arr)<>'array' OR jsonb_array_length(v_arr)=0 THEN
        RETURN QUERY SELECT v_op,'otkaz','nekorrektnyy_vhod','Некорректный набор проверок',NULL::timestamptz,v_ver,NULL::text,0,0;
        RETURN;
    END IF;

    SELECT p.razmernost
      INTO v_dim
      FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v
      JOIN qbit_bot_pervichnogo_obrascheniya.profili_indeksa p ON p.id=v.profil_indeksa_id
     WHERE v.id=v_ver
       AND v.profil_indeksa_id=v_profile
       AND v.status='chernovik'
     FOR UPDATE OF v;

    IF NOT FOUND THEN
        RETURN QUERY SELECT v_op,'konflikt','versiya_ili_profil','Draft version/profile не совпадают',NULL::timestamptz,v_ver,NULL::text,0,0;
        RETURN;
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(v_arr) LOOP
        v_q:=NULL;
        v_nomer:=NULL;
        BEGIN
            v_q:=NULLIF(v_item->>'vopros_id','')::uuid;
        EXCEPTION WHEN OTHERS THEN
            v_q:=NULL;
        END;
        BEGIN
            v_nomer:=NULLIF(v_item->>'nomer_voprosa','')::integer;
        EXCEPTION WHEN OTHERS THEN
            v_nomer:=NULL;
        END;

        IF v_q IS NULL AND v_nomer IS NULL THEN
            RAISE EXCEPTION 'Check requires vopros_id or nomer_voprosa';
        END IF;

        IF v_q IS NULL THEN
            SELECT k.id
              INTO v_q
              FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k
             WHERE k.versiya_id=v_ver
               AND k.nomer=v_nomer;
        END IF;

        IF v_q IS NULL OR NOT EXISTS (
            SELECT 1
              FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k
             WHERE k.id=v_q
               AND k.versiya_id=v_ver
               AND (v_nomer IS NULL OR k.nomer=v_nomer)
        ) THEN
            RAISE EXCEPTION 'Question does not belong to version or number does not match';
        END IF;

        BEGIN
            v_limit:=(v_item->>'limit_rezultatov')::integer;
        EXCEPTION WHEN OTHERS THEN
            v_limit:=NULL;
        END;
        IF v_limit IS NULL OR v_limit<1 OR v_limit>50 THEN
            RAISE EXCEPTION 'Invalid top-k limit';
        END IF;

        IF jsonb_array_length(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb))>v_limit THEN
            RAISE EXCEPTION 'Stored result count exceeds top-k limit';
        END IF;

        IF EXISTS (
            SELECT 1
              FROM jsonb_array_elements_text(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb)) x
             WHERE NOT EXISTS (
                SELECT 1
                  FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f
                 WHERE f.id=x::uuid
                   AND f.versiya_id=v_ver
             )
        ) THEN
            RAISE EXCEPTION 'Check references fragment outside version';
        END IF;

        INSERT INTO qbit_bot_pervichnogo_obrascheniya.proverki_znaniy(
            versiya_id,vopros_id,profil_indeksa_id,porog_shodstva,limit_rezultatov,
            poluchennye_fragmenty,shodstva,rezultat,opisanie
        )
        VALUES(
            v_ver,v_q,v_profile,(v_item->>'porog_shodstva')::numeric,v_limit,
            ARRAY(SELECT x::uuid FROM jsonb_array_elements_text(COALESCE(v_item->'poluchennye_fragmenty','[]'::jsonb)) x),
            ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(COALESCE(v_item->'shodstva','[]'::jsonb)) x),
            v_item->>'rezultat',NULLIF(v_item->>'opisanie','')
        );
    END LOOP;

    SELECT count(*)::integer
      INTO v_all
      FROM qbit_bot_pervichnogo_obrascheniya.kontrolnye_voprosy k
     WHERE k.versiya_id=v_ver;

    WITH latest AS (
        SELECT DISTINCT ON (p.vopros_id) p.vopros_id,p.rezultat
          FROM qbit_bot_pervichnogo_obrascheniya.proverki_znaniy p
         WHERE p.versiya_id=v_ver
         ORDER BY p.vopros_id,p.vremya_proverki DESC,p.id DESC
    )
    SELECT count(*) FILTER(WHERE rezultat='uspeshno')::integer
      INTO v_ok
      FROM latest;

    SELECT count(*)::integer
      INTO v_frag
      FROM qbit_bot_pervichnogo_obrascheniya.fragmenty_znaniy f
     WHERE f.versiya_id=v_ver
       AND extensions.vector_dims(f.vektor)=v_dim;

    IF v_all BETWEEN 3 AND 10 AND v_ok=v_all AND v_frag>0 THEN
        v_status:='gotova';
    ELSE
        v_status:='chernovik';
    END IF;

    UPDATE qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy
       SET status=v_status,
           vremya_proverki=clock_timestamp()
     WHERE id=v_ver;

    UPDATE qbit_bot_pervichnogo_obrascheniya.zagruzki_znaniy z
       SET status=CASE WHEN v_status='gotova' THEN 'ozhidaet_proverki' ELSE z.status END,
           vremya_obnovleniya=clock_timestamp()
      FROM qbit_bot_pervichnogo_obrascheniya.versii_dokumentov_znaniy v
     WHERE v.id=v_ver
       AND z.id=v.zagruzka_id;

    RETURN QUERY SELECT v_op,'uspeshno',NULL::text,NULL::text,NULL::timestamptz,v_ver,v_status,v_ok,v_all;
END
$fn$;

REVOKE ALL ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb) TO qbit_test_sluzhebnyy;

RESET ROLE;

DO $verify$
DECLARE
    v_oid oid;
    v_def text;
BEGIN
    v_oid:=pg_catalog.to_regprocedure('qbit_bot_pervichnogo_obrascheniya.sohranit_proverki_znaniy(jsonb)');
    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'Patched function missing';
    END IF;
    v_def:=pg_catalog.pg_get_functiondef(v_oid);
    IF v_def NOT LIKE '%nomer_voprosa%'
       OR NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=v_oid)
       OR pg_catalog.pg_get_userbyid((SELECT p.proowner FROM pg_catalog.pg_proc p WHERE p.oid=v_oid))<>'qbit_test_owner'
       OR NOT pg_catalog.has_function_privilege('qbit_test_sluzhebnyy',v_oid,'EXECUTE') THEN
        RAISE EXCEPTION 'KB-01R5B patch verification failed';
    END IF;
END
$verify$;

COMMIT;

SELECT jsonb_build_object(
    'kb01r5b_patch_result',
    jsonb_build_object(
        'status','applied',
        'patch','KB-01R5B_PATCH_v0.1',
        'schema','qbit_bot_pervichnogo_obrascheniya',
        'question_reference','vopros_id_or_nomer_voprosa',
        'production_untouched_informational',true
    )
) AS kb01r5b_patch_result;
