# KB-01R — сверка и исправление experimental KB → нормативный DB-04/DB-05

Статус: **reconciliation применена и structurally verified в test; следующий этап — runtime validation**.

## Исходное расхождение

03.10.2026 в test schema `qbit_bot_pervichnogo_obrascheniya` были экспериментально созданы три KB-таблицы и две SECURITY DEFINER-функции B1/B2. После сверки выяснилось, что промежуточный контракт не совпадает с нормативным DB-04/DB-05.

Старый локально сгенерированный workflow `Шаблон_мультиканальный_KB-01_v0.3.json` под этот API не является каноническим и не импортируется.

## KB-01R1 — inventory + mapping — **ГОТОВО**

Результат: `docs/KB-01R1_INVENTORY_MAPPING.md`.

Подтверждено структурное несовпадение experimental и нормативной моделей; B3 поверх B1/B2 продолжать нельзя.

## KB-01R2 — выбор пути — **ГОТОВО**

Live read-only verifier подтвердил нулевые row counts и отсутствие дополнительных KB-объектов. Выбран путь **recreate**, а не migration-on-place.

Решение: `docs/KB-01R2_DECISION.md`.

## KB-01R3 — подготовка recreate — **ГОТОВО**

Подготовлены:

1. `sql/DB-04_05_knowledge_recreate_test.sql` — canonical **KB-01R3 v0.2**.
2. `sql/DB-04_05_knowledge_rollback_test.sql` — guarded emergency rollback.
3. исходные verifier-файлы и отдельный verifier без role switching.
4. `docs/KB-01R3_RECREATE_ROLLBACK.md` — порядок применения и отката.

## KB-01R4 — test apply + structural verifier — **ГОТОВО**

04.10.2026 recreate v0.2 применён в test Supabase.

Server result:
- `status=applied`;
- `migration=KB-01R3_v0.2`;
- schema `qbit_bot_pervichnogo_obrascheniya`.

Первый verifier с `SET ROLE` выявил только ограничение trusted SQL-session: `postgres` не может `SET ROLE qbit_test_sluzhebnyy`. Сам DB-04/DB-05 к этому моменту уже был committed.

Финальная structural проверка выполнена отдельным файлом:

`sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`

Результат `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`:
- `status=verified`;
- experimental objects absent;
- normative tables present and empty;
- owners/SECURITY DEFINER/search_path OK;
- PUBLIC EXECUTE denied;
- runtime direct table DML denied;
- EXECUTE matrix OK;
- vector(1024) + HNSW OK;
- integrity triggers OK;
- role switching не использовался.

Evidence: `docs/evidence/KB-01/KB-01R4_APPLIED_VERIFIED_2026-10-04.md`.

## Reconciliation result

Structural reconciliation experimental KB → normative DB-04/DB-05 **завершена**. Старые experimental B1/B2 и таблицы больше не являются live test-состоянием.

Это не означает полного runtime завершения KB-01: verifier не выполнял API через фактические n8n Credentials и не проверял OpenAI embeddings.

## KB-01R5 — runtime validation

Чтобы не делать один большой тест, runtime validation разделяется на три небольшие задачи.

### KB-01R5A — **СЛЕДУЮЩАЯ ЗАДАЧА**

Проверить под фактическим Credential `qbit_test_sluzhebnyy`:
- регистрацию синтетической `.md` загрузки;
- duplicate и conflict semantics;
- claim knowledge job;
- lease heartbeat;
- fencing/stale worker;
- retry/finish semantics.

Тест не включает embeddings, publish или client RAG. Синтетические данные должны быть удалены/откачены по заранее определённому test-сценарию, не ручным произвольным DELETE.

### KB-01R5B — после R5A

Version/profile/fragments/reference checks + draft-only search. Для DB-поведения допустимы синтетические vector(1024); фактический OpenAI embedding проверяется отдельно PRE-02E.

### KB-01R5C — после R5B

Stale/parallel publish, atomic active switch, bot active-only search и dash_admin revoke.

## Отдельная зависимость PRE-02E

Фактическая длина embedding `text-embedding-3-large` с `dimensions=1024` должна быть подтверждена в каноническом OpenAI workflow. Structural DB verifier этого не доказывает.

## Постоянные ограничения

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG до необходимых runtime-тестов;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не использовать аварийный KB rollback после появления нужных данных без отдельного плана сохранения.
