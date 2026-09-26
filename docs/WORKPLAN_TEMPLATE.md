# План создания шаблона

Подготовка реализации разрешена Павлом 23 сентября 2026 года. До закрытия DOC-03 исполняемые компоненты и сервер не меняются; после этого работа идёт по одному ID, начиная с PRE-01. Изменения production и переключение рабочего трафика требуют отдельного явного разрешения. Один ID — одна небольшая сессия; большой пункт сначала делится на подзадачи по [правилам документации](DOCUMENTATION_RULES.md).

Статусы: `[ ]` не начато, `[~]` в работе, `[x]` проверено и завершено, `[!]` пауза. Текущая задача — в [PROJECT_STATE](PROJECT_STATE.md).

## Документационная основа

| Статус / ID | Результат | Проверка |
|---|---|---|
| [x] DOC-01 | Созданы исходные требования, два плана и роли | Исходные документы есть в истории GitHub; это не отметка готовности реализации |
| [x] DOC-02 | Исправлены требования, единый Supabase, обмен, знания, напоминания, метрики, восстановление и передача сессий | Связность комплекта и покрытие замечаний: [аудит](DOCUMENTATION_AUDIT.md) |
| [x] INFRA-01 | Зафиксировано базовое размещение продукта на одном российском сервере и граница внешних AI API | [INFRASTRUCTURE_RU_SERVER](INFRASTRUCTURE_RU_SERVER.md) определяет локальные сервисы, допустимое движение данных, изоляцию компаний, заменяемость провайдеров и проверки до production |
| [x] DOC-03 | Определена первая эталонная установка qBit и безопасные исходные параметры внедрения | Компания qBit; код `qbit`; первый проверяемый канал Telegram, затем сайт; неизвестные технические параметры оставлены для PRE-01; секретов нет, сервер не изменён |

DOC-03 не требует писать SQL. Частные сведения компании остаются в закрытой копии [паспорта](../templates/company-passport.md). Технические значения без доступа к установке не выдумываются.

## Подготовка реализации

Начинается после отдельной команды Павла приступить к реализации. ChatGPT руководит и готовит инструкции; Павел выполняет необходимые действия в интерфейсах.

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] PRE-01 | DOC-03, разрешение на реализацию | Проверен паспорт сервера и выбран реализуемый путь Telegram: ручной Webhook n8n с проверкой secret header, транзакционной регистрацией в PostgreSQL и Respond to Webhook только после commit; фактическое испытание с отказами остаётся RT-01 |
| [x] DB-SCHEMA-01 | DB-03 | Rename завершён: canonical schema `qbit_bot_pervichnogo_obrascheniya`; старый `qbit_test` отсутствует; старую rename-миграцию больше не запускать. Закрыто после успешного DB-SCHEMA-01F v0.4 |
| [x] DB-SCHEMA-01F | DB-SCHEMA-01 | `sql/DB-SCHEMA-01F_v0.4_verify_renamed_schema.sql` успешно выполнен 25.09.2026: `verified`, old schema absent, new schema present, owner ok, 25 tables, 28 SECURITY DEFINER functions, EXECUTE 17/10/1, runtime DML denied, temporary DB CREATE revoked, canary present; production `qbit` не требуется и отсутствует. Supabase-stage завершён; следующая сессия PRE-02/n8n |
| [~] PRE-02 | PRE-01 | Родительский блок AI-профиля. Завершается только после PRE-02A…PRE-02D; основной документ — [PROCESSING_PROFILE](specs/PROCESSING_PROFILE.md) |
| [~] PRE-02A | PRE-01 | Из self-hosted n8n выполнен тестовый вызов OpenRouter `deepseek/deepseek-v4.1-flash` через отдельный test Credential; сохранены обезличенные вход/статус/модель/структура ответа, секрет не попал в workflow/GitHub |
| [ ] PRE-02B | PRE-02A | Из self-hosted n8n выполнен embedding-вызов `qwen/qwen3-embedding-8b` с `dimensions=1024`; фактическая длина вектора равна 1024 либо документирован переход на резерв `qwen/qwen3-embedding-0.6b` без смешивания профилей |
| [ ] PRE-02C | PRE-02A | В self-hosted n8n проверены доступность и воспроизводимость `markdown-it 15.0.2`, `yaml 2.9.1` и tokenizer `Qwen/Qwen3-Embedding-8B`; зафиксирован способ исполнения без секретов |
| [ ] PRE-02D | PRE-02B, PRE-02C | На минимум 60 обезличенных сценариях прогнан контрольный набор; threshold проверен в диапазоне 0.45–0.85 шагом 0.05, выбран профиль и сохранены метрики retrieval/ошибок |
| [ ] PRE-03 | PRE-01 | Определены сроки хранения, резервные копии, восстановление, внешний мониторинг, канал аварийного оповещения, ограничения затрат и нагрузка для тестов |

