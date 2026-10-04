# SESSION HANDOFF

Обновлено: 2026-10-04.

## Исходная точка

Рабочая ветка: `main`.

На старте следующей сессии сначала проверить актуальный `main` HEAD и прочитать `docs/PROJECT_STATE.md` + `docs/KB-01_RECONCILIATION_PLAN.md`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

189 nodes, 153 connection keys, 215 edges, inactive, duplicate names 0, dangling connections 0. SHA-256 compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## KB-01R1…R4

R1 зафиксировал несовпадение experimental KB с нормативным DB-04/DB-05. R2 выбрал recreate. R3 подготовил canonical recreate `KB-01R3 v0.2`. R4 применил его в test Supabase и structurally verified через `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`.

Нормативный DB-04/DB-05 является live test state. Production не менялась.

## KB-01R5A — выполнено

`sql/KB-01R5A_runtime_ingestion_queue_probe.sql` запущен в n8n через фактический Credential `qbit_test_sluzhebnyy`.

PASS:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Подтверждены ingestion/duplicate/conflict, claim, heartbeat, retry, fencing/stale worker и finish. Финальный intentional exception откатил синтетические строки.

## KB-01R5B — выполнено

При подготовке найден runtime API-gap: service workflow не мог получить внутренний UUID вопроса при запрещённом direct SELECT. Применён test-only backward-compatible patch:

`sql/KB-01R5B_patch_question_number_test.sql`

Server result:

`KB-01R5B_PATCH_v0.1 applied`, `question_reference=vopros_id_or_nomer_voprosa`.

Основной runtime probe:

`sql/KB-01R5B_runtime_version_fragments_draft_probe.sql`

PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Guards probe:

`sql/KB-01R5B_runtime_guards_probe.sql` v0.2

PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

R5B runtime подтверждает:
- version/profile creation;
- synthetic `vector(1024)` storage;
- fragment batch idempotency;
- hash/dimension/token guards;
- profile fingerprint immutability semantics;
- 3 reference questions + 3 successful checks;
- transition to `gotova`;
- explicit draft search before publication;
- service credential cannot call client active search.

Оба probe откатили синтетические rows intentional PASS exception. PRE-02E с реальным OpenAI embedding остаётся отдельным.

## Следующая одна задача

**KB-01R5C — publish concurrency + atomic active switch + bot active-only search + revoke.**

Нужно проверить runtime на синтетических test-data:
1. создать ready version и опубликовать её;
2. подготовить следующую version того же logical document;
3. проверить stale expected-active conflict;
4. корректно опубликовать следующую version и подтвердить archive предыдущей + active switch;
5. через реальный Credential `qbit_test_bot` доказать, что client search видит только active published version и не видит draft;
6. проверить `otozvat_dokument_znaniy` через разрешённый `qbit_test_dash_admin` путь;
7. подтвердить отсутствие лишних EXECUTE/DML прав.

По возможности сохранить быстрый формат: подготовительный service probe + отдельные короткие проверки реальными bot/dash credentials, с синтетическими данными и контролируемым rollback/cleanup.

Не переходить автоматически к PRE-02E до закрытия R5C.

## После R5C

- **PRE-02E:** фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Запреты

**Не продолжать старый B3.**
**Не импортировать старый KB workflow.**
**Не включать client RAG workflow до закрытия R5C.**
**Не применять experimental evidence SQL повторно.**
**Не менять production.**
**Не запускать аварийный rollback после появления нужных KB-данных без отдельного плана сохранения.**
