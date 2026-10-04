# Текущее состояние проекта

Обновлено: 2026-10-04.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Исходная точка этой сессии

`main` перед изменениями: `9e02ad48d5de5438b3690b717ea331ef395f5227` (`docs: close KB-01R5C runtime validation`).

Git checkpoint `workflows/checkpoints/2026-10-03_v0.3/` был сделан из фактического export `... версия 0.2 (6).json`. Павел передал более поздний файл `... версия 0.2 (7).json`. Его топология: 189 nodes / 153 connection keys / 215 edges / `active=false`; это совпадает с checkpoint по структуре, но manifest Git прямо фиксирует источником `(6)`, поэтому считать `(7)` уже сохранённым в репозитории было нельзя.

Для продолжения `(7)` принят как фактическая новая исходная копия. Raw SHA-256 переданного `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`. На его основе подготовлен очищенный v0.4 KB-01A. Он сохранён в Git как точный gzip+base64 checkpoint `workflows/checkpoints/2026-10-04_v0.4_KB-01A/`; restore script восстанавливает полный import-ready JSON с проверкой SHA-256. Сырый `(7)` с instance-specific Credential refs в Git не сохраняется.

## DB-04 / DB-05 — фактическое состояние

Сводный `WORKPLAN_TEMPLATE.md` отстаёт: строки `[ ] DB-04` и `[ ] DB-05` больше не отражают фактическое состояние.

После KB-01R4 и runtime-проверок KB-01R5A/B/C в test schema нормативные DB-04/DB-05 существуют и проверены для текущего bot/service контура:

- ingestion upload + durable knowledge queue, lease/fencing/idempotency/conflict;
- canonical version/profile/fragments/reference checks;
- `vector(1024)` и profile/dimension guards;
- draft-only service search;
- atomic publish с stale conflict;
- active-only bot search, скрывающий archive/draft;
- старый active набор сохраняется до успешного publish commit.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

## PRE-02E

Отдельного PRE-02E smoke больше нет. Требование OpenAI переносится внутрь канонического knowledge workflow: `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`, строгая проверка фактической длины вектора. Runtime document embedding будет закрываться в `KB-03A` вместе с реальной обработкой документа.

Существующий client query-embedding adapter в workflow уже содержит этот профиль, но это не заменяет будущую проверку document embeddings.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

KB-01/KB-02/KB-03 разбиты на:
`KB-01A` → `KB-01B` → `KB-02A` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## KB-01A — реализация и Git persistence готовы, runtime ожидается

Полный import-ready workflow создан в этой сессии из переданного `(7)`:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

SHA-256 pretty JSON: `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.

Compact JSON SHA-256 подготовленного checkpoint: `e9a196e03281704c6b08ae7512e7f3790317a22c5040e7a93a74e2e44b6fa26a`.

В Git сохранён точный checkpoint `workflows/checkpoints/2026-10-04_v0.4_KB-01A/`: 10 base64-частей gzip, `MANIFEST.md` и обновлённый `tools/restore_workflow_checkpoint.py`. Restore восстанавливает полный import-ready JSON и проверяет SHA-256 `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.

Статически проверено:
- 196 nodes;
- 161 connection keys;
- 225 edges;
- `active=false`;
- duplicate node names = 0;
- dangling connections = 0;
- изменённые/new Code nodes проходят JS syntax check;
- Credential ID/credential objects удалены;
- top-level `id`, `versionId`, `meta.instanceId` удалены;
- реальный service group ID удалён;
- obvious API key / Bearer / Telegram bot token не найден.

KB-01A добавляет реальный intake `.md` через существующий единый service webhook:
1. DB-03D1 долговечно регистрирует service Telegram update;
2. только private `dokument_kb` идёт в KB;
3. whitelist user ID + private chat ID и лимит 5 MiB проверяются до скачивания;
4. служебный Telegram-бот скачивает файл;
5. фактические bytes повторно проверяются;
6. service Postgres node вызывает `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)`;
7. нормативный DB API окончательно проверяет `.md`, UTF-8, фактический размер, SHA-256, durable service event и idempotency, затем создаёт upload + knowledge job.

Парсинг YAML/Markdown, chunking, document embeddings, reference checks и publish в KB-01A намеренно не выполняются.

## Почему KB-01A ещё не `[x]`

Реальный `.md` runtime-тест ещё не выполнен. JSON не импортировался в n8n и server runtime не менялся.

Перед runtime-test Павел в n8n:
- выбирает существующий служебный Telegram Credential для Telegram нод KB-01A;
- выбирает существующий служебный Postgres Credential для `Служебный_KB_Зарегистрировать загрузку`;
- в `Настройки служебного бота` заполняет whitelist своим Telegram user ID и private chat ID.

После одного безопасного test `.md` нужно подтвердить `uspeshno`, `zagruzka_id`, `zadanie_id` и ожидающий durable knowledge job. Только после этого KB-01A можно закрыть.

## Постоянные ограничения

- Production не менять.
- Не импортировать старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json`.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до появления фактического dash_admin connection.
- Не считать наличие JSON в Git доказательством runtime.
