# Текущее состояние проекта

Обновлено: 2026-09-25. Документационная основа v0.3; подготовка реализации разрешена.

## Режим

**Подготовка реализации.** 23 сентября 2026 года Павел отдельно разрешил приступить к реализации шаблона. Это разрешение не включает изменение production, удаление рабочих данных или переключение рабочего трафика.

Завершена задача DOC-03. Первая эталонная установка создаётся для компании qBit; безопасный технический код — `qbit`. В PRE-01 подтверждены: n8n 2.41.0; Docker 29.8.1; Docker Compose v5.5.1; self-hosted Supabase в Docker; Supabase Postgres image 17.6.1.136 и PostgreSQL 17.6; Auth/GoTrue 2.196.0; Supavisor 2.9.12; PostgREST 14.17; Studio 2026.09.07-sha-7996410; отдельная БД n8n — PostgreSQL 17.11-alpine; reverse proxy Caddy 2.11.4; Portainer 2.45.1. pgvector 0.8.2 включён и функционально проверен: операция L2 для тестовых векторов вернула `1`. Сверка с текущим официальным Docker Compose Supabase показала совпадение основных тегов стека; переустановка Supabase ради векторного хранилища не требуется. n8n и Supabase открываются через веб-интерфейсы; сервер администрируется через терминал. Instance ID n8n и имя сервера в публичную документацию не сохраняются. SQL DB-01, DB-02 и весь DB-03 применены и проверены в self-hosted Supabase; DB-04/DB-05 намеренно не начаты до закрытия PRE-02; production-код не создавался. Draft workflow уже импортированы Павлом 24.09.2026; это отражено ниже. Production, рабочий трафик и production schema/roles не менялись.

## Последний завершённый блок

**INFRA-01 — зафиксировано базовое размещение на российском сервере.**

Создан [INFRASTRUCTURE_RU_SERVER](INFRASTRUCTURE_RU_SERVER.md). Зафиксированы отдельные сервисы на одном физическом сервере, российский Supabase как постоянное хранилище, локальная псевдонимизация, сменные внешние LLM/embedding API, ограничения передаваемых данных, обязательная изоляция компаний и проверки до production.

Это архитектурная позиция, а не подтверждение готовности сервера. Внешние DeepSeek/Qwen не образуют полностью закрытый российский контур: им можно передавать только разрешённые обезличенные данные. При запрете внешней передачи используются локальные модели без изменения CORE.

## Ранее завершённый блок

**DOC-02 — исправление документации по десяти замечаниям и переходу между сессиями.**

- Восстановлены CORE, блок настроек, адаптеры каналов, варианты CRM, роли и разделение поведения/оформления.
- Один серверный Supabase: schema и ограниченные роли для каждой компании и среды; прямого доступа браузера к schema нет.
- Зафиксированы обмен данными, надёжный приём, последовательная очередь, короткая сохраняемая память и восстановление частичных действий.
- Напоминания применяются только к незавершённому ожиданию; потеря — через 24 часа после фактически отправленного второго напоминания.
- Основная конверсия считает пользователей с первым обращением в периоде; возвраты и история потерь учитываются отдельно.
- Markdown, идентичность документов, черновики, проверка и атомарная публикация имеют согласованные правила.
- Админ-панель только Павлу; служебный бот отдельный у каждой компании; тестовые токены отличаются от рабочих.
- Планы имеют постоянные ID, критерии приёмки, условия выпуска и готовую передачу сессии.

Проверки документов и соответствие замечаниям: [DOCUMENTATION_AUDIT](DOCUMENTATION_AUDIT.md). Это проверка описания, не испытание системы. Окончательный SHA данного блока находится в сообщении передачи; новая сессия сверяет актуальную ветку main.

## Последний завершённый подготовительный блок

**DOC-03 — определена первая эталонная установка qBit.**

Зафиксировано:
- компания: qBit;
- безопасный технический код: `qbit`;
- целевой шаблон n8n с самого начала предусматривает адаптеры всех запланированных каналов, но неподтверждённые адаптеры остаются отключёнными;
- первый фактически проверяемый клиентский канал — Telegram;
- следующий подключаемый и проверяемый канал — сайт;
- готовность Telegram не считается доказательством готовности сайта, Авито, VK или MAX;
- перед проектированием клиентского workflow n8n Павел передаст свой образец workflow, который нужно изучить как обязательный вход для проектирования.

