# SESSION HANDOFF

Обновлено: 2026-10-04.

## Исходная точка

Рабочая ветка: `main`.

На старте следующей сессии сначала проверить актуальный `main` HEAD и прочитать `docs/PROJECT_STATE.md` + `docs/KB-01_RECONCILIATION_PLAN.md`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

189 nodes, 153 connection keys, 215 edges, inactive, duplicate names 0, dangling connections 0. SHA-256 compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## KB-01R1…R4

R1 зафиксировал несовпадение experimental KB с нормативным DB-04/DB-05. R2 выбрал recreate. R3 подготовил canonical recreate `KB-01R3 v0.2`. R4 применил его в test Supabase и structurally verified через `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`.

Нормативный DB-04/DB-05 является live test state. Production не менялась.

## KB-01R5A — выполнено

Файл runtime-probe:

`sql/KB-01R5A_runtime_ingestion_queue_probe.sql`

Запущен в n8n Postgres node через фактический Credential `qbit_test_sluzhebnyy`.

Фактический результат:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Подтверждено:
- durable service event create + duplicate;
- knowledge upload create + duplicate;
- same event + changed bytes → conflict;
- первый claim → attempts=1, fence=1;
- heartbeat текущего worker;
- stale heartbeat чужого worker;
- retry;
- второй claim → attempts=2, fence=2;
- stale finish старого worker;
- успешный finish текущего worker;
- после finish → `net_zadaniya`.

Финальный PASS exception намеренно откатил все синтетические строки statement, поэтому cleanup вручную не нужен.

## Следующая одна задача

**KB-01R5B — version/profile/fragments/reference checks + draft search.**

Цель: runtime через фактический `qbit_test_sluzhebnyy` проверить подготовку версии, immutable profile, сохранение fragments, hash/vector/token guards, 3–10 контрольных вопросов, сохранение результатов проверок и draft-only search.

Для DB-теста использовать синтетический `vector(1024)`; не подключать OpenAI embeddings в эту задачу. PRE-02E остаётся отдельной задачей.

Не переходить автоматически к R5C.

## После R5B

- **KB-01R5C:** stale/parallel publish, atomic active switch, bot active-only search, revoke.
- **PRE-02E:** фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Запреты

**Не продолжать старый B3.**
**Не импортировать старый KB workflow.**
**Не включать client RAG до нужных runtime-тестов.**
**Не применять experimental evidence SQL повторно.**
**Не менять production.**
**Не запускать аварийный rollback после появления нужных KB-данных без отдельного плана сохранения.**