Модель и порог не выбираются «по памяти». Ограничения проверяются по официальным источникам и пробным документам. Название Astru, выбранной для управления проектом в чате, само по себе не задаёт модель будущего клиентского бота или embeddings.

## База и надёжная обработка

SQL-файлы готовит ChatGPT; Павел запускает готовые файлы по инструкции. Помощник в VSCode может выполнять порученную работу с файлами и Git.

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] DB-00 | PRE-01, WF-01 | Согласован нормативный [DB-контракт](specs/DB_CONTRACT.md): 33 таблицы DB-01…DB-05, роли, поля, индексы и прикладные PostgreSQL-функции; закрыты PII/facts/guard, очередь знаний, операторская тема/зеркало/ручной перехват и медиа. SQL и сервер не менялись |
| [x] DB-01 | DB-00, PRE-01 | `sql/DB-01_test_schemas_roles.sql` v0.3 успешно применён 24.09.2026 в self-hosted Supabase/PostgreSQL 17.6: созданы `qbit_bot_pervichnogo_obrascheniya` и `kompaniya_001_test`, 12 ограниченных ролей; встроенные проверки подтвердили владельцев, отсутствие межкомпанейского USAGE, отсутствие оставшихся probe-объектов и неизменность production |
| [x] DB-02 | DB-01 | `sql/DB-02_dialog_content.sql` v0.1 успешно применён 24.09.2026 в `qbit_bot_pervichnogo_obrascheniya`: `tables_ok=true`, `contract_indexes_ok=true`, `probe_rows_remaining=0`, duplicate-message guard=true, runtime direct DML=false, isolation canary untouched=true; две forward FK оставлены для DB-03 по контракту |
| [x] DB-03 | DB-02 | DB-03A/B/C/D и DB-03V завершены в `qbit_bot_pervichnogo_obrascheniya`: таблицы/FK, ingress/idempotency, context/memory guard, queue lease/fencing, outgoing confirmed/retry/unknown, reminders/loss, service topic/mirror, atomic Take/Return/manual outgoing/private alert и crossing `bot v_rabote → Take → late confirmed` проверены; probe rows=0, production untouched |
| [x] DB-03A | DB-02 | `sql/DB-03A_reliability_core.sql` v0.1 успешно применён 24.09.2026: 9 core-таблиц, 25 индексов, integration FK=true, probe_rows=0, runtime direct DML=false, isolation canary untouched=true |
| [x] DB-03B | DB-03A | `sql/DB-03B_operator_tables.sql` v0.1 успешно применён 24.09.2026: 3 таблицы, 10 индексов, manager FK=true, probe_rows=0, runtime direct DML=false, isolation canary untouched=true |
| [x] DB-03C | DB-03A, DB-03B | DB-03C1…C4 применены и проверены: ingress idempotency/conflict, memory CAS, queue lease/fencing/reclaim, stale version, outgoing confirmed/retry/unknown, reminders/loss-check; production untouched |
| [x] DB-03C1 | DB-03B | `sql/DB-03C1_client_ingress.sql` v0.3 успешно применён 24.09.2026: 4 functions_ok, bot_execute_ok=true, service_execute_denied=true, runtime direct DML=false, attachment idempotency indexes=true, probe_rows=0; probes подтвердили variable/ambiguity/phone normalization/idempotency/conflict/wait-cancel; production untouched |
| [x] DB-03C2 | DB-03C1 | `sql/DB-03C2_context_memory_guard.sql` v0.1 успешно применён 25.09.2026: functions_ok=true, bot_execute_ok=true, admin_unblock_execute_ok=true, service_execute_denied=true, runtime_direct_dml=false, probe_rows=0; AI-safe context/memory CAS/rate-limit/thematic block/admin-unblock проверены; production untouched |
| [x] DB-03C3 | DB-03C2 | `sql/DB-03C3_processing_queue.sql` v0.1 успешно применён 25.09.2026: functions_ok=true, bot_execute_ok=true, service_execute_denied=true, one_active_job_index_ok=true, runtime_direct_dml=false, probe_rows=0; queue claim/SKIP LOCKED/lease heartbeat/fencing/reclaim/dialog-version CAS проверены; production untouched |
| [x] DB-03C4 | DB-03C3 | `sql/DB-03C4_outgoing_reminders.sql` v0.2 успешно применён 25.09.2026: functions_ok=true, bot_execute_ok=true, service_execute_denied=true, runtime_direct_dml=false, outgoing/reminder unique guards=true, probe_rows=0; verified outgoing intent/lease, in-flight confirmed fact, confirmed-vs-unknown effects, t0/reminders/loss-check; production untouched |
| [x] DB-03D | DB-03B, DB-03C | DB-03D1 и DB-03D2 применены и проверены: service ingress/topic/mirror, first-commit-wins Take по expected version, foreign manager deny, manual outgoing через client-bot queue, Return без client auto-message, private alert trusted target, service raw SELECT denied |
| [x] DB-03D1 | DB-03B, DB-03C | `sql/DB-03D1_service_topic_mirror.sql` v0.1 успешно применён: functions_ok=true, service_execute_ok=true, bot_service_execute_denied=true, service_raw_select_denied=true, topic/mirror unique guards=true, probe_rows=0; service ingress/private-chat/topic claim-confirm-unknown/mirror narrow payload+media/retry-unknown проверены; production untouched |
| [x] DB-03D2 | DB-03D1 | `sql/DB-03D2_take_return_manual.sql` v0.1 успешно применён 25.09.2026: functions_ok=true, c4_manager_upgrade_ok=true, service_execute_ok=true, bot_private_alert_execute_ok=true, cross_role_execute_denied=true, service_raw_select_denied=true, probe_rows=0; atomic Take/Return/manual manager outgoing/C4 manager claim-result/private alert проверены; Return не создаёт client auto-message; production untouched |
| [x] DB-03V | DB-03D | `sql/DB-03V_late_confirm_after_take.sql` v0.2 успешно проверен 25.09.2026: late_confirm_fact_preserved=true, human_owner_preserved=true, stale_effects_suppressed=true, wait_t0_reminders_not_restored=true, stage_goal_not_applied=true, bot_mirror_marks_effects_false=true, probe_rows=0, production_untouched=true; parent_db03_ready_to_close=true |
| [ ] DB-04 | DB-00, DB-01, PRE-02 | Созданы загрузки/очередь знаний, документы, версии, профили, фрагменты и проверки; ограничения допускают много архивных версий и один активный указатель |
| [ ] DB-05 | DB-04 | Проверены отдельный поиск по активным знаниям, проверочный поиск по конкретному черновику, HNSW/cosine и атомарная публикация/отзыв; клиентский доступ к черновику запрещён |
| [ ] RT-01 | DB-03, PRE-01 | Первый входной адаптер гарантирует сохранение события до окончательного подтверждения либо использует проверенный внешний буфер/восстановление; повтор, отключение БД и перезапуск не теряют принятые сообщения |
| [ ] RT-02 | RT-01 | Работают последовательная обработка, память и исходящие действия; неизвестная отправка не повторяется вслепую, новый вход не затирается старым работником |

