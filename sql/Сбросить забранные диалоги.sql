-- Сбросить забранные диалоги
-- TEST-only. Менять только Telegram user ID менеджера в VALUES('...').
-- История сообщений и operator topic сохраняются. Production не затрагивается.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
SET LOCAL search_path=pg_catalog;

DO $trusted$
BEGIN
  IF session_user <> 'postgres'
     OR NOT pg_catalog.pg_has_role(session_user,'qbit_test_owner','SET') THEN
    RAISE EXCEPTION 'Нужна trusted postgres session с SET qbit_test_owner';
  END IF;
END
$trusted$;

SET LOCAL ROLE qbit_test_owner;

CREATE TEMP TABLE _qbit_reset_param(telegram_user_id text NOT NULL) ON COMMIT DROP;
INSERT INTO _qbit_reset_param VALUES ('TELEGRAM_USER_ID_МЕНЕДЖЕРА');

DO $check$
DECLARE v_user text; v_manager uuid;
BEGIN
  SELECT telegram_user_id INTO v_user FROM _qbit_reset_param;
  IF v_user IS NULL OR pg_catalog.btrim(v_user)='' OR v_user='TELEGRAM_USER_ID_МЕНЕДЖЕРА' THEN
    RAISE EXCEPTION 'Укажите Telegram user ID менеджера внутри кавычек';
  END IF;
  SELECT id INTO v_manager
  FROM qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram
  WHERE telegram_user_id=v_user;
  IF v_manager IS NULL THEN
    RAISE EXCEPTION 'Менеджер с Telegram user ID % не найден в TEST',v_user;
  END IF;
END
$check$;

CREATE TEMP TABLE _qbit_reset_targets ON COMMIT DROP AS
SELECT d.id dialog_id,d.versiya_dialoga versiya_do,d.pokolenie_ozhidaniya pokolenie_do
FROM qbit_bot_pervichnogo_obrascheniya.dialogi d
JOIN qbit_bot_pervichnogo_obrascheniya.menedzhery_telegram m
  ON m.id=d.tekushchiy_menedzher_id
JOIN _qbit_reset_param p ON p.telegram_user_id=m.telegram_user_id
WHERE d.vladelec='chelovek' AND d.status='peredan_cheloveku';

DO $guard$
DECLARE v_count bigint;
BEGIN
  SELECT count(*) INTO v_count
  FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya a
  JOIN _qbit_reset_targets t ON t.dialog_id=a.dialog_id
  WHERE a.status='v_rabote';
  IF v_count>0 THEN
    RAISE EXCEPTION 'Reset остановлен: % outgoing action status=v_rabote',v_count;
  END IF;
END
$guard$;

UPDATE qbit_bot_pervichnogo_obrascheniya.zadaniya_obrabotki j
SET status='otmeneno',vladelec_arendy=NULL,arenda_do=NULL,
    kod_oshibki='test_manager_reset',opisanie_oshibki='TEST-only reset к bot.',
    vremya_obnovleniya=clock_timestamp()
FROM _qbit_reset_targets t
WHERE j.dialog_id=t.dialog_id AND j.status IN ('ozhidaet','povtor','v_rabote');

UPDATE qbit_bot_pervichnogo_obrascheniya.napominaniya n
SET status='otmeneno',prichina='test_manager_reset',vremya_obnovleniya=clock_timestamp()
FROM _qbit_reset_targets t
WHERE n.dialog_id=t.dialog_id AND n.status IN ('zaplanirovano','v_rabote');

UPDATE qbit_bot_pervichnogo_obrascheniya.soobshcheniya s
SET status_otpravki='otmeneno'
WHERE s.id IN (
  SELECT a.soobshchenie_id
  FROM qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya a
  JOIN _qbit_reset_targets t ON t.dialog_id=a.dialog_id
  WHERE a.status IN ('zaplanirovano','povtor') AND a.soobshchenie_id IS NOT NULL
);

UPDATE qbit_bot_pervichnogo_obrascheniya.ishodyashchie_deystviya a
SET status='otmeneno',vladelec_arendy=NULL,arenda_do=NULL,
    kod_oshibki='test_manager_reset',opisanie_oshibki='TEST-only reset: pending outgoing отменён.',
    vremya_obnovleniya=clock_timestamp()
FROM _qbit_reset_targets t
WHERE a.dialog_id=t.dialog_id AND a.status IN ('zaplanirovano','povtor');

UPDATE qbit_bot_pervichnogo_obrascheniya.dialogi d
SET vladelec='bot',status='aktivnyy',tekushchiy_menedzher_id=NULL,
    ozhidaetsya_otvet=false,t0=NULL,
    pokolenie_ozhidaniya=d.pokolenie_ozhidaniya+1,
    versiya_dialoga=d.versiya_dialoga+1,
    vremya_obnovleniya=clock_timestamp()
FROM _qbit_reset_targets t
WHERE d.id=t.dialog_id AND d.vladelec='chelovek' AND d.status='peredan_cheloveku';

DO $post$
DECLARE v_bad bigint;
BEGIN
  SELECT count(*) INTO v_bad
  FROM qbit_bot_pervichnogo_obrascheniya.dialogi d
  JOIN _qbit_reset_targets t ON t.dialog_id=d.id
  WHERE d.vladelec IS DISTINCT FROM 'bot'
     OR d.status IS DISTINCT FROM 'aktivnyy'
     OR d.tekushchiy_menedzher_id IS NOT NULL
     OR d.ozhidaetsya_otvet IS DISTINCT FROM false
     OR d.t0 IS NOT NULL
     OR d.versiya_dialoga<>t.versiya_do+1
     OR d.pokolenie_ozhidaniya<>t.pokolenie_do+1;
  IF v_bad>0 THEN
    RAISE EXCEPTION 'Postcheck failed for % dialogs',v_bad;
  END IF;
END
$post$;

SELECT pg_catalog.jsonb_build_object(
  'test_reset_status','applied',
  'dialogov_sbroseno',(SELECT count(*) FROM _qbit_reset_targets),
  'novyy_vladelec','bot',
  'novyy_status','aktivnyy',
  'istoriya_sohranena',true,
  'production_untouched',true
) AS test_manager_dialog_reset_result;

COMMIT;
