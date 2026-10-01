# WF-02B3 — controlled n8n smoke checks

Дата начала: 30 сентября 2026.

Статус: **в работе**. Это доказательство подготовки и статического preflight; runtime-smoke в n8n ещё не подтверждён.

## Объект проверки

Канонический файл:

`workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`

Исходный Git HEAD для preflight:

`39753d78306bfd0f718e430a9431d21f44c212f5`

Цель WF-02B3 — импортировать этот workflow в **test n8n 2.41.0** и выполнить только разрешённые smoke-проверки ingress / queue / outgoing / operator. Production и рабочий трафик не менять.

## Статический preflight — VERIFIED

Проверка канонического JSON дала:

- JSON разбирается без ошибки;
- `active=false`;
- 167 нод;
- 140 connection keys;
- duplicate node names: 0;
- dangling connections: 0;
- Credential references в export: 0;
- `instanceId`: отсутствует;
- literal `Authorization`, Bearer token, API key и password: не найдены;
- client webhook: `qbit-test-telegram-v2`, `headerAuth`, ответ через Respond to Webhook;
- service webhook: `qbit-test-service-telegram-v1`, `headerAuth`, ответ через Respond to Webhook.

Пять worker Postgres-нод в каноническом JSON имеют `disabled=true`:

1. `Взять следующее задание`;
2. `Взять исходящее действие`;
3. `Обработать следующее напоминание`;
4. `Взять создание темы оператора`;
5. `Взять событие зеркала оператору`.

**Исправление безопасности 30.09.2026:** в n8n 2.41.0 отключённая обычная нода не является stop-gate: execution engine передаёт её вход дальше (`handleDisabledNode` возвращает первый main input). Поэтому эти пять `disabled`-нод нельзя считать надёжной блокировкой runtime. До WF-02B3A workflow обязан оставаться `inactive`, а controlled smoke нельзя запускать через расписания. Источник: исходный код n8n 2.41.0, `packages/core/src/execution-engine/workflow-execute.ts`.

WF-02B3A должен заменить это на явные execution gates, у которых закрытая ветка физически не продолжает worker, и добавить credential-routing validation.

## S0 — подключение PostgreSQL — PARTIAL VERIFIED

30 сентября 2026 Павел явно разрешил настройку test Credentials и runtime-проверки в test n8n.

Проверено:
- ограниченная роль `qbit_test_bot` имеет LOGIN/CONNECT/USAGE и не имеет superuser/createdb/createrole/bypassrls;
- прямой TCP-вход этой роли в PostgreSQL успешно проверен;
- Docker публикует PostgreSQL только на loopback хоста БД, не на `0.0.0.0`;
- транспорт n8n → DB server идёт через SSH tunnel по Private Key;
- Postgres Credential в test n8n успешно прошёл connection test под `qbit_test_bot`;
- tenant suffix Supavisor в прямом PostgreSQL-пути не используется;
- секреты, DB password, private key и адрес сервера в GitHub не сохранены.

Supavisor в этой test-установке не выбран базовым runtime-путём для n8n: встроенное административное подключение через pooler работало, но custom runtime-role получила password-auth error при том же валидном PostgreSQL password. Это не мешает прямому ограниченному PostgreSQL-подключению через SSH.

Отдельный Credential роли `qbit_test_sluzhebnyy` и остальные API Credentials ещё нужно проверить.

Подробное переносимое правило: [N8N_POSTGRES_CONNECTION](N8N_POSTGRES_CONNECTION.md).

## Порядок runtime-smoke

Runtime выполняется только в test n8n и по одному участку.

### S1 — импорт

- импортировать канонический JSON;
- workflow оставить inactive;
- убедиться, что n8n не сообщает missing/unknown node type;
- проверить, что workflow остаётся inactive; состояние `disabled` worker-нод фиксируется только как структура импорта и **не считается защитным gate**;
- не подключать production webhook и не переключать Telegram traffic.

Критерий: workflow открывается и сохраняется в test n8n без структурной ошибки.

### S2 — client ingress

Использовать только тестовый webhook и синтетический Telegram update без реальных переписок.

