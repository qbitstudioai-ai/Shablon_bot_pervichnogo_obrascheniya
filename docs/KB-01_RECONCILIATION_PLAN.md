# KB-01R — сверка experimental KB → нормативный DB-04/DB-05

Статус: **завершена для текущего bot/service test-контура. Активная реализация перешла в `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.**

## Итог KB-01R

### KB-01R1 — inventory + mapping — ГОТОВО

Зафиксировано структурное несовпадение experimental и нормативных DB-04/DB-05; старый B3 поверх B1/B2 продолжать нельзя.

### KB-01R2 — recreate decision — ГОТОВО

Live read-only inventory подтвердил безопасное исходное состояние; выбран recreate.

### KB-01R3 — canonical recreate — ГОТОВО

Подготовлены canonical recreate, guarded rollback и verifier.

### KB-01R4 — test apply + structural verifier — ГОТОВО

04.10.2026 нормативные DB-04/DB-05 созданы в test schema. Проверены owners, SECURITY DEFINER/search_path, EXECUTE matrix, запрет direct runtime DML, `vector(1024)`, HNSW и integrity guards.

### KB-01R5A — ingestion + knowledge queue — ГОТОВО

Runtime через фактический `qbit_test_sluzhebnyy` подтвердил durable service event, upload create/duplicate/conflict, claim, heartbeat, retry, fencing/stale worker и finish.

### KB-01R5B — version/profile/fragments/reference checks + draft search — ГОТОВО

Runtime подтвердил:
- version/profile/fragments;
- dimension/profile/hash guards;
- 3–10 reference checks;
- draft-only service search;
- отсутствие service доступа к active client search.

Backward-compatible test patch разрешает `sohranit_proverki_znaniy` принимать `vopros_id` или `nomer_voprosa`.

### KB-01R5C — publish concurrency + active-only bot search — ГОТОВО

Runtime подтвердил:
- V1 publish;
- competing V2/V3;
- V2 atomic active switch;
- stale V3 conflict;
- V1 archive;
- bot видит только active V2;
- archive/draft скрыты.

Синтетические данные удалены guarded cleanup. Production не затрагивалась.

Evidence: `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`.

### KB-01R5D — dash_admin revoke — ОТЛОЖЕНО

Отдельный `qbit_test_dash_admin` Credential пока не создавался. Structural EXECUTE matrix проверена в R4; фактический runtime revoke будет отдельной задачей dashboard stage.

## Что изменилось после завершения reconciliation

Старые строки `[ ] DB-04` / `[ ] DB-05` в `WORKPLAN_TEMPLATE.md` отстают и не являются фактическим состоянием.

Отдельный PRE-02E smoke отменён как самостоятельная задача. OpenAI `text-embedding-3-large` с `dimensions=1024` должен быть фактически проверен на document embeddings внутри канонического workflow в `KB-03A`.

Текущий активный план:

`docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`

Текущий ID:

`KB-01A`.

## Постоянные ограничения

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не запускать `sql/KB-01R5C_service_publish_prepare.sql`;
- не использовать аварийный KB rollback после появления нужных данных без отдельного плана сохранения.
