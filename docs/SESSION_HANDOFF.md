# SESSION HANDOFF

Обновлено: 2026-10-04.

## Исходная точка

Рабочая ветка: `main`.

На старте новой сессии сначала проверить актуальный `main` HEAD и прочитать `docs/PROJECT_STATE.md` + `docs/KB-01_RECONCILIATION_PLAN.md`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

189 nodes, 153 connection keys, 215 edges, inactive, duplicate names 0, dangling connections 0. SHA-256 compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## KB-01R1/R2/R3

R1 зафиксировал несовпадение experimental KB с нормативным DB-04/DB-05. R2 live read-only проверка подтвердила пустые experimental таблицы и выбрала recreate. R3 подготовил canonical recreate `KB-01R3 v0.2`, verifier и rollback.

## KB-01R4 — выполнено

04.10.2026 Павел применил в test Supabase:

`sql/DB-04_05_knowledge_recreate_test.sql`

Фактический результат:
- `status=applied`;
- `migration=KB-01R3_v0.2`;
- schema `qbit_bot_pervichnogo_obrascheniya`.

После COMMIT experimental B1/B2 и три experimental KB-таблицы больше не являются live state; создан нормативный DB-04/DB-05.

Первые verifier-попытки упирались в `SET ROLE qbit_test_sluzhebnyy` (`42501`), потому что trusted SQL-session не является членом runtime-роли. DB-04/DB-05 из-за этого не менялся.

Успешная structural проверка выполнена файлом:

`sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`

Результат:
- `status=verified`;
- `verifier_version=KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`;
- `experimental_objects_absent=true`;
- `normative_tables_present_and_empty=true`;
- `owners_ok=true`;
- `security_definer_and_search_path_ok=true`;
- `public_execute_denied=true`;
- `runtime_direct_dml_denied=true`;
- `execute_matrix_ok=true`;
- `vector_1024_hnsw_ok=true`;
- `integrity_triggers_ok=true`;
- `role_switch_used=false`;
- `runtime_execution_under_credentials_tested_here=false`.

Evidence:
`docs/evidence/KB-01/KB-01R4_APPLIED_VERIFIED_2026-10-04.md`.

## Фактическое состояние test DB сейчас

- Нормативный DB-04/DB-05 создан и structurally verified.
- Восемь новых KB-таблиц на момент verifier пустые.
- Experimental KB отсутствует.
- Прямой DML/SELECT runtime-ролей к KB-таблицам запрещён.
- EXECUTE matrix структурно подтверждена.
- Production не менялась.

## Следующая одна задача

**KB-01R5A — runtime ingestion + knowledge queue через реальный Credential `qbit_test_sluzhebnyy`.**

Цель:
1. зарегистрировать только синтетическую test `.md` загрузку через `zaregistrirovat_zagruzku_znaniy`;
2. проверить same-event duplicate и changed-content conflict;
3. claim job через `zabrat_zadanie_znaniy`;
4. проверить heartbeat lease;
5. проверить fencing/stale worker;
6. проверить retry/finish semantics;
7. завершить тест в заранее контролируемом состоянии без перехода к embeddings/publish.

Это должна быть одна небольшая runtime-задача. Не переходить автоматически к R5B/R5C.

## После R5A

- **KB-01R5B:** version/profile/fragments/reference checks + draft search.
- **KB-01R5C:** stale/parallel publish, atomic active switch, active-only bot search, revoke.
- **PRE-02E:** отдельно подтвердить фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Запреты

**Не продолжать старый B3.**
**Не импортировать старый KB workflow.**
**Не включать client RAG до нужных runtime-тестов.**
**Не применять experimental evidence SQL повторно.**
**Не менять production.**
**Не запускать аварийный rollback после появления нужных KB-данных без отдельного плана сохранения.**
