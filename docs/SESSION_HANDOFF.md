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

Для продолжения PRE-02A Павел передаёт **очищенный JSON-экспорт фактически импортированного клиентского workflow n8n**. Токены, API keys и другие секреты из экспорта удалить/не присылать. Экспорт нужен, чтобы определить точные существующие ноды и не запускать DB/Telegram/операторские ветки вслепую.

После чтения JSON:
- использовать только test Credential `QBIT_TEST_LLM` с ограниченным бюджетом;
- выполнить один обезличенный вызов `deepseek/deepseek-v4.1-flash` из self-hosted n8n;
- зафиксировать статус, фактический model ID и форму ответа без секрета и личных данных;
- Telegram/RT-01 пока не считать начатым;
- DB-04/DB-05 не начинать.

Production, рабочий трафик и production Credentials не менять без отдельного разрешения Павла.