# Текущее состояние проекта

Обновлено: 2026-10-04.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки: 189 нод, 153 connection keys, 215 edges, `active=false`, duplicate names 0, dangling connections 0; credentials/instance ID/реальный ID служебной группы удалены. SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировать**.

## KB-01R1…R4

KB-01R1 выполнила mapping experimental KB к нормативному DB-04/DB-05. KB-01R2 выбрала recreate. KB-01R3 подготовила canonical recreate `KB-01R3 v0.2`. KB-01R4 применила его в test Supabase и structurally verified через `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`.

Подтверждено: experimental KB отсутствует; нормативные DB-04/DB-05 созданы; owners/search_path/SECURITY DEFINER/EXECUTE matrix корректны; direct runtime table DML запрещён; `vector(1024)` + HNSW и integrity triggers присутствуют. Production не менялась.

## KB-01R5A — runtime ingestion + queue VERIFIED

04.10.2026 в n8n выполнен `sql/KB-01R5A_runtime_ingestion_queue_probe.sql` через фактический Postgres Credential `qbit_test_sluzhebnyy`.

n8n вернул ожидаемую intentional error:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Это подтверждает runtime под реальным служебным Credential:
- durable service event registration;
- service-event duplicate semantics;
- knowledge upload creation;
- upload duplicate с теми же IDs;
- changed-content conflict;
- первый claim: `popytki=1`, `nomer_vladeniya=1`;
- heartbeat текущего worker;
- stale heartbeat чужого worker;
- retry;
- второй claim: `popytki=2`, `nomer_vladeniya=2`;
- stale finish старого worker;
- успешный finish текущего worker;
- после finish очередь возвращает `net_zadaniya`.

Финальный PASS exception намеренно откатил весь statement, поэтому синтетические service event/upload/job не сохранились.

## Что ещё не проверено

- version/profile/fragments/reference checks;
- draft isolation/search;
- stale/parallel publish и atomic active switch;
- bot active-only search;
- admin revoke;
- PRE-02E OpenAI embedding `dimensions=1024`.

Реальная `.md` база компании не загружалась. Client RAG не включался. Production не менялась.

## Текущая одна задача

**KB-01R5B — runtime-проверить version/profile/fragments/reference checks + draft search.**

Для DB-поведения допустимы синтетические `vector(1024)`. Фактический OpenAI embedding отдельно проверяется в PRE-02E.

Следующие этапы, не начинать автоматически:
- **KB-01R5C** — publish concurrency/active-only search/revoke;
- **PRE-02E** — фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Ограничения

- Production не изменялась.
- Старый B3 не продолжать.
- Старый KB workflow не импортировать.
- Client RAG не включать до нужных runtime-тестов.
- Experimental evidence SQL повторно не запускать.
- `sql/DB-04_05_knowledge_rollback_test.sql` теперь только аварийный rollback; после появления нужных KB-данных его нельзя запускать без отдельного плана сохранения.
