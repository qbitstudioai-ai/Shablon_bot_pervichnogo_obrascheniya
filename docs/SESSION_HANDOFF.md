# SESSION HANDOFF

Обновлено: 2026-10-03.

## Исходная точка

Рабочая ветка: `main`.

Checkpoint до reconciliation:
`bb729507ba1ccfc33e2a93c009b37fd3010df191` — `checkpoint KB-01 state and current workflow`.

KB-01R1, KB-01R2 и подготовка KB-01R3 выполнены после checkpoint. Новая сессия сначала проверяет актуальный `main` HEAD и читает `docs/PROJECT_STATE.md` + `docs/KB-01_RECONCILIATION_PLAN.md`.

## Workflow

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

189 nodes, 153 connection keys, 215 edges, inactive, duplicate names 0, dangling connections 0. SHA-256 compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Experimental KB live state перед recreate

KB-01R2 read-only verifier 03.10.2026 подтвердил в test schema:
- `znaniya_dokumenty` = 0 строк;
- `znaniya_versii` = 0 строк;
- `znaniya_fragmenty` = 0 строк;
- active/leased/error/fragmented = 0;
- ровно три experimental tables;
- ровно две functions B1/B2;
- B1 definition md5 `56654d3112113f99acda41df4a53b8e8`;
- B2 definition md5 `4ea8ce93b420723239fbe6fabec868ed`;
- service role не имеет direct table DML/SELECT.

Решение KB-01R2: **recreate**.

## KB-01R3 — подготовлено, но не applied

Canonical files в `main`:

- `sql/DB-04_05_knowledge_recreate_test.sql` — **KB-01R3 v0.2**;
- `sql/DB-04_05_knowledge_verifier.sql` — **KB-01R3_VERIFIER v0.2**;
- `sql/DB-04_05_knowledge_rollback_test.sql` — rollback только пока новые KB tables пустые;
- `docs/KB-01R3_RECREATE_ROLLBACK.md` — применение/rollback.

Recreate v0.2 перед DROP повторно проверяет live state, fingerprints и `row_counts=0`; при расхождении останавливается. DROP выполняется без CASCADE и только по подтверждённому experimental набору. Всё находится в одной транзакции: ошибка до COMMIT восстанавливает старое состояние автоматически.

Нормативный набор создаёт восемь DB-04 tables и DB-05 API: durable knowledge queue/lease/fencing, immutable profile, fragment vectors 1024, reference checks, draft search, bot active-only search, atomic publish и dash_admin revoke. Runtime roles не получают прямой table DML.

**На сервере эти файлы ещё не запускались.** Experimental B1/B2 и три experimental tables пока остаются фактическим test состоянием.

## Следующая одна задача

**KB-01R4 — применить recreate v0.2 в test Supabase и сразу выполнить structural verifier v0.2.**

После явной команды Павла:

1. проверить актуальный `main` HEAD;
2. открыть `sql/DB-04_05_knowledge_recreate_test.sql` именно из `main`; первая строка должна быть `KB-01R3 v0.2`;
3. запустить весь файл один раз в test Supabase;
4. прислать полный результат; ожидание: `status=applied`, `migration=KB-01R3_v0.2`;
5. если applied — до любых n8n/KB действий запустить весь `sql/DB-04_05_knowledge_verifier.sql`; первая строка `KB-01R3 verifier v0.2`;
6. ожидание verifier: `status=verified`, `verifier_version=KB-01R3_VERIFIER_v0.2`;
7. если recreate упал до COMMIT — отдельный rollback не запускать;
8. если recreate committed, но verifier failed и новые KB tables всё ещё пустые — следовать `docs/KB-01R3_RECREATE_ROLLBACK.md`, не делать ручных DROP.

KB-01R4 не включает импорт n8n, первую реальную `.md` загрузку или включение client RAG.

## После structural verification

Нужны отдельные runtime-тесты DB-04/DB-05 и фактическое PRE-02E подтверждение OpenAI embedding `dimensions=1024`. Structural verifier не заменяет эти проверки.

## Запреты

**Не продолжать старый B3.**
**Не импортировать старый KB workflow.**
**Не включать client RAG до нужных runtime-тестов.**
**Не применять experimental evidence SQL повторно.**
**Не менять production.**

## Evidence / решения

- `docs/KB-01_APPLIED_TEST_STATE_2026-10-03.md`
- `docs/KB-01R1_INVENTORY_MAPPING.md`
- `docs/KB-01R2_DECISION.md`
- `docs/KB-01R3_RECREATE_ROLLBACK.md`
- `docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`
