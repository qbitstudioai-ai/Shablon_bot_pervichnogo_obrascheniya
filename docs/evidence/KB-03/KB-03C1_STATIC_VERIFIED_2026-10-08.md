# KB-03C1 — static verified, 2026-10-08

## Статус

KB-03C1 **CLOSED / static verified**.

Подготовлен repository-safe workflow документов с publish branch. В рамках KB-03C1 workflow не импортировался в n8n и `opublikovat_versiyu_znaniy` не выполнялась. Active version в TEST не менялась; production и рабочий трафик не затрагивались.

## Read-only preflight TEST

Перед сборкой Павел выполнил read-only проверку готовой version:
- `versiya_id=1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- `dokument_id=2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- `identifikator_dokumenta=qbit_klientskaya_baza_znaniy`;
- `status_versii=gotova`;
- `status_zagruzki=ozhidaet_proverki`;
- `ozhidaemaya_aktivnaya_versiya_id=NULL`;
- текущая `aktivnaya_versiya_id=NULL`;
- expected active совпадает;
- fragments = 53;
- fragments с неправильной размерностью = 0;
- canonical questions = 9;
- latest successful checks = 9;
- `opublikovat_versiyu_znaniy(jsonb)` существует;
- service role `qbit_test_sluzhebnyy` имеет EXECUTE;
- bot role `qbit_test_bot` не имеет EXECUTE;
- итог: `READY_FOR_KB03C1_WORKFLOW_PREP`.

Проверка была read-only и не меняла БД.

## Фактический DB-05 contract

Workflow собран по текущей реализации `opublikovat_versiyu_znaniy(jsonb)`, а не по предположению.

Publish payload использует:
- стабильный `operaciya_id`;
- exact `versiya_id` из DB/runtime context;
- `ozhidaemaya_aktivnaya_versiya_id` из `podgotovit_versiyu_znaniy`.

DB самостоятельно проверяет `gotova`, fragments/vectors/reference checks и optimistic concurrency. При stale expected-active возвращается `konflikt / stale_expected_active`; active pointer не должен быть перезаписан. При success DB атомарно публикует новую version, архивирует предыдущую active при её наличии, меняет active pointer, завершает upload и knowledge job.

## Изменение workflow

Обновлён:
`workflows/current/Шаблон Загрузка документов Qbit.json`.

Добавлено 9 нод KB-03C1:
- `KB-03C1 Версия уже готова?`;
- `KB-03C1 B1 готов к публикации?`;
- `KB-03C1 Подготовить публикацию`;
- `KB-03C1 Publish gate открыт?`;
- `Служебный_KB_Опубликовать версию`;
- `KB-03C1 Проверить результат публикации`;
- `KB-03C1 Публикация успешна?`;
- `KB-03C1 Итог публикации`;
- `Служебный_KB_Завершить после ошибки публикации`.

Ключевая особенность для текущей готовой version: если `podgotovit_versiyu_znaniy` возвращает уже существующую version как `dublikat` со status `gotova`/`opublikovana`, workflow не пытается повторно выполнять KB-03A/KB-03B, а переходит в безопасный publish gate. Для новой draft version прежний путь KB-03A → KB-03B1 сохранён.

## Static checks

Одноразовая GitHub Actions-проверка завершилась success:
- run `37825254670`;
- candidate commit `912f92764a7870b5c96865a89ebeb11594f4c984`;
- candidate workflow blob `e1da790ccb222bea23a76c751476e2aa642d5da9`;
- nodes total = 67;
- новых KB-03C1/publish nodes = 9;
- JSON parse PASS;
- duplicate node names = 0;
- duplicate node IDs = 0;
- dangling connections = 0;
- JavaScript syntax checked for 21 Code nodes;
- `opublikovat_versiyu_znaniy` присутствует;
- explicit `stale_expected_active` handling присутствует;
- workflow остаётся `active=false`;
- Credential bindings отсутствуют;
- OpenAI/Authorization/Telegram token patterns не найдены.

Workflow клиентского бота не менялся: его существующая нода `Найти опубликованные знания` уже вызывает `poisk_aktivnyh_znaniy`.

## Что НЕ проверено

KB-03C1 не является runtime publish evidence. Ещё не доказано на текущей real TEST version:
- фактическая публикация version;
- итоговые `status_versii=opublikovana` и `status_zagruzki=zavershena`;
- active-only поиск после этой публикации;
- stale-conflict сценарий именно на текущем наборе.

Это задача KB-03C2.

## Итог

KB-03C1 выполнен: publish workflow подготовлен и статически проверен без server mutation.

Следующий этап: **KB-03C2 — импорт отдельной неактивной TEST-копии, привязка нужных service Credentials, затем отдельное разрешённое TEST runtime publish + active-only regression**.
