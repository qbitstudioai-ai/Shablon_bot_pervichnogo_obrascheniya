# WF-02B3C — E2E runtime plan

Обновлено: 2026-10-14.

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

Финальный чистый проход подтвердил клиентский Telegram vertical slice до grounded ответа и подтверждённой внешней доставки.

### WF-02B3C-E2E-02 — operator handoff/service bot — IN PROGRESS

#### WF-02B3C-E2E-02A — human-needed → тема/сигнал — CLOSED / runtime verified

Дата: 2026-10-12.

Подтверждено:
- реальная просьба клиента подключить человека дошла до durable human-needed path;
- обычный bot-answer path не продолжился;
- тема клиента создаётся event-driven без polling;
- mapping темы подтверждён в DB;
- клиентские/bot mirror events реально доставляются в правильную тему;
- сигнал с кнопкой «Забрать диалог» виден менеджерам;
- competing webhook не создавался; Production не затрагивался.

#### WF-02B3C-E2E-02B — atomic Take + bot stop — CLOSED / runtime verified

Дата закрытия: 2026-10-14.

Runtime подтверждения:
- steady-state client mirror в существующую тему работает;
- bot reply mirror работает;
- callback «Забрать диалог» проходит через текущий service webhook и durable ingress;
- manager/topic state читается narrow DB API;
- список менеджеров синхронизируется без прямого DML service role;
- optimistic concurrency работает: stale version возвращает `konflikt/stale_dialog_version`, повтор с актуальной версией успешен;
- `zabrat_dialog_operatorom(jsonb)` выполняет Take first-commit-wins;
- owner становится `chelovek`, status=`peredan_cheloveku`, закрепляется конкретный manager;
- публичное сообщение о захвате видно другим менеджерам;
- ручной текст закреплённого менеджера создаёт `sozdat_ruchnoe_ishodyashchee(jsonb)` и реально приходит клиенту через client sender;
- после Take клиентские сообщения продолжают сохраняться/зеркалироваться;
- бот после Take не отвечает;
- кнопка «Забрать диалог» после Take на новых mirror-сообщениях не показывается;
- read-only post-Take check: active reminders=0, pending bot/system outgoing=0, active bot jobs=0.

DoD 02B выполнен: steady-state mirror подтверждён, atomic Take подтверждён runtime, bot-side continuation и ожидающие напоминания/задачи после Take отсутствуют.

#### WF-02B3C-E2E-02C — private manager alerts + group work — ACTIVE

Бизнес-решение 14.10.2026:
- менеджер ведёт переписку с клиентом **только в теме общей служебной Telegram-группы**;
- личный чат служебного бота используется только для важных уведомлений, а не для рабочей переписки;
- уведомление «нужен менеджер» должно приходить нескольким разрешённым менеджерам, у которых включены личные уведомления и подтверждён private chat;
- Take остаётся first-commit-wins: забирает диалог только один менеджер;
- после Take диалог остаётся у менеджера; обязательное действие «Завершить диалог» сейчас не реализуется и не является условием закрытия этого этапа;
- старый Return-переход не используется.

Уже подтверждено runtime:
- DB-03H `sozdat_lichnye_uvedomleniya_menedzheram(jsonb)` применён в TEST: `function_ok=true`, `bot_execute_ok=true`, `service_execute_denied=true`, `production_untouched=true`;
- служебный runtime v8 PRIVATE ALERTS импортирован и активирован;
- `/start` в личном чате разрешённого менеджера успешно подтвердил private chat; служебный бот ответил, что личные уведомления подключены.

Следующий runtime-порядок:
1. заменить клиентский runtime v10 на подготовленный v11 PRIVATE ALERTS;
2. проверить Credentials и активировать только v11;
3. создать новый TEST-запрос человека от клиента;
4. подтвердить, что `🚨 Нужен менеджер` остаётся в теме клиента;
5. подтвердить, что личное уведомление приходит разрешённому менеджеру;
6. проверить кнопку «Забрать диалог» и first-commit-wins Take;
7. после Take продолжить переписку только в теме группы и убедиться, что бот не отвечает.

DoD 02C: private alert доставлен минимум одному подтверждённому менеджеру, групповой сигнал сохранён, Take работает из служебного Telegram-контура, а рабочая переписка после Take остаётся только в forum topic.

### WF-02B3C-E2E-03 — reminders / opt-out / recovery — PENDING

После Gate C отдельно проверить:
- reminder только после confirmed outbound, реально требующего ответа;
- новый client input отменяет ожидание;
- handoff/refusal отменяют ожидание;
- opt-out запрещает инициативные сообщения;
- unknown/ambiguous external delivery не повторяется вслепую;
- явный детерминированный внешний отказ не должен ошибочно классифицироваться как `neizvestno`;
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

`WF-02B3C` остаётся `[~]`.

Закрыты runtime: `WF-02B3C-E2E-01`, `WF-02B3C-E2E-02A`, `WF-02B3C-E2E-02B`.

Активный один ID: `WF-02B3C-E2E-02C` — личные уведомления менеджерам + работа в общей теме.