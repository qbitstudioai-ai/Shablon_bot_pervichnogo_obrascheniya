# SESSION HANDOFF

Обновлено: 2026-10-03.

## Исходная точка

Рабочая ветка: `main`.

Checkpoint до KB-01R:
`bb729507ba1ccfc33e2a93c009b37fd3010df191` — `checkpoint KB-01 state and current workflow`.

KB-01R1 и KB-01R2 выполнены после checkpoint. Новая сессия сначала проверяет актуальный `main` HEAD и читает `docs/KB-01_RECONCILIATION_PLAN.md`.

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

## KB-01 — фактическое experimental состояние

В test schema существуют experimental:
- `znaniya_dokumenty`;
- `znaniya_versii`;
- `znaniya_fragmenty`.

B1 `kb01_postavit_dokument(jsonb)` VERIFIED настоящей ролью `qbit_test_sluzhebnyy`.
B2 `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)` VERIFIED с lease/fencing.

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

## KB-01R2 — выполнено

Read-only live verifier:

`docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`

Результат 03.10.2026:
- `znaniya_dokumenty` = 0 строк;
- `znaniya_versii` = 0 строк;
- `znaniya_fragmenty` = 0 строк;
- active/leased/error/fragmented counts = 0;
- найдены ровно три experimental KB-таблицы;
- найдены ровно две функции B1/B2;
- дополнительных KB-таблиц/функций verifier не обнаружил;
- у `qbit_test_sluzhebnyy` нет прямых `SELECT/INSERT/UPDATE/DELETE` на этих таблицах.

Выбран путь: **recreate**.

Причина: данных для миграции нет, а experimental-модель структурно несовместима с нормативным DB-04/DB-05. Переделка на месте добавила бы переходные состояния и риск без полезной цели.

Решение подробно: [KB-01R2_DECISION](KB-01R2_DECISION.md).

Важно: KB-01R2 только выбрала путь. Experimental объекты ещё не удалялись; нормативный DB-04/DB-05 ещё не применялся.

## Следующая одна задача

**KB-01R3 — подготовить полный test-only recreate SQL, verifier и rollback-план для нормативного DB-04/DB-05.**

Обязательная база:
- `docs/KB-01R1_INVENTORY_MAPPING.md`;
- `docs/KB-01R2_DECISION.md`;
- `docs/specs/DB_CONTRACT.md`;
- `docs/specs/KNOWLEDGE_INGESTION.md`;
- `docs/specs/MARKDOWN_FORMAT.md`;
- действующие правила access/isolation и naming.

KB-01R3 должна подготовить полный файл, а не фрагменты. В начале destructive-части нужны защитные проверки live signatures и `row_counts=0`; при несовпадении SQL должен остановиться до удаления.

Сам SQL не применять автоматически в ходе подготовки. Применение и runtime verification должны быть явно отделены от факта создания файла.

## Запреты остаются

**Не импортировать** `Шаблон_мультиканальный_KB-01_v0.3.json`.
**Не продолжать B3**.
**Не включать client RAG**.
**Не применять experimental evidence SQL повторно**.
**Не менять production**.

## Evidence

- [KB-01_APPLIED_TEST_STATE_2026-10-03](KB-01_APPLIED_TEST_STATE_2026-10-03.md)
- [KB-01R1_INVENTORY_MAPPING](KB-01R1_INVENTORY_MAPPING.md)
- [KB-01R2_DECISION](KB-01R2_DECISION.md)
- `docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_tables_2026-10-03.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B1_v0.9.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B2_v0.10.sql`

Experimental SQL сохранён только как доказательство test-истории. Его не запускать повторно.
