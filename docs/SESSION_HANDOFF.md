# SESSION HANDOFF

Обновлено: 2026-10-12.

## Исходная точка

Рабочая ветка: `main`.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

WF-02B3C остаётся IN PROGRESS. Закрыты runtime:
- `WF-02B3C-E2E-01` — client → guard → RAG → grounded Telegram answer;
- `WF-02B3C-E2E-02A` — human-needed → operator topic/signal.

Новая сессия обязана сначала перечитать фактический HEAD `main`, `README.md`, `docs/PROJECT_STATE.md`, этот handoff и `docs/WF-02B3C_E2E_PLAN.md`.

## Текущие repository-safe workflow

- `workflows/current/Шаблон Загрузка документов Qbit.json` — knowledge pipeline + publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — client bot + active-only knowledge search.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

Instance-specific TEST runtime workflow, runtime Credentials, bridge secrets и diagnostic/reset artifacts в repository-safe JSON не переносились.

## KB-03C2 — CLOSED / runtime verified

Runtime target опубликован, active-only поиск под `qbit_test_bot` проверен: 12/12 результатов только из target published version; direct SELECT fragments=false. Полное evidence:
`docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

Supported publication-visibility rollback: `otozvat_dokument_znaniy(jsonb)` через dash-admin role после отдельной необходимости/авторизации. Direct DML не использовать.

## WF-02B3C-E2E-01 — CLOSED / runtime verified 11.10.2026

Реальный TEST client Telegram vertical slice завершился содержательным grounded ответом клиенту.

Подтверждено:
- guard корректно разрешил вопрос по услуге/цене с `nuzhen_rag=true`;
- planner и OpenAI embedding отработали;
- DB-05 active search вызывается текущей JSONB-функцией под bot role;
- caller не получил лишний доступ к schema `extensions`;
- RAG adapter использует текущие поля `tekst_fragmenta` и `shodstvo`;
- answer-LLM получила непустой evidence;
- клиент реально получил grounded ответ;
- финальный чистый проход не ушёл в handoff.

## WF-02B3C-E2E-02A — CLOSED / runtime verified 12.10.2026

Реальный TEST operator handoff до служебной topic завершён.

Подтверждено:
- клиент явно попросил человека;
- durable human-needed path сработал, обычный bot-answer path не продолжился;
- topic intent забран event-driven worker без polling;
- n8n 2.41.0 Telegram node не предоставляет `createForumTopic`, поэтому в TEST для этого вызова используется отдельный минимальный bridge к Telegram Bot API;
- bridge изолирован от Supabase/n8n database, Telegram token и bridge key не хранятся в workflow/Git;
- service group и bot права проверялись через Bot API: target — supergroup forum, service bot — administrator с правом manage topics;
- критичное runtime-исправление: числовой service chat ID для `createForumTopic` передаётся как Number, не строка;
- Telegram подтвердил создание topic, DB сохранила mapping со статусом `gotova` и thread ID;
- накопленные mirror events были привязаны к созданному thread и реально доставлены во внешнюю topic;
- human-needed signal с кнопкой «Забрать диалог» реально присутствует;
- competing webhook на service Telegram token не создавался;
- Production не затрагивался.

### Наблюдение по отображению

Первое успешное создание topic произошло после нескольких предыдущих TEST-сообщений, поэтому накопленная очередь mirror events выгрузилась пачкой. В Telegram клиентские события оказались сгруппированы выше, bot-события ниже. Это не доказательство steady-state порядка.

Перед нажатием «Забрать диалог» в следующей сессии нужно отправить **одно новое** client message и проверить, как оно live-зеркалируется в уже существующую topic без backlog flush.

### Найденные долги

1. **Topic error semantics.** Текущий parser переводит любой неуспех `createForumTopic` в `create_forum_topic_neizvestno`. Во время диагностики явный Telegram HTTP 400 также попал в `neizvestno`. В recovery/regression нужно разделить детерминированный отказ и действительно неоднозначный transport/result outcome; blind retry запрещён при неоднозначном результате.
2. **Operability.** Один client message может порождать несколько n8n executions. До финального regression оценить упрощение в сторону одного основного execution, сохранив отдельные Wait/sender executions только там, где это оправдано lifecycle/reliability. Durable queues и final recheck не ослаблять.

## Текущая модель TEST runtime

Guard/planner/answer: `gpt-6-luna` с low reasoning. Embedding: `text-embedding-3-large`, dimensions 1024.

Не менять модель из-за уже исправленных state/RAG/topic integration проблем.

## Следующая маленькая задача — WF-02B3C-E2E-02B

Цель: подтвердить steady-state mirror, затем atomic Take и остановку bot-side continuation.

Порядок:
1. перечитать актуальные документы и HEAD `main`;
2. не менять Production и не создавать competing Telegram webhook;
3. отправить одно новое сообщение клиентскому TEST Telegram-боту;
4. проверить, что оно появляется в существующей operator topic в обычном live-режиме и не создаёт новую topic;
5. после этого нажать существующую кнопку «Забрать диалог»;
6. доказать, что callback прошёл через согласованный service webhook и durable service ingress;
7. проверить `zabrat_dialog_operatorom(jsonb)` / first-commit-wins Take;
8. доказать owner=`chelovek` с конкретным manager;
9. проверить, что поздний/stale bot outgoing и reminders после Take не продолжают диалог.

DoD 02B: steady-state mirror подтверждён, atomic Take runtime-подтверждён, bot-side continuation после Take заблокирован DB state/final recheck.

После 02B отдельной сессией: `WF-02B3C-E2E-02C` — manual manager reply + explicit Return.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks на том же token запрещены.
- VSCode/helper до dashboard stage не подключать.