Частные сведения, токены и Credentials в публичный репозиторий не добавлялись. Сервер в DOC-03 не изменялся.

## Последний завершённый подготовительный блок

**DB-00 — нормативный DB-контракт. Статус: завершено 24 сентября 2026 года.**

Создан [DB_CONTRACT](specs/DB_CONTRACT.md) для DB-01…DB-05. Он фиксирует 33 таблицы текущего DB-этапа, 6 ролей на компанию/среду, поля/типы/индексы и 40 узких PostgreSQL-функций. Контракт проверен против DATA_DICTIONARY, RELIABILITY_AND_MEMORY, BOT_CORE_WORKFLOW, OPERATOR_HANDOFF, INTEGRATION_CONTRACTS, ACCESS_AND_ISOLATION, CONVERSATION_LIFECYCLE, KNOWLEDGE_INGESTION и NAMING_CONVENTIONS.

DB-00 отдельно закрыл недостающие структурные объекты: долговечные факты с доказательством, локальные PII-соответствия, журнал тематических нарушений и долговечную очередь знаний. Для вложений добавлен локальный сохраняемый контент/абстракция хранилища, потому что file_id клиентского Telegram-бота нельзя считать переносимым на служебного бота. Служебная роль не получает общий SELECT сырой клиентской переписки: зеркало и медиа выдаются только узкими функциями конкретного задания. Неоднозначное создание forum topic имеет состояние `neizvestno` и не повторяется вслепую.

SQL, schema, роли и PostgreSQL-функции по DB-00 ещё не создавались и на сервер не применялись.

Сырые JSON draft из предыдущего чата не находятся в GitHub и недоступны текущей сессии как файл. Поэтому DB-00 выполнен по нормативным спецификациям и зафиксированному поведению draft. До RT-01/RT-02 нужно сверить экспорт фактически импортированных workflow с именами функций и форматами ответов DB_CONTRACT.

24 сентября 2026 года Павел импортировал и активировал в n8n:
- `client_bot_template_v0.2.json`;
- `service_telegram_operator_v0.1.json`.

Оба workflow активировались без первых признаков ошибки. Сквозные runtime-тесты не выполнялись. PostgreSQL-контракт ещё не реализован SQL, Credentials/API не считаются проверенными, локальный STT не развёрнут. Сам факт активации draft не является допуском production.

### PRE-02 остаётся в работе

PRE-02 разделён на небольшие проверяемые подзадачи PRE-02A…PRE-02D. Активна только **PRE-02A — runtime-проверка LLM OpenRouter из self-hosted n8n**. На 25 сентября 2026 года по официальной документации OpenRouter подтверждены актуальный model ID `deepseek/deepseek-v4.1-flash`, доступность `qwen/qwen3-embedding-8b` и параметр `dimensions` у `POST /api/v1/embeddings`. Это проверка документации, а не runtime сервера.

Для PRE-02A нужен отдельный test Credential `QBIT_TEST_LLM` с ограниченным бюджетом и один обезличенный пробный вызов из n8n. Секрет не передаётся в чат и не сохраняется в workflow/GitHub. Runtime-вызов ещё не выполнен.

25 сентября 2026 года Павел передал JSON-экспорт `Шаблон — служебный Telegram и перехват диалогов — версия 0.1` для проверки перед публикацией. Экспорт структурно целый: 168 нод, 192 связи, все 155 функциональных нод достижимы от шести trigger-веток; явных API/Telegram токенов и закреплённых реальных Telegram ID не найдено. Однако публиковать и использовать его как актуальный runtime-шаблон нельзя: 33 PostgreSQL-ноды используют старый DB API, в workflow найден 31 уникальный прикладной вызов, а с 28 проверенными DB-03 функциями совпадают по имени только `sohranit_transkripciyu_golosa`, `zabrat_dialog_operatorom`, `vernut_dialog_botu`; их сигнатуры тоже несовместимы, потому что DB-03 принимает единый `jsonb`, а draft передаёт старые позиционные аргументы. В workflow также есть `poisk_aktivnyh_znaniy`, относящийся к ещё не реализованному DB-05. Экспорт содержит n8n `instanceId` и instance-specific metadata, которые перед публикацией должны быть удалены. Файл объединяет клиентские и служебные ветки в одном workflow, тогда как актуальная архитектура ведёт их как отдельные workflow. Исходный JSON в GitHub не сохранён. Павел отдельно подтвердил, что согласованная логика, последовательность блоков и поведение этого pipeline должны максимально сохраняться: WF-02 не перепроектирует CORE, а только увязывает существующие ноды с фактическим Supabase/DB-03 API, отделяет переносимые экспорты и очищает instance-specific metadata.

