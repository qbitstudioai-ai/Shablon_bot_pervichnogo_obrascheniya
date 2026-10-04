# Текущее состояние проекта

Обновлено: 2026-10-04.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки: 189 нод, 153 connection keys, 215 edges, `active=false`, duplicate names 0, dangling connections 0; credentials/instance ID/реальный ID служебной группы удалены. SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировать**.

## KB-01R1…R4

KB-01R1 выполнила mapping experimental KB к нормативному DB-04/DB-05. KB-01R2 выбрала recreate. KB-01R3 подготовила canonical recreate `KB-01R3 v0.2`. KB-01R4 применила его в test Supabase и structurally verified через `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH`.

Подтверждено: experimental KB отсутствует; нормативные DB-04/DB-05 созданы; owners/search_path/SECURITY DEFINER/EXECUTE matrix корректны; direct runtime table DML запрещён; `vector(1024)` + HNSW и integrity triggers присутствуют. Production не менялась.

## KB-01R5A — runtime ingestion + queue VERIFIED

04.10.2026 в n8n выполнен `sql/KB-01R5A_runtime_ingestion_queue_probe.sql` через фактический Postgres Credential `qbit_test_sluzhebnyy`.

Фактический PASS:

`KB-01R5A_PASS ... attempts=2 fence1=1 fence2=2 rollback=guaranteed`

Подтверждены durable service event, upload create/duplicate/conflict, claim, heartbeat, retry, fencing/stale worker и finish. Финальный PASS exception откатил синтетические строки.

## KB-01R5B — version/profile/fragments/reference checks + draft search VERIFIED

04.10.2026 сначала применён test-only patch:

`sql/KB-01R5B_patch_question_number_test.sql`

Результат: `KB-01R5B_PATCH_v0.1 applied`. Patch обратно-совместимо разрешил `sohranit_proverki_znaniy` принимать `nomer_voprosa` вместо необходимости узнавать скрытый внутренний UUID вопроса; прежний `vopros_id` сохранён.

Основной runtime probe:

`sql/KB-01R5B_runtime_version_fragments_draft_probe.sql`

Фактический PASS:

`KB-01R5B_PASS ... fragments=2 questions=3 checks=3 status=gotova draft_search=verified rollback=guaranteed`

Подтверждены:
- подготовка logical document/version;
- index profile `razmernost=1024`;
- сохранение двух fragments и идемпотентный повтор batch;
- version-scoped draft search с ожидаемым fragment и cosine similarity;
- 3 контрольных вопроса;
- 3 успешные проверки по `nomer_voprosa`;
- переход draft version в `gotova`;
- draft search после `gotova` до публикации.

Дополнительный guards probe:

`sql/KB-01R5B_runtime_guards_probe.sql` v0.2

Фактический PASS:

`KB-01R5B_GUARDS_PASS hash_guard=true dimension_guard=true token_guard=true profile_fingerprint_guard=true service_active_search_denied=true rollback=guaranteed`

Подтверждены отрицательные защиты:
- неверный fragment hash отклоняется;
- неправильная размерность vector отклоняется;
- превышение max token count отклоняется;
- один profile fingerprint нельзя переиспользовать с другим profile/model;
- `qbit_test_sluzhebnyy` не может вызывать клиентский `poisk_aktivnyh_znaniy`.

Оба runtime probe завершались intentional exception и откатили синтетические строки. Фактический OpenAI embedding всё ещё отдельно проверяется в PRE-02E.

## Что ещё не проверено

- stale/parallel publish и atomic active switch;
- bot active-only search через реальный `qbit_test_bot` Credential;
- dash_admin revoke;
- PRE-02E OpenAI embedding `dimensions=1024`.

Реальная `.md` база компании не загружалась. Client RAG не включался. Production не менялась.

## Текущая одна задача

**KB-01R5C — runtime-проверить publish concurrency, atomic active switch, bot active-only search и admin revoke.**

Цель R5C:
- подготовить синтетические ready versions;
- доказать stale/expected-active protection при публикации;
- доказать атомарное переключение active version и архивирование предыдущей;
- проверить `poisk_aktivnyh_znaniy` через фактический Credential `qbit_test_bot`;
- подтвердить, что draft не попадает в client active search;
- проверить `otozvat_dokument_znaniy` через разрешённый `dash_admin` API и отсутствие лишних прав.

Следующий этап после R5C, не начинать автоматически:
- **PRE-02E** — фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Ограничения

- Production не изменялась.
- Старый B3 не продолжать.
- Старый KB workflow не импортировать.
- Client RAG не включать до завершения R5C.
- Experimental evidence SQL повторно не запускать.
- `sql/DB-04_05_knowledge_rollback_test.sql` теперь только аварийный rollback; после появления нужных KB-данных его нельзя запускать без отдельного плана сохранения.
