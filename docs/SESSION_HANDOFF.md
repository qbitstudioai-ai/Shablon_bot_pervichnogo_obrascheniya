# SESSION HANDOFF

Обновлено: 2026-10-08.

## Исходная точка

Рабочая ветка: `main`.

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1.

Текущая маленькая задача — **KB-03C1**.

Не загружать без необходимости весь репозиторий. Для KB-03C1 достаточно актуального `PROJECT_STATE`, `KB_WORKFLOW_IMPLEMENTATION_PLAN`, `KB-03C_IMPLEMENTATION_PLAN`, текущего workflow документов и фактического SQL/contract только функций publish/job-finish.

## Текущие workflow

Repository-safe текущие файлы:
- `workflows/current/Шаблон Загрузка документов Qbit.json`;
- `workflows/current/Шаблон — Workflow бота Qbit.json`.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Текущий workflow документов доводит version до KB-03B1, но не вызывает `opublikovat_versiyu_znaniy`.

Workflow бота уже содержит ноду `Найти опубликованные знания` и вызывает `poisk_aktivnyh_znaniy`; в KB-03C1 его не менять.

## KB-03B1 — CLOSED / runtime verified

Safe retry execution 08.10.2026 подтвердил:
- 53 fragments;
- 9 canonical YAML reference questions;
- one OpenAI question embedding batch `text-embedding-3-large/1024/float`;
- 9 vectors, finite values true, index mapping true;
- draft-only/version/profile-scoped top-12;
- positive grid full pass 9/9 до threshold 0.60;
- `sohranit_proverki_znaniy`: `uspeshnyh=9`, `vsego=9`, `status_versii=gotova`;
- `publish_vypolnen=false`;
- `full_pass=true`, `next_stage=KB-03C`.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

`status_zadaniya=povtor` после B1 — ожидаемый stage handoff текущей manual test-цепочки, а не fail.

## KB-03C1 — текущая задача

Полный план: `docs/KB-03C_IMPLEMENTATION_PLAN.md`.

Цель: подготовить новую repository-safe версию workflow документов с publish branch, **без импорта и без server execution**.

Условие начала выполнено: KB-03B1 9/9, version `gotova`, publish=false.

Перед изменением JSON:
1. прочитать фактическую SQL-реализацию/contract `opublikovat_versiyu_znaniy`;
2. прочитать только нужную часть `zavershit_zadanie_znaniy` для terminal/retry statuses;
3. payload/status не угадывать.

Разрешено в KB-03C1:
- менять только `workflows/current/Шаблон Загрузка документов Qbit.json` и связанную документацию;
- добавить gate после B1 full pass/`gotova`;
- добавить service Postgres publish call;
- добавить явные success/stale-conflict/error paths;
- выполнить локальные/static проверки JSON/nodes/connections/Code/security.

Не разрешено в KB-03C1:
- импортировать новый workflow в n8n;
- активировать его;
- выполнять `opublikovat_versiyu_znaniy` на сервере;
- менять Supabase или production;
- менять workflow клиентского бота.

Критерий готовности: полный import-ready JSON статически проверен, соответствует DB-05, fail-closed, не содержит Credential refs/секретов и не менял сервер.

Откат: Git revert/возврат к предыдущему JSON; server state не меняется.

## После KB-03C1

KB-03C2 — отдельный TEST runtime atomic publish + stale conflict + active-only regression. Перед первым mutating run отдельно уточнить plan rollback по фактическому DB-05 SQL. Прямой DML для отката не использовать.

B1 threshold 0.60 — не финальный client retrieval threshold; negative/no-answer calibration остаётся обязательной позже.

## Запреты

- Production не менять.
- Рабочий трафик не переключать.
- В KB-03C1 ничего не публиковать на сервере.
- Не импортировать experimental workflow.
- Не продолжать старый B3.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
