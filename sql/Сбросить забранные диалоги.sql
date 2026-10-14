-- Сбросить забранные диалоги
-- Project: Shablon_bot_pervichnogo_obrascheniya
-- Назначение: TEST-only ручной сброс диалогов, ранее забранных конкретным менеджером.
--
-- КОГДА ИСПОЛЬЗОВАТЬ
--   Только в TEST, когда нужно снова тестировать обычное общение клиента с ботом.
--   Это НЕ продуктовая функция «Вернуть боту» и не должна вызываться из n8n runtime.
--
-- ЧТО НУЖНО МЕНЯТЬ
--   Ровно одну строку ниже: TELEGRAM_USER_ID_МЕНЕДЖЕРА.
--   Используется Telegram user ID МЕНЕДЖЕРА, а не клиента.
--
-- ЧТО ДЕЛАЕТ
--   * находит все текущие TEST-диалоги этого менеджера, где
--       vladelec='chelovek' AND status='peredan_cheloveku';
--   * не удаляет сообщения, историю и operator topic;
--   * отменяет active internal jobs/reminders;
--   * отменяет ещё не начатые outgoing actions (zaplanirovano/povtor);
--   * НЕ стирает уже начатую внешнюю отправку;
--   * возвращает dialog к bot/aktivnyy;
--   * снимает tekushchiy_menedzher_id;
--   * увеличивает versiya_dialoga и pokolenie_ozhidaniya;
--   * следующий новый client input снова обрабатывается ботом;
--   * Production schema qbit не затрагивается.
--
-- SAFETY
--   Если для одного из целевых диалогов сейчас есть external outgoing
--   status='v_rabote', весь reset прерывается до изменений. Повторить позже.
--
-- ЗАПУСК
--   Supabase Studio -> SQL Editor -> вставить ВЕСЬ файл -> Run.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL search_path = pg_catalog;

-- ============================================================================
-- 1. ЕДИНСТВЕННЫЙ ПАРАМЕТР: МЕНЯТЬ ТОЛЬКО ЭТУ СТРОКУ
-- ============================================================================

CREATE TEMP TABLE _qbit_reset_param (
    telegram_user_id text NOT NULL
) ON COMMIT DROP;

INSERT INTO _qbit_reset_param (telegram_user_id)
VALUES ('TELEGRAM_USER_ID_МЕНЕДЖЕРА');

-- ============================================================================
-- 2. PRECHECK
-- ============================================================================

DO $precheck$
DECLARE
    v_user text;
    v_manager_id uuid;
