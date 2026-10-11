# Текущее состояние проекта

Обновлено: 2026-10-11.

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
- version=`opublikovana`;
- upload=`zavershena`;
- workflow terminal `publish_vypolnen=true`.

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

`WF-02B3C` как родитель остаётся `[~]`: operator handoff, reminders/opt-out/recovery и финальный regression ещё не проверены.

## Следующая маленькая задача — WF-02B3C-E2E-02

Проверить один TEST operator handoff/service-bot vertical slice по `docs/WF-02B3C_E2E_PLAN.md`:
- явная просьба клиента подключить человека;
- durable human-needed state;
- service topic/mirror path через согласованный service ingress;
- atomic Take;
- после Take bot/reminders не продолжают диалог;
- manual reply и explicit Return.

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
