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
| [x] DB-SCHEMA-01 | DB-03 | Rename завершён: canonical schema `qbit_bot_pervichnogo_obrascheniya`; старый `qbit_test` отсутствует; старую rename-миграцию больше не запускать. Закрыто после успешного DB-SCHEMA-01F v0.5 |
| [x] DB-SCHEMA-01F | DB-SCHEMA-01 | `sql/DB-SCHEMA-01F_v0.5_verify_renamed_schema.sql` успешно выполнен 25.09.2026: `verified`, old schema absent, new schema present, owner ok, 25 tables, 28 SECURITY DEFINER functions, EXECUTE 17/10/1, runtime DML denied, temporary DB CREATE revoked, canary present; production `qbit` не требуется и отсутствует. Supabase-stage завершён; следующая сессия PRE-02/n8n |
| [~] PRE-02 | PRE-01 | Родительский блок AI-профиля. OpenRouter-путь PRE-02A/PRE-02B остановлен после смены провайдера; актуальный путь закрывается PRE-02E, PRE-02C и PRE-02D. Основной документ — [PROCESSING_PROFILE](specs/PROCESSING_PROFILE.md) |
| [~] PRE-02A | PRE-01 | Исторический OpenRouter LLM-путь: остановлен без закрытия критерия после решения 28.09.2026 перейти на OpenAI; не является зависимостью актуального PRE-02 |
| [~] PRE-02B | PRE-02A | Исторический OpenRouter/Qwen embedding-путь: остановлен до runtime после решения 28.09.2026 перейти на OpenAI; будущая vector dimension по нему не фиксируется |
| [ ] PRE-02C | PRE-02E | После выбора OpenAI embedding model проверены parser/tokenizer runtime и воспроизводимый chunking; зафиксирован способ исполнения без секретов |
| [ ] PRE-02D | PRE-02E, PRE-02C | На минимум 60 обезличенных сценариях прогнан контрольный набор; threshold проверен в диапазоне 0.45–0.85 шагом 0.05, выбран профиль и сохранены метрики retrieval/ошибок |
| [~] PRE-02E | PRE-01 | OpenAI candidate profile сохранён в `docs/PRE-02E_OPENAI_PROFILE.md`: guard/planner `gpt-6-luna`, grounded answer `gpt-6-sol`, embeddings `text-embedding-3-large` / candidate 1024 dimensions. Отдельные smoke-workflow удалены; runtime-проверка выполняется только внутри будущего канонического переделанного workflow. До фактической проверки профиль остаётся кандидатом |
| [ ] PRE-03 | PRE-01 | Определены сроки хранения, резервные копии, восстановление, внешний мониторинг, канал аварийного оповещения, ограничения затрат и нагрузка для тестов |

Модель и порог не выбираются «по памяти». Ограничения проверяются по официальным источникам и пробным документам. Название Astru, выбранной для управления проектом в чате, само по себе не задаёт модель будущего клиентского бота или embeddings.

## База и надёжная обработка

