# KB-01R — сверка и исправление experimental KB → нормативный DB-04/DB-05

Статус: **reconciliation применена; structural verification и runtime R5A/R5B завершены; следующий этап — KB-01R5C**.

## KB-01R1 — inventory + mapping — ГОТОВО

Зафиксировано структурное несовпадение experimental и нормативной моделей; старый B3 поверх B1/B2 продолжать нельзя.

## KB-01R2 — выбор пути — ГОТОВО

Live read-only verifier подтвердил нулевые row counts и отсутствие дополнительных KB-объектов. Выбран путь **recreate**.

## KB-01R3 — подготовка recreate — ГОТОВО

Подготовлены canonical recreate `KB-01R3 v0.2`, guarded rollback и verifier.

## KB-01R4 — test apply + structural verifier — ГОТОВО

04.10.2026 recreate v0.2 применён в test Supabase. Финальная structural проверка выполнена `sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`.

Подтверждено: experimental objects absent; нормативные таблицы присутствуют; owners/SECURITY DEFINER/search_path и EXECUTE matrix корректны; direct runtime table DML запрещён; `vector(1024)` + HNSW и integrity triggers присутствуют.

## KB-01R5 — runtime validation

### KB-01R5A — ingestion + knowledge queue — ГОТОВО

`sql/KB-01R5A_runtime_ingestion_queue_probe.sql` выполнен в n8n через фактический Credential `qbit_test_sluzhebnyy`.

PASS:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Подтверждены service event, upload create/duplicate/conflict, claim, heartbeat, stale worker, retry, fencing и finish. Синтетические строки откатились финальным intentional exception.

### KB-01R5B — version/profile/fragments/reference checks + draft search — ГОТОВО

Перед runtime probe выявлен API-gap: `sohranit_kontrolnye_voprosy` скрывает внутренние UUID вопросов, а `sohranit_proverki_znaniy` первоначально требовал `vopros_id`. Прямой SELECT таблицы для `qbit_test_sluzhebnyy` запрещён и не открывался.

Test-only patch:

`sql/KB-01R5B_patch_question_number_test.sql`

Результат: `KB-01R5B_PATCH_v0.1 applied`. Функция `sohranit_proverki_znaniy` теперь обратно-совместимо принимает либо `vopros_id`, либо `nomer_voprosa`.

Основной runtime probe:

`sql/KB-01R5B_runtime_version_fragments_draft_probe.sql`

PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Подтверждены:
- `podgotovit_versiyu_znaniy`;
- profile dimension 1024;
- batch save fragments + idempotent repeat;
- draft-only search по явной version/profile;
- 3 контрольных вопроса;
- 3 успешные проверки по `nomer_voprosa`;
- переход version в `gotova`;
- draft search для ready-but-unpublished version.

Дополнительный guards probe:

`sql/KB-01R5B_runtime_guards_probe.sql` v0.2

PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

Подтверждены fragment hash guard, vector dimension guard, max-token guard, immutable profile-fingerprint semantics и запрет service-role вызывать client active search. Синтетические данные обоих probe откатились.

### KB-01R5C — СЛЕДУЮЩАЯ ЗАДАЧА

Runtime-проверить:
- публикацию первой ready version;
- публикацию новой version с ожидаемой предыдущей active version;
- stale `ozhidaemaya_aktivnaya_versiya_id` conflict;
- атомарный active switch + archive предыдущей version;
- `poisk_aktivnyh_znaniy` через фактический `qbit_test_bot` Credential;
- отсутствие draft в client active search;
- `otozvat_dokument_znaniy` через фактический разрешённый dash_admin путь;
- отсутствие лишних DB-прав у bot/service/dash_admin.

Использовать только синтетические test-data и заранее контролируемый rollback/cleanup. Не включать реальный client RAG workflow.

## Отдельная зависимость PRE-02E

Фактическая длина embedding `text-embedding-3-large` с `dimensions=1024` должна быть подтверждена в каноническом OpenAI workflow. DB runtime с синтетическим vector этого не заменяет.

## Постоянные ограничения

- не продолжать старый B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG workflow до завершения нужных runtime-тестов;
- не менять production;
- не запускать experimental evidence SQL повторно;
- не использовать аварийный KB rollback после появления нужных данных без отдельного плана сохранения.