Проверить:
- Header Auth обязателен;
- `zaregistrirovat_vhod_klienta(jsonb)` возвращает `uspeshno` или `dublikat`;
- HTTP 200 выдаётся только после успешной DB-регистрации;
- повтор того же update не создаёт второй вход/job.

Processing worker при этом остаётся закрыт **явным execution gate WF-02B3A**. До его появления S2 разрешён только как изолированный ручной ingress-test без активации workflow.

### S3 — queue

Открыть только явный queue execution gate WF-02B3A. Само переключение `disabled` у Postgres-ноды не используется как механизм безопасности.

Проверить:
- claim идёт через `zabrat_zadanie_obrabotki(jsonb)`;
- возвращаются `zadanie_id`, `worker_id/vladelec_arendy`, `nomer_vladeniya`, `versiya_dialoga`;
- exact source читается через `poluchit_soderzhimoe_zadaniya(jsonb)`;
- stale worker/version не получает право продолжить.

До AI/Telegram внешних вызовов smoke должен останавливаться безопасно, если trusted профиль компании ещё не заполнен.

После проверки явный execution gate снова закрыть.

### S4 — outgoing

Создать только тестовое durable outgoing action разрешённым DB API. Затем открыть только явный outgoing execution gate WF-02B3A.

Проверить:
- claim через `zabrat_ishodyashchee_deystvie(jsonb)`;
- final pre-send recheck через `poluchit_soderzhimoe_ishodyashchego(jsonb)`;
- confirmed фиксируется через `zafiksirovat_rezultat_ishodyashchego(jsonb)`;
- ambiguous/unknown не повторяется вслепую.

Если для Telegram-send нет отдельно разрешённого test Credential/chat, проверка останавливается до внешней отправки и это не считается провалом DB/sender contract.

После проверки явный execution gate снова закрыть.

### S5 — operator

Использовать только test service workflow/Telegram.

По отдельности проверить:
- service ingress → `zaregistrirovat_sluzhebnoe_sobytie(jsonb)`;
- topic claim → `zabrat_sozdanie_operator_temy(jsonb)`;
- точный `message_thread_id` → `podtverdit_operator_temu(jsonb)`;
- неоднозначный createForumTopic → terminal `otmetit_temu_neizvestnoy(jsonb)`, без blind retry;
- mirror claim → `zabrat_sobytie_zerkala(jsonb)`;
- mirror confirmed/unknown/error → `zafiksirovat_rezultat_zerkala(jsonb)`.

Явные topic и mirror execution gates WF-02B3A открывать только по одному и после проверки снова закрывать.

## Что не входит в WF-02B3

- production webhook или production Telegram traffic;
- production schema/data;
- удаление рабочих данных;
- DB-04/DB-05 и RAG quality;
- production Credentials и публикация любых секретов; test Credentials разрешены Павлом 30.09.2026 и проверяются в рамках controlled smoke;
- массовые реальные сообщения;
- окончательная проверка OpenAI profile — она закрывается отдельными PRE-02 задачами.

## Текущий результат

Статический preflight подтверждён. Test Postgres Credential `qbit_test_bot` также прошёл реальный connection test через SSH tunnel и прямой PostgreSQL. Дополнительная проверка исходного кода n8n 2.41.0 показала, что `disabled` обычной ноды — pass-through, а не stop-gate. Поэтому runtime smoke заблокирован до WF-02B3A (явные execution gates + автоматический DB Credential audit). WF-02B3 остаётся **в работе**.


## WF-02B3A — VERIFIED offline 30.09.2026

Исправлен ошибочный safety-механизм на `disabled` обычных нод n8n:

- добавлены пять явных IF execution gates: processing, outgoing, reminders, operator_topic, operator_mirror;
- все пять flags находятся в trusted `Настройки компании.runtime_gates` и по умолчанию `false`;
- false branch каждого gate не имеет downstream;
- пять worker Postgres nodes снова enabled: их выполнение контролирует gate, а не `disabled=true`;
- актуальные DB-03D1 service Postgres nodes имеют префикс `Служебный_`;
- старые service SQL nodes помечены `LEGACY_Служебный_`;
- Schedule Trigger старой служебной очереди физически не имеет downstream; queue-output service switch также пуст;
- legacy service block недостижим от trigger/webhook;
- канонический workflow не содержит Credential refs;
- `tools/check_n8n_postgres_credentials.py` проверяет gates, legacy reachability и runtime bot/service Credential routing без вывода Credential IDs.

