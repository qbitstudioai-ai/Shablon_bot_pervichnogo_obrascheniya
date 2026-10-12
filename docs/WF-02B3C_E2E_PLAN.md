# WF-02B3C — E2E runtime plan

Обновлено: 2026-10-12.

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

### WF-02B3C-E2E-02 — operator handoff/service bot — IN PROGRESS

Родительский Gate C разделён на три малых runtime шага, чтобы не смешивать signal/topic, ownership CAS и manual outgoing в одной диагностике.

#### WF-02B3C-E2E-02A — human-needed → topic/signal — CLOSED / runtime verified

Дата: 2026-10-12.

Финальный TEST-проход подтвердил:
- реальная явная просьба клиента подключить человека дошла до durable human-needed path;
- клиентский bot-answer path завершился передачей менеджеру, а не обычным AI-ответом;
- topic intent был выдан event-driven worker без polling;
- topic создаётся через изолированный TEST bridge к Telegram Bot API, потому что текущая n8n Telegram node не предоставляет `createForumTopic`;
- для `createForumTopic` числовой service chat ID нормализуется в JSON как Number; после этого Telegram подтвердил создание topic;
- DB topic mapping подтверждён один раз со статусом `gotova` и сохранённым `message_thread_id`;
- накопленные mirror events после подтверждения topic привязались к правильному thread и были реально доставлены во внешнюю service topic;
- в topic реально виден human-needed сигнал с кнопкой «Забрать диалог»;
- использован существующий service Telegram bot и текущий согласованный service ingress; competing webhook не создавался;
- Production не затрагивался.

DoD 02A выполнен: реальная просьба клиента привела к подтверждённому внешнему сигналу в правильной TEST operator topic без polling и без Production.

Наблюдение для следующего шага: при первом успешном создании topic накопившаяся очередь mirror events выгрузилась пачкой, поэтому видимый порядок backlog-сообщений не считается проверкой steady-state. Перед Take в 02B нужно отправить одно новое клиентское сообщение и проверить его обычное live-зеркалирование в уже существующую topic.

#### WF-02B3C-E2E-02B — atomic Take + bot stop — ACTIVE

После закрытия 02A:
- сначала отправить одно новое TEST client message и проверить steady-state mirror в существующую operator topic без backlog-flush эффекта;
- callback «Забрать диалог» приходит через существующий service webhook и durable service ingress;
- manager/topic state читается narrow DB-03E API;
- `zabrat_dialog_operatorom(jsonb)` выполняет first-commit-wins Take;
- owner становится `chelovek` с конкретным manager;
- поздний/stale bot outgoing и reminders не продолжают диалог.

DoD 02B: steady-state mirror подтверждён, atomic Take подтверждён runtime и bot-side continuation после Take заблокирован DB state/final recheck.

#### WF-02B3C-E2E-02C — manual reply + explicit Return — PENDING

После закрытия 02B:
- текст текущего менеджера в operator topic создаёт `sozdat_ruchnoe_ishodyashchee(jsonb)`;
- client sender доставляет manual action через клиентского Telegram-бота и подтверждает результат;
- callback «Вернуть боту» проходит через тот же service ingress;
- `vernut_dialog_botu(jsonb)` явно возвращает owner `chelovek → bot`;
- Return не создаёт автоматическое client message.

DoD 02C: ручной ответ реально получен клиентом, Return подтверждён runtime, самопроизвольного сообщения после Return нет.

### WF-02B3C-E2E-03 — reminders / opt-out / recovery — PENDING

После Gate C отдельно проверить:
- reminder только после confirmed outbound, реально требующего ответа;
- новый client input отменяет ожидание;
- handoff/refusal/completion отменяют ожидание;
- opt-out запрещает инициативные сообщения;
- unknown/ambiguous external delivery не повторяется вслепую;
- явный детерминированный внешний отказ, например Telegram HTTP 4xx до подтверждённого успеха, не должен ошибочно классифицироваться как `neizvestno`; `neizvestno` оставлять только для действительно неоднозначного transport/result состояния;
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

Дополнительный operability debt перед финальным regression: расследовать, можно ли упростить runtime topology в сторону «одно client message = одно основное execution», сохранив отдельные executions только там, где это оправдано Wait/lifecycle/reliability. Текущие durable queues, final recheck и sender safety при этом не ослаблять.

## Текущий статус

`WF-02B3C` остаётся `[~]`. `WF-02B3C-E2E-01` и `WF-02B3C-E2E-02A` закрыты runtime. Активный один ID: `WF-02B3C-E2E-02B`.