## Служебный workflow и знания

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [ ] KB-01 | RT-01, DB-04, PRE-02 | Ветка единого служебного Telegram Webhook принимает .md только от разрешённого Павла; операторские сообщения/callback маршрутизируются отдельно, неверный источник, размер и структура документа отклоняются |
| [ ] KB-02 | KB-01 | Очистка и деление сохраняют факты, таблицы и пути; токены ограничены, контрольные вопросы не попадают в поисковый текст |
| [ ] KB-03 | KB-02, DB-05 | Векторы, дубли, проверка и публикация работают; сбой обновления оставляет старую версию, ошибка отчёта не отменяет публикацию |
| [ ] OPS-01 | RT-02, KB-03, PRE-03 | Ошибки сообщаются через служебного бота; недоступность n8n замечает независимая проверка; нет потока одинаковых уведомлений |

## Клиентский бот и интеграции

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] WF-00 | PRE-01 | Спроектирован неактивный draft клиентского workflow: русские ноды и sticky-блоки, надёжный вход, очередь, guard/3 предупреждения, PII, память, RAG, продажи, handoff, безопасная отправка и напоминания; Павел подтвердил, что v0.1 импортируется в n8n 2.41.0, runtime/DB ещё не проверены |
| [x] WF-01 | WF-00 | Подготовлены клиентский v0.2 и служебный операторский v0.1 с темой/зеркалом, локальным STT, «Забрать/Вернуть» и ручным ответом. 24.09.2026 Павел импортировал и активировал оба draft в n8n без первых признаков ошибки; это не runtime-проверка — PostgreSQL-функции, Credentials/API и STT ещё не проверены |
| [ ] WF-02 | WF-01, DB-03, PRE-02A | Сохранена согласованная логика и порядок существующего pipeline; меняется только техническая стыковка его нод с проверенным DB-03 JSONB API, разделение на переносимые клиентский/служебный экспорты и очистка metadata. Будущие DB-04/DB-05 вызовы не должны исполняться до своего этапа; очищенные экспорты повторно импортируются в n8n 2.41.0 без ошибок и только после этого сохраняются в GitHub |
| [ ] BOT-00 | RT-02 | Тематический guard отличает разрешённый диалог, smalltalk, уточнение, off-topic, injection и передачу человеку; после трёх подтверждённых нарушений действует логическая блокировка с административной разблокировкой, а недостаток знаний/ошибка не считаются нарушением |
| [ ] BOT-01 | BOT-00, KB-03 | CORE отвечает в исходный канал с настраиваемым окном 3–5 сообщений, долговечными важными фактами и активными знаниями своей компании; PII удаляется до внешних LLM/embeddings, поля LLM и доказательства проверяются |
| [ ] BOT-02 | BOT-01, WF-01 | Проверены этапы, цели, настраиваемый сбор полей, локальная заявка, завершение и операторский Telegram: тема с первого сообщения, зеркало, личный сигнал, атомарный захват, ручной ответ и явный возврат; после захвата бот/напоминания не продолжают диалог |
| [ ] BOT-03 | BOT-02 | Проверены настраиваемые сроки напоминаний; для qBit стартово 3 часа / 12 часов, отмена, задержки и одновременный ответ; технический сбой не записывается как молчание клиента |
| [ ] BOT-04 | BOT-03 | Проверены возврат потерянного, повтор после успеха, отказ от инициативных сообщений и восстановление памяти на сайте |
| [ ] INT-01 | BOT-02 | Для выбранного режима net/bitrix24/amocrm проверены заявка, стабильный ключ и восстановление частичного сбоя; неподключённые ветки не вызываются |
| [ ] INT-02 | BOT-04 | Каждый дополнительный канал проходит отдельную карточку подключения с проверкой API, идентичности, подтверждения приёма и ограничений отправки |

