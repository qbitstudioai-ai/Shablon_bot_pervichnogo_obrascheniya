# SESSION HANDOFF

Обновлено: 2026-10-03.

## Исходная точка

Ветка: `main`.

До checkpoint HEAD был:
`13badcd14d709e0d8696cdc2fec46fee2e94650e` — `WF-02B3C replace polling with event-driven workers`.

Новая сессия сначала проверяет актуальный HEAD после checkpoint.

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

## KB-01 — фактическое состояние

В test schema существуют экспериментальные:
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

## Обнаруженное расхождение

Экспериментальная модель не соответствует нормативному DB-04/DB-05 и `KNOWLEDGE_INGESTION`:
- норматив v1 принимает только `.md` UTF-8 до 5 MiB;
- норматив различает загрузку, очередь, документ, версию, профиль, фрагменты, контрольные вопросы и проверки;
- ранее generated KB workflow собран под другой промежуточный API;
- B1/B2 фактически возвращают `jsonb`;
- B3/publish/error/search отсутствуют.

**Не импортировать** `Шаблон_мультиканальный_KB-01_v0.3.json`.
**Не продолжать B3** до KB-01R.

## Следующая одна задача

Открыть [KB-01_RECONCILIATION_PLAN](KB-01_RECONCILIATION_PLAN.md) и выполнить только **KB-01R1**: read-only инвентаризация текущих experimental KB objects и mapping к нормативному DB-04/DB-05.

Не удалять test KB-объекты, не применять новую миграцию и не менять production без отдельного решения.

## Evidence

- [KB-01_APPLIED_TEST_STATE_2026-10-03](KB-01_APPLIED_TEST_STATE_2026-10-03.md)
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_tables_2026-10-03.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B1_v0.9.sql`
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B2_v0.10.sql`

Эти SQL сохранены только как доказательство test-истории. Их не запускать повторно.
