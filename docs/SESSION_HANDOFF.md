# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B и KB-03A завершены и runtime-проверены. Текущая маленькая задача — **KB-03B**.

В начале следующей сессии проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/specs/KNOWLEDGE_INGESTION.md`;
6. `docs/specs/DB_CONTRACT.md` — только reference-question/search/check contract;
7. `docs/specs/PROCESSING_PROFILE.md` — OpenAI embedding/retrieval profile.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore:
`python tools/restore_workflow_checkpoint.py`

SHA-256 старого checkpoint:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**:
`Шаблон — мультиканальный бот и служебный Telegram — версия 0.11 KB-03A.json`

SHA-256:
`54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`.

OpenAI Credential подключается только в n8n UI. Credential/API key не должен попадать в export/Git. Отдельный Git-checkpoint v0.11 ещё не сохранён; не утверждать обратное.

## Доказанный runtime

### KB-01A
Service `.md` intake → durable upload/job.
Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Safe parser + deterministic `hash_soderzhaniya` + fenced retry.
Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
Profile/fingerprints + version 1 `chernovik`.
Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A1
Большая safe база: structural blocks/heading paths, YAML/questions excluded, DB save 0.
Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
Большая safe база: exact `cl100k_base`, 130 blocks → 53 candidates, 87..551 tokens, LLM/embeddings/DB save 0.
Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02B
Live v0.10: 6 final fragment records, exact text/hash/token count/order/trace; 3 separate YAML reference questions; LLM/embeddings/DB save/publish 0.
Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-03A
Первая попытка на большой базе дошла до 53 fragments / 12568 input tokens и безопасно остановилась на `Credentials not found`; DB save/publish не выполнялись, job → `povtor`.

После привязки TEST OpenAI Credential успешный live-run на safe документе:
- fence `5`;
- 6 exact fragments;
- one OpenAI batch;
- `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- usage 910 input tokens;
- vectors 6, dimension min/max 1024/1024;
- all values finite;
- exact fragment input + mapping by API index confirmed;
- generative LLM 0;
- `sohranit_fragmenty_znaniy` → `uspeshno`;
- `sohraneno_fragmentov=6`, `vsego_fragmentov=6`;
- version remains `chernovik`;
- reference questions not embedded/saved;
- publish false;
- job → `povtor`.

Evidence: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.

## Guard по нагрузке на LLM

- parsing/cleaning/chunking/token counting — без generative LLM;
- embeddings — индексные/поисковые операции, не генерация ответа;
- fragment records не являются prompt целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM;
- candidate top-k = 12;
- final evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- позже зафиксировать общий evidence token budget.

## Текущая задача — KB-03B

Цель: сохранить reference questions и доказать draft-only retrieval quality по уже сохранённым fragments/vectors.

Обязательные свойства:
- использовать canonical YAML questions из KB-02B;
- сохранить через `sohranit_kontrolnye_voprosy`;
- question embedding: OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
- embedding input = только текст `vopros`;
- каждый vector length 1024, finite;
- `poisk_chernovika_znaniy` должен искать только в своей `versiya_id`/profile;
- для каждого question проверить `ozhidaemyy_razdel`; optional `ozhidaemyy_fakt` проверять по фактическому найденному тексту, без LLM-самооценки;
- сохранить фактические results через `sohranit_proverki_znaniy`;
- only full pass → version `gotova`;
- any fail → version остаётся неготовой;
- publish не выполнять;
- similarity threshold калибровать по фактическим результатам, не назначать по памяти;
- job не терять при API/search/check error;
- production не менять.

## Следующая задача после KB-03B

`KB-03C` — atomic publish + active-only end-to-end regression.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
