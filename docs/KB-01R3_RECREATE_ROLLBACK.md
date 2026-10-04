# KB-01R3 — применение и откат DB-04/DB-05 recreate

Дата подготовки: 2026-10-03. Фактическое применение: 2026-10-04.

Статус: **recreate v0.2 применён в test и structurally verified; rollback не требуется**.

## Файлы

1. `sql/DB-04_05_knowledge_recreate_test.sql` — canonical **KB-01R3 v0.2**.
2. `sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql` — фактически успешно использованный structural verifier.
3. `sql/DB-04_05_knowledge_rollback_test.sql` — только аварийный rollback к состоянию «KB отсутствует», пока новые KB-таблицы пустые и нет нужных данных.

## Фактическое применение

04.10.2026 Павел запустил recreate v0.2 целиком в test Supabase.

Server result:
- `status=applied`;
- `migration=KB-01R3_v0.2`;
- schema `qbit_bot_pervichnogo_obrascheniya`.

Транзакция закоммичена. Experimental B1/B2 и три experimental таблицы удалены, нормативный DB-04/DB-05 создан.

## Structural verification

Первый вариант verifier пытался `SET ROLE qbit_test_sluzhebnyy` и получил `42501`, так как trusted SQL-session не имеет membership этой runtime-роли. Это не было ошибкой recreate и не меняло DB-04/DB-05.

Для проверки без role switching использован:

`sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`

Результат `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`:
- `status=verified`;
- normative tables present and empty;
- experimental objects absent;
- owners OK;
- SECURITY DEFINER/search_path OK;
- PUBLIC EXECUTE denied;
- direct runtime DML denied;
- EXECUTE matrix OK;
- vector(1024) + HNSW OK;
- integrity triggers OK.

Подробное evidence: `docs/evidence/KB-01/KB-01R4_APPLIED_VERIFIED_2026-10-04.md`.

## Что делал recreate v0.2

В одной транзакции recreate:
- сверил live experimental state, fingerprints и `row_counts=0`;
- без `CASCADE` удалил только подтверждённые experimental объекты;
- создал восемь нормативных DB-04 таблиц;
- добавил FK `ishodyashchie_deystviya.zagruzka_id → zagruzki_znaniy.id`;
- создал ingestion queue/lease/fencing API;
- создал version/profile/fragments/reference-check API;
- создал DB-05 draft search, active-only bot search, atomic publish и admin revoke;
- отозвал прямой table DML у runtime-ролей и выдал точечный EXECUTE;
- выполнил structural self-check до COMMIT.

## Rollback

До COMMIT recreate был транзакционным: ошибка откатывала и DROP, и CREATE автоматически.

После успешного COMMIT `sql/DB-04_05_knowledge_rollback_test.sql` остаётся только аварийной мерой. На момент successful verifier новые KB-таблицы были пустыми, поэтому guarded rollback технически ещё мог бы пройти, но оснований его запускать нет.

Как только runtime-тесты или реальные загрузки создадут данные, автоматический rollback нельзя использовать без отдельного плана сохранения. Сам rollback обязан остановиться, если обнаружит данные/ссылки.

Он не восстанавливает experimental B1/B2: эти объекты признаны неканоническими.

## Что ещё нужно доказать отдельно

Structural verification не является runtime verification. Следующие этапы должны проверить функции под реальными Credentials:
- ingestion + duplicate/conflict;
- queue lease/fencing/retry;
- version/profile/fragments/checks;
- draft isolation;
- publish concurrency/active switch;
- active-only bot search;
- admin revoke.

PRE-02E также отдельно должен подтвердить фактический OpenAI embedding `dimensions=1024`.

## Ограничения

- Production schema `qbit` и production roles не изменялись.
- Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.
- Старый B3 не продолжать.
- Client RAG не включать до необходимых runtime-тестов.
