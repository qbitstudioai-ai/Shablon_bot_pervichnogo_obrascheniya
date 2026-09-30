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

Опасные runtime-gates до smoke оставлены выключенными:

1. `Взять следующее задание`;
2. `Взять исходящее действие`;
3. `Обработать следующее напоминание`;
4. `Взять создание темы оператора`;
5. `Взять событие зеркала оператору`.

Это означает, что сам импорт канонического JSON не должен запускать processing/sender/reminder/topic/mirror worker.

## Порядок runtime-smoke

Runtime выполняется только в test n8n и по одному участку.

### S1 — импорт

- импортировать канонический JSON;
- workflow оставить inactive;
- убедиться, что n8n не сообщает missing/unknown node type;
- проверить, что пять runtime-gates выше остаются disabled;
- не подключать production webhook и не переключать Telegram traffic.

Критерий: workflow открывается и сохраняется в test n8n без структурной ошибки.

### S2 — client ingress

Использовать только тестовый webhook и синтетический Telegram update без реальных переписок.

Проверить:
- Header Auth обязателен;
- `zaregistrirovat_vhod_klienta(jsonb)` возвращает `uspeshno` или `dublikat`;
- HTTP 200 выдаётся только после успешной DB-регистрации;
- повтор того же update не создаёт второй вход/job.

Processing claim при этом остаётся disabled.

### S3 — queue

Временно включить только `Взять следующее задание`.

Проверить:
- claim идёт через `zabrat_zadanie_obrabotki(jsonb)`;
- возвращаются `zadanie_id`, `worker_id/vladelec_arendy`, `nomer_vladeniya`, `versiya_dialoga`;
- exact source читается через `poluchit_soderzhimoe_zadaniya(jsonb)`;
- stale worker/version не получает право продолжить.

До AI/Telegram внешних вызовов smoke должен останавливаться безопасно, если trusted профиль компании ещё не заполнен.

После проверки gate снова выключить.

### S4 — outgoing

Создать только тестовое durable outgoing action разрешённым DB API. Затем временно включить `Взять исходящее действие`.

Проверить:
- claim через `zabrat_ishodyashchee_deystvie(jsonb)`;
- final pre-send recheck через `poluchit_soderzhimoe_ishodyashchego(jsonb)`;
- confirmed фиксируется через `zafiksirovat_rezultat_ishodyashchego(jsonb)`;
- ambiguous/unknown не повторяется вслепую.

Если для Telegram-send нет отдельно разрешённого test Credential/chat, проверка останавливается до внешней отправки и это не считается провалом DB/sender contract.

После проверки gate снова выключить.

### S5 — operator

Использовать только test service workflow/Telegram.

По отдельности проверить:
- service ingress → `zaregistrirovat_sluzhebnoe_sobytie(jsonb)`;
- topic claim → `zabrat_sozdanie_operator_temy(jsonb)`;
- точный `message_thread_id` → `podtverdit_operator_temu(jsonb)`;
- неоднозначный createForumTopic → terminal `otmetit_temu_neizvestnoy(jsonb)`, без blind retry;
- mirror claim → `zabrat_sobytie_zerkala(jsonb)`;
- mirror confirmed/unknown/error → `zafiksirovat_rezultat_zerkala(jsonb)`.

Topic и mirror gates включать только по одному и после проверки снова выключать.

## Что не входит в WF-02B3

- production webhook или production Telegram traffic;
- production schema/data;
- удаление рабочих данных;
- DB-04/DB-05 и RAG quality;
- смена Credentials;
- массовые реальные сообщения;
- окончательная проверка OpenAI profile — она закрывается отдельными PRE-02 задачами.

## Текущий результат

Статический preflight подтверждён. Runtime import/smoke пока не доказан, поэтому WF-02B3 остаётся **в работе**.
