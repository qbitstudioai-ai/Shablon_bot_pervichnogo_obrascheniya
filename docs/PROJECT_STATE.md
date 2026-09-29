# Текущее состояние проекта

Обновлено: 2026-09-28. Документационная основа v0.3; подготовка реализации разрешена.

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

28 сентября 2026 года Павел изменил целевую архитектуру:
- рабочий n8n перенесён на сервер в Амстердаме;
- Supabase/PostgreSQL/pgvector и две проверенные test schema пока остаются на российском сервере;
- целевой AI-провайдер для LLM и embeddings — **OpenAI**, OpenRouter/Qwen больше не являются целевым профилем;
- существующий клиентский pipeline нужно максимально сохранить, но свежий экспорт должен быть заново проверен против DB-03 и переделан под OpenAI.

**Supabase сейчас не менять.** DB-01/DB-02/DB-03 уже проверены; DB-04/DB-05 не начинались, поэтому ни vector-таблицы, ни размерность embeddings ещё не зафиксированы. Сначала PRE-02E должен выбрать и runtime-проверить конкретный OpenAI LLM/embedding profile и фактическую размерность. После этого можно проектировать DB-04/DB-05 без миграции уже созданных knowledge vectors.

Официальная документация OpenAI на 28.09.2026 подтверждает API embeddings и модели `text-embedding-3-small` / `text-embedding-3-large`; конкретную модель и размерность эта сессия намеренно не выбирает. Для OpenAI API данные по умолчанию не используются для обучения моделей, но abuse-monitoring logs могут храниться до 30 дней; это нужно учесть отдельно при политике PII и PRE-03.

**WF-02A завершена 28 сентября 2026 года.** Свежий экспорт фактически перенесённого workflow полностью разобран; Павел подтвердил фактическую версию амстердамского n8n **2.41.0**. Зафиксирована карта замены старого PostgreSQL API на DB-03 JSONB API и четырёх OpenRouter-вызовов на будущий OpenAI-профиль. Подробности — [WF-02A_WORKFLOW_AUDIT](WF-02A_WORKFLOW_AUDIT.md). Полный JSON пока не переделывался и не импортировался.

Следующая одна задача — **PRE-02E**: выбрать и runtime-проверить конкретные OpenAI LLM/embedding model ID и фактическую размерность. Только после PRE-02E разрешено готовить WF-02B и проектировать DB-04/DB-05 vector-поля.


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

## Последний завершённый workflow-блок

**WF-02A — аудит свежего workflow после переноса n8n в Амстердам. Статус: завершено 28 сентября 2026 года.**

Проверен свежий экспорт `Шаблон — служебный Telegram и перехват диалогов — версия 0.1.json`: 168 нод, workflow неактивен (`active=false`), `pinData` пуст, внутри объединены клиентский и служебный/операторский pipeline. Павел подтвердил фактическую версию амстердамского n8n: **2.41.0**.

Главный результат аудита: согласованную бизнес-логику pipeline можно сохранить, но старые PostgreSQL-вызовы несовместимы с реализованным DB-03 API. WF-02B должен заменить старые позиционные/устаревшие вызовы на текущие JSONB-функции и протащить обязательные worker/lease/fencing, expected dialog version, стабильные idempotency keys и семантику `confirmed/retry/unknown`.

AI-слой содержит четыре OpenRouter HTTP-вызова: тематический контроль, план поиска, embeddings и решение менеджера. Они должны быть заменены OpenAI только после PRE-02E. Текущая размерность `1024` из старого workflow **не принимается как новая норма**. Ветка `poisk_aktivnyh_znaniy(...vector(1024)...)` не может исполняться до PRE-02E → DB-04 → DB-05.

Экспорт проверен на переносимость: явных API-ключей, Authorization/Bearer, Credential IDs, pinData и реальной переписки не найдено; `meta.instanceId` присутствует и должен быть удалён из канонического экспорта. Credentials в самом JSON не закреплены, поэтому их фактическое подключение в живом n8n этим аудитом не подтверждено. URL локального STT `http://stt-local:8000/v1/transcriptions` после переноса n8n в Амстердам требует отдельной runtime-проверки маршрута; сырой голос в OpenAI автоматически не переводить.

Полная карта и критерии WF-02B сохранены в [WF-02A_WORKFLOW_AUDIT](WF-02A_WORKFLOW_AUDIT.md). Supabase, Credentials, production и рабочий трафик в WF-02A не менялись.

## Последний завершённый архитектурный блок

**WF-02B1 — DB-03 runtime-архитектура n8n. Статус: завершено 28 сентября 2026 года.**

По фактически применённым SQL DB-03 зафиксирована правильная runtime-схема: client webhook выполняет durable ingress и HTTP 200 только после commit; processing, outgoing, topic/mirror и reminder workers работают отдельно через narrow API, lease/fencing и stable keys. Финальная поставка возвращается к двум логическим workflow с разными client/service Telegram и PostgreSQL Credentials.

Подготовлен post-DB03 gap-fix **DB-03E v0.5**:
- `poluchit_soderzhimoe_zadaniya(jsonb)` — recoverable channel identity + raw source только текущему fenced worker для локального rate-limit/guard/PII/STT;
- `poluchit_sostoyanie_operatora(jsonb)` — service-only owner/status/stage/current manager/version по известному dialog/topic без переписки/PII; основа CAS Take/Return/manual reply;
- `sozdat_preduprezhdenie_tematiky(jsonb)` — stable warning intent для exact recorded violation; третье предупреждение разрешено sender-у после логической блокировки только если БД подтверждает связь с тем самым blocking violation;
- `poluchit_soderzhimoe_ishodyashchego(jsonb)` — current sender lease получает exact message text/payload своего action и проходит final owner/version/block/opt-out recheck непосредственно перед внешним API; stale action отменяется до Telegram;
- `ustanovit_zapret_iniciativy(jsonb)`;
- `zaprosit_cheloveka(jsonb)`;
- `obrabotat_sleduyushchee_napominanie(jsonb)`.

Файлы:
- `sql/DB-03E_runtime_gap_closure.sql`;
- `sql/DB-03E_v0.5_verify.sql`;
- `docs/WF-02B1_DB03_N8N_ARCHITECTURE.md`.

DB-03E v0.5 статически проверен в репозитории, но **на Supabase не применён**. Прямые права SELECT/INSERT/UPDATE/DELETE runtime-ролям не добавляются. Для применения DB-03E в test нужен отдельный явный приказ Павла; после применения обязателен read-only verifier.





## Последний завершённый workflow-блок

**WF-02B2A — клиентский вход + получение задания из очереди. Статус: завершено offline 29 сентября 2026 года.**

