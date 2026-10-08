# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-08.

Нормативные DB-04/DB-05 созданы и runtime-проверены в test-контуре. Production не менять без отдельного явного разрешения Павла.

Текущая repository-safe основа:
- `workflows/current/Шаблон Загрузка документов Qbit.json`;
- `workflows/current/Шаблон — Workflow бота Qbit.json`.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Исторический восстановимый checkpoint KB-01A остаётся в `workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/` и не является текущей версией для импорта.

Подплан завершённой KB-03B: `docs/KB-03B_IMPLEMENTATION_PLAN.md`.
Активный подплан KB-03C: `docs/KB-03C_IMPLEMENTATION_PLAN.md`.

## Этапы

| Статус / ID | Зависимости | Результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует upload/job. |
| [x] KB-01B1 | KB-01A | Manual worker claim + lease/fencing + safe YAML/Markdown parser + deterministic `hash_soderzhaniya`. |
| [x] KB-01B2 | KB-01B1 | Processing/index profile + draft version. |
| [x] KB-02A1 | KB-01B2 | Ordered semantic blocks с heading path; YAML/reference questions исключены из retrieval text. |
| [x] KB-02A2 | KB-02A1 | Exact `cl100k_base` + structural packing; target 600, hard max 800, overlap только внутри реально разрезанного блока. |
| [x] KB-02B | KB-02A2 | Final fragment records + отдельные YAML reference questions; exact text/hash/token count/order/trace. |
| [x] KB-03A | KB-02B | OpenAI `text-embedding-3-large/1024/float`; vectors строго проверены; fragments/vectors сохранены через `sohranit_fragmenty_znaniy`. |
| [x] KB-03B0 | KB-03A | TEST-only SECURITY DEFINER bridge возвращает реальные `vopros_id` только своей live fenced job/version; direct table SELECT не выдаётся. |
| [x] KB-03B1 | KB-03B0 runtime | Save questions → bridge IDs → one-batch question embeddings → draft-only top-12 → factual threshold grid → deterministic expected path/fact checks → `sohranit_proverki_znaniy`; runtime 9/9, `gotova`, publish=false. |
| [~] KB-03C | KB-03B1 runtime | Разделена на KB-03C1 prepare-only publish branch и KB-03C2 runtime atomic publish + stale conflict + active-only regression. |

## Guard по нагрузке на LLM

Постоянное правило knowledge/RAG:
- ingestion, parsing, cleaning, chunking и token counting выполняются без generative LLM;
- embeddings используются только для индексации/semantic search;
- вся база, structural blocks и candidate set никогда не передаются клиентской LLM целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → ограниченный evidence package → финальная LLM;
- candidate top-k = 12; финальный evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- до завершения retrieval-калибровки зафиксировать общий evidence token budget.

A2 runtime: 130 structural blocks → 53 candidates, 87..551 tokens, average 237.1, >800 = 0. Target 600 не является минимумом.

KB-03A использует один embeddings batch на набор fragments. KB-03B1 использует один embeddings batch только на canonical questions. Это не generative LLM.

## Доказанный runtime

- KB-01A: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.
- KB-01B1: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-01B2: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A1: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A2: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02B: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-03A: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-03B0: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.
- KB-03B1 final: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.
- KB-03B1 historical partial 6/8: `docs/evidence/KB-03/KB-03B1_PARTIAL_RUNTIME_2026-10-07.md`.

## KB-03B1 — CLOSED

Runtime 08.10.2026 подтвердил:
1. 9 canonical YAML questions сохранены;
2. question IDs получены через B0 bridge под live fence;
3. один OpenAI batch exact question texts: `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
4. 9 vectors, dimension 1024, finite values, index mapping true;
5. `poisk_chernovika_znaniy` ограничен текущими `versiya_id` + profile;
6. top-k 12, initial search threshold 0;
7. factual grid 0.45..0.85 рассчитана;
8. full pass 9/9 на 0.45..0.60, максимальный full-pass threshold = 0.60;
9. expected section/fact проверены одним fragment детерминированно, generative LLM = 0;
10. `sohranit_proverki_znaniy` сохранил 9/9 и перевёл version в `gotova`;
11. publish=false;
12. job безопасно освобождён для следующего этапа; `next_stage=KB-03C`.

B1 threshold 0.60 **не является финальным client retrieval threshold**: для него позже нужен negative/no-answer набор.

## KB-03C — ACTIVE

Подплан: `docs/KB-03C_IMPLEMENTATION_PLAN.md`.

### KB-03C1 — текущая маленькая задача

**Prepare-only:** обновить repository-safe workflow документов, добавив безопасный publish branch после B1 full pass/`gotova`, но не импортировать его и не выполнять publication/server mutation.

Перед кодом прочитать только фактический SQL/contract `opublikovat_versiyu_znaniy` и `zavershit_zadanie_znaniy`; payload/status не угадывать.

Критерий: полный import-ready JSON статически проверен, publish path fail-closed, stale/conflict обработан явно, B1 path не сломан, секретов/Credential refs нет, сервер не изменён.

### KB-03C2 — после C1

Отдельный TEST runtime: atomic publish + stale conflict + active-only end-to-end regression через уже существующий клиентский `poisk_aktivnyh_znaniy`.

Production и рабочий трафик не менять.
