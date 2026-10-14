# Текущее состояние проекта

Обновлено: 2026-10-14.

## Режим

Реализация TEST-контура разрешена. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Каноническая schema: `qbit_bot_pervichnogo_obrascheniya`.

## Текущие workflow

Repository-safe файлы:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — service intake + knowledge processing + publish branch KB-03C;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот и active-only RAG search.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Instance-specific TEST runtime workflow и точечные diagnostic/reset artifacts в Git не сохраняются.

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
- manager/topic state читается narrow DB API;
- список менеджеров синхронизируется без прямого DML service role;
- optimistic concurrency работает: stale version возвращает `konflikt/stale_dialog_version`, повтор с актуальной версией успешен;
- `zabrat_dialog_operatorom(jsonb)` выполняет Take first-commit-wins;
- owner становится `chelovek`, status=`peredan_cheloveku`, закрепляется конкретный manager;
- публичное сообщение о захвате видно другим менеджерам;
- ручной текст закреплённого менеджера создаёт `sozdat_ruchnoe_ishodyashchee(jsonb)` и реально приходит клиенту через client sender;
- после Take клиентские сообщения продолжают сохраняться/зеркалироваться;
- бот после Take не отвечает;
- кнопка «Забрать диалог» после Take на новых сообщениях не показывается;
- read-only post-Take check: active reminders=0, pending bot/system outgoing=0, active bot jobs=0.

DoD 02B выполнен.

## WF-02B3C-E2E-02C — ACTIVE

Актуальное бизнес-решение 14.10.2026:
- менеджер ведёт клиентскую переписку только в теме общей служебной Telegram-группы;
- личный чат служебного бота используется только для важных уведомлений «нужен менеджер»;
- уведомления могут получать несколько активных разрешённых менеджеров;
- Take остаётся first-commit-wins, диалог закрепляется за одним менеджером;
- после Take диалог остаётся у менеджера; обязательное завершение сейчас не вводится;
- старый Return-переход не используется.

Runtime подтверждено:
- DB-03H `sozdat_lichnye_uvedomleniya_menedzheram(jsonb)` применён в TEST;
- `function_ok=true`;
- `bot_execute_ok=true`;
- `service_execute_denied=true`;
- `production_untouched=true`;
- служебный runtime v8 PRIVATE ALERTS импортирован и активирован;
- `/start` в личном чате разрешённого менеджера успешно подтвердил private chat;
- служебный бот ответил: личные уведомления о запросах менеджера подключены.

Подготовлено локально, но ещё не runtime-проверено:
- клиентский runtime v11 PRIVATE ALERTS — при human-needed создаёт fan-out через DB-03H и будит существующую очередь зеркала;
- сам workflow не принимает private chat ID и не выбирает менеджеров: получатели определяются внутри SECURITY DEFINER API по доверенной таблице менеджеров.

## Следующая маленькая задача — WF-02B3C-E2E-02C

1. Заменить клиентский TEST runtime v10 на v11 PRIVATE ALERTS.
2. Проверить Credentials и активировать только новый v11.
3. Отправить новый TEST-запрос человека от клиента.
4. Проверить одновременно:
   - в теме группы есть `🚨 Нужен менеджер`;
   - в личный чат подтверждённого менеджера пришло важное уведомление;
   - Take по-прежнему работает first-commit-wins;
   - после Take менеджер отвечает только из темы группы, бот не продолжает диалог.

DoD 02C: личное уведомление реально доставлено минимум одному подтверждённому менеджеру, групповой сигнал не потерян, Take и групповая ручная переписка продолжают работать.

Production не затрагивать. Не создавать competing webhook на service Telegram token.

## Следующие этапы

После 02C: `WF-02B3C-E2E-03` — reminders / opt-out / recovery, затем `WF-02B3C-E2E-04` — final regression/security.

## Rollback state

Для publication visibility существует поддерживаемый DB-05 API `otozvat_dokument_znaniy(jsonb)` под dash-admin role. Direct DML не использовать.

## Постоянные ограничения

- Production не менять.
- Рабочий трафик не переключать без отдельного разрешения.
- Не использовать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- `KB-01R5D` оставить до dashboard stage.
- VSCode/helper не подключать до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.