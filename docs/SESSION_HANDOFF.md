# SESSION HANDOFF

Обновлено: 2026-10-04.

## Исходная точка

Рабочая ветка: `main`.

Исходный HEAD перед KB-01A: `9e02ad48d5de5438b3690b717ea331ef395f5227`.

В начале следующей сессии:
1. проверить актуальный `main` HEAD;
2. прочитать `README.md`;
3. прочитать `docs/PROJECT_STATE.md`;
4. прочитать этот файл;
5. прочитать активный `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
6. для runtime KB-01A читать только нужные части `docs/specs/KNOWLEDGE_INGESTION.md`, `docs/specs/MARKDOWN_FORMAT.md` и `docs/specs/DB_CONTRACT.md`.

## Что выяснено про workflow

Git checkpoint 03.10.2026 основан на export `(6)`. Павел передал `Шаблон — служебный Telegram и перехват диалогов — версия 0.2 (7).json`.

У `(7)` проверена топология: 189 nodes / 153 connection keys / 215 edges / inactive / duplicate names 0 / dangling 0. Поскольку Git manifest называл исходником именно `(6)`, `(7)` принят как более свежая фактическая основа. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`. На нём подготовлен v0.4 KB-01A; точный checkpoint сохранён в Git в `workflows/checkpoints/2026-10-04_v0.4_KB-01A/`.

Полный import-ready JSON подготовлен локально в этой сессии:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

SHA-256 pretty JSON: `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.

Подготовленный compact checkpoint SHA-256: `e9a196e03281704c6b08ae7512e7f3790317a22c5040e7a93a74e2e44b6fa26a`.

**Важно:** checkpoint v0.4 KB-01A уже сохранён в Git. `python tools/restore_workflow_checkpoint.py` восстанавливает полный import-ready JSON и проверяет SHA-256. Не пересобирать workflow с нуля.

## DB-04 / DB-05

Не ориентироваться на старые `[ ]` в `WORKPLAN_TEMPLATE.md`.

Нормативные DB-04/DB-05 уже созданы в test и runtime-проверены по KB-01R4/R5 для bot/service: ingestion queue, version/profile/fragments/checks, draft search, publish concurrency/active switch и active-only bot search.

`KB-01R5D` dash_admin revoke остаётся отложен до dashboard stage.

## Текущая задача — KB-01A

Статус: **реализация JSON готова и статически проверена; runtime реальным документом ещё не выполнен**.

Существующий единый service Telegram webhook сохранён. После `zaregistrirovat_sluzhebnoe_sobytie` добавлена ветка:

`KB-01A Проверить источник документа`
→ whitelist/private/.md/declared size
→ `KB-01A Скачать Markdown`
→ actual binary/size
→ `Служебный_KB_Зарегистрировать загрузку`
→ `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)`
→ Telegram-ответ о постановке в очередь.

Нормативный DB API является final gate: actual bytes <= 5 MiB, `.md`, UTF-8, SHA-256, durable service event, duplicate/conflict; при успехе создаёт `zagruzki_znaniy` + `zadaniya_znaniy`.

Парсер/chunking/embedding/check/publish ещё не подключены — это следующие ID активного плана.

## Статическая проверка

- 196 nodes;
- 161 connection keys;
- 225 edges;
- `active=false`;
- duplicate names 0;
- dangling connections 0;
- Credential objects / Credential ID отсутствуют;
- top-level `id`, `versionId`, `meta.instanceId` отсутствуют;
- real service group ID отсутствует;
- obvious secrets/tokens не найдены;
- новые/изменённые Code nodes проходят `node --check`.

Файл **не импортировался** в n8n, server runtime **не менялся**.

## Что сделать в следующей сессии

Продолжить тот же ID `KB-01A`, не начинать KB-01B.

1. Восстановить канонический v0.4 через `python tools/restore_workflow_checkpoint.py`, убедиться, что SHA совпадает, затем импортировать JSON **неактивным**.
2. В UI n8n назначить существующие Credentials:
   - служебный Telegram — всем новым KB Telegram nodes;
   - `qbit_test_sluzhebnyy` — `Служебный_KB_Зарегистрировать загрузку`;
   - остальные Credential связи восстановить по существующему workflow, не угадывая роли Postgres.
3. В `Настройки служебного бота` заполнить:
   - `kb.razreshennye_otpraviteli_telegram_id` — Telegram user ID Павла;
   - `kb.razreshennye_lichnye_chat_id` — private chat ID Павла.
4. Не включать production и не переключать рабочий трафик.
5. Отправить один безопасный test `.md` без реальных данных компании.
6. Сохранить execution evidence: service event, ответ KB-01A, `rezultat=uspeshno`, `zagruzka_id`, `zadanie_id`, статус knowledge job.
7. Проверить, что `/start`, operator callback/ручные сообщения не ушли в KB.
8. Только после этих проверок поставить `KB-01A [x]`.

## PRE-02E

Не запускать отдельный smoke. OpenAI document embedding `text-embedding-3-large`, `dimensions=1024` будет добавлен и runtime-проверен в каноническом workflow на `KB-03A`. Существующая query-embedding ветка с этим профилем сохранена.

## Запреты

- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не менять production.
- Не запускать experimental evidence SQL.
- Не считать статический JSON runtime-проверкой.
