# SESSION HANDOFF

Обновлено: 2026-10-14.

## Исходная точка

Рабочая ветка: `main`.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

WF-02B3C остаётся IN PROGRESS. Закрыты runtime:
- `WF-02B3C-E2E-01` — client → guard → RAG → grounded Telegram answer;
- `WF-02B3C-E2E-02A` — human-needed → служебная тема/сигнал;
- `WF-02B3C-E2E-02B` — atomic Take + bot stop.

Активный один ID: `WF-02B3C-E2E-02C` — завершение диалога менеджером без возврата боту.

Новая сессия обязана сначала перечитать фактический HEAD `main`, `README.md`, `docs/PROJECT_STATE.md`, этот handoff и `docs/WF-02B3C_E2E_PLAN.md`.

## Текущие repository-safe workflow

- `workflows/current/Шаблон Загрузка документов Qbit.json` — knowledge pipeline + publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — client bot + active-only knowledge search.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

Instance-specific TEST runtime workflow, runtime Credentials, промежуточные Telegram-сервисы и diagnostic/reset artifacts в repository-safe JSON не переносились.

## WF-02B3C-E2E-02B — CLOSED / runtime verified 14.10.2026

Подтверждено:
- steady-state зеркалирование клиента и подтверждённого ответа бота работает;
- callback «Забрать диалог» проходит durable service ingress;
- optimistic concurrency возвращает `stale_dialog_version`, затем повтор с актуальной версией проходит;
- `zabrat_dialog_operatorom(jsonb)` переводит owner `bot → chelovek` и фиксирует конкретного менеджера;
- в служебной теме видно, кто забрал диалог;
- ручной текст текущего менеджера реально доставляется клиенту через клиентского бота;
- клиентские сообщения после Take продолжают сохраняться/зеркалироваться;
- бот после Take не отвечает;
- кнопка «Забрать диалог» после Take больше не показывается;
- read-only post-Take check: active reminders=0, pending bot/system outgoing=0, active bot jobs=0.

DoD 02B выполнен.

## Бизнес-решение для 02C

После захвата менеджер обязан довести текущий диалог до завершения.

Целевой жизненный цикл:

`bot → chelovek → zavershen`.

Переход `chelovek → bot` для того же `dialog_id` больше не является целевым сценарием.

Нормативная спецификация `docs/specs/OPERATOR_HANDOFF.md` обновлена на v0.2: Return удалён из целевой логики, добавлено явное завершение менеджером и правило нового диалога после завершения.

## WF-02B3C-E2E-02C — ACTIVE

Уже подтверждено из 02B:
- текущий закреплённый менеджер может писать клиенту;
- другой менеджер не должен получать право через клиентский текст;
- bot-side continuation после Take остановлен.

Подготовлено локально, но **ещё не применено/не импортировано/не runtime-проверено**:
- `DB-03D3_manager_completion.sql` — narrow SECURITY DEFINER API `zavershit_dialog_menedzherom(jsonb)` для TEST;
- служебный runtime v8 — принимает `complete:<dialog_id>`, проверяет тему/менеджера/версию и вызывает DB-03D3;
- клиентский runtime v11 — на событии успешного Take показывает кнопку `✅ Завершить диалог`, а завершение отображает обычным сообщением без кнопок.

DB-03D3 не создаёт автоматического сообщения клиенту. Он должен отменить ожидания/напоминания/не начатые действия, записать terminal state и durable событие `✅ <имя менеджера> завершил диалог` в служебную тему.

Порядок runtime-проверки 02C:
1. применить полный DB-03D3 в TEST Supabase и проверить итоговый JSON-result;
2. заменить служебный runtime на v8 и клиентский runtime на v11; включить только после проверки Credentials;
3. создать новый TEST-диалог и выполнить Take;
4. убедиться, что на сообщении успешного захвата есть `✅ Завершить диалог`;
5. нажать кнопку текущим закреплённым менеджером;
6. проверить DB result: `status_dialoga=zavershen`, manager сохранён, версия увеличена;
7. проверить видимое сообщение о завершении в служебной теме;
8. проверить, что завершение не отправило клиенту автоматический текст;
9. после завершения отправить новое сообщение клиента и доказать, что создан новый `dialog_id`, а старый не переоткрыт.

## Следующий этап после 02C

`WF-02B3C-E2E-03` — reminders / opt-out / recovery.

Отдельные долги до финального regression:
- явный Telegram HTTP 4xx для создания темы отделить от действительно неоднозначного внешнего результата;
- оценить упрощение количества n8n executions без ослабления durable queue/final recheck.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks на том же token запрещены.
- VSCode/helper до dashboard stage не подключать.
