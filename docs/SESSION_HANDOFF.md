# SESSION HANDOFF

Обновлено: 2026-10-04.

## Исходная точка

Рабочая ветка: `main`.

На старте следующей сессии проверить актуальный `main` HEAD и прочитать `README.md`, `docs/PROJECT_STATE.md`, `docs/SESSION_HANDOFF.md`, `docs/KB-01_RECONCILIATION_PLAN.md` и `docs/PRE-02E_OPENAI_PROFILE.md`.

## Workflow checkpoint

Последний фактический workflow Павла:

`workflows/checkpoints/2026-10-03_v0.3/`

189 nodes, 153 connection keys, 215 edges, inactive, duplicate names 0, dangling connections 0. SHA-256 compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## KB-01R1…R4

R1 mapping → R2 recreate decision → R3 canonical recreate → R4 test apply + structural verifier. Нормативный DB-04/DB-05 является live test state. Production не менялась.

## KB-01R5A — выполнено

PASS через фактический `qbit_test_sluzhebnyy`:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

## KB-01R5B — выполнено

Test-only patch `sql/KB-01R5B_patch_question_number_test.sql` разрешил `sohranit_proverki_znaniy` принимать `vopros_id` или `nomer_voprosa`.

PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Guards PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

## KB-01R5C — выполнено для текущего bot/service runtime

Service `qbit_test_sluzhebnyy`:

- `KB-01R5C_PHASE1_v0.1` → V1 published;
- `KB-01R5C_PHASE2A_v0.1` → V2/V3 ready;
- `KB-01R5C_PHASE2B_v0.1` → V2 published, V3 stale conflict;
- `stale_expected_active` подтверждён;
- active switch V1→V2 и archive предыдущей версии подтверждены.

Bot `qbit_test_bot`:

`KB-01R5C_BOT_v0.2 status=verified`

Подтверждено: active V2 видна, archived V1 скрыта, unpublished V3 скрыта, draft-search denied.

Cleanup:

`KB-01R5C_CLEANUP_v0.3 status=cleaned`

Удалено 3 versions, 3 uploads, 3 jobs, 3 events, 3 fragments, 9 questions, 9 checks. Production не затрагивалась.

Evidence: `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`.

`sql/KB-01R5C_service_publish_prepare.sql` теперь только tombstone `OBSOLETE_DO_NOT_RUN`.

## KB-01R5D — отложено до dashboard stage

В n8n сейчас существуют только два фактических Postgres Credentials: bot и service. Отдельный `qbit_test_dash_admin` Credential не создавался.

Поэтому runtime revoke через `otozvat_dokument_znaniy` не объявляется проверенным. Structural EXECUTE matrix dash_admin уже проверена R4. Когда начнётся dashboard stage и появится реальный dash_admin connection, выполнить отдельную задачу `KB-01R5D`.

## Следующая одна задача

**PRE-02E — фактический OpenAI embedding `text-embedding-3-large` с `dimensions=1024` в каноническом workflow.**

В начале следующей сессии:

1. проверить `main` HEAD;
2. прочитать `docs/PRE-02E_OPENAI_PROFILE.md`;
3. не считать synthetic `vector(1024)` доказательством OpenAI dimensions;
4. работать только с checkpoint `workflows/checkpoints/2026-10-03_v0.3/`;
5. не включать client RAG и не менять production без отдельного разрешения.

## Запреты

**Не продолжать старый B3.**
**Не импортировать старый KB workflow.**
**Не запускать `sql/KB-01R5C_service_publish_prepare.sql`.**
**Не применять experimental evidence SQL повторно.**
**Не менять production.**
**Не запускать аварийный rollback после появления нужных KB-данных без отдельного плана сохранения.**
