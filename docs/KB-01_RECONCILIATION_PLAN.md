# KB-01R — сверка и исправление experimental KB → нормативный DB-04/DB-05

Статус: **reconciliation применена; structural verification и runtime R5A завершены; следующий этап — KB-01R5B**.

## KB-01R1 — inventory + mapping — ГОТОВО

Зафиксировано структурное несовпадение experimental и нормативной моделей; старый B3 поверх B1/B2 продолжать нельзя.

## KB-01R2 — выбор пути — ГОТОВО

Live read-only verifier подтвердил нулевые row counts и отсутствие дополнительных KB-объектов. Выбран путь **recreate**.

## KB-01R3 — подготовка recreate — ГОТОВО

Подготовлены canonical recreate `KB-01R3 v0.2`, guarded rollback и verifier.

## KB-01R4 — test apply + structural verifier — ГОТОВО

04.10.2026 recreate v0.2 применён в test Supabase. Финальная structural проверка выполнена `sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`.

Подтверждено: experimental objects absent; нормативные таблицы присутствуют; owners/SECURITY DEFINER/search_path и EXECUTE matrix корректны; direct runtime table DML запрещён; `vector(1024)` + HNSW и integrity triggers присутствуют.

## KB-01R5 — runtime validation

### KB-01R5A — ingestion + knowledge queue — ГОТОВО

04.10.2026 выполнен `sql/KB-01R5A_runtime_ingestion_queue_probe.sql` в n8n Postgres node через фактический Credential `qbit_test_sluzhebnyy`.

Ожидаемый итог:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Runtime подтверждены:
- durable service event registration и duplicate semantics;
- knowledge upload create/duplicate/conflict;
- claim;
- heartbeat;
- stale worker rejection;
- retry;
- повторный claim с увеличением attempts и fencing;
- stale finish старого worker;
- finish текущего worker;
- `net_zadaniya` после finish.

Финальный intentional exception откатил все синтетические строки этого statement.

### KB-01R5B — СЛЕДУЮЩАЯ ЗАДАЧА

Проверить под фактическим `qbit_test_sluzhebnyy`:
- `podgotovit_versiyu_znaniy`;
- immutable index profile semantics;
- batch `sohranit_fragmenty_znaniy`;
- fragment hash/vector dimension/token checks;
- `sohranit_kontrolnye_voprosy`;
- `sohranit_proverki_znaniy`;
- draft-only `poisk_chernovika_znaniy`;
- изоляцию draft от active/client search.

Для DB runtime допустим синтетический `vector(1024)`. Фактический OpenAI embedding отдельно проверяется PRE-02E.

### KB-01R5C — после R5B

Stale/parallel publish, atomic active switch, bot active-only search и dash_admin revoke.

## Отдельная зависимость PRE-02E

Фактическая длина embedding `text-embedding-3-large` с `dimensions=1024` должна быть подтверждена в каноническом OpenAI workflow. DB runtime с синтетическим vector этого не заменяет.

## Постоянные ограничения

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG до необходимых runtime-тестов;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не использовать аварийный KB rollback после появления нужных данных без отдельного плана сохранения.
