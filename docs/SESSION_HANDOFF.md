# SESSION HANDOFF

Обновлено: 2026-10-03.

## Исходная точка

Ветка: `main`.

Checkpoint до KB-01R1:
`bb729507ba1ccfc33e2a93c009b37fd3010df191` — `checkpoint KB-01 state and current workflow`.

Новая сессия сначала проверяет актуальный `main` HEAD и читает `docs/KB-01_RECONCILIATION_PLAN.md`.

## Workflow

Последний фактический workflow Павла сохранён как точный очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

До упаковки проверено:
- 189 nodes;
- 153 connection keys;
- 215 edges;
- inactive;
- duplicate names 0;
- dangling connections 0;
- Credentials / instance ID / реальный ID служебной группы удалены.

SHA-256 compact JSON:
`ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Восстановление:
`python tools/restore_workflow_checkpoint.py`.

Старый canonical `версия 0.2.json` удалён из текущего дерева Git.

## KB-01 — фактическое состояние checkpoint

В test schema существуют experimental:
- `znaniya_dokumenty`;
- `znaniya_versii`;
- `znaniya_fragmenty`.

B1 `kb01_postavit_dokument(jsonb)` VERIFIED настоящей ролью `qbit_test_sluzhebnyy`:
- first → `uspeshno`, `ozhidaet`;
- repeat same idempotency key → `dublikat`;
- IDs совпали;
- runtime test → `ROLLBACK`.

B2 `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)` VERIFIED:
- first worker → `v_rabote`;
- `nomer_vladeniya=1`;
- `popytki=1`;
- second worker → `net_zadaniya`;
- runtime test → `ROLLBACK`.

Production не затрагивалась.

## KB-01R1 — выполнено

Read-only/documentary mapping сохранён в:
[KB-01R1_INVENTORY_MAPPING](KB-01R1_INVENTORY_MAPPING.md).

Сопоставление показало:
- `znaniya_dokumenty` — частичное соответствие `dokumenty_znaniy`;
- `znaniya_versii` смешивает загрузку, durable job, версию и часть index profile;
- `znaniya_fragmenty` — частичное соответствие `fragmenty_znaniy`;
- нормативные `kontrolnye_voprosy`, `proverki_znaniy` отсутствуют;
- нормативные draft/active search, atomic publish и revoke отсутствуют;
- B1/B2 нельзя продолжать через B3 как готовую основу DB-04/DB-05.

Во время KB-01R1 SQL на сервер не выполнялся. Прямого DB-доступа в сессии не было, поэтому mapping основан на checkpoint/evidence 03.10.2026, а не на новом live `pg_catalog` snapshot.

## Следующая одна задача

**KB-01R2 — выбрать безопасный путь migration vs recreate.**

Перед решением:
- перечитать `docs/KB-01R1_INVENTORY_MAPPING.md`;
- при необходимости получить только read-only row counts/object signatures test schema;
- не считать experimental таблицы пустыми без проверки;
- не применять DDL/DML и не удалять объекты до выбора пути;
- production не менять.

После выбора пути отдельной задачей KB-01R3 подготовить полный SQL, проверки и rollback-план. Не начинать KB-01R3 автоматически в той же сессии, если Павел поручил только KB-01R2.

## Запреты остаются

**Не импортировать** `Шаблон_мультиканальный_KB-01_v0.3.json`.
**Не продолжать B3**.
**Не включать client RAG**.
**Не применять evidence SQL повторно**.

## Evidence

- [KB-01_APPLIED_TEST_STATE_2026-10-03](KB-01_APPLIED_TEST_STATE_2026-10-03.md)
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_tables_2026-10-03.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B1_v0.9.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B2_v0.10.sql`

Эти SQL сохранены только как доказательство test-истории. Их не запускать повторно.