Для текущего test n8n подготовлен отдельный import-ready runtime JSON на основе свежего export Павла. В нём существующие bot/service Credentials назначены автоматически всем Postgres nodes по классу. Этот instance-specific файл не сохраняется в GitHub.

WF-02B3A закрыт offline. WF-02B3 остаётся в работе до реального импорта и controlled runtime smoke.


### S1 runtime import accepted — 30.09.2026

Павел импортировал подготовленный WF-02B3A instance-specific JSON в test n8n 2.41.0. n8n принял workflow без видимых ошибок импорта. Это подтверждает отсутствие явной структурной/import ошибки на стороне UI.

На момент фиксации workflow не активировать. Проверка сохранения в inactive state и последующий client-ingress smoke выполняются отдельно.


## WF-02B3B — quiet interactive smoke

После первого production-webhook запуска обнаружено, что включённые Schedule Trigger создают отдельные executions каждые 3–5 секунд/1 минуту даже при закрытых runtime gates. Это засоряет Execution history и мешает искать ошибку конкретного Telegram-запроса.

Для интерактивного smoke все четыре Schedule Trigger в каноническом workflow выставлены `disabled=true`:
- `Проверять очередь`;
- `Проверять напоминания`;
- `Проверять зеркало оператору`;
- `Проверять служебную очередь`.

Для trigger nodes это корректный механизм: n8n 2.41.0 `Workflow.queryNodes()` пропускает nodes с `disabled === true` при формировании trigger/poll node set. Это отличается от выполнения disabled ordinary node внутри уже начавшегося execution.

Во время текущего Telegram smoke workflow можно активировать только с этими четырьмя Schedule Trigger disabled. Тогда новый execution должен создаваться только внешним webhook/ручным тестом. Worker schedules включаются позже по одному, когда соответствующая ветка готова к runtime проверке.


### WF-02B3B runtime export graph repair — 30.09.2026

Проверен свежий export Павла после первого Telegram production-webhook test.

Найдено:
- 172 nodes;
- 191 фактическое edge-соединение;
- dangling connections = 0;
- Merge nodes имеют необходимые input 0/1;
- единственное отличие фактических edges от текущего canonical graph — лишняя runtime-связь `Подтвердить приём клиенту -> Не брать job сразу после webhook`;
- эта связь опасна, потому что disabled ordinary node в n8n 2.41.0 не является stop-gate;
- четыре Schedule Trigger в runtime export всё ещё были enabled.

Подготовлен новый instance-specific runtime JSON:
- лишняя связь удалена;
- все 4 Schedule Trigger disabled;
- существующие Credentials Павла сохранены;
- итог: 172 nodes / 190 edges / dangling=0 / Merge inputs OK;
- legacy service polling остаётся физически отсоединённым.

Canonical workflow в GitHub уже содержал правильную структуру; executable canonical файл в этом шаге менять не потребовалось.


## WF-02B3C — event-driven smoke

Архитектура runtime-smoke изменена после фактического шума от periodic executions.

Ожидаемая цепочка одного клиентского сообщения:
1. client Telegram webhook execution: durable ingress + HTTP response + emit processing event;
2. processing event execution: claim/process one DB job; при создании outgoing intent emit sender event;
3. outgoing event execution: claim/final recheck/send/confirm;
4. если confirmed message действительно требует ответа — execution переходит в Wait; после пробуждения DB final recheck решает reminder1/reminder2/loss-check.

Schedule Trigger и резервный sweeper отсутствуют.

Service topic/mirror event emissions остаются выключены до отдельного service Telegram Credential.

Критерий первого smoke: после одного Telegram message нет periodic executions; executions появляются только как причинно связанные ingress/event runs.
