# KB-01R4 — evidence применения и structural verification

Дата: 2026-10-04.

Контур: **только test schema `qbit_bot_pervichnogo_obrascheniya`**. Production не изменялась.

## Применение recreate

Павел запустил целиком `sql/DB-04_05_knowledge_recreate_test.sql` версии **KB-01R3 v0.2**.

Фактический итог сервера:

- `status = applied`;
- `migration = KB-01R3_v0.2`;
- `schema = qbit_bot_pervichnogo_obrascheniya`.

Это означает, что transaction COMMIT выполнен: подтверждённый experimental KB удалён, а нормативный DB-04/DB-05 создан в test schema.

## История verifier

Первый verifier использовал `SET ROLE qbit_test_sluzhebnyy` и завершился ошибкой PostgreSQL `42501 permission denied to set role`. Ошибка относилась к verifier, а не к recreate. Verifier выполнялся в read-only транзакции и не изменял DB-04/DB-05.

Чтобы не требовать членства trusted SQL-session в runtime-ролях, создан отдельный verifier:

`sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`

Он не использует `SET ROLE` / `SET SESSION AUTHORIZATION`, а проверяет effective ACL через каталоги PostgreSQL.

## Успешный verifier

Фактический итог `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`:

- `status = verified`;
- `owners_ok = true`;
- `role_switch_used = false`;
- `execute_matrix_ok = true`;
- `vector_1024_hnsw_ok = true`;
- `integrity_triggers_ok = true`;
- `public_execute_denied = true`;
- `runtime_direct_dml_denied = true`;
- `experimental_objects_absent = true`;
- `normative_tables_present_and_empty = true`;
- `security_definer_and_search_path_ok = true`;
- `runtime_execution_under_credentials_tested_here = false`.

## Что этим доказано

В test Supabase структурно подтверждены нормативные DB-04/DB-05 объекты, владельцы, ограничения доступа, HNSW/vector(1024), integrity triggers, отсутствие experimental KB и отсутствие прямого runtime DML к KB-таблицам.

## Что этим НЕ доказано

Structural verifier не заменяет runtime-тесты под фактическими Postgres Credentials. Пока не проверены в реальном исполнении:

- service ingestion + duplicate semantics;
- knowledge queue claim/lease/fencing/retry;
- version/profile/fragments/reference checks;
- draft-only search;
- stale/parallel publish и atomic active switch;
- bot active-only search;
- admin revoke;
- фактический OpenAI embedding `dimensions=1024` по PRE-02E.

Реальная `.md` база компании не загружалась, client RAG не включался, старый experimental workflow не импортировался.
