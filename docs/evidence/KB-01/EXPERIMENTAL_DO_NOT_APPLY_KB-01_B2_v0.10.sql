-- EVIDENCE ONLY / НЕ КАНОНИЧЕСКАЯ МИГРАЦИЯ.
-- Этот SQL был применён и runtime-проверен в test 03.10.2026,
-- но после сверки обнаружено расхождение с нормативным DB-04/DB-05.
-- НЕ ПОВТОРЯТЬ и НЕ ИСПОЛЬЗОВАТЬ В PRODUCTION.
-- Следовать docs/KB-01_RECONCILIATION_PLAN.md.

-- KB-01 v0.10 / STAGE B2
-- Атомарный захват следующей версии документа обработчиком KB-01.
-- Предусловия:
--   - таблицы KB-01 созданы;
--   - kb01_postavit_dokument(jsonb) уже VERIFIED;
--   - запускать файл целиком в Supabase SQL Editor без выделенного фрагмента.

SET ROLE qbit_test_owner;

BEGIN;

CREATE OR REPLACE FUNCTION
qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, qbit_bot_pervichnogo_obrascheniya, pg_temp
AS $b2$
DECLARE
    v_worker text := NULLIF(btrim(p->>'worker_id'), '');
    v_company text := NULLIF(btrim(p->>'kompaniya_kod'), '');
    v_env text := NULLIF(btrim(p->>'sreda'), '');
    v_lease integer;
    v_result jsonb;
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
        RETURN jsonb_build_object(
            'rezultat', 'otkaz',
            'kod_oshibki', 'nekorrektnyy_vhod',
            'opisanie', 'Ожидается JSON object.'
        );
    END IF;

    IF NULLIF(p->>'arenda_sekund', '') IS NULL THEN
        v_lease := 900;
    ELSIF (p->>'arenda_sekund') ~ '^[0-9]+$' THEN
        v_lease := (p->>'arenda_sekund')::integer;
    ELSE
        RETURN jsonb_build_object(
            'rezultat', 'otkaz',
            'kod_oshibki', 'nekorrektnaya_arenda',
            'opisanie', 'arenda_sekund должна быть целым числом 60..3600.'
        );
    END IF;

    IF v_worker IS NULL
       OR v_company IS NULL
       OR v_env IS NULL
       OR v_lease < 60
       OR v_lease > 3600
    THEN
        RETURN jsonb_build_object(
            'rezultat', 'otkaz',
            'kod_oshibki', 'nekorrektnyy_vhod',
            'opisanie', 'Нужны worker_id, kompaniya_kod, sreda и arenda_sekund 60..3600.'
        );
    END IF;

    WITH candidate AS (
        SELECT v.id
        FROM qbit_bot_pervichnogo_obrascheniya.znaniya_versii AS v
        JOIN qbit_bot_pervichnogo_obrascheniya.znaniya_dokumenty AS d
          ON d.id = v.dokument_id
        WHERE (
            v.status = 'ozhidaet'
            OR (
                v.status = 'v_rabote'
                AND v.arenda_do IS NOT NULL
                AND v.arenda_do < clock_timestamp()
            )
        )
          AND d.kompaniya_kod = v_company
          AND d.sreda = v_env
        ORDER BY
            CASE WHEN v.status = 'ozhidaet' THEN 0 ELSE 1 END,
            v.vremya_sozdaniya,
            v.id
        FOR UPDATE OF v SKIP LOCKED
        LIMIT 1
    )
    UPDATE qbit_bot_pervichnogo_obrascheniya.znaniya_versii AS v
       SET status = 'v_rabote',
           vladelec_arendy = v_worker,
           nomer_vladeniya = v.nomer_vladeniya + 1,
           arenda_do = clock_timestamp() + make_interval(secs => v_lease),
           popytki = v.popytki + 1,
           vremya_nachala_obrabotki =
               COALESCE(v.vremya_nachala_obrabotki, clock_timestamp()),
           kod_oshibki = NULL,
           opisanie_oshibki = NULL
      FROM candidate AS c
     WHERE v.id = c.id
    RETURNING jsonb_build_object(
        'rezultat', 'uspeshno',
        'versiya_id', v.id,
        'dokument_id', v.dokument_id,
        'nomer_versii', v.nomer_versii,
        'status', v.status,
        'telegram_chat_id', v.telegram_chat_id,
        'telegram_from_id', v.telegram_from_id,
        'telegram_update_id', v.telegram_update_id,
        'telegram_file_id', v.telegram_file_id,
        'telegram_file_unique_id', v.telegram_file_unique_id,
        'imya_fayla', v.imya_fayla,
        'mime_type', v.mime_type,
        'file_size', v.file_size,
        'model_embedding', v.model_embedding,
        'razmernost_embedding', v.razmernost_embedding,
        'vladelec_arendy', v.vladelec_arendy,
        'nomer_vladeniya', v.nomer_vladeniya,
        'arenda_do', v.arenda_do,
        'popytki', v.popytki
    )
    INTO v_result;

    IF v_result IS NULL THEN
        RETURN jsonb_build_object(
            'rezultat', 'net_zadaniya',
            'opisanie', 'Подходящих версий KB-01 сейчас нет.'
        );
    END IF;

    RETURN v_result;
END;
$b2$;

REVOKE ALL
ON FUNCTION
qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION
qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)
TO qbit_test_sluzhebnyy;

COMMIT;

RESET ROLE;

SELECT
    pg_catalog.to_regprocedure(
        'qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)'
    ) IS NOT NULL AS function_exists,

    (
        SELECT pg_catalog.pg_get_userbyid(p.proowner)
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
          AND p.proname = 'kb01_zabrat_sleduyushchuyu_versiyu'
        LIMIT 1
    ) AS function_owner,

    (
        SELECT p.prosecdef
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'qbit_bot_pervichnogo_obrascheniya'
          AND p.proname = 'kb01_zabrat_sleduyushchuyu_versiyu'
        LIMIT 1
    ) AS security_definer_ok,

    pg_catalog.has_function_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.kb01_zabrat_sleduyushchuyu_versiyu(jsonb)',
        'EXECUTE'
    ) AS service_execute_ok,

    pg_catalog.has_table_privilege(
        'qbit_test_sluzhebnyy',
        'qbit_bot_pervichnogo_obrascheniya.znaniya_versii',
        'UPDATE'
    ) AS service_direct_update_versions;
