# SESSION HANDOFF

Обновлено: 2026-10-14.

## Исходная точка

Рабочая ветка: `main`.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

WF-02B3C остаётся IN PROGRESS. Закрыты runtime:
- `WF-02B3C-E2E-01` — client → guard → RAG → grounded Telegram answer;
- `WF-02B3C-E2E-02A` — human-needed → служебная тема/сигнал;
- `WF-02B3C-E2E-02B` — atomic Take + bot stop;
- `WF-02B3C-E2E-02C` — private manager alerts + group work.

Активный один ID: `WF-02B3C-E2E-03A` — confirmed outbound → ожидание → reminder lifecycle.

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

## WF-02B3C-E2E-03A — ACTIVE

Цель: доказать базовый reminder contract на одном bot-owned TEST-аккаунте, не используя handoff.

Нужно проверить реальным runtime:
1. бот отправляет сообщение, которое действительно требует ответа пользователя;
2. исходящая доставка подтверждается;
3. только после confirmed outbound появляется ожидание/reminder и фиксируется `t0`;
4. до срока не возникает лишней инициативной отправки;
5. новый client input до срока отменяет старое ожидание;
6. после wake выполняется final DB recheck и stale reminder не отправляется.

DoD 03A: один полный reminder lifecycle подтверждён, включая cancellation новым входом и отсутствие устаревшей отправки.

После 03A отдельно идут:
- `WF-02B3C-E2E-03B` — handoff/refusal/opt-out cancellation;
- `WF-02B3C-E2E-03C` — unknown/ambiguous delivery recovery;
- затем `WF-02B3C-E2E-04` — final regression/security.

## Известные долги до финального regression

- явный Telegram HTTP 4xx при создании темы отделить от действительно неоднозначного внешнего результата;
- оценить упрощение количества n8n executions без ослабления durable queue/final recheck.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks запрещены.
- VSCode/helper до dashboard stage не подключать.