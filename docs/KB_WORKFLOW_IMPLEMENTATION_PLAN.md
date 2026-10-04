# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-04.

Этот план заменяет завершённый `KB-01R` как активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5; старые строки `[ ] DB-04/DB-05` в `WORKPLAN_TEMPLATE.md` считаются отставшим сводным планом и не являются фактическим состоянием.

Каноническая основа workflow: фактический export Павла `Шаблон — служебный Telegram и перехват диалогов — версия 0.2 (7).json`. Git checkpoint 03.10.2026 был сделан из `(6)`, поэтому `(7)` принят как более свежая фактическая основа. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`. Полный очищенный v0.4 KB-01A уже создан и статически проверен, но большой JSON/checkpoint ещё не записан в Git из-за ограничения текущего GitHub-коннектора; это отдельный обязательный шаг помощника VSCode перед runtime.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [~] KB-01A | DB-03D1, DB-04 | Единый служебный Telegram webhook после durable registration выделяет только личный `.md` от разрешённого user/chat, ограничивает заявленный размер, скачивает файл служебным ботом, проверяет фактические bytes и регистрирует их через `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)`, которая создаёт durable knowledge job. Полный JSON подготовлен и статически проверен; runtime реальным `.md` оставлен следующей сессии. |
| [ ] KB-01B | KB-01A runtime | Knowledge worker claim-ит durable job с lease/fencing, безопасно разбирает YAML/Markdown, проверяет обязательные поля/структуру, рассчитывает канонический hash/processing fingerprint и вызывает `podgotovit_versiyu_znaniy`. Дубль активной версии не идёт дальше. |
| [ ] KB-02A | KB-01B | Детерминированная очистка и chunking сохраняют путь заголовков, FAQ, таблицы и факты; профиль 600/800/100 считается токенизатором выбранной embedding-модели; контрольные вопросы не входят в поисковый текст. |
| [ ] KB-02B | KB-02A | 3–10 контрольных вопросов извлечены отдельно, подготовлены окончательные fragments с метаданными/хэшами/числом токенов; ошибки завершают или безопасно повторяют только текущий fenced knowledge job. |
| [ ] KB-03A | KB-02B | В том же каноническом workflow документные embeddings создаются OpenAI `text-embedding-3-large` с `dimensions=1024`, длина каждого фактического вектора строго проверяется, затем fragments/vectors сохраняются через нормативный DB API. Это одновременно runtime-проверка бывшего PRE-02E; отдельного smoke-workflow PRE-02E нет. |
| [ ] KB-03B | KB-03A | Каждый reference question векторизуется тем же профилем, выполняется `poisk_chernovika_znaniy` только по своей версии, результаты сохраняются через `sohranit_proverki_znaniy`; версия становится `gotova` только после полного набора успешных проверок. |
| [ ] KB-03C | KB-03B | `opublikovat_versiyu_znaniy` атомарно переключает active version и архивирует прежнюю; stale publish конфликтует; Telegram-отчёт выполняется после публикации и его сбой не откатывает знания. Knowledge job корректно завершается. |

## KB-01A — текущая подзадача

### Что реализовано в JSON

- Существующий `Принять вход служебного бота` остаётся единственным webhook.
- `Служебный_Сохранить служебный вход` по-прежнему первым долговечно регистрирует update через DB-03D1; HTTP acknowledgement не переносится перед commit.
- После durable registration только `dokument_kb` идёт в knowledge intake; callback, `/start`, сообщения менеджеров и operator routing не переводятся в KB.
- В `Настройки служебного бота` добавлен блок `kb`: включение, лимит 5 MiB и два whitelist-массива — Telegram user ID и private chat ID. В каноническом JSON они пустые и должны быть заполнены Павлом в n8n перед runtime-test.
- До скачивания проверяются private chat, whitelist, `.md`, `file_id` и заявленный размер.
- Файл скачивается через существующий служебный Telegram Credential, который Павел выбирает в UI n8n после импорта.
- Фактические bytes извлекаются из binary data n8n, повторно проверяется размер.
- `Служебный_KB_Зарегистрировать загрузку` вызывает `qbit_bot_pervichnogo_obrascheniya.zaregistrirovat_zagruzku_znaniy(jsonb, bytea)` только через служебный PostgreSQL Credential. БД остаётся окончательным gate для `.md`, UTF-8, фактических bytes, SHA-256, durable service event и idempotency/conflict.
- На `uspeshno` создаются upload и durable `zadaniya_znaniy`; парсинг/chunking/embedding/check/publish в KB-01A не выполняются.

### Статическая проверка этой сессии

- JSON импортного формата разбирается как корректный JSON; SHA-256 pretty artifact `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.
- 196 nodes, 161 connection keys, 225 edges.
- `active=false`.
- duplicate node names: 0.
- dangling connections: 0.
- все изменённые/новые Code nodes проходят `node --check`.
- top-level `id`, `versionId`, `meta.instanceId` отсутствуют.
- node `credentials` отсутствуют полностью.
- реальный ID служебной Telegram-группы удалён.
- очевидные OpenAI keys, Bearer tokens и Telegram bot tokens не найдены.
- существующий OpenAI query-embedding adapter сохранён: `/v1/embeddings`, `text-embedding-3-large`, `dimensions=1024`, строгая проверка длины. Документная embedding-ветка добавляется в KB-03A.

### Что ещё не проверено

Файл не импортировался в n8n в этой сессии и реальный `.md` не отправлялся. Большой JSON/checkpoint также ещё не записан в Git: его должен сохранить помощник VSCode ровно из подготовленного artifact. Поэтому KB-01A остаётся `[~]`, а не `[x]`.

Для закрытия KB-01A следующая сессия должна импортировать канонический JSON, назначить служебные Telegram/Postgres Credentials, заполнить whitelist, отправить один безопасный test `.md` и подтвердить:
1. webhook подтверждён только после durable service event;
2. Telegram сообщает, что файл поставлен в очередь;
3. DB возвращает `uspeshno` с `zagruzka_id` и `zadanie_id`;
4. knowledge job имеет ожидаемое состояние `ozhidaet`;
5. остальные служебные маршруты не сломаны.

Production, рабочий трафик и реальные документы компании этой задачей не меняются.
