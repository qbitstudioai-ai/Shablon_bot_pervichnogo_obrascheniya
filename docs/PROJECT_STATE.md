# Текущее состояние проекта

Обновлено: 2026-10-07.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Фактическая основа workflow — export Павла `(7)`, raw SHA-256 `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore:
`python tools/restore_workflow_checkpoint.py`

SHA-256 старого восстановленного checkpoint:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**:
- SHA-256 `54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`;
- OpenAI Credential подключается только в n8n UI и не хранится в export/Git;
- отдельный Git-checkpoint v0.11 ещё не сохранён; не утверждать обратное.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test: ingestion queue, lease/fencing, version/profile/fragments/reference checks, `vector(1024)`, draft-only service search, atomic publish и active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

KB-03A впервые сохранил реальные fragments/vectors через нормативный `sohranit_fragmenty_znaniy`. DB повторно проверяет exact fragment SHA-256, token max профиля и vector dimension.

При подготовке KB-03B найден DB-контрактный разрыв: `sohranit_kontrolnye_voprosy(jsonb)` возвращает только количество сохранённых вопросов, а `sohranit_proverki_znaniy(jsonb)` требует реальный `vopros_id`. Прямой `SELECT` таблицы `kontrolnye_voprosy` служебной роли запрещён. Поэтому KB-03B разделена на `KB-03B0` и `KB-03B1`.

Подготовлен TEST-only SQL:
`sql/KB-03B0_question_ids_bridge_test.sql`.

Он добавляет узкую SECURITY DEFINER-функцию `poluchit_kontrolnye_voprosy_znaniy(jsonb)`, которая выдаёт ID/metadata вопросов только для своей live fenced job/version. SQL **ещё не считается применённым на сервере**, пока Павел не пришлёт `kb03b0_status=verified`.

## Ограничение нагрузки на LLM

Постоянный guard:
- ingestion, parsing, cleaning, chunking и token counting — без generative LLM;
- embeddings — только для индексации/semantic search;
- вся база/все blocks/candidates никогда не идут в клиентскую LLM целиком;
- сначала query embedding → vector search → фильтрация/дедупликация;
- candidate top-k 12, финальный evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- до retrieval-калибровки зафиксировать общий evidence token budget.

На большой safe-базе A2 получил 53 candidates из 130 structural blocks, average 237.1 tokens, max 551. KB-03A использует один embedding batch на набор fragments, а не generative LLM.

KB-03B1 также не будет использовать generative LLM: 3–10 reference questions отправляются одним embeddings batch, а проверочный поиск выполняется PostgreSQL/pgvector.

## OpenAI embedding profile — runtime verified

Document embeddings runtime подтверждён в KB-03A:
- provider OpenAI;
- model `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- input = exact `tekst_fragmenta`;
- vector length строго 1024;
- finite values only;
- mapping по API `index`;
- один batch request на набор fragments.

Успешный safe runtime: 6 fragments, 910 input tokens, 6 vectors, DB `sohraneno_fragmentov=6`, `vsego_fragmentov=6`.

Первая попытка на большой базе с 53 fragments / 12568 input tokens была безопасно остановлена только из-за отсутствующего Credential; DB save/publish не произошли, job вернулся в `povtor`.

## Активный план

Родительский план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.
Подплан текущей задачи: `docs/KB-03B_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B0` → `KB-03B1` → `KB-03C`.

## Закрытые runtime-этапы

- KB-01A — service `.md` intake → durable upload/job. Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.
- KB-01B1 — safe parser + deterministic `hash_soderzhaniya` + fenced retry. Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-01B2 — profile/fingerprints + version 1 `chernovik`. Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A1 — structural blocks/heading paths, YAML/questions excluded from retrieval text. Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A2 — exact `cl100k_base` + structural candidate packing. Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02B — final fragment records + separate YAML reference questions. Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-03A — OpenAI document embeddings + strict vector validation + normative fragment/vector save. Evidence: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-03A — CLOSED / runtime verified

Успешный live-run на safe документе:
- fence 5;
- 6 exact final fragments;
- 1 OpenAI embeddings batch;
- 6 vectors × 1024;
- finite values only;
- exact input/order mapping подтверждены;
- `sohranit_fragmenty_znaniy` → `uspeshno`;
- `sohraneno_fragmentov=6`;
- `vsego_fragmentov=6`;
- version 1 остаётся `chernovik`;
- questions не embedded/saved;
- publish false;
- job → `povtor`.

Поле `kb03a_otchet.db_fragmenty_sohraneny=false` относится к pre-save snapshot. Фактический post-save результат — DB response + `db_save_ok=true`.

## Текущая маленькая задача — KB-03B0

Применить и проверить `sql/KB-03B0_question_ids_bridge_test.sql` в TEST.

Критерий:
- функция `poluchit_kontrolnye_voprosy_znaniy(jsonb)` существует и принадлежит `qbit_test_owner`;
- SECURITY DEFINER + fixed search_path;
- EXECUTE только у `qbit_test_sluzhebnyy`, не у bot/PUBLIC;
- прямой SELECT `kontrolnye_voprosy` служебной роли остаётся запрещён;
- smoke даёт контролируемый `otkaz / nekorrektnyy_vhod`;
- финальный `kb03b0_result.kb03b0_status = verified`;
- production untouched.

После runtime-verified KB-03B0 без новой паузы готовить `KB-03B1` workflow: save questions → получить ID через bridge → one-batch OpenAI question embeddings → draft-only top-12 search → фактическая калибровка 0.45..0.85 → deterministic expected path/fact checks → `sohranit_proverki_znaniy`.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.