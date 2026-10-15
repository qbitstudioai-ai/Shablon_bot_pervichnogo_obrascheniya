# WF-02B3C — E2E runtime plan

Обновлено: 2026-10-15.

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
- OpenAI guard/planner/answer используют текущую TEST-конфигурацию;
- event webhooks используют явный fast ack через Respond to Webhook;
- постоянные Schedule/Manual trigger отсутствуют в runtime client workflow;
- опубликованная TEST база знаний и active-only поиск под bot role уже runtime-проверены отдельно.

### WF-02B3C-E2E-01 — клиент → guard → RAG → ответ — CLOSED / runtime verified

Дата: 2026-10-11.

Финальный чистый проход подтвердил client Telegram vertical slice до grounded ответа и подтверждённой внешней доставки.

### WF-02B3C-E2E-02 — operator handoff/service bot — CLOSED / runtime verified

#### WF-02B3C-E2E-02A — human-needed → тема/сигнал — CLOSED / runtime verified

Дата: 2026-10-12.

Подтверждено:
- реальная просьба клиента подключить человека дошла до durable human-needed path;
- обычный bot-answer path не продолжился;
- тема клиента создаётся event-driven без polling;
- mapping темы подтверждён в DB;
- client/bot mirror events реально доставляются в правильную тему;
- сигнал с кнопкой «Забрать диалог» виден менеджерам.

#### WF-02B3C-E2E-02B — atomic Take + bot stop — CLOSED / runtime verified

Дата: 2026-10-14.

Подтверждено:
- steady-state mirror работает;
- callback «Забрать диалог» проходит durable service ingress;
- optimistic concurrency и first-commit-wins Take работают;
- owner становится `chelovek`, status=`peredan_cheloveku`, закрепляется конкретный manager;
- ручной текст закреплённого менеджера реально приходит клиенту;
- после Take сообщения клиента продолжают сохраняться/зеркалироваться;
- бот после Take не отвечает;
- новые сообщения после Take не показывают кнопку Take;
- active reminders=0, pending bot/system outgoing=0, active bot jobs=0.

#### WF-02B3C-E2E-02C — private manager alerts + group work — CLOSED / runtime verified

Дата: 2026-10-14.

Бизнес-решение:
- рабочая переписка менеджера с клиентом идёт только в forum topic общей служебной группы;
- private chat служебного бота используется только для важных уведомлений;
- уведомление может fan-out нескольким активным разрешённым менеджерам с подтверждённым private chat;
- Take остаётся first-commit-wins;
- обязательного completion и Return в текущей v1-логике нет.

Runtime подтверждено:
- DB-03H применён: функция доступна bot role, недоступна service role, Production не затронут;
- service runtime v8 PRIVATE ALERTS активирован;
- `/start` подтвердил private chat менеджера;
- client runtime v11 PRIVATE ALERTS активирован;
- новый human-needed запрос сохранил групповой сигнал и реально доставил private alert `🔴 Требуется подключение`;
- существующие human-owned диалоги под новым runtime продолжили штатно работать через темы группы;
- новый тестовый аккаунт намеренно оставлен bot-owned для следующих E2E-проверок; повторный Take не требовался, поскольку atomic Take уже runtime-подтверждён в 02B.

DoD 02C выполнен.

### WF-02B3C-E2E-03 — reminders / opt-out / recovery — ACTIVE

Проверяем небольшими подшагами.

#### WF-02B3C-E2E-03A — confirmed outbound → ожидание → reminder lifecycle — ACTIVE / PARTIAL RUNTIME VERIFIED

Дата текущего partial proof: 2026-10-15.

Цель: на одном bot-owned TEST-аккаунте доказать базовый reminder contract без handoff.

Уже runtime подтверждено:
- bot reply с `ozhidaet_otvet=true` был подтверждён внешним Telegram result;
- `t0` установлен по времени подтверждённой отправки;
- только после confirmed outbound БД создала durable reminder1/reminder2;
- при controlled TEST интервалах 1/3 минуты reminder1 и reminder2 реально доставлены примерно в ожидаемые сроки;
- sender второго reminder не запускает новый reminder lifecycle, потому что payload содержит `napominanie_id`.

Найден и подготовлен к исправлению runtime wiring defect:
- old reminder IF был ошибочно связан с mirror wake;
- mirror condition не получала confirmed outbound;
- outgoing sender wake не был защищён от результата `otkaz` при создании intent.

Локально подготовлен repository-safe workflow: independent fan-out integration/reminder/loss/mirror, explicit reminder gate, dedicated `Исходящее действие создано?` gate и удаление disconnected LEGACY cluster. Исправленный JSON должен быть импортирован неактивным и проверен в TEST перед заменой активной версии.

Осталось подтвердить для DoD 03A:
- новый client input до reminder срока отменяет старое ожидание;
- после wake final DB recheck не отправляет stale reminder;
- исправленная wiring-версия реально проходит тот же reminder lifecycle после импорта.

DoD 03A: один полный реальный цикл ожидания подтверждён runtime, включая отмену новым client input и отсутствие stale reminder. Пока НЕ закрыт.

#### WF-02B3C-E2E-03B — handoff/refusal/opt-out cancellation — PENDING

Проверить отдельно:
- handoff отменяет ожидание;
- отказ/terminal business decision отменяет ожидание;
- opt-out запрещает инициативные сообщения.

#### WF-02B3C-E2E-03C — external delivery recovery — PENDING

Проверить отдельно:
- unknown/ambiguous external delivery не повторяется вслепую;
- явный детерминированный Telegram/API отказ не классифицируется как `neizvestno`;
- recovery не создаёт дублей без подтверждённой поддержки внешнего API.

### WF-02B3C-E2E-04 — final regression/security — PENDING

Финальный проход:
- event-driven topology без постоянного polling;
- credential routing и role split;
- active-only KB isolation;
- no direct runtime table DML;
- secret-safe export;
- production untouched;
- обязательные exception/security cases.

Дополнительный operability debt перед финальным regression: оценить, можно ли упростить runtime topology в сторону «одно client message = одно основное execution», сохранив отдельные executions только там, где это оправдано Wait/lifecycle/reliability. Durable queues, final recheck и sender safety не ослаблять.

## TEST-only reset utility

`sql/Сбросить забранные диалоги.sql` v0.3 хранится как ручной TEST-инструмент без реальных Telegram ID. Runtime проверено: два human-owned TEST-диалога возвращены в `bot/aktivnyy`, история сохранена, Production не затронут.

## Текущий статус

`WF-02B3C` остаётся `[~]`.

Закрыты runtime: `WF-02B3C-E2E-01`, `WF-02B3C-E2E-02A`, `WF-02B3C-E2E-02B`, `WF-02B3C-E2E-02C`.

Активный один ID: `WF-02B3C-E2E-03A`. Reminder1/reminder2 delivery уже runtime подтверждены; следующий тест — cancellation новым client input и stale reminder suppression на исправленном workflow.
