# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-07.

Нормативные DB-04/DB-05 созданы и runtime-проверены в test-контуре. Production не менять без отдельного явного разрешения Павла.

Каноническая основа workflow — фактический export Павла `(7)`, raw SHA-256 `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний сохранённый в Git восстановимый runtime-checkpoint пока остаётся KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**, SHA-256 `54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`. Отдельный Git-checkpoint v0.11 ещё не сохранён.

Для текущего KB-03B1 подготовлен локальный **v0.12 KB-03B1**, ещё не runtime-проверенный:
- SHA-256 `d562404cdc51788783eaf22b745310b69bcf3b2d07bcb8b5495fffdeffd6597c`;
- 254 nodes;
- 206 connection keys;
- 288 edges;
- `active=false`;
- Credential refs 0;
- duplicate names 0;
- dangling connections 0;
- все Code nodes проходят JavaScript syntax check;
- ручной путь не содержит generative LLM nodes; внешние AI-вызовы только OpenAI embeddings.

Подплан текущей задачи: `docs/KB-03B_IMPLEMENTATION_PLAN.md`.

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
| [~] KB-03B1 | KB-03B0 runtime | Save questions → bridge IDs → one-batch question embeddings → draft-only top-12 → factual threshold grid → deterministic expected path/fact checks → `sohranit_proverki_znaniy`; `gotova` только при полном pass. |
| [ ] KB-03C | KB-03B1 | Atomic publish + stale conflict + active-only end-to-end regression. |

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

KB-03A использует один embeddings batch на набор fragments. KB-03B1 использует один embeddings batch только на 3–10 canonical questions. Это не generative LLM.

## Доказанный runtime

- KB-01A: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.
- KB-01B1: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-01B2: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A1: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A2: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02B: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-03A: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-03B0: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.

KB-03A successful safe runtime: 6 fragments, one OpenAI batch, 6 vectors ×1024, finite values only, exact input/index mapping, DB `sohraneno_fragmentov=6`, `vsego_fragmentov=6`, version remained `chernovik`, publish false, job → `povtor`.

KB-03B0 runtime verified:
- `poluchit_kontrolnye_voprosy_znaniy(jsonb)` owner `qbit_test_owner`;
- service execute true;
- bot/public execute false;
- direct service SELECT questions false;
- production untouched;
- next stage KB-03B1.

## KB-03B1 — текущая задача

v0.12 обязан:
1. заново получить canonical YAML questions через deterministic parser/KB-02B;
2. после подтверждённого fragment DB save сохранить 3–10 questions через `sohranit_kontrolnye_voprosy`;
3. получить реальные `vopros_id` через KB-03B0 bridge под текущим live lease/fencing;
4. одним OpenAI batch получить embeddings exact `vopros`: `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
5. проверить count/index/vector length 1024/finite values;
6. вызвать `poisk_chernovika_znaniy` только по своей `versiya_id`/profile;
7. собрать top-12 при search threshold 0, чтобы до калибровки не терять similarities;
8. оценить фактическую grid 0.45..0.85 шаг 0.05;
9. для B1 validation выбрать **максимальный grid threshold, на котором все positive YAML reference questions проходят**; если полного pass в grid нет — сохранить checks на 0.45 и оставить version `chernovik`;
10. `ozhidaemyy_razdel` и optional `ozhidaemyy_fakt` должны подтверждаться одним и тем же найденным fragment детерминированно, без LLM-самооценки;
11. сохранить фактические fragment IDs/similarities/results через `sohranit_proverki_znaniy`;
12. DB может перевести version в `gotova` только при полном pass всех canonical questions;
13. выбранный B1 threshold **не считается финальным client retrieval threshold**: для него позже нужен также negative/no-answer набор;
14. publish в B1 не выполняется;
15. production не менять.

После runtime-verified KB-03B1 переходить к KB-03C.
