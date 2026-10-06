# Текущее состояние проекта

Обновлено: 2026-10-06.

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

Фактически текущий runtime-проверенный import-ready workflow — **v0.10 KB-02B**:
- SHA-256 `f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`;
- 223 nodes;
- 180 connection keys;
- 251 edges;
- `active=false`;
- Credential refs 0;
- duplicate names 0;
- dangling connections 0.

Отдельный Git-checkpoint v0.10 ещё не сохранён; не утверждать обратное.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test: ingestion queue, lease/fencing, version/profile/fragments/reference checks, `vector(1024)`, draft-only service search, atomic publish и active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

`fragmenty_znaniy` требуют уже готовый `vector(1024)`. Поэтому KB-02A1/A2/B ничего не записывали в fragments. Нормативный `sohranit_fragmenty_znaniy` впервые вызывается в KB-03A после embeddings.

DB при сохранении повторно проверяет exact fragment text SHA-256, token max профиля и vector dimension.

## Ограничение нагрузки на LLM

Постоянный guard:
- ingestion, parsing, cleaning, chunking и token counting — без generative LLM;
- embeddings — только для индексации/semantic search;
- вся база/все blocks/candidates никогда не идут в клиентскую LLM целиком;
- сначала query embedding → vector search → фильтрация/дедупликация;
- candidate top-k 12, финальный evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- до retrieval-калибровки зафиксировать общий evidence token budget.

На большой safe-базе A2 получил 53 candidates из 130 structural blocks, average 237.1 tokens, max 551. Разные темы не объединяются ради target 600.

## PRE-02E / tokenizer

Отдельного PRE-02E smoke нет. OpenAI document embeddings `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` и строгая проверка длины закрываются в KB-03A.

Tokenizer runtime уже доказан в KB-02A2: встроенный n8n TokenTextSplitter использует локальный `cl100k_base`; exact count подтверждён canary и runtime.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## Закрытые runtime-этапы

- KB-01A — service `.md` intake → durable upload/job. Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.
- KB-01B1 — safe YAML/Markdown parser + deterministic content hash + fenced retry. Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-01B2 — profile/fingerprints + version 1 `chernovik`. Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A1 — structural blocks/heading paths, YAML/questions excluded from retrieval text. Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02A2 — exact `cl100k_base` + structural candidate packing. Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.
- KB-02B — final fragment records + separate YAML reference questions. Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02B — CLOSED / runtime verified

Live v0.10 runtime прошёл на safe документе `qbit_podgotovka_k_pervichnomu_razboru`:
- fence 4;
- A2: 6 candidates, exact `cl100k_base`, 102..211 tokens;
- B: 6 final fragment records, sequential numbering, exact text/hash/token count и runtime source-block trace;
- `hash_nabora_fragmentov=d367f0824cee817d498778f95815b4175a3e47cebd2facebdcacaffc1703a0d2`;
- 3 YAML reference questions;
- `hash_nabora_kontrolnyh_voprosov=d34d9e8222fa5608d2c4612a2decf5d158b7cbf3dc8fbba8499774639082e70a`;
- `hash_gotovogo_nabora=ad69f88ebbd5c99147cf3c750fcacaa37e4d12ff58366bd53f5573e04b150455`;
- questions не входят в retrieval text;
- LLM/embeddings/DB fragment save/question save/publish = 0;
- version 1 осталась `chernovik`;
- job возвращён в `povtor`.

Детерминизм B-кода дополнительно подтверждён двумя локальными запусками на идентичном входе с побайтово одинаковым полным JSON. Второй live-claim не выполнялся.

## Следующая маленькая задача — KB-03A

Цель: получить embeddings OpenAI для final fragment records и сохранить fragments/vectors через `sohranit_fragmenty_znaniy`.

Критерий:
- модель только `text-embedding-3-large`;
- `dimensions=1024`, `encoding_format=float`;
- embedding input = exact `tekst_fragmenta` из KB-02B без дополнительного splitter;
- каждый vector длиной ровно 1024, только конечные числа;
- порядок vectors однозначно связан с `nomer_fragmenta`;
- DB payload содержит exact text/path/token/hash + vector;
- один batch 1..100 fragments;
- DB возвращает корректные `sohraneno_fragmentov` / `vsego_fragmentov`;
- при внешней/частичной ошибке publish не выполняется и fenced job не теряется;
- reference questions в KB-03A ещё не векторизуются;
- production не менять.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