Полноценное подключение клиентского Telegram и испытание надёжного входа относится к RT-01 после PRE-02A и не считается доказательством PRE-02. База знаний пока не загружена; DB-04/DB-05 не начинать до завершения PRE-02.

## Последний завершённый блок

**DB-01 — основа test schema и ограниченных ролей. Статус: завершено 24 сентября 2026 года.**

Файл `sql/DB-01_test_schemas_roles.sql` v0.3 успешно выполнен Павлом в self-hosted Supabase Studio на базе PostgreSQL 17.6. До запуска read-only диагностикой подтверждены фактические права среды: session/current user `postgres`, `rolsuper=false`, `rolcreaterole=true`, `rolcreatedb=true`, CREATE на текущей БД=true, CREATE для PUBLIC в schema `public`=false, `vector=0.8.2`.

На сервере созданы только test-объекты DB-01:
- schema `qbit_bot_pervichnogo_obrascheniya`, владелец `qbit_test_owner`;
- schema `kompaniya_001_test`, владелец `kompaniya_001_test_owner`;
- по 6 ограниченных ролей на каждую schema: `owner`, `deploy`, `bot`, `sluzhebnyy`, `dash_read`, `dash_admin`.

Финальный серверный результат SQL:
- `db01_status = applied`;
- `roles_ok = true`;
- `qbit_bot_foreign_usage = false`;
- `fictional_bot_foreign_usage = false`;
- `probe_objects_remaining = false`;
- owners обеих schema совпадают с контрактом;
- `postgres_version = 17.6`, `vector_version = 0.8.2`;
- финальная проверка: `DB-01 SQL APPLIED: assertions passed; production objects untouched.`

Тем самым критерий DB-01 выполнен: основа двух test schema создана, прикладные роли не получают чужую schema, disposable probe-объекты удалены. Production schema/production-роли не создавались, Credentials не менялись, рабочий трафик не переключался.

Важно: два ранних неуспешных запуска были остановлены до `COMMIT` и не считаются применённым DB-01. Актуальная проверенная версия — v0.3.

## Последний завершённый блок

**DB-02 — test-таблицы пользователя, диалога и содержимого. Статус: завершено 24 сентября 2026 года.**

Павел выполнил `sql/DB-02_dialog_content.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db02_status = applied`;
- owner schema = `qbit_test_owner`;
- `tables_ok = true`;
- `contract_indexes_ok = true`;
- `probe_rows_remaining = 0`;
- `duplicate_message_guard = true`;
- `runtime_direct_dml = false`;
- `isolation_canary_untouched = true`;
- результат: `DB-02 SQL APPLIED: 13 tables, links/comments/duplicate guard verified; probe data removed; production untouched.`

На сервере теперь существуют 13 таблиц DB-02 в `qbit_bot_pervichnogo_obrascheniya`, 37 контрактных индексов, FK/CHECK/UNIQUE и русские COMMENT. Одноразовые probe-данные удалены откатом SAVEPOINT. Production и `kompaniya_001_test` не изменялись.

Две forward-связи остаются обязательной частью DB-03:
- `dialogi.tekushchiy_menedzher_id → menedzhery_telegram.id`;
- `soobshcheniya.sobytie_id → sobytiya_integraciy.id`.

## Последний завершённый блок

**DB-03A — core-таблицы надёжности. Статус: завершено 24 сентября 2026 года.**

Павел выполнил `sql/DB-03A_reliability_core.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03a_status = applied`;
- owner = `qbit_test_owner`;
- `tables_ok = true`;
- `contract_indexes_ok = true`;
- `integration_fk_ok = true`;
- `probe_rows_remaining = 0`;
- `runtime_direct_dml = false`;
- `operator_tables_created = false`;
- `isolation_canary_untouched = true`;
- результат: `DB-03A SQL APPLIED: 9 core reliability tables and integration-event FK verified; probe data removed; production untouched.`

На сервере созданы 9 core-таблиц DB-03A и добавлен FK `soobshcheniya.sobytie_id → sobytiya_integraciy.id`. Probe-данные удалены. Production и операторские таблицы не затронуты.

## Последний завершённый блок

**DB-03B — операторские таблицы и FK текущего менеджера. Статус: завершено 24 сентября 2026 года.**

Павел выполнил `sql/DB-03B_operator_tables.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03b_status = applied`;
- owner = `qbit_test_owner`;
- `tables_ok = true`;
- `contract_indexes_ok = true`;
- `manager_fk_ok = true`;
- `probe_rows_remaining = 0`;
- `runtime_direct_dml = false`;
- `functions_created = false`;
- `isolation_canary_untouched = true`;
- результат: `DB-03B SQL APPLIED: operator manager/topic/mirror tables and manager FK verified; probe data removed; production untouched.`

На сервере созданы `menedzhery_telegram`, `operator_telegram_temy`, `sobytiya_zerkala_operatora` и добавлен FK `dialogi.tekushchiy_menedzher_id → menedzhery_telegram.id`. Probe-данные удалены. Production не затронут.

## Последний завершённый блок

**DB-03C1 — клиентский ingress, вложения, STT и PII. Статус: завершено 24 сентября 2026 года.**

Павел выполнил `sql/DB-03C1_client_ingress.sql` v0.3 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03c1_status = applied`;
- `functions_ok = true`;
- `bot_execute_ok = true`;
- `service_execute_denied = true`;
- `runtime_direct_dml = false`;
- `attachment_idempotency_indexes_ok = true`;
- `probe_rows_remaining = 0`;
- результат: `DB-03C1 v0.3 SQL APPLIED: ingress/media/STT/PII API verified; variable/ambiguity/phone-normalization/idempotency/conflict/wait-cancel probes passed; production untouched.`

Тем самым серверно проверены четыре узкие API-функции ingress/media/STT/PII, два UNIQUE-index для retry вложений, идемпотентность входа, конфликт hash, повтор external message без второго dialog/message, отмена старого ожидания, local STT/PII и нормализация RU-телефона. v0.1 и v0.2 остаются в истории как неуспешные попытки, остановленные до COMMIT; применён только v0.3.

## Последний завершённый блок

**DB-03C2 — контекст, память, rate limit, тематический guard и unblock. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03C2_context_memory_guard.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03c2_status = applied`;
- `functions_ok = true`;
- `bot_execute_ok = true`;
- `admin_unblock_execute_ok = true`;
- `service_execute_denied = true`;
- `runtime_direct_dml = false`;
- `probe_rows_remaining = 0`;
- результат: `DB-03C2 SQL APPLIED: AI-safe context/memory CAS/rate-limit/thematic block/admin-unblock verified; probe data removed; production untouched.`

Тем самым серверно подтверждены AI/local PII separation, CAS памяти/диалога, deidentified memory window, flood-limit отдельно от thematic counter, предупреждения/логическая блокировка, отмена wait/reminders, stale-job invalidation и idempotent административная разблокировка. Production не затронут.

## Последний завершённый блок

