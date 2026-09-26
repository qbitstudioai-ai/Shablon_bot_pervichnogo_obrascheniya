# SESSION HANDOFF

Обновлено: 25 сентября 2026.

## Где остановились

Текущий Supabase-этап завершён.

DB-03 полностью завершён и проверен. DB-SCHEMA-01 и DB-SCHEMA-01F также закрыты.

Canonical qBit schema:
`qbit_bot_pervichnogo_obrascheniya`.

Роли `qbit_test_*` намеренно не переименовывались.

Финальный серверный verifier:
`sql/DB-SCHEMA-01F_v0.4_verify_renamed_schema.sql`.

Павел успешно выполнил его в Supabase Studio. Подтверждено:
- `verifier_version=DB-SCHEMA-01F_v0.4_fresh_path`;
- `db_schema_01f_status=verified`;
- old `qbit_test` absent;
- new schema present;
- owner `qbit_test_owner`;
- 25 tables;
- 28 SECURITY DEFINER functions;
- EXECUTE distribution bot=17 / service=10 / dash_admin=1;
- runtime direct DML denied;
- temporary CREATE ON DATABASE revoked;
- canary `kompaniya_001_test` present;
- production `qbit` is not required and is currently absent;
- `supabase_stage_complete=true`;
- `next_stage=PRE-02_n8n_openrouter`.

Старый `sql/DB-SCHEMA-01_rename_qbit_schema.sql` и промежуточные verifier v0.1–v0.3 больше не запускать.

## Следующая одна задача

**PRE-02A — runtime-проверка LLM-профиля в n8n/OpenRouter.**

Текущая сессия уже:
1. сверила `main` = `2879c826bbd577b0dbf255d9ee1cf75ce59c658d` перед началом работы;
2. прочитала README, PROJECT_STATE, WORKPLAN_TEMPLATE, SESSION_HANDOFF, DOCUMENTATION_RULES и PROCESSING_PROFILE;
3. разделила большой PRE-02 на PRE-02A…PRE-02D;
4. по официальной документации OpenRouter на 25.09.2026 подтвердила актуальность `deepseek/deepseek-v4.1-flash`, `qwen/qwen3-embedding-8b` и параметра embeddings `dimensions`;
5. не выполняла runtime-вызов и не меняла Credentials/production.

Павел передал экспорт `Шаблон — служебный Telegram и перехват диалогов — версия 0.1.json`. Текущая сессия выполнила read-only аудит и **не сохранила сам JSON в GitHub**.

Результат аудита:
- 168 нод, 192 связи; все функциональные ноды достижимы от trigger-веток;
- явных API/Telegram токенов и закреплённых реальных Telegram ID не найдено;
- экспорт содержит `instanceId` конкретного n8n и другие instance-specific ID, поэтому требует очистки перед публичным GitHub;
- 33 PostgreSQL-ноды используют старый контракт: из 31 уникального прикладного вызова только три совпадают по имени с текущими 28 DB-03 функциями, и у всех трёх несовместимая сигнатура;
- workflow вызывает `poisk_aktivnyh_znaniy`, но DB-05 ещё не начат;
- один экспорт объединяет клиентскую и служебную части, хотя актуальная архитектура требует отдельные workflow;
- поэтому этот JSON нельзя считать актуальным runtime-шаблоном и нельзя использовать для Telegram end-to-end теста без доработки.

В WORKPLAN добавлена будущая задача **WF-02**. Важное решение Павла: согласованную логику и порядок текущего pipeline максимально сохранить. WF-02 не является перепроектированием CORE; разрешённые изменения — только техническая стыковка существующих нод с DB-03 JSONB API, подготовка переносимых клиентского/служебного экспортов, очистка metadata и недопуск будущих DB-04/DB-05 веток к исполнению раньше их этапа.

Текущая активная задача остаётся **PRE-02A**. Географическая проверка дала различие: российский n8n получает `403 Forbidden` на OpenRouter Credential, а на сервере Павла в Амстердаме с n8n 2.20.9 Credential подключается без этой ошибки. Принято решение использовать Amsterdam n8n как минимальный AI relay, сохраняя CORE, Supabase, PII, очереди и каналы в России. Relay не получает PostgreSQL/Supabase Credentials.

Для закрытия PRE-02A ещё нужен один фактический обезличенный LLM-вызов через `workflows/PRE-02A_openrouter_amsterdam_n8n_2.20.9.json` с сохранением результата без секрета. Успешного сохранения Credential недостаточно.

Следом PRE-02B обязан проверить **два** вида embedding-вызова через relay: очищенный document chunk и очищенный query. Оба используют один профиль `qwen/qwen3-embedding-8b` + `dimensions=1024`; query embedding нужен при каждом semantic RAG-поиске, после чего российский Supabase/pgvector выполняет similarity search. Если финальный ответ создаётся через OpenRouter, LLM-запрос тоже идёт через relay. Telegram/RT-01 до WF-02 не начинать.

Production, рабочий трафик и production Credentials не менять без отдельного разрешения Павла.