# Текущее состояние проекта

Обновлено: 2026-10-13.

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

### KB-03C2 final runtime 10.10.2026

Target:
- document `2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- upload `328035d0-6fd7-4af3-83a3-2643a8b24d2f`;
- job `91de6175-da91-471a-be7a-97feffb646a3`.

До publish worker queue был очищен только от двух конкретных старых TEST retry jobs отдельными guarded one-shot workflow; массовой очистки не было.

Atomic publish result:
- `rezultat=uspeshno`;
- previous active = NULL;
- version=`opublikovana`, upload=`zavershena`, workflow terminal `publish_vypolnen=true`.

Post-publish read-only verification:
- active pointer = exact target version;
- job=`zaversheno`;
- lease owner/deadline = NULL;
- fragments=53;
- published versions for the document=1;
- result `KB03C2_POST_PUBLISH_OK`.

Bot active-only regression:
- actual PostgreSQL role=`qbit_test_bot`;
- function EXECUTE=true;
- direct fragment table SELECT=false;
- search results=12;
- target-version results=12;
- other-version results=0;
- old-draft results=0;
- max similarity=`0.793885026323472`;
- result `KB03C2_BOT_ACTIVE_ONLY_OK`.

Stale expected-active protection не провоцировалась повторно на текущей published target version: DB function short-circuits same-active publish как `dublikat`. Сам optimistic-concurrency path уже runtime-проверен ранее через реальный service role на synthetic competing V2/V3 (`konflikt/stale_expected_active`) в `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`; C1 stale routing дополнительно статически проверен.

Evidence:
`docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## WF-02B3C — event-driven TEST runtime — IN PROGRESS

Активный малый план: `docs/WF-02B3C_E2E_PLAN.md`.

### WF-02B3C-E2E-01 — CLOSED / runtime verified 11.10.2026

Реальный клиентский Telegram vertical slice прошёл до grounded ответа:
- ingress/processing выполнялись в TEST;
- guard корректно разрешил вопрос по услугам/ценам и запросил RAG;
- planner + OpenAI embedding отработали;
- active-only поиск использует текущий DB-05 API `qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)` под bot role;
- caller не требует `USAGE` на schema `extensions`;
- RAG adapter читает актуальные поля DB-05 `tekst_fragmenta/shodstvo`;
- answer-LLM получила непустой evidence и сформировала содержательный ответ по опубликованным знаниям;
- клиент реально получил ответ в Telegram;
- в финальном чистом проходе ложной передачи менеджеру не было.

Во время E2E были найдены и исправлены только в TEST runtime:
- конфликт internal webhook topology с unused Respond to Webhook в n8n 2.41.0;
- старое состояние тестового диалога `peredacha_cheloveku`, для одного разрешённого TEST dialog выполнен guarded reset без удаления raw history;
- legacy RAG вызов с внешним `extensions.vector` cast;
- отсутствие schema qualification при DB-05 call;
- legacy mapping `soderzhanie/podobie` вместо текущего `tekst_fragmenta/shodstvo`.

### WF-02B3C-E2E-02A — CLOSED / runtime verified 12.10.2026

Реальный TEST handoff до служебной operator topic подтверждён:
- явная просьба клиента о человеке перевела обработку в durable human-needed path;
- обычный bot-answer path не продолжился;
- event-driven topic worker выдал topic intent без polling;
- текущая n8n Telegram node не поддерживает `createForumTopic`, поэтому в TEST используется отдельный минимальный bridge к Telegram Bot API без хранения Telegram token в workflow;
- после нормализации числового service chat ID в JSON как Number Telegram подтвердил `createForumTopic`;
- DB mapping operator topic подтверждён со статусом `gotova` и сохранённым thread ID;
- queued mirror events привязались к thread и реально появились в созданной topic;
- human-needed сигнал с кнопкой «Забрать диалог» реально виден в служебной topic;
- competing service Telegram webhook не создавался; Production не затрагивался.