INT-02 создаёт отдельные подзадачи для сайта, Авито, VK или MAX, когда канал действительно нужен. Готовность Telegram не означает готовность остальных.

## Дашборд и выпуск

Дашборд и его серверную часть разрабатывает помощник в VSCode по заданию ChatGPT.

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [ ] UI-01 | DB-02, DB-03, DB-05 | Авторизация и серверный API ограничивают компанию и роль; браузер не получает доступы PostgreSQL |
| [ ] UI-02 | UI-01, BOT-04 | Показатели по фиксированному учебному набору совпадают с ручным расчётом; период первой заявки, дата среза и возвраты различимы |
| [ ] UI-03 | UI-02 | Доступны разрешённые переписки, этапы, причины потери, ошибки, оценка реакции и обратная связь; вывод LLM отличим от факта |
| [ ] UI-04 | UI-01 | Админ-панель только Павлу: оформление, доступы, состояния и аудит; прямой запрос руководителя к функции администратора запрещён |
| [ ] QA-01 | OPS-01, BOT-04, INT-01, UI-03, UI-04; нужные INT-02 | На тестовой установке пройдены обязательные сценарии [выпуска](RELEASE_CHECKLIST.md), результаты сохранены с версиями |
| [ ] REL-01 | QA-01 | Зафиксирована версия шаблона, очищенные экспорты, миграции, восстановление и процедура копирования; замечания, запрещающие запуск, закрыты |

REL-01 готовит шаблон к внедрению. Фактический запуск компании идёт по [отдельному плану](WORKPLAN_CLIENT_DEPLOYMENT.md), с разрешением на переключение production.

## Что делать в конце каждого ID

Обновить основной документ задачи, этот план и PROJECT_STATE. Указать результат проверок, что применено на сервере и что осталось. Сохранить изменения в GitHub и дать Павлу [сообщение передачи](SESSION_HANDOFF.md). Следующий чат проверяет актуальную ветку и начинает с одного ID.