Канонический файл:
`workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Основа — полный пользовательский export версии 0.1. Сохранены **168 нод** и **135 ключей connections**. Изменены только 6 нод первого участка:
- нормализация клиентского Telegram update теперь формирует пакет текущего DB-03 ingress;
- `Сохранить вход и поставить в очередь` использует `zaregistrirovat_vhod_klienta(jsonb)`;
- HTTP 200 возвращается только для `uspeshno/dublikat`, иначе 500;
- немедленный claim конкретного job после webhook отключён и отсоединён;
- отдельный queue worker настроен на `zabrat_zadanie_obrabotki(jsonb)`;
- проверка наличия job понимает новый результат DB-03.

Queue claim пока `disabled=true`: следующие старые ноды ещё ожидают прежний формат job, поэтому включать аренду до WF-02B2B небезопасно. Это не runtime-проверка.

AI/OpenRouter, local STT, media, outgoing, reminders и service/operator части в WF-02B2A не менялись. `meta.instanceId` удалён; Credential IDs и secrets в export не добавлены.

## Последний завершённый workflow-блок

**WF-02B2B — начало обработки задания. Статус: завершено offline 29 сентября 2026 года.**

Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Начало processing переведено на текущий DB-контракт:
- exact source — `poluchit_soderzhimoe_zadaniya(jsonb)`;
- owner/block/current context — `poluchit_kontekst_dialoga(jsonb)`;
- rate-limit — `proverit_limit_chastoty(jsonb)`;
- превышенный rate-limit сразу освобождает lease через fenced `zavershit_zadanie_obrabotki(status=povtor)`;
- данные source/context возвращаются в совместимом виде для существующего switch форматов.

Сохранены **168 нод**. Connection keys стали **138**, потому что три старые terminal DB-ноды этого же участка теперь продолжают последовательную DB-цепочку; новых нод не добавлено.

В `Настройки компании` добавлены обязательные `bezopasnost.limit_chastoty.okno_sekund` и `limit_soobshcheniy` со значением `null`: бизнес-значения не выдумывались. Пока они не заполнены, профиль компании не считается готовым.

Queue claim остаётся `disabled=true`: DB-03E v0.5 ещё не применён на Supabase. Source/context conflict безопасно прекращает текущую ветку без внешней отправки; просроченный lease затем обрабатывается DB claim/reclaim logic.

Media/STT/AI/outgoing/reminders/service не менялись.

## Последний завершённый workflow-блок

**WF-02B2C — voice/STT + локальное PII-сохранение. Статус: завершено offline 29 сентября 2026 года.**

Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Изменён только существующий voice/PII-участок:
- успешный local STT сохраняется через `sohranit_transkripciyu_golosa(jsonb)` по exact `soobshchenie_id`;
- локальный PII-detector понимает reverse-map DB-03 формата `[{tip_pii,psevdometka,znachenie_zashchishchennoe}]`;
- новые соответствия и обезличенный текст сохраняются через `sohranit_obezlichivanie(jsonb)`;
- existing local STT HTTP transport, media branches, AI и outgoing не менялись.

В `Настройки компании` добавлена trusted-настройка `bezopasnost.region_telefona:null`. Регион не выдумывался; пока он не заполнен, профиль компании не считается готовым.

Структура сохранена: **168 нод, 138 connection keys**. Queue claim остаётся disabled до DB-03E apply+verify.

## Последний завершённый workflow-блок

**WF-02B2D — thematic guard OpenAI. Статус: завершено offline 29 сентября 2026 года.**

Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Изменены только три существующие guard-ноды и настройка модели:
- подготовка guard формирует OpenAI Responses payload;
- модель guard вынесена отдельно: `model.guard='gpt-6-luna'`;
- используется `store=false`, `max_output_tokens` и strict `text.format/json_schema`;
- HTTP-вызов идёт на `https://api.openai.com/v1/responses` через OpenAI Credential n8n;
- parser читает Responses output и проверяет допустимое действие, причину, уверенность и RAG flag;
- error, refusal, incomplete или некорректная структура безопасно дают `peredat_cheloveku`.

OpenAI Credential ID и API key в JSON не закреплены. Credential выбирается в UI n8n после импорта.

Planner и основной answer пока остаются на OpenRouter; embedding остаётся старым. Структура workflow: **168 нод, 138 connection keys**. Queue claim остаётся disabled до DB-03E apply+verify. PRE-02E остаётся runtime-unverified.

## Последний завершённый workflow-блок

**WF-02B2E — planner OpenAI. Статус: завершено offline 29 сентября 2026 года.**

Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Изменены только planner-настройка и три существующие planner-ноды:
- добавлен отдельный `model.planner='gpt-6-luna'`;
- подготовка плана использует OpenAI Responses API payload, `store=false` и strict `text.format/json_schema`;
- schema ограничивает план до 1–3 `queries` и 1–5 `required_points`;
- `Построить план поиска` теперь вызывает `https://api.openai.com/v1/responses` через OpenAI Credential n8n;
- parser читает Responses output; при error/refusal/invalid сохраняется прежняя безопасная логика fallback: один обезличенный пользовательский запрос.

Guard остаётся на OpenAI. Query embedding всё ещё OpenRouter/Qwen, основной answer всё ещё OpenRouter. RAG/DB-05 не включался.

Структура workflow не изменилась: **168 нод, 138 connection keys**. Queue claim остаётся disabled до DB-03E apply+verify. PRE-02E всё ещё runtime-unverified.

## Текущая задача

**WF-02B2F — query embedding OpenAI.**

Краткий состав: заменить только OpenRouter/Qwen embedding поискового запроса на OpenAI `text-embedding-3-large`, candidate `dimensions=1024`, и адаптировать разбор вектора. Сам поиск DB-05 не включать, основной answer и outgoing пока не менять.

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