Первое отображение topic было backlog-flush после позднего создания темы: клиентские mirror-сообщения и bot-сообщения пришли пачками. Это не считается проверкой steady-state порядка. В начале E2E-02B нужно отправить одно новое client message и проверить live mirror в уже существующую topic до нажатия Take.

Обнаруженный recovery debt: явный Telegram HTTP 4xx сейчас попадает в общий `create_forum_topic_neizvestno`. До финального recovery/regression нужно разделить детерминированный внешний отказ и действительно неоднозначный transport/result outcome; blind retry допустим только после доказанного отсутствия внешнего успеха.

Operability debt: один client message сейчас может порождать несколько n8n executions. Перед финальным regression отдельно оценить упрощение в сторону одного основного execution, сохраняя отдельные Wait/sender executions только там, где это оправдано lifecycle/reliability.

`WF-02B3C` как родитель остаётся `[~]`: atomic Take, manual reply, completion, reminders/opt-out/recovery и финальный regression ещё не закрыты.

### WF-02B3C-E2E-02B — runtime progress 13.10.2026

Подтверждено в TEST runtime:
- новое клиентское сообщение live-зеркалируется в уже существующую тему;
- подтверждённый ответ бота также live-зеркалируется;
- callback «Забрать диалог» проходит через существующий служебный webhook и durable ingress;
- отдельный webhook для того же служебного Telegram-бота не создавался;
- список разрешённых менеджеров синхронизируется через узкую SECURITY DEFINER функцию без прямого DML служебной роли;
- `zabrat_dialog_operatorom(jsonb)` успешно перевёл owner `bot → chelovek` и закрепил конкретного менеджера;
- в теме появляется публичное сообщение `👤 Диалог переключён на <имя менеджера>` и статус владельца;
- текст закреплённого менеджера проходит через `sozdat_ruchnoe_ishodyashchee(jsonb)` и существующий client sender и реально доставляется клиенту;
- после Take новые сообщения клиента продолжают зеркалироваться в ту же тему;
- после исправления runtime client mirror кнопка «Забрать диалог» больше не показывается на новых сообщениях, когда текущий владелец уже `chelovek`.

Ещё не проверено для закрытия E2E-02B:
- новый клиентский вход после Take не должен запускать новый bot-answer;
- stale/in-flight bot outgoing после Take должен быть отброшен финальной проверкой;
- ранее запланированные напоминания после Take не должны отправляться.

Отдельное бизнес-решение 13.10.2026: после захвата менеджер должен вести текущий диалог до завершения; возврат этому же диалогу обратно боту больше не является целевым сценарием. Нужна отдельная следующая задача для явного действия «Завершить диалог» и обновления нормативной спецификации.

## Следующая маленькая задача — WF-02B3C-E2E-02B

Завершить проверку bot stop после уже подтверждённого Take:
- отправить одно новое TEST-сообщение клиента в уже захваченном диалоге;
- убедиться, что оно сохраняется и зеркалируется, но автоматический ответ бота не создаётся и не отправляется;
- проверить final-recheck для потенциального stale outgoing;
- проверить, что напоминания текущего диалога отменены/не отправляются после Take.

После этого E2E-02B можно закрыть и перейти к отдельной задаче ручного завершения диалога менеджером.

Production не затрагивать. Не создавать competing webhook на service Telegram token.

## Rollback state

Для publication visibility существует поддерживаемый DB-05 API `otozvat_dokument_znaniy(jsonb)` под dash-admin role. В KB-03C2 rollback не выполнялся, потому что publish и active-only проверки прошли успешно.

При первой active version revoke вернул бы document active pointer в NULL и archived бы текущую version. Это rollback видимости публикации, а не полное восстановление job/upload статусов. Прямой DML не использовать.

## Постоянные ограничения

- Production не менять.
- Рабочий трафик не переключать без отдельного разрешения.
- Не использовать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- `KB-01R5D` оставить до dashboard stage.
- VSCode/helper не подключать до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