SQL-файлы готовит ChatGPT; Павел запускает готовые файлы по инструкции. Помощник в VSCode может выполнять порученную работу с файлами и Git.

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] DB-00 | PRE-01, WF-01 | Согласован нормативный [DB-контракт](specs/DB_CONTRACT.md): 33 таблицы DB-01…DB-05, роли, поля, индексы и прикладные PostgreSQL-функции; закрыты PII/facts/guard, очередь знаний, операторская тема/зеркало/ручной перехват и медиа. SQL и сервер не менялись |
| [x] DB-01 | DB-00, PRE-01 | `sql/DB-01_test_schemas_roles.sql` v0.5 успешно применён 24.09.2026 в self-hosted Supabase/PostgreSQL 17.6: созданы `qbit_bot_pervichnogo_obrascheniya` и `kompaniya_001_test`, 12 ограниченных ролей; встроенные проверки подтвердили владельцев, отсутствие межкомпанейского USAGE, отсутствие оставшихся probe-объектов и неизменность production |
| [x] DB-02 | DB-01 | `sql/DB-02_dialog_content.sql` v0.1 успешно применён 24.09.2026 в `qbit_bot_pervichnogo_obrascheniya`: `tables_ok=true`, `contract_indexes_ok=true`, `probe_rows_remaining=0`, duplicate-message guard=true, runtime direct DML=false, isolation canary untouched=true; две forward FK оставлены для DB-03 по контракту |
| [x] DB-03 | DB-02 | DB-03A/B/C/D и DB-03V завершены в `qbit_bot_pervichnogo_obrascheniya`: таблицы/FK, ingress/idempotency, context/memory guard, queue lease/fencing, outgoing confirmed/retry/unknown, reminders/loss, service topic/mirror, atomic Take/Return/manual outgoing/private alert и crossing `bot v_rabote → Take → late confirmed` проверены; probe rows=0, production untouched |
| [~] DB-03E | DB-03, WF-02B1 | `sql/DB-03E_runtime_gap_closure.sql` v0.7 и read-only verifier подготовлены и статически проверены. Запуски v0.5 и v0.6 30.09.2026 откатились до COMMIT с `42501: permission denied for function poluchit_soderzhimoe_zadaniya`. Точная причина: ACL-секция `REVOKE/GRANT` выполнялась после `RESET ROLE` как `postgres`, а новые функции принадлежат `qbit_test_owner`; v0.6 исправляла только более поздний probe и не достигала его. В v0.7 секция ACL и disposable probe выполняются под `qbit_test_owner`, затем роль сбрасывается перед COMMIT; runtime privilege split проверяется отдельно; `functions_ok` ожидает 7 функций. **DB-03E на Supabase ещё не применён успешно**. Добавляются 7 narrow SECURITY DEFINER API: fenced read exact source content claimed job для recoverable local PII/STT; service-only operator state/version для CAS Take/Return/manual reply без чтения переписки; durable thematic warning including exact third warning after block; fenced outgoing content + final pre-send recheck for claimed sender action; persistent initiative opt-out/explicit opt-in; stable group `nuzhen_chelovek` без преждевременного Take; due reminder/loss scheduler без direct SELECT. `[x]` только после отдельного разрешения Павла, применения в test и успешного verifier |
| [x] DB-03A | DB-02 | `sql/DB-03A_reliability_core.sql` v0.1 успешно применён 24.09.2026: 9 core-таблиц, 25 индексов, integration FK=true, probe_rows=0, runtime direct DML=false, isolation canary untouched=true |
| [x] DB-03B | DB-03A | `sql/DB-03B_operator_tables.sql` v0.1 успешно применён 24.09.2026: 3 таблицы, 10 индексов, manager FK=true, probe_rows=0, runtime direct DML=false, isolation canary untouched=true |
| [x] DB-03C | DB-03A, DB-03B | DB-03C1…C4 применены и проверены: ingress idempotency/conflict, memory CAS, queue lease/fencing/reclaim, stale version, outgoing confirmed/retry/unknown, reminders/loss-check; production untouched |
| [x] DB-03C1 | DB-03B | `sql/DB-03C1_client_ingress.sql` v0.5 успешно применён 24.09.2026: 4 functions_ok, bot_execute_ok=true, service_execute_denied=true, runtime direct DML=false, attachment idempotency indexes=true, probe_rows=0; probes подтвердили variable/ambiguity/phone normalization/idempotency/conflict/wait-cancel; production untouched |
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
| [ ] WF-02 | WF-01, DB-03, PRE-02E | Родительская задача обновления workflow: сохранить согласованную логику pipeline, синхронизировать DB-03 JSONB API и заменить AI-слой на OpenAI; выполнить через WF-02A/WF-02B без преждевременного запуска DB-04/DB-05 |
| [x] WF-02A | DB-03 | 28.09.2026 полностью прочитан свежий экспорт из амстердамского n8n; Павел подтвердил n8n 2.41.0; карта старых DB-вызовов → DB-03 JSONB API и 4 OpenRouter → OpenAI сохранена в [WF-02A_WORKFLOW_AUDIT](WF-02A_WORKFLOW_AUDIT.md); secrets/Credential IDs/real chat data не найдены, `meta.instanceId` отмечен к удалению; workflow/сервер/Supabase не менялись |
| [ ] WF-02B | WF-02A, PRE-02E, DB-03E | Родитель обновления runtime workflow. Закрывается через WF-02B1/B2/B3: DB-03 архитектура → два полных JSON → import/runtime smoke; knowledge branch не считается рабочей до DB-05 |
| [x] WF-02B1 | WF-02A, DB-03 | 28.09.2026 по фактическим SQL DB-03 зафиксирована целевая runtime-архитектура двух n8n workflow, lease/fencing, отдельный outgoing sender, service/topic/mirror routing и три DB API gap. Документ: [WF-02B1_DB03_N8N_ARCHITECTURE](WF-02B1_DB03_N8N_ARCHITECTURE.md) |
| [ ] WF-02B2 | WF-02B1, PRE-02E, DB-03E | Взять свежий исходный workflow на 168 нод как единственную основу; сохранить его бизнес-логику/визуальную структуру, заменить старые вызовы Supabase на текущий DB-03/DB-03E контракт и OpenRouter/Qwen на OpenAI. Не создавать отдельные smoke/skeleton workflow; knowledge/RAG остаётся gated до DB-05 |
| [x] WF-02B2A | WF-02B1, DB-03 | 29.09.2026 на полном исходном workflow выполнен первый DB-участок: `zaregistrirovat_vhod_klienta(jsonb)` + отдельный `zabrat_zadanie_obrabotki(jsonb)`, webhook больше не claim-ит созданный job. Сохранены 168 нод и 135 connection keys; изменены только 6 нод первого участка, `instanceId` удалён. Queue claim временно disabled до адаптации downstream. Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json` |
| [x] WF-02B2B | WF-02B2A, DB-03E contract | 29.09.2026 offline в том же полном workflow адаптировано начало processing: exact source через `poluchit_soderzhimoe_zadaniya`, context/owner/block через `poluchit_kontekst_dialoga`, rate-limit через `proverit_limit_chastoty`; превышение лимита освобождает lease через `zavershit_zadanie_obrabotki(...povtor...)`. 168 нод сохранены; из-за последовательного продолжения трёх бывших terminal DB-нод connection keys стали 138. Media/STT/AI/outgoing не менялись. Claim disabled до DB-03E apply+verify |
| [x] WF-02B2C | WF-02B2B, DB-03C1, DB-03C2 | 29.09.2026 offline в том же полном workflow: успешная локальная транскрипция сохраняется через `sohranit_transkripciyu_golosa(jsonb)`, PII-detector принимает новый список reverse-map и сохраняет обезличивание через `sohranit_obezlichivanie(jsonb)`. Добавлена обязательная trusted-настройка `bezopasnost.region_telefona=null`; значение не выдумано. 168 нод/138 connection keys сохранены; media transport, AI/outgoing не менялись |
| [x] WF-02B2D | WF-02B2C, PRE-02E | 29.09.2026 offline в том же полном workflow thematic guard переведён с OpenRouter на OpenAI Responses API: gpt-6-luna, store=false, strict text.format/json_schema; parser читает Responses output[].content[].output_text, проверяет schema и fail-closed переводит error/refusal/incomplete к peredat_cheloveku. Planner/embeddings/answer/outgoing не менялись; runtime OpenAI Credential ещё не проверен |
| [x] WF-02B2E | WF-02B2D, PRE-02E | 29.09.2026 offline в том же полном workflow planner переведён с OpenRouter на OpenAI Responses API: отдельный `model.planner='gpt-6-luna'`, `store=false`, strict `text.format/json_schema`, 1–3 queries и 1–5 required_points. Parser читает Responses output и при error/refusal/invalid сохраняет старый безопасный fallback на один обезличенный пользовательский запрос. Embedding/RAG query, основной answer/outgoing не менялись |
| [x] WF-02B2F | WF-02B2E, PRE-02E | 29.09.2026 offline в том же полном workflow query embedding переведён с OpenRouter/Qwen на OpenAI `/v1/embeddings`: `text-embedding-3-large`, candidate `dimensions=1024`, `encoding_format=float`; parser проверяет наличие числового вектора и точную размерность 1024. DB-05 search node и основной answer/outgoing не менялись; runtime OpenAI embedding и retrieval quality ещё не проверены |
| [x] WF-02B2G | WF-02B2F, PRE-02E | 29.09.2026 offline основной LLM-ответ переведён с OpenRouter/DeepSeek на OpenAI Responses API: отдельный `model.answer='gpt-6-sol'`, `store=false`, strict `text.format/json_schema`; parser читает Responses output, валидирует этап/booleans/arrays и fail-closed переводит error/refusal/incomplete/invalid к менеджеру. OpenRouter/DeepSeek полностью удалены из канонического workflow; outgoing/DB-03C4 не менялись, RAG остаётся gated до DB-05 |
| [x] WF-02B2H | WF-02B2G, DB-03C4, DB-03E contract | 29.09.2026 offline bot outgoing переведён на текущий контракт: durable intent `sozdat_ishodyashchee_deystvie`, отдельный sender claim `zabrat_ishodyashchee_deystvie`, DB-03E final pre-send recheck `poluchit_soderzhimoe_ishodyashchego`, confirmed/unknown result через `zafiksirovat_rezultat_ishodyashchego`. Unknown не retry-ится вслепую. Sender claim остаётся disabled до DB-03E apply+verify. 168 нод, 139 connection keys |
| [x] WF-02B2I | WF-02B2H, DB-03C2, DB-03E contract | 30.09.2026 offline guard DB-actions переведены на текущий контракт: `zapisat_narushenie_tematiky`, exact warning через `sozdat_preduprezhdenie_tematiky`, handoff через `zaprosit_cheloveka`, opt-out через `ustanovit_zapret_iniciativy`. Warning больше не создаёт второй generic outgoing; non-block warning завершает job, blocking warning оставляет stale job для DB cleanup. Handoff/opt-out сами отменяют current job. AI/sender/service Telegram не менялись |
| [x] WF-02B2J | WF-02B2I, DB-03C3, DB-03C4 | 30.09.2026 offline в существующем `Сохранить намерение отправки` добавлено атомарное продолжение: сначала `sozdat_ishodyashchee_deystvie(jsonb)`, затем только при `uspeshno/dublikat` и для обычной processing-ветки fenced `zavershit_zadanie_obrabotki(status=zaversheno)`. Handoff/opt-out исключены, warning уже отдельный special path. 168 нод/139 connection keys, runtime gates disabled |
| [x] WF-02B2K | WF-02B2J, DB-03C1/DB-03E | 30.09.2026 проведён статический аудит всех 34 PostgreSQL-нод: 16 уже используют текущие DB-03/DB-03E API, 1 — disabled no-op, 17 требуют дальнейшей миграции. Остаток разделён на reminders (1), service ingress/topic/mirror (8), Take/Return/manual/manager registration (6), future-gated RAG (1) и external integration (1). Отчёт: `docs/WF-02B2K_DB_CALL_AUDIT.md` |
| [x] WF-02B2L | WF-02B2K, DB-03C4, DB-03E | 30.09.2026 offline reminder-ветка переведена на DB-03E `obrabotat_sleduyushchee_napominanie(jsonb)`: передаются trusted reminder1/reminder2 texts и `poterya_posle_sekund`; функция сама выбирает один due reminder/loss-check, делает final recheck и при необходимости создаёт обычный outgoing action. Inline sender connection удалён; общий sender забирает action своей очередью. Reminder node disabled до DB-03E apply+verify |
| [x] WF-02B2M | WF-02B2L, DB-03D1 | 30.09.2026 offline service Telegram ingress переведён на durable DB-03D1 `zaregistrirovat_sluzhebnoe_sobytie(jsonb)`: нормализация строит trusted account/external/idempotency/content packet, webhook отвечает 200 только при `uspeshno/dublikat`. Связь webhook → старый `vzyat_sluzhebnoe_zadanie` удалена, потому что новый ingress не возвращает legacy `zadanie_id`. Сами old service queue/topic/mirror/Take/Return/manual ноды не менялись |
| [x] WF-02B2N | WF-02B2M, DB-03D1 | 30.09.2026 offline service mirror runtime переведён на `zabrat_sobytie_zerkala(jsonb)` + fenced `zafiksirovat_rezultat_zerkala(jsonb)`. Нормализованы текущие D1 event types; media берётся из локально сохранённых DB bytes вместо client-bot file_id. Confirmed требует Telegram message_id; ambiguous = terminal `neizvestno`, локально отсутствующие media bytes = `oshibka`. Mirror claim disabled до topic migration. Topic/Take/Return/manual не менялись |
| [x] WF-02B2O | WF-02B2N, DB-03D1 | 30.09.2026 offline создание operator forum-topic переведено на `zabrat_sozdanie_operator_temy(jsonb)` → Telegram `createForumTopic` → `podtverdit_operator_temu(jsonb)` либо terminal `otmetit_temu_neizvestnoy(jsonb)` с worker/lease/fencing. HTTP blind retry удалён; topic и mirror claim остаются disabled до test-import/smoke. Mirror/Take/Return/manual не расширялись; workflow 167 нод/140 connection keys |
| [ ] WF-02B3 | WF-02B2 | Оба JSON импортированы в test n8n 2.41.0 без secrets/instance metadata; выполнены разрешённые ingress/queue/outgoing/operator smoke-checks и результаты сохранены |
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


- DB-03E v0.8 (30.09.2026): v0.7 reached reminder behavior probe and correctly returned `otmenit` because the synthetic client input timestamp was newer than `t0`. The fixture is corrected so client input precedes waiting `t0`. The loss-check fixture now also creates the DB-03C4-required confirmed reminder2 fact before testing `proverka_poteri`. Runtime functions are unchanged. DB-03E remains unapplied until a successful migration + verifier.

- DB-03E v0.9 (30.09.2026): reminder fixture isolated onto dedicated account `db03e_reminder_bot` so earlier opt-out/opt-in behavior probes cannot contaminate reminder final recheck. Post-probe cleanup assertion now checks both synthetic accounts. Runtime functions unchanged; DB-03E remains unapplied until successful migration + verifier.


### SQL-CLEANUP-01 — 30.09.2026
[x] После DB-03E v0.11 VERIFIED удалены из текущего `main` девять устаревших verifier-файлов `sql/DB-03E_v0.2_verify.sql` … `sql/DB-03E_v0.10_verify.sql`. Канонический `sql/DB-03E_runtime_gap_closure.sql` и актуальный `sql/DB-03E_v0.11_verify.sql` сохранены. История старых версий остаётся в Git. Другие SQL-блоки не удалялись.
