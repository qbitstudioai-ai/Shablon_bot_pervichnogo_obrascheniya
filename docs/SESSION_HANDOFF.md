# SESSION HANDOFF

Обновлено: 2026-10-07.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B и KB-03A завершены и runtime-проверены.

KB-03B при подготовке разделена на две постоянные подзадачи:
- **KB-03B0** — TEST DB bridge для получения `vopros_id` сохранённых reference questions под live lease/fencing;
- **KB-03B1** — workflow question embeddings → draft-only search → deterministic checks → save checks.

Текущая маленькая задача — **KB-03B0**.

Перед продолжением проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/KB-03B_IMPLEMENTATION_PLAN.md`;
6. `sql/KB-03B0_question_ids_bridge_test.sql`;
7. `docs/specs/KNOWLEDGE_INGESTION.md`;
8. `docs/specs/DB_CONTRACT.md` — reference-question/search/check contract;
9. `docs/specs/PROCESSING_PROFILE.md` — OpenAI embedding/retrieval profile.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore:
`python tools/restore_workflow_checkpoint.py`

SHA-256 старого checkpoint:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**:
`Шаблон — мультиканальный бот и служебный Telegram — версия 0.11 KB-03A.json`

SHA-256:
`54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`.

OpenAI Credential подключается только в n8n UI. Credential/API key не должен попадать в export/Git. Отдельный Git-checkpoint v0.11 ещё не сохранён.

## Доказанный runtime до текущей задачи

### KB-03A
Успешный live-run на safe документе:
- fence `5`;
- 6 exact fragments;
- one OpenAI batch;
- `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
- usage 910 input tokens;
- vectors 6, dimension min/max 1024/1024;
- all values finite;
- exact fragment input + mapping by API index confirmed;
- generative LLM 0;
- `sohranit_fragmenty_znaniy` → `uspeshno`;
- `sohraneno_fragmentov=6`, `vsego_fragmentov=6`;
- version remains `chernovik`;
- reference questions not embedded/saved;
- publish false;
- job → `povtor`.

Evidence: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.

## Почему нужен KB-03B0

`sohranit_kontrolnye_voprosy(jsonb)` возвращает только количество вопросов. `sohranit_proverki_znaniy(jsonb)` требует настоящий `vopros_id`. Прямой SELECT таблицы служебной роли запрещён. Поэтому workflow нельзя корректно завершить без узкого DB API для ID.

Подготовлен файл:
`sql/KB-03B0_question_ids_bridge_test.sql`

Локальный SHA-256 подготовленного SQL:
`7e0579221b6f4974f686639d24e5f3900d8068989f6f51a64369e82de9448919`.

Файл создаёт только в TEST:
`qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)`.

Функция требует текущие `zadanie_id`, `worker_id`, `nomer_vladeniya`, `versiya_id`, проверяет live lease/fencing и выдаёт только 3–10 вопросов своей версии. PUBLIC/bot execute запрещены, service получает только EXECUTE; прямой table SELECT не выдаётся.

## Действие Павла для KB-03B0

Запустить **весь** `sql/KB-03B0_question_ids_bridge_test.sql` trusted postgres session в TEST. Ничего из файла не выполнять по частям.

Ожидаемые финальные результаты:
- smoke: `smoke_result=otkaz`, `smoke_kod=nekorrektnyy_vhod`;
- `kb03b0_result.kb03b0_status=verified`;
- `service_execute=true`;
- `bot_execute=false`;
- `public_execute=false`;
- `direct_service_select_questions=false`;
- `production_untouched=true`;
- `next_stage=KB-03B1_workflow`.

До такого результата **не** считать bridge применённым и не запускать KB-03B1.

## KB-03B1 после bridge

После verified B0 сразу подготовить workflow поверх v0.11, но не повторять document embeddings без необходимости. Путь B1:

`claim/parser/A1/A2/B → prepare draft/version → save canonical questions → bridge IDs → one batch OpenAI question embeddings → strict vectors → draft-only top-12 search → фактическая threshold grid 0.45..0.85 → deterministic expected path/fact checks → sohranit_proverki_znaniy → gotova only on full pass`.

Reference checks не используют generative LLM и не публикуют версию.

## Guard по нагрузке на LLM

- parsing/cleaning/chunking/token counting — без generative LLM;
- embeddings — индексные/поисковые операции, не генерация ответа;
- question embeddings B1 — один batch на 3–10 вопросов;
- draft search — PostgreSQL/pgvector;
- client runtime по-прежнему query embedding → vector search → небольшой evidence package → финальная LLM;
- candidate top-k = 12, final evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы.

## Следующая задача после KB-03B1

`KB-03C` — atomic publish + active-only end-to-end regression.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.