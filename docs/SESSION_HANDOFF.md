# SESSION HANDOFF

Обновлено: 2026-10-17.

## Исходная точка

Рабочая ветка: `main`.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

WF-02B3C остаётся IN PROGRESS. Закрыты runtime:
- `WF-02B3C-E2E-01` — client → guard → RAG → grounded Telegram answer;
- `WF-02B3C-E2E-02A` — human-needed → служебная тема/сигнал;
- `WF-02B3C-E2E-02B` — atomic Take + bot stop;
- `WF-02B3C-E2E-02C` — private manager alerts + group work.

Активный следующий ID: `WF-02B3C-E2E-03B` — handoff/refusal/opt-out cancellation.

Новая сессия обязана сначала перечитать фактический HEAD `main`, `README.md`, `docs/PROJECT_STATE.md`, этот handoff и `docs/WF-02B3C_E2E_PLAN.md`.

## Текущие repository-safe workflow

- `workflows/current/Шаблон Загрузка документов Qbit.json` — knowledge pipeline + publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — client bot + active-only knowledge search.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются. Instance-specific TEST runtime workflow также не сохраняются.

Повторно используемый TEST-only SQL `sql/Сбросить забранные диалоги.sql` v0.3 хранится в Git без реальных Telegram ID.

## Operator handoff — runtime verified

Актуальное бизнес-решение:
- менеджер общается с клиентом только в forum topic общей служебной Telegram-группы;
- private chat служебного бота используется только для важных уведомлений;
- personal alert может быть отправлен нескольким разрешённым менеджерам;
- Take остаётся first-commit-wins и закрепляет одного менеджера;
- после Take диалог остаётся у менеджера;
- обязательного `Завершить диалог` и Return в текущей v1-логике нет.

Runtime подтверждено:
- service runtime v8 PRIVATE ALERTS активен;
- `/start` подтверждает private chat разрешённого менеджера;
- client runtime v11 PRIVATE ALERTS активен;
- human-needed сохранил групповой mirror и доставил private alert `🔴 Требуется подключение`;
- ранее захваченные диалоги под новым runtime продолжают зеркалироваться в правильные темы и управляться менеджером;
- atomic Take и ручной ответ менеджера были отдельно доказаны в 02B.

Новый тестовый аккаунт намеренно оставлен bot-owned для дальнейших проверок; повторный Take не выполнялся, чтобы сохранить возможность тестировать обычного бота.

## TEST reset utility

`sql/Сбросить забранные диалоги.sql` v0.3 — ручной TEST-only reset по Telegram user ID менеджера.

Runtime доказательство 14.10.2026:
- `current_role=qbit_test_owner`;
- `dialogov_sbroseno=2`;
- новый owner=`bot`;
- новый status=`aktivnyy`;
- история сохранена;
- Production не затронут.

Этот SQL не является продуктовой кнопкой Return и не вызывается runtime workflow.

## WF-02B3C-E2E-03A — CLOSED / runtime verified 17.10.2026

Подтверждено в реальном TEST runtime:
- confirmed reply-needing bot answer создаёт waiting/reminder lifecycle только после подтверждённой отправки;
- `t0` относится к confirmed outbound;
- reminder1/reminder2 реально доставляются при controlled TEST 1/3 минуты;
- corrected workflow импортирован и активирован без видимых ошибок;
- mirror branch восстановлена и работает независимо от reminder branch; накопленные mirror events были доставлены после восстановления связи;
- новый client input до reminder1 отменяет старое ожидание: по старому ответу stale reminder не был отправлен после wake, напоминания пришли только по актуальному сообщению;
- sender wake после `Сохранить намерение отправки` теперь защищён gate `Исходящее действие создано?`.

Corrected workflow имеет 148 nodes и прошёл static graph validation. Runtime TEST-файл содержит instance-specific настройки и в Git не сохраняется. Repository-safe corrected JSON подготовлен локально без Credential refs/реальных Telegram ID, но большой workflow-файл пока не перезаписан в GitHub из-за ограничения текущего коннектора на передачу локального файла как содержимого write action.

### Следующий один ID: WF-02B3C-E2E-03B

Проверить отдельно:
- handoff отменяет активное ожидание;
- terminal refusal отменяет ожидание;
- opt-out запрещает инициативные сообщения.

03C после этого остаётся external delivery recovery; затем E2E-04 final regression/security.

Перед продолжением проверить TEST reminder settings. В 03A использовались ускоренные 1/3 минуты и loss 60 минут; после reminder-блока вернуть штатные 180/720 минут и loss 1440 минут.

## Известные долги до финального regression

- явный Telegram HTTP 4xx при создании темы отделить от действительно неоднозначного внешнего результата;
- оценить упрощение количества n8n executions без ослабления durable queue/final recheck;
- event recovery для пропущенного wake остаётся отдельным reliability debt: постоянного sweeper в текущем event-driven workflow нет.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks запрещены.
- VSCode/helper до dashboard stage не подключать.
