# Текущее состояние проекта

Обновлено: 2026-10-04.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки: 189 нод, 153 connection keys, 215 edges, `active=false`, duplicate names 0, dangling connections 0; credentials/instance ID/реальный ID служебной группы удалены. SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировать**.

## KB-01R1…R4

R1 выполнил mapping experimental KB к нормативному DB-04/DB-05. R2 выбрал recreate. R3 подготовил canonical recreate `KB-01R3 v0.2`. R4 применил его в test Supabase и structurally verified через `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`.

Подтверждено: experimental KB отсутствует; нормативные DB-04/DB-05 созданы; owners/search_path/SECURITY DEFINER/EXECUTE matrix корректны; direct runtime table DML запрещён; `vector(1024)` + HNSW и integrity triggers присутствуют. Production не менялась.

## KB-01R5A — VERIFIED

`sql/KB-01R5A_runtime_ingestion_queue_probe.sql` выполнен через фактический `qbit_test_sluzhebnyy`.

PASS: `KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`.

Подтверждены durable service event, upload create/duplicate/conflict, claim, heartbeat, retry, fencing/stale worker и finish.

## KB-01R5B — VERIFIED

Применён test-only backward-compatible patch `sql/KB-01R5B_patch_question_number_test.sql`: `sohranit_proverki_znaniy` принимает `vopros_id` или `nomer_voprosa`.

Основной PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Guards PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

Фактический OpenAI embedding всё ещё отдельно проверяется в PRE-02E.

## KB-01R5C — publish + active-only search VERIFIED

04.10.2026 runtime-проверка выполнена на синтетическом logical document через реальные n8n Credentials.

Service (`qbit_test_sluzhebnyy`):

- `KB-01R5C_PHASE1_v0.1` → `v1_published`;
- `KB-01R5C_PHASE2A_v0.1` → `v2_v3_ready`;
- `KB-01R5C_PHASE2B_v0.1` → `v2_published_v3_stale`;
- stale V3 → `konflikt / stale_expected_active`;
- V2 стала active, V1 архивирована.

Bot (`qbit_test_bot`):

`KB-01R5C_BOT_v0.2 status=verified`

Подтверждено:
- `active_v2_found=true`;
- `archived_v1_hidden=true`;
- `unpublished_v3_hidden=true`;
- `draft_search_denied=true`.

Синтетические данные затем удалены guarded cleanup:

`KB-01R5C_CLEANUP_v0.3 status=cleaned`

Удалено 3 versions, 3 uploads, 3 jobs, 3 events, 3 fragments, 9 questions, 9 checks. Production не затрагивалась.

Evidence: `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`.

Ранний `sql/KB-01R5C_service_publish_prepare.sql` помечен `OBSOLETE_DO_NOT_RUN`: несколько успешных active-switch внутри одной SQL transaction не моделируют обычный n8n runtime.

## KB-01R5D — dash_admin runtime revoke — DEFERRED

Отдельный n8n Credential `qbit_test_dash_admin` сейчас не создан; в n8n фактически есть только bot и service Credentials. Структурная EXECUTE matrix dash_admin уже проверена в R4, но реальный runtime revoke не объявляется проверенным.

`KB-01R5D` выполнить на этапе подключения dashboard, когда появится фактический dash_admin connection. Создавать третий n8n Credential только ради текущего теста не требуется.

## Текущая одна задача

**PRE-02E — подтвердить фактический OpenAI embedding `text-embedding-3-large` с `dimensions=1024` в каноническом workflow.**

PRE-02E не считать выполненной по синтетическим vectors DB-проверок: нужен фактический OpenAI runtime результат.

## Ограничения

- Production не изменялась.
- Старый B3 не продолжать.
- Старый KB workflow не импортировать.
- Client RAG пока не включать до проверки PRE-02E.
- Experimental evidence SQL повторно не запускать.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `sql/DB-04_05_knowledge_rollback_test.sql` использовать только как аварийный rollback по отдельному плану.
