# SESSION HANDOFF

Обновлено: 2026-10-15.

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

## WF-02B3C-E2E-03A — ACTIVE / partial runtime proof 15.10.2026

Уже доказано в реальном TEST runtime:
- обычный bot answer с `ozhidaet_otvet=true` был confirmed Telegram delivery;
- `t0` зафиксирован по подтверждённой отправке;
- БД создала `napominanie_1` и `napominanie_2` только после confirmed outbound;
- controlled TEST настройки 1/3 минуты дали реальные reminder1 и reminder2 примерно в ожидаемые сроки;
- loss delay пришлось вернуть к допустимому минимуму 60 минут, потому что DB contract отклоняет waiting effects с `poterya_posle_sekund < 3600`;
- reminder sender корректно не запускает новый reminder lifecycle, когда payload уже содержит `napominanie_id`.

Во время диагностики обнаружено, почему интерфейс n8n вводил в заблуждение:
- экспортированный runtime содержал старую `Нужно запланировать напоминания?`, подключённую к mirror-ветке;
- `Служебные события включены? зеркало` была disconnected от `Подтвердить отправку и обновить состояние`;
- `Запустить зеркало по событию` ошибочно продолжал выполнение в old reminder IF;
- параллельно была добавлена временная `Нужно запланировать напоминания? TEST`, которая действительно запускала Wait и дала успешные reminder1/reminder2.

Подготовлен исправленный JSON:
- одна каноническая `Нужно запланировать напоминания?` с пятью явными AND-проверками;
- confirmed outbound независимо запускает integration/reminder/loss/mirror checks;
- mirror gate ведёт только в mirror wake;
- `Сохранить намерение отправки` теперь проходит через `Исходящее действие создано?`, поэтому sender wake разрешён только после `uspeshno/dublikat` и наличия `deystvie_id`;
- удалён disconnected LEGACY service/manual reply/Return cluster и orphan duplicate внутреннего ACK;
- repository-safe export не содержит Credential refs и реальных Telegram ID и подготовлен неактивным.

Static validation corrected JSON: 148 nodes, unique node names, все connection source/targets существуют, активных функциональных orphan nodes нет. Runtime import/activation исправленного файла пока не проверены.

DoD 03A НЕ закрыт. Следующий один runtime-шаг после безопасного импорта исправленного JSON: отправить bot-owned клиенту сообщение, дождаться confirmed reply-needing bot answer, затем ДО reminder1 отправить новый client input и доказать в БД/Telegram, что старое ожидание отменено и stale reminder после wake не отправлен.

После завершения теста вернуть reminder intervals с временных TEST 1/3 минут к нормальным значениям 180/720 минут; loss default 1440 минут.

## После 03A

- `WF-02B3C-E2E-03B` — handoff/refusal/opt-out cancellation;
- `WF-02B3C-E2E-03C` — unknown/ambiguous delivery recovery;
- затем `WF-02B3C-E2E-04` — final regression/security.

## Известные долги до финального regression

- явный Telegram HTTP 4xx при создании темы отделить от действительно неоднозначного внешнего результата;
- оценить упрощение количества n8n executions без ослабления durable queue/final recheck;
- event recovery для пропущенного wake остаётся отдельным reliability debt: постоянного sweeper в текущем event-driven workflow нет.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks запрещены.
- VSCode/helper до dashboard stage не подключать.
