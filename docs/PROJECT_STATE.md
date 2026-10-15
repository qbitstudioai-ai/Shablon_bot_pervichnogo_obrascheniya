# Текущее состояние проекта

Обновлено: 2026-10-15.

## Режим

Реализация TEST-контура разрешена. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Каноническая schema: `qbit_bot_pervichnogo_obrascheniya`.

## Текущие workflow

Repository-safe файлы:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — service intake + knowledge processing + publish branch KB-03C;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот и active-only RAG search.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Instance-specific TEST runtime workflow в Git не сохраняется. Повторно используемый TEST-only SQL-инструмент `sql/Сбросить забранные диалоги.sql` хранится в репозитории без реальных Telegram ID.

## Knowledge workflow — CLOSED / runtime verified

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1, KB-03C2.

KB-03C1 закрыт как static verified; KB-03C2 подтвердил prepared publish branch на реальном TEST runtime.

Evidence: `docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## WF-02B3C — event-driven TEST runtime — IN PROGRESS

Активный малый план: `docs/WF-02B3C_E2E_PLAN.md`.

### WF-02B3C-E2E-01 — CLOSED / runtime verified 11.10.2026

Реальный клиентский Telegram vertical slice прошёл guard → planner → OpenAI embedding → active-only DB-05 RAG → answer → Telegram; клиент получил grounded ответ по опубликованным знаниям.

### WF-02B3C-E2E-02A — CLOSED / runtime verified 12.10.2026

Реальная просьба клиента о человеке создала durable human-needed path и служебную тему клиента. Клиентские/bot events доставляются в правильную тему; кнопка «Забрать диалог» видна менеджерам; Production не затрагивался.

Обнаруженный recovery debt: явный Telegram HTTP 4xx при создании темы нужно отделить от действительно неоднозначного внешнего результата.

Operability debt: перед финальным regression оценить упрощение количества n8n executions без ослабления durable queue/final recheck.

### WF-02B3C-E2E-02B — CLOSED / runtime verified 14.10.2026

Подтверждено в TEST runtime:
- steady-state client mirror и bot reply mirror работают;
- callback «Забрать диалог» проходит durable service ingress;
- optimistic concurrency и first-commit-wins Take работают;
- owner становится `chelovek`, status=`peredan_cheloveku`, закрепляется конкретный manager;
- закреплённый менеджер реально отвечает клиенту из темы группы;
- после Take клиентские сообщения продолжают сохраняться/зеркалироваться;
- бот после Take не отвечает;
- read-only post-Take check: active reminders=0, pending bot/system outgoing=0, active bot jobs=0.

### WF-02B3C-E2E-02C — CLOSED / runtime verified 14.10.2026

Актуальное бизнес-решение:
- менеджер ведёт клиентскую переписку только в теме общей служебной Telegram-группы;
- личный чат служебного бота используется только для важных уведомлений «нужен менеджер»;
- уведомления могут получать несколько активных разрешённых менеджеров;
- Take остаётся first-commit-wins и закрепляет диалог за одним менеджером;
- после Take диалог остаётся у менеджера; обязательное завершение сейчас не вводится;
- старый Return-переход не используется.

Runtime подтверждено:
- DB-03H `sozdat_lichnye_uvedomleniya_menedzheram(jsonb)` применён в TEST; bot EXECUTE разрешён, service EXECUTE запрещён, Production не затронут;
- служебный runtime v8 PRIVATE ALERTS активирован;
- `/start` успешно подтвердил private chat разрешённого менеджера;
- клиентский runtime v11 PRIVATE ALERTS активирован;
- новый human-needed запрос сохранил групповой mirror и одновременно доставил менеджеру личное уведомление `🔴 Требуется подключение`;
- уже захваченные диалоги под новым runtime продолжили штатно зеркалировать сообщения клиента в тему группы и оставались под управлением менеджера;
- повторный Take нового тестового аккаунта намеренно не выполнялся: два тестовых аккаунта уже ранее подтвердили atomic Take в 02B, третий оставлен bot-owned для дальнейших E2E-проверок.

DoD 02C выполнен: private alert реально доставлен, групповой сигнал не потерян, а работа human-owned диалогов через forum topic не сломалась.

### TEST utility — runtime verified 14.10.2026

`sql/Сбросить забранные диалоги.sql` v0.3 — ручной TEST-only инструмент. Меняется только Telegram user ID менеджера; SQL возвращает его текущие захваченные TEST-диалоги в `bot/aktivnyy`, сохраняет историю и темы, отменяет незавершённые ожидания/действия и не затрагивает Production.

Runtime-проверка: `dialogov_sbroseno=2`, `current_role=qbit_test_owner`, `istoriya_sohranena=true`, `production_untouched=true`.

## WF-02B3C-E2E-03 — ACTIVE

Следующая маленькая задача: reminders / opt-out / recovery.

Проверять по одному небольшому сценарию, начиная с базового контракта reminder:
- reminder создаётся только после подтверждённо отправленного сообщения, которое действительно требует ответа;
- новый client input отменяет ожидание;
- handoff/refusal отменяют ожидание;
- Wait wake делает final DB recheck;
- unknown/ambiguous external delivery не повторяется вслепую;
- явный детерминированный внешний отказ не классифицируется как `neizvestno`;
- opt-out запрещает инициативные сообщения.

### WF-02B3C-E2E-03A — ACTIVE / partial runtime proof 15.10.2026

Runtime уже подтверждено на bot-owned TEST-диалоге:
- основной ответ действительно требовал ответа (`ozhidaet_otvet=true`), был подтверждён внешним Telegram result и получил `t0` по факту подтверждённой отправки;
- БД атомарно создала durable `napominanie_1` и `napominanie_2` только после confirmed outbound;
- для ускоренного TEST использовались разрешённые интервалы 1 и 3 минуты, а `poterya_posle_vtorogo_minut` установлен в минимально допустимые 60 минут;
- первое и второе напоминания реально пришли клиенту примерно через 1 и 3 минуты от основного ответа;
- напоминание не запускает новый reminder lifecycle: sender reminder содержит `napominanie_id`, поэтому reminder gate корректно отсекает его.

Во время теста найден runtime wiring defect в экспортированном workflow:
- старая нода `Нужно запланировать напоминания?` была ошибочно подключена после mirror-ветки;
- `Служебные события включены? зеркало` не имела входа от confirmed outbound;
- `Запустить зеркало по событию` ошибочно продолжал выполнение в старую reminder-ноду;
- `Сохранить намерение отправки` будил sender даже когда БД вернула отказ и outgoing intent не был создан.

Локально подготовлена repository-safe коррекция для `workflows/current/Шаблон — Workflow бота Qbit.json`:
- confirmed outbound расходится независимо в integration/reminder/loss/mirror checks;
- reminder gate использует пять явных AND-условий и ведёт только в `Ждать первое напоминание`;
- mirror gate ведёт только в `Запустить зеркало по событию`;
- после `Сохранить намерение отправки` добавлен gate `Исходящее действие создано?`, который будит sender только при `uspeshno/dublikat` и наличии `deystvie_id`;
- удалён disconnected LEGACY service/manual reply/Return cluster и orphan duplicate внутреннего ACK.

Static-проверка подготовленного JSON: валидный JSON, 148 nodes, без дублирующихся имён и битых connection targets; активных функциональных orphan nodes нет. Repository-safe export не содержит Credential refs и реальных Telegram ID. Файл подготовлен неактивным; его импорт/активация в n8n после этой фиксации ещё не являются runtime proof.

DoD 03A пока НЕ закрыт: осталось импортировать исправленный TEST JSON и доказать, что новый client input до срока отменяет старое ожидание, а stale reminder после wake не отправляется.

Production не затрагивался.

## Следующие этапы

После E2E-03: `WF-02B3C-E2E-04` — final regression/security.

## Rollback state

Для publication visibility существует поддерживаемый DB-05 API `otozvat_dokument_znaniy(jsonb)` под dash-admin role. Direct DML не использовать.

## Постоянные ограничения

- Production не менять.
- Рабочий трафик не переключать без отдельного разрешения.
- Не использовать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- `KB-01R5D` оставить до dashboard stage.
- VSCode/helper не подключать до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
