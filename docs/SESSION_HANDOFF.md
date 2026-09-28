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

**WF-02A — аудит свежего workflow после переноса n8n в Амстердам и карта переделки под OpenAI + DB-03.**

Актуальное решение Павла на 28 сентября 2026:
- весь рабочий n8n перенесён на сервер в Амстердаме;
- Supabase/PostgreSQL/pgvector и две test schema пока остаются на российском сервере;
- OpenRouter/Qwen больше не целевой AI-профиль;
- LLM и embeddings должны быть от OpenAI;
- согласованную логику и порядок существующего pipeline максимально сохранить.

Supabase сейчас **не менять**: DB-01/DB-02/DB-03 применены и проверены, DB-04/DB-05 ещё не начинались. Поэтому knowledge vector dimension пока не фиксировать. После выбора OpenAI embedding profile в PRE-02E можно проектировать DB-04/DB-05 без переделки уже созданных knowledge tables.

В новой сессии Павел передаёт **свежий JSON-экспорт фактически работающего/перенесённого workflow из амстердамского n8n**. Первая подзадача WF-02A:
1. проверить `main` и этот handoff;
2. определить фактическую версию n8n из экспорта/со слов Павла;
3. прочитать весь JSON и сохранить согласованную бизнес-логику pipeline;
4. составить точную карту: какие PostgreSQL-ноды переводятся на DB-03 JSONB API, какие OpenRouter/Qwen ноды заменяются OpenAI, какие будущие DB-04/DB-05 ветки пока не должны исполняться;
5. проверить экспорт на secrets, Credential IDs, instanceId и реальные данные;
6. не переписывать сразу весь workflow, если объём велик — сначала разделить WF-02 на безопасные подзадачи и закончить только одну.

Параллельная AI-подзадача **PRE-02E** должна до DB-04/DB-05 зафиксировать конкретный OpenAI LLM model, embedding model и vector dimension и проверить LLM + document/query embedding smoke-tests.

Официально подтверждено на 28.09.2026: OpenAI API поддерживает `/v1/embeddings` и модели `text-embedding-3-small`, `text-embedding-3-large`; конкретный выбор не делать по памяти. OpenAI API customer content по умолчанию не используется для обучения, но стандартные abuse-monitoring logs могут храниться до 30 дней.

Production, рабочий трафик, удаление старого российского сервера и перенос Supabase не выполнять без отдельного разрешения Павла.
