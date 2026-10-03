# KB-01R — сверка и исправление experimental KB → нормативный DB-04/DB-05

Статус: **reconciliation preparation завершена; следующий шаг — test application KB-01R4**.

## Исходное расхождение

03.10.2026 в test schema `qbit_bot_pervichnogo_obrascheniya` были экспериментально созданы три KB-таблицы и две SECURITY DEFINER-функции B1/B2. После сверки выяснилось, что этот промежуточный контракт не совпадает с нормативным DB-04/DB-05: норматив разделяет загрузку, durable queue, документ, версию, profile, fragments, контрольные вопросы и проверки, а DB-05 отдельно задаёт draft/active search, atomic publish и revoke.

Старый локально сгенерированный workflow `Шаблон_мультиканальный_KB-01_v0.3.json` под этот промежуточный API не является каноническим и не импортируется.

## KB-01R1 — inventory + mapping — **ГОТОВО**

Результат: `docs/KB-01R1_INVENTORY_MAPPING.md`.

Подтверждено, что:
- `znaniya_dokumenty` только частично соответствует `dokumenty_znaniy`;
- `znaniya_versii` смешивает upload/job/version/profile concerns;
- `znaniya_fragmenty` только частично соответствует нормативному fragment;
- значительная часть DB-04/DB-05 отсутствует;
- B3 нельзя продолжать поверх B1/B2.

## KB-01R2 — выбор пути — **ГОТОВО**

Read-only live verifier `KB-01R2_READ_ONLY_v0.1` подтвердил:
- `znaniya_dokumenty` = 0;
- `znaniya_versii` = 0;
- `znaniya_fragmenty` = 0;
- active/leased/error/fragmented = 0;
- найдено ровно три experimental KB-таблицы и две B1/B2 функции;
- дополнительных KB-объектов нет;
- runtime service role не имеет прямого table DML/SELECT.

Выбран путь **recreate**. Решение: `docs/KB-01R2_DECISION.md`.

## KB-01R3 — подготовка реализации recreate — **ГОТОВО К ОТДЕЛЬНОМУ ПРИМЕНЕНИЮ**

Подготовлены:

1. `sql/DB-04_05_knowledge_recreate_test.sql` — **KB-01R3 v0.2**.
2. `sql/DB-04_05_knowledge_verifier.sql` — **KB-01R3_VERIFIER v0.2**, READ ONLY.
3. `sql/DB-04_05_knowledge_rollback_test.sql` — guarded emergency rollback, только пока новые KB-таблицы пустые.
4. `docs/KB-01R3_RECREATE_ROLLBACK.md` — порядок применения и отката.

Recreate SQL содержит:
- preflight до destructive-части: test schema/owner, DB-03 prerequisites, pgvector/digest, точный experimental object set, `row_counts=0`, fingerprints B1/B2, отсутствие уже созданного нормативного DB-04;
- DROP только подтверждённых experimental объектов, без `CASCADE`;
- восемь нормативных DB-04 таблиц и необходимые FK/indexes/HNSW;
- `zaregistrirovat_zagruzku_znaniy`, knowledge queue claim/lease/finish, version/profile/fragments/check functions;
- DB-05 draft search, active-only bot search, atomic publish и admin revoke;
- точечную EXECUTE matrix и отсутствие direct runtime table DML;
- structural self-check до COMMIT.

Каноническая v0.2 дополнительно устранила технические риски первичной сборки: нет широкого revoke чужих sequences, PL/pgSQL conflict resolution зафиксирован, service-event repeats сверяются по content/metadata, queue учитывает active job того же document, profile fingerprint проверяет chunking параметры, fragment hash пересчитывается в БД.

**Факт:** KB-01R3 подготовила файлы в GitHub. Никакой KB-01R3 SQL на сервер в этой задаче не запускался.

## KB-01R4 — test apply + structural verifier — **СЛЕДУЮЩАЯ ЗАДАЧА**

После явной команды Павла на этот server-step:

1. проверить актуальный `main` HEAD;
2. запустить целиком `sql/DB-04_05_knowledge_recreate_test.sql` только в test Supabase;
3. принять только итог `status=applied`, `migration=KB-01R3_v0.2`;
4. до каких-либо n8n/KB действий запустить целиком `sql/DB-04_05_knowledge_verifier.sql`;
5. принять только `status=verified`, `verifier_version=KB-01R3_VERIFIER_v0.2`;
6. при verifier failure и пустых новых таблицах использовать только подготовленный rollback-план; не импровизировать с DROP.

KB-01R4 не включает импорт n8n workflow, первую реальную загрузку документа или client RAG.

## После KB-01R4

Отдельными задачами нужны runtime-проверки DB-04/DB-05: очередь/lease/fencing, duplicate semantics, fragments/profile, draft isolation, stale publish, atomic active switch, active-only search, revoke, а также фактическое подтверждение PRE-02E embedding dimension 1024.

## Постоянные запреты до applied + verified

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не считать подготовленный GitHub SQL применённым без server result.

## Критерий reconciliation preparation

1. mapping experimental → normative — **готово KB-01R1**;
2. выбран migration/recreate — **готово KB-01R2: recreate**;
3. полный recreate SQL + verifier + rollback — **готово KB-01R3**;
4. следующий server-step однозначен — **KB-01R4**.
