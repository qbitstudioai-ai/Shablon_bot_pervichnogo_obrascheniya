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

**PRE-02 — runtime-проверка AI-профиля в n8n/OpenRouter.**

Новая сессия должна:
1. прочитать README, PROJECT_STATE, этот SESSION_HANDOFF и WORKPLAN_TEMPLATE;
2. проверить ветку `main` и последний commit;
3. прочитать `docs/specs/PROCESSING_PROFILE.md` и только связанные с PRE-02 спецификации;
4. проверить runtime-параметры LLM/embedding, tokenizer/parser и калибровку similarity threshold по плану PRE-02;
5. не начинать DB-04/DB-05 до закрытия PRE-02;
6. не менять production, рабочий трафик или Credentials без отдельного разрешения Павла.

Исходный SHA перед закрывающим документационным commit этой сессии:
`dc1da53cb3b8e9bc1fc0af00697b624a5c466919`.

Новая сессия обязана сверить фактический текущий SHA `main` на GitHub.