BEGIN
    IF session_user <> 'postgres' THEN
        RAISE EXCEPTION
            'Reset must run from trusted postgres session. session_user=%',
            session_user;
    END IF;

    SELECT p.telegram_user_id
      INTO v_user
      FROM _qbit_reset_param AS p;

    IF v_user IS NULL
       OR pg_catalog.btrim(v_user) = ''
       OR v_user = 'TELEGRAM_USER_ID_МЕНЕДЖЕРА' THEN
        RAISE EXCEPTION
            'Замените TELEGRAM_USER_ID_МЕНЕДЖЕРА на реальный Telegram user ID менеджера.';
    END IF;

    IF pg_catalog.to_regclass(
        'qbit_bot_pervichnogo_obrascheniya.dialogi'
    ) IS NULL
    OR pg_catalog.to_regclass(
        'qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Canonical TEST schema/tables are missing.';
    END IF;

    SELECT m.id
      INTO v_manager_id
      FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
     WHERE m.telegram_user_id = v_user;

    IF v_manager_id IS NULL THEN
        RAISE EXCEPTION
            'Менеджер с Telegram user ID % не найден в TEST.',
            v_user;
    END IF;
END
$precheck$;

-- ============================================================================
-- 3. ТОЧНЫЙ НАБОР ЦЕЛЕВЫХ ДИАЛОГОВ
-- ============================================================================

CREATE TEMP TABLE _qbit_reset_targets
ON COMMIT DROP
AS
SELECT
    d.id AS dialog_id,
    d.versiya_dialoga AS versiya_do,
    d.pokolenie_ozhidaniya AS pokolenie_do
FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
JOIN qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram AS m
  ON m.id = d.tekushchiy_menedzher_id
JOIN _qbit_reset_param AS p
  ON p.telegram_user_id = m.telegram_user_id
WHERE d.vladelec = 'chelovek'
  AND d.status = 'peredan_cheloveku';

-- Нельзя безопасно «забывать» внешнюю отправку, которая уже началась.
DO $inflight_guard$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(*)
      INTO v_count
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
      JOIN _qbit_reset_targets AS t
        ON t.dialog_id = a.dialog_id
     WHERE a.status = 'v_rabote';

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Reset остановлен: найдено % outgoing action status=v_rabote. Подождите завершения отправки и повторите.',
            v_count;
    END IF;
END
$inflight_guard$;

-- ============================================================================
-- 4. ОЧИСТИТЬ ТОЛЬКО НЕЗАВЕРШЁННЫЕ RUNTIME-ОЖИДАНИЯ
-- ============================================================================

UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki AS j
   SET status = 'otmeneno',
       vladelec_arendy = NULL,
       arenda_do = NULL,
       kod_oshibki = 'test_manager_reset',
       opisanie_oshibki = 'TEST-only reset забранного диалога к bot.',
       vremya_obnovleniya = clock_timestamp()
  FROM _qbit_reset_targets AS t
 WHERE j.dialog_id = t.dialog_id
   AND j.status IN ('ozhidaet', 'povtor', 'v_rabote');

UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya AS n
   SET status = 'otmeneno',
       prichina = 'test_manager_reset',
       vremya_obnovleniya = clock_timestamp()
  FROM _qbit_reset_targets AS t
 WHERE n.dialog_id = t.dialog_id
   AND n.status IN ('zaplanirovano', 'v_rabote');

-- Сначала синхронизируем logical message status для действий, которые ещё не начали API call.
UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya AS s
   SET status_otpravki = 'otmeneno'
 WHERE s.id IN (
    SELECT a.soobshchenie_id
      FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
      JOIN _qbit_reset_targets AS t
        ON t.dialog_id = a.dialog_id
     WHERE a.status IN ('zaplanirovano', 'povtor')
       AND a.soobshchenie_id IS NOT NULL
 );

UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya AS a
   SET status = 'otmeneno',
       vladelec_arendy = NULL,
       arenda_do = NULL,
       kod_oshibki = 'test_manager_reset',
       opisanie_oshibki = 'TEST-only reset: не начатая отправка отменена.',
       vremya_obnovleniya = clock_timestamp()
  FROM _qbit_reset_targets AS t
 WHERE a.dialog_id = t.dialog_id
   AND a.status IN ('zaplanirovano', 'povtor');

-- ============================================================================
-- 5. ВЕРНУТЬ ТОЛЬКО ТЕКУЩИЕ HUMAN-OWNED ДИАЛОГИ ЭТОГО МЕНЕДЖЕРА К BOT
-- ============================================================================

UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi AS d
   SET vladelec = 'bot',
       status = 'aktivnyy',
       tekushchiy_menedzher_id = NULL,
       ozhidaetsya_otvet = false,
       t0 = NULL,
       pokolenie_ozhidaniya = d.pokolenie_ozhidaniya + 1,
       versiya_dialoga = d.versiya_dialoga + 1,
       vremya_obnovleniya = clock_timestamp()
  FROM _qbit_reset_targets AS t
 WHERE d.id = t.dialog_id
   AND d.vladelec = 'chelovek'
   AND d.status = 'peredan_cheloveku';

-- ============================================================================
-- 6. POSTCHECK
-- ============================================================================

DO $postcheck$
DECLARE
    v_bad bigint;
BEGIN
    SELECT count(*)
      INTO v_bad
      FROM qbit_bot_pervichnogo_obrascheniya.dialogi AS d
      JOIN _qbit_reset_targets AS t
        ON t.dialog_id = d.id
     WHERE d.vladelec IS DISTINCT FROM 'bot'
        OR d.status IS DISTINCT FROM 'aktivnyy'
        OR d.tekushchiy_menedzher_id IS NOT NULL
        OR d.ozhidaetsya_otvet IS DISTINCT FROM false
        OR d.t0 IS NOT NULL
        OR d.versiya_dialoga <> t.versiya_do + 1
        OR d.pokolenie_ozhidaniya <> t.pokolenie_do + 1;

    IF v_bad > 0 THEN
        RAISE EXCEPTION
            'Postcheck failed for % reset dialogs; transaction will roll back.',
            v_bad;
    END IF;
END
$postcheck$;

-- Итог формируется ДО COMMIT, пока временная таблица ещё существует.
SELECT pg_catalog.jsonb_build_object(
    'test_reset_status', 'applied',
    'dialogov_sbroseno', (SELECT count(*) FROM _qbit_reset_targets),
    'novyy_vladelec', 'bot',
    'novyy_status', 'aktivnyy',
    'istoriya_sohranena', true,
    'production_untouched', true,
    'result', CASE
        WHEN (SELECT count(*) FROM _qbit_reset_targets) = 0
        THEN 'У этого менеджера нет текущих забранных TEST-диалогов; изменений не было.'
        ELSE 'Забранные TEST-диалоги менеджера возвращены боту. История и темы сохранены.'
    END
) AS test_manager_dialog_reset_result;

COMMIT;
