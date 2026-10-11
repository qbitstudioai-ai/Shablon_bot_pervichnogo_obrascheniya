# SESSION HANDOFF

Обновлено: 2026-10-11.

## Исходная точка

Рабочая ветка: `main`.

HEAD до текущего блока WF-02B3C: `f7fc58ed2ddcbe9166532eb6af36afe9e348eaf4` (`docs: close KB-03C2 runtime verification`).

В этой сессии документация WF-02B3C обновлялась отдельными последовательными GitHub commits; новая сессия обязана сначала перечитать фактический HEAD `main`.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

## Текущие repository-safe workflow

- `workflows/current/Шаблон Загрузка документов Qbit.json` — knowledge pipeline + publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — client bot + active-only knowledge search.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

Instance-specific TEST runtime workflow и diagnostic/reset artifacts в repository-safe JSON не переносились.

## KB-03C2 — CLOSED / runtime verified

Runtime target был опубликован и active-only поиск под `qbit_test_bot` проверен: 12/12 результатов только из target published version; direct SELECT fragments=false. Полное evidence:
`docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

Supported publication-visibility rollback: `otozvat_dokument_znaniy(jsonb)` через dash-admin role после отдельной необходимости/авторизации. Direct DML не использовать.

## WF-02B3C — IN PROGRESS

Активный малый план:
`docs/WF-02B3C_E2E_PLAN.md`.

### WF-02B3C-E2E-01 — CLOSED / runtime verified 11.10.2026

Реальный TEST client Telegram vertical slice завершился содержательным grounded ответом клиенту.

Подтверждено:
- guard классифицирует вопрос по услуге/цене как `razresheno` и `nuzhen_rag=true` на чистом состоянии диалога;
- planner и OpenAI embedding отрабатывают;
- DB-05 active search вызывается текущей функцией `qbit_bot_pervichnogo_obrascheniya.poisk_aktivnyh_znaniy(jsonb)` под bot PostgreSQL role;
- caller не получает лишний доступ к schema `extensions`;
- RAG adapter использует `tekst_fragmenta` и `shodstvo` текущего DB-05 contract;
- answer-LLM получает непустой evidence;
- клиент реально получил grounded ответ и follow-up вопрос;
- финальный чистый проход не ушёл в handoff.

### Что обнаружили по пути

1. Internal event webhooks в n8n 2.41.0 требовали явный Respond to Webhook ack; иначе event call падал из-за unused Respond node topology.
2. Client runtime временно содержал лишний service/KB pipeline; для текущей TEST runtime-копии оставили только client + active-only RAG.
3. После старых тестов один TEST dialog сохранял stage `peredacha_cheloveku`; Павел отдельно разрешил точечный guarded reset. Raw history не удалялась.
4. Старый RAG SQL делал caller-side `::extensions.vector(1024)` и использовал устаревший интерфейс; текущий DB-05 принимает JSONB.
5. Вызов DB-05 без schema qualification не находился по connection `search_path`; используется полное имя schema.
6. RAG adapter ждал legacy `soderzhanie/podobie`, поэтому evidence был пустым и answer-LLM логично выбирала менеджера. Mapping исправлен на `tekst_fragmenta/shodstvo`.

Не считать старые ложные handoff доказательством плохого guard: после чистого reset guard корректно разрешил тот же вопрос; последующий handoff был вызван пустым evidence до исправления RAG mapping.

## Текущая модель TEST runtime

Guard/planner/answer: `gpt-6-luna` с low reasoning. Embedding: `text-embedding-3-large`, dimensions 1024.

Не менять модель только из-за уже исправленных ошибок state/RAG adapter. Повышать отдельную роль только если дальнейший runtime покажет проблему качества самой модели.

## Следующая маленькая задача — WF-02B3C-E2E-02

Новая сессия должна проверить один TEST operator handoff/service-bot vertical slice:
1. перечитать `README.md`, `docs/PROJECT_STATE.md`, этот handoff и `docs/WF-02B3C_E2E_PLAN.md`;
2. проверить фактический HEAD `main`;
3. использовать текущие два runtime workflow: client и service/KB; не плодить отдельные diagnostic workflow без фактической ошибки;
4. отправить клиенту явную просьбу подключить человека;
5. доказать durable human-needed state и service Telegram route;
6. проверить atomic Take, что после Take bot/reminders не продолжают диалог;
7. проверить manual manager reply и explicit Return;
8. production не трогать и не создавать competing webhook на service Telegram token.

После E2E-02 отдельно останутся reminders/opt-out/recovery и финальный regression/security.

## Постоянные ограничения

- Production/рабочие данные/рабочий трафик не менять без отдельного явного разрешения Павла.
- Реальные Telegram ID, Credential refs, secrets, переписки и документы компаний не сохранять в Git.
- Один service Telegram bot использует один согласованный webhook ingress; competing webhooks на том же token запрещены.
- VSCode/helper до dashboard stage не подключать.
