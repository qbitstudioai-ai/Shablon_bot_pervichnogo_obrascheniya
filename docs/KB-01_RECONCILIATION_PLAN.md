# KB-01R — сверка и исправление experimental KB → нормативный DB-04/DB-05

Статус: **reconciliation применена; R5A/R5B/R5C runtime-проверки текущего bot/service контура завершены; dash_admin runtime вынесен в R5D на dashboard stage; следующая задача — PRE-02E**.

## KB-01R1 — inventory + mapping — ГОТОВО

Зафиксировано структурное несовпадение experimental и нормативной моделей; старый B3 поверх B1/B2 продолжать нельзя.

## KB-01R2 — выбор пути — ГОТОВО

Live read-only verifier подтвердил нулевые row counts и отсутствие дополнительных KB-объектов. Выбран путь **recreate**.

## KB-01R3 — подготовка recreate — ГОТОВО

Подготовлены canonical recreate `KB-01R3 v0.2`, guarded rollback и verifier.

## KB-01R4 — test apply + structural verifier — ГОТОВО

04.10.2026 recreate v0.2 применён в test Supabase. Подтверждены owners/SECURITY DEFINER/search_path, EXECUTE matrix, запрет direct runtime DML, `vector(1024)` + HNSW и integrity triggers.

## KB-01R5 — runtime validation

### KB-01R5A — ingestion + knowledge queue — ГОТОВО

PASS через фактический `qbit_test_sluzhebnyy`:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Подтверждены service event, upload create/duplicate/conflict, claim, heartbeat, stale worker, retry, fencing и finish.

### KB-01R5B — version/profile/fragments/reference checks + draft search — ГОТОВО

Применён test-only backward-compatible patch `sql/KB-01R5B_patch_question_number_test.sql`: `sohranit_proverki_znaniy` принимает `vopros_id` или `nomer_voprosa`.

PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Guards PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

### KB-01R5C — publish concurrency + atomic active switch + bot active-only search — ГОТОВО

После ранних probe-итераций финальная runtime-проверка была разбита на отдельные транзакции, как это будет происходить в n8n runtime.

Service Credential `qbit_test_sluzhebnyy`:

- Phase1: V1 успешно опубликована;
- Phase2A: V2/V3 подготовлены как competing `gotova` versions с одной ожидаемой active V1;
- Phase2B: V2 опубликована, V1 стала предыдущей/архивной;
- stale V3 получила `konflikt / stale_expected_active`.

Bot Credential `qbit_test_bot`:

`KB-01R5C_BOT_v0.2 status=verified`

Подтверждены active-only semantics: V2 видна, V1 скрыта, V3 скрыта, draft-search для bot запрещён.

После проверки exact synthetic rows удалены:

`KB-01R5C_CLEANUP_v0.3 status=cleaned`

Удалено 3 versions, 3 uploads, 3 jobs, 3 events, 3 fragments, 9 questions, 9 checks. Production не затрагивалась.

Evidence: `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`.

Ранний `sql/KB-01R5C_service_publish_prepare.sql` помечен `OBSOLETE_DO_NOT_RUN`.

### KB-01R5D — dash_admin runtime revoke — ОТЛОЖЕНО ДО DASHBOARD STAGE

Первоначально revoke входил в R5C, но runtime-проверка требует фактический connection роли `qbit_test_dash_admin`. Такого n8n Credential сейчас нет; фактически созданы только bot и service Credentials.

Структурная EXECUTE matrix dash_admin уже проверена в R4. Реальный `otozvat_dokument_znaniy` через dash_admin выполнить в R5D при подключении dashboard. Не создавать третий n8n Credential только ради текущего теста.

## Отдельная зависимость PRE-02E — СЛЕДУЮЩАЯ ЗАДАЧА

Фактическая длина embedding `text-embedding-3-large` с `dimensions=1024` должна быть подтверждена в каноническом OpenAI workflow. DB runtime с синтетическим vector этого не заменяет.

## Постоянные ограничения

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG до PRE-02E runtime-проверки;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не запускать `sql/KB-01R5C_service_publish_prepare.sql`;
- не использовать аварийный KB rollback после появления нужных данных без отдельного плана сохранения.