**DB-03C3 — очередь обработки, аренда job и fencing/CAS завершения. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03C3_processing_queue.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03c3_status = applied`;
- `functions_ok = true`;
- `bot_execute_ok = true`;
- `service_execute_denied = true`;
- `one_active_job_index_ok = true`;
- `runtime_direct_dml = false`;
- `probe_rows_remaining = 0`;
- результат: `DB-03C3 SQL APPLIED: queue claim/SKIP LOCKED/lease heartbeat/fencing/reclaim/dialog-version CAS verified; probe data removed; production untouched.`

Тем самым серверно подтверждены atomic queue claim, один active job на dialog, monotonic fencing number, heartbeat текущего worker, expired lease reclaim, запрет stale heartbeat/completion после нового входа, retry/reclaim и terminal success/error/cancel paths. Production не затронут.

## Последний завершённый блок

**DB-03C4 — исходящие действия, подтверждение отправки, напоминания и потеря без ответа. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03C4_outgoing_reminders.sql` v0.2 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03c4_status = applied`;
- `functions_ok = true`;
- `bot_execute_ok = true`;
- `service_execute_denied = true`;
- `runtime_direct_dml = false`;
- `outgoing_unique_key_ok = true`;
- `reminder_unique_generation_ok = true`;
- `probe_rows_remaining = 0`;
- результат: `DB-03C4 SQL APPLIED: outgoing intent/lease/in-flight-confirmed fact/confirmed-vs-unknown effects/t0/reminders/loss-check verified; probe data removed; production untouched.`

Тем самым серверно подтверждены: сохранение outgoing intent до внешнего API, lease/fencing исходящей очереди, различие confirmed/retry/unknown, сохранение реального confirmed-факта при in-flight изменении dialog с подавлением stale effects, постановка `t0` только после подтверждённого основного сообщения, reminder1/reminder2 без переноса `t0`, operator mirror и durable loss-check после подтверждённого reminder2.

Неуспешные ранние запуски v0.1 были остановлены внутри SAVEPOINT-probe до `COMMIT` и откатились. Применена только v0.2. Production не затронут.

**Родительский DB-03C завершён:** DB-03C1 v0.3, DB-03C2 v0.1, DB-03C3 v0.1 и DB-03C4 v0.2 применены и проверены в `qbit_bot_pervichnogo_obrascheniya`.

## Последний завершённый блок

**DB-03D1 — service ingress, private chat менеджера, operator topic и mirror queue. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03D1_service_topic_mirror.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03d1_status = applied`;
- `functions_ok = true`;
- `service_execute_ok = true`;
- `bot_service_execute_denied = true`;
- `service_raw_select_denied = true`;
- `topic_unique_mapping_ok = true`;
- `mirror_unique_key_ok = true`;
- `probe_rows_remaining = 0`;
- результат: `DB-03D1 SQL APPLIED: service ingress/private-chat/topic claim-confirm-unknown/mirror narrow payload+media/retry-unknown verified; service raw SELECT denied; probe data removed; production untouched.`

## Последний завершённый блок

**DB-03D2 — Take/Return, ручное исходящее менеджера и private alert. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03D2_take_return_manual.sql` v0.1 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03d2_status = applied`;
- `functions_ok = true`;
- `c4_manager_upgrade_ok = true`;
- `service_execute_ok = true`;
- `bot_private_alert_execute_ok = true`;
- `cross_role_execute_denied = true`;
- `service_raw_select_denied = true`;
- `probe_rows_remaining = 0`;
- результат: `DB-03D2 SQL APPLIED: atomic Take/Return/manual manager outgoing/C4 manager claim-result/private alert verified; Return creates no client auto-message; service raw SELECT denied; probe data removed; production untouched.`

Тем самым:
- DB-03C1…C4 завершены и родительский **DB-03C закрыт**;
- DB-03D1/D2 завершены и родительский **DB-03D закрыт**;
- DB-03A и DB-03B также ранее завершены.

## Последний завершённый блок

**DB-03V — интегральная проверка позднего bot-ответа после Take. Статус: завершено 25 сентября 2026 года.**

Павел выполнил `sql/DB-03V_late_confirm_after_take.sql` v0.2 целиком в self-hosted Supabase Studio. Сервер вернул:
- `db03v_status = verified`;
- `late_confirm_fact_preserved = true`;
- `human_owner_preserved = true`;
- `stale_effects_suppressed = true`;
- `wait_t0_reminders_not_restored = true`;
- `stage_goal_not_applied = true`;
- `bot_mirror_marks_effects_false = true`;
- `probe_rows_remaining = 0`;
- `production_untouched = true`;
- `parent_db03_ready_to_close = true`.

Подтверждён критический crossing-сценарий `bot action v_rabote → operator Take → late confirmed`: внешний confirmed-факт и внешний message ID сохраняются, но post-Take human owner/version остаются текущими, stale stage/goal/wait/t0/reminders не восстанавливаются, а operator mirror отмечает `effekty_primeneny=false`.

