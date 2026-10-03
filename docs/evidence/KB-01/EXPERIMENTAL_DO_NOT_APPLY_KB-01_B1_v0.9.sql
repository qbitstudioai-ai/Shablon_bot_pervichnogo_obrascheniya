-- EVIDENCE ONLY / НЕ КАНОНИЧЕСКАЯ МИГРАЦИЯ.
-- Этот SQL был применён и runtime-проверен в test 03.10.2026,
-- но после сверки обнаружено расхождение с нормативным DB-04/DB-05.
-- НЕ ПОВТОРЯТЬ и НЕ ИСПОЛЬЗОВАТЬ В PRODUCTION.
-- Следовать docs/KB-01_RECONCILIATION_PLAN.md.

-- KB-01 v0.9 / STAGE B1
-- Компактная функция постановки документа в очередь KB-01.
-- Выполнять файл целиком.

SET ROLE qbit_test_owner;

BEGIN;

CREATE OR REPLACE FUNCTION qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya, pg_temp
AS $b1$
DECLARE
    v_key text := NULLIF(btrim(p->>'klyuch_idempotentnosti'), '');
    v_company text := NULLIF(btrim(p->>'kompaniya_kod'), '');
    v_env text := NULLIF(btrim(p->>'sreda'), '');
    v_name text := NULLIF(btrim(p->>'imya_fayla'), '');
    v_doc uuid;
    v_ver uuid;
    v_num integer;
    v_status text;
BEGIN
    IF p IS NULL
       OR jsonb_typeof(p) <> 'object'
       OR v_key IS NULL
       OR v_company IS NULL
       OR v_env IS NULL
       OR v_name IS NULL
       OR NULLIF(btrim(p->>'telegram_chat_id'), '') IS NULL
       OR NULLIF(btrim(p->>'telegram_from_id'), '') IS NULL
       OR NULLIF(btrim(p->>'telegram_file_id'), '') IS NULL
    THEN
        RAISE EXCEPTION 'KB01: обязательные поля документа не заполнены'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'kb01:' || v_company || chr(31) || v_env || chr(31) || lower(v_name),
            0
        )
    );

    SELECT id, dokument_id, nomer_versii, status
      INTO v_ver, v_doc, v_num, v_status
      FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
     WHERE klyuch_idempotentnosti = v_key
     LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'rezultat', 'dublikat',
            'dokument_id', v_doc,
            'versiya_id', v_ver,
            'nomer_versii', v_num,
            'status', v_status
        );
    END IF;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty(
        kompaniya_kod, sreda, put_logicheskiy, nazvanie
    )
    VALUES (
        v_company, v_env, lower(v_name), v_name
    )
    ON CONFLICT (kompaniya_kod, sreda, put_logicheskiy)
    DO UPDATE SET
        nazvanie = EXCLUDED.nazvanie,
        vremya_obnovleniya = clock_timestamp()
    RETURNING id INTO v_doc;

    SELECT COALESCE(MAX(nomer_versii), 0) + 1
      INTO v_num
      FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii
     WHERE dokument_id = v_doc;

    INSERT INTO qbit_bot_pervichnogo_obrascheniya.znaniya_versii(
        dokument_id,
        nomer_versii,
        status,
        klyuch_idempotentnosti,
        telegram_update_id,
        telegram_chat_id,
        telegram_from_id,
        telegram_file_id,
        telegram_file_unique_id,
        imya_fayla,
        mime_type,
        file_size,
        model_embedding,
        razmernost_embedding
    )
    VALUES (
        v_doc,
        v_num,
        'ozhidaet',
        v_key,
        NULLIF(p->>'telegram_update_id', ''),
        p->>'telegram_chat_id',
        p->>'telegram_from_id',
        p->>'telegram_file_id',
        NULLIF(p->>'telegram_file_unique_id', ''),
        v_name,
        NULLIF(p->>'mime_type', ''),
        NULLIF(p->>'file_size', '')::bigint,
        COALESCE(NULLIF(p->>'model_embedding', ''), 'text-embedding-3-large'),
        1024
    )
    RETURNING id, status INTO v_ver, v_status;

    RETURN jsonb_build_object(
        'rezultat', 'uspeshno',
        'dokument_id', v_doc,
        'versiya_id', v_ver,
        'nomer_versii', v_num,
        'status', v_status
    );
END;
$b1$;

REVOKE ALL
ON FUNCTION qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)
FROM PUBLIC;

GRANT USAGE
ON SCHEMA qbit_bot_pervichnogo_obrascheniya
TO qbit_test_sluzhebnyy;

GRANT EXECUTE
ON FUNCTION qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)
TO qbit_test_sluzhebnyy;

COMMIT;

RESET ROLE;

SELECT
    pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)'
    ) IS NOT NULL AS function_exists,

    (
        SELECT pg_catalog.pg_get_userbyid(p.proowner)
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
          AND p.proname = 'kb01_postavit_dokument'
        LIMIT 1
    ) AS function_owner,

    (
        SELECT p.prosecdef
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
          AND p.proname = 'kb01_postavit_dokument'
        LIMIT 1
    ) AS security_definer_ok,

    pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.kb01_postavit_dokument(jsonb)',
        'EXECUTE'
    ) AS service_execute_ok;
