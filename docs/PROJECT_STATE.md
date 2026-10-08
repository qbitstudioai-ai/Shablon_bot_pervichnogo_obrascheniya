# Текущее состояние проекта

Обновлено: 2026-10-08.

## Режим

Реализация TEST-контура разрешена. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Каноническая schema: `qbit_bot_pervichnogo_obrascheniya`.

## Текущие workflow

Repository-safe файлы:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — service intake + knowledge processing + подготовленный KB-03C1 publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот и active-only RAG search.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Workflow бота уже вызывает `poisk_aktivnyh_znaniy`; для KB-03C1 он не менялся.

## Закрытые knowledge stages

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1.

KB-03B1 final runtime 08.10.2026:
- 53 fragments;
- 9/9 canonical checks;
- question embeddings OpenAI `text-embedding-3-large/1024/float`;
- draft-only/version/profile top-12;
- full positive pass до 0.60;
- `status_versii=gotova`;
- publish=false.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

## KB-03C1 — CLOSED / static verified

Read-only preflight готовой TEST version подтвердил:
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5` = `gotova`;
- document `qbit_klientskaya_baza_znaniy`;
- 53 fragments, bad vector dimensions = 0;
- 9/9 latest successful checks;
- expected active = NULL, current active = NULL;
- `opublikovat_versiyu_znaniy` существует;
- service execute = true, bot execute = false;
- итог `READY_FOR_KB03C1_WORKFLOW_PREP`.

В workflow документов добавлен безопасный publish branch по фактическому DB-05 contract. Для уже подготовленной `gotova` version есть resume path: повторный worker run не пересчитывает embeddings/checks, а после DB-confirmed existing ready version переходит к publish gate.

Static verification:
- JSON valid;
- 67 nodes, 9 новых C1/publish nodes;
- duplicate names/IDs = 0;
- dangling connections = 0;
- 21 Code nodes syntax PASS;
- workflow остаётся inactive;
- secrets/Credential bindings отсутствуют.

Evidence: `docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

В KB-03C1 ничего не импортировалось в n8n и ничего не публиковалось в Supabase.

## Активный план

Родительский план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.
Активный подплан: `docs/KB-03C_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B0` → `KB-03B1` → `KB-03C1` → `KB-03C2`.

## Следующая маленькая задача — KB-03C2

Подготовительный безопасный шаг:
1. импортировать current workflow документов как отдельную неактивную TEST-копию, не перезаписывая старую;
2. привязать существующий `qbit_test_sluzhebnyy` только к нужным Postgres-нодам текущего resume/publish пути;
3. workflow не активировать и mutating Execute пока не запускать.

После этого перед конкретной TEST publication отдельно подтвердить действие и rollback. Затем выполнить atomic publish и active-only regression.

## Постоянные ограничения

- Production не менять.
- Рабочий трафик не переключать.
- Не выполнять publication без отдельного подтверждения конкретного TEST действия.
- Не запускать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- `KB-01R5D` оставить до dashboard stage.
- VSCode/helper не подключать до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
