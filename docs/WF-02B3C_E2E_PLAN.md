# WF-02B3C — E2E runtime plan

Обновлено: 2026-10-11.

Родительская задача: `WF-02B3C` из `docs/WORKPLAN_TEMPLATE.md`.

## Границы

Только TEST. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Runtime artifacts с Credential refs, Telegram ID и instance-specific настройками в Git не сохранять. Repository-safe workflow остаются в `workflows/current/`.

VSCode/helper до dashboard stage не подключать.

## Проверяемая цепочка

Целевая event-driven схема:
1. client Telegram webhook сохраняет вход в PostgreSQL и подтверждает HTTP только после durable ingress;
2. internal processing event забирает один job и обрабатывает его;
3. обычный ответ создаёт durable outgoing intent и internal sender event;
4. sender делает final DB recheck, отправляет и подтверждает результат;
5. confirmed reply-needing message может перейти в Wait; после wake выполняется DB final recheck для reminders/loss.

Постоянного polling/Schedule Trigger в runtime-версии не должно быть.

## Подзадачи

### WF-02B3C-A — static/runtime prerequisites — CLOSED

Проверено до E2E:
- bot/service PostgreSQL routing разнесён;
- service и client workflow разделены;
- knowledge pipeline удалён из client workflow, оставлен active-only RAG;
- OpenAI guard/planner/answer используют `gpt-6-luna` в текущем TEST runtime;
- event webhooks используют явный fast ack через Respond to Webhook;
- постоянные Schedule/Manual trigger отсутствуют в runtime client workflow;
- опубликованная TEST база знаний и active-only поиск под bot role уже runtime-проверены отдельно.

### WF-02B3C-E2E-01 — клиент → guard → RAG → ответ — CLOSED / runtime verified

Дата: 2026-10-11.

Финальный чистый проход после точечных runtime-исправлений подтвердил:
- клиентский вопрос по стоимости принят и durable processing начался;
- guard классифицировал его как разрешённый вопрос по услугам/ценам с `nuzhen_rag=true`, а не как просьбу о человеке;
- planner сформировал поисковый запрос и required point;
- embedding выполняется через OpenAI profile текущей TEST-конфигурации;
- active-only DB-05 search вызывается как `qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)` под bot PostgreSQL role;
- caller больше не делает cast в `extensions.vector`; доступ runtime role к schema `extensions` расширять не потребовалось;
- RAG adapter читает актуальные поля DB-05 `tekst_fragmenta` и `shodstvo`, поэтому answer-LLM получает непустой evidence;
- answer-LLM сформировала содержательный grounded ответ по опубликованным знаниям и уточняющий вопрос;
- клиент реально получил ответ в Telegram;
- ложной передачи менеджеру в финальном чистом проходе не было.

Во время диагностики были выявлены и устранены TEST-runtime несоответствия:
- старое состояние диалога `peredacha_cheloveku` влияло на guard; для одного разрешённого TEST-диалога выполнен guarded reset с сохранением raw history;
- старый RAG query использовал устаревшую многoаргументную сигнатуру и внешний `extensions.vector` cast;
- вызов DB-05 без schema qualification не находился по connection `search_path`;
- RAG adapter ожидал legacy `soderzhanie/podobie`, тогда как DB-05 возвращает `tekst_fragmenta/shodstvo`.

DoD E2E-01 выполнен: реальный клиентский Telegram message прошёл основную bot-вертикаль до grounded ответа и подтверждённой внешней доставки.

### WF-02B3C-E2E-02 — operator handoff/service bot — NEXT

Проверить один реальный TEST handoff:
- явная просьба клиента подключить человека;
- durable human-needed state;
- service Telegram получает/отражает требуемое событие только через согласованный service ingress;
- Take выполняется атомарно текущим менеджером;
- после Take bot и reminders не продолжают разговор;
- ручной ответ менеджера идёт через разрешённый durable outgoing path;
- Return явно возвращает диалог боту без автоматического client message.

Не включать дополнительные competing Telegram webhooks на том же service bot token.

### WF-02B3C-E2E-03 — reminders / opt-out / recovery — PENDING

После Gate C отдельно проверить:
- reminder только после confirmed outbound, реально требующего ответа;
- новый client input отменяет ожидание;
- handoff/refusal/completion отменяют ожидание;
- opt-out запрещает инициативные сообщения;
- unknown/ambiguous external delivery не повторяется вслепую;
- Wait wake делает final DB recheck.

### WF-02B3C-E2E-04 — final regression/security — PENDING

Финальный проход после C/D:
- event-driven topology без постоянного polling;
- credential routing и role split;
- active-only KB isolation;
- no direct runtime table DML;
- secret-safe export;
- production untouched;
- обязательные exception/security cases без избыточного тестирования.

## Текущий статус

`WF-02B3C` остаётся `[~]`, потому что проверена только основная клиентская вертикаль. Следующий один ID: `WF-02B3C-E2E-02`.