v0.1 ранее остановился на SQL parse до выполнения probe из-за недопустимого `pg_catalog.position(... IN ...)`; применений на сервере не было. В v0.2 использован `pg_catalog.strpos`.

**Родительский DB-03 завершён:** DB-03A, DB-03B, весь DB-03C, весь DB-03D и интегральный DB-03V применены/проверены в `qbit_bot_pervichnogo_obrascheniya`. Production не затронут.

## Последний завершённый блок

**DB-SCHEMA-01 / DB-SCHEMA-01F — rename qBit schema и финальная серверная проверка. Статус: завершено 25 сентября 2026 года.**

Canonical schema первой qBit-установки — `qbit_bot_pervichnogo_obrascheniya`; роли `qbit_test_*` сохранены по принятому решению.

После нескольких безопасно остановленных/исправленных попыток rename был фактически сохранён в DB-SCHEMA-01 v0.3 до ошибочного post-COMMIT reporting SELECT. Поэтому старую rename-миграцию повторно запускать нельзя.

Финальный read-only verifier:
`sql/DB-SCHEMA-01F_v0.4_verify_renamed_schema.sql`.

Павел успешно выполнил его целиком в self-hosted Supabase Studio. Сервер вернул:
- `verifier_version = DB-SCHEMA-01F_v0.4_fresh_path`;
- `db_schema_01f_status = verified`;
- `old_schema_absent = true`;
- `new_schema_present = true`;
- `schema_owner = qbit_test_owner`;
- `tables_ok = true`;
- `functions_ok = true`;
- `execute_distribution = bot=17/service=10/dash_admin=1`;
- `runtime_direct_dml_denied = true`;
- `temporary_database_create_revoked = true`;
- `canary_schema_present = true`;
- `production_schema_qbit_required = false`;
- `production_schema_qbit_present_informational = false`;
- `supabase_stage_complete = true`;
- `next_stage = PRE-02_n8n_openrouter`.

Тем самым подтверждено: старая `qbit_test` отсутствует; canonical schema существует и принадлежит `qbit_test_owner`; 25 таблиц и 28 ожидаемых SECURITY DEFINER функций используют новый schema/search_path; PUBLIC EXECUTE отсутствует; runtime-роли не имеют прямого DML; временный CREATE ON DATABASE отозван; межкомпанейская canary-изоляция сохранена. Production schema `qbit` не создавалась и на test-stage не требуется.

**DB-SCHEMA-01F и родительский DB-SCHEMA-01 закрыты. Текущий Supabase-этап завершён.**

## Следующая задача

**PRE-02 — runtime-проверка AI-профиля в n8n/OpenRouter.**

Начинать в новой сессии. Нужно проверить актуальный `main`, прочитать `docs/specs/PROCESSING_PROFILE.md` и связанные с PRE-02 спецификации, затем выполнить только PRE-02. DB-04/DB-05 не начинать до закрытия PRE-02. Production, рабочий трафик и Credentials не менять без отдельного разрешения.

## Параметры, которые предстоит проверить до реализации/выпуска

Это технические параметры конкретной установки, а не повторное обсуждение принятых бизнес-правил:

- реальные версии сервера и доступные механизмы Auth/подключений;
- момент подтверждения webhook каждого канала и устойчивый путь приёма;
- модель ответа, embedding-модель, размерность, tokenizer и библиотеки;
- top-k, порог поиска и общий бюджет короткой памяти по испытаниям;
- сроки хранения, копирования и восстановления;
- нагрузка, лимиты затрат и внешний аварийный канал.

Начальные размеры уже определены: Markdown до 5 MiB; фрагмент — цель 600, максимум 800 токенов, перекрытие до 100 в пределах раздела. Эти значения проверяются с выбранной моделью.

## Продолжение работы

Активный план — [WORKPLAN_TEMPLATE](WORKPLAN_TEMPLATE.md). [План компании](WORKPLAN_CLIENT_DEPLOYMENT.md) используется после готовности шаблона. Каждая новая сессия читает текущие файлы и последние изменения GitHub, выполняет один небольшой ID и оставляет подтверждённую передачу.
