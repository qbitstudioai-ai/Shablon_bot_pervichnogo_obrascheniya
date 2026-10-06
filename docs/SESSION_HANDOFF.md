# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2 и KB-02B завершены и runtime-проверены. Текущая маленькая задача — **KB-03A**.

В начале следующей сессии проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/specs/KNOWLEDGE_INGESTION.md`;
6. `docs/specs/DB_CONTRACT.md` — только DB-04 save fragment contract;
7. `docs/specs/PROCESSING_PROFILE.md` — OpenAI embedding profile.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore:
`python tools/restore_workflow_checkpoint.py`

SHA-256 старого checkpoint:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.10 KB-02B**:
`Шаблон — мультиканальный бот и служебный Telegram — версия 0.10 KB-02B.json`

SHA-256:
`f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`.

Статика: 223 nodes, 180 connection keys, 251 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Отдельный Git-checkpoint v0.10 ещё не сохранён; не утверждать обратное.

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
Большая safe база: 57 headings, 130 structural blocks, warnings 0, YAML/questions excluded, DB save 0.
Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
Большая safe база: exact `cl100k_base`, 130 blocks → 53 candidates, 87..551 tokens, average 237.1, >800 = 0, LLM/embeddings/DB save 0.
Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02B
Live v0.10 на safe документе `qbit_podgotovka_k_pervichnomu_razboru`:
- fence `4`;
- A2: 6 candidates, 102..211 tokens;
- 6 final fragment records;
- sequential numbering + exact text/hash/token count + source-block trace;
- `hash_nabora_fragmentov=d367f0824cee817d498778f95815b4175a3e47cebd2facebdcacaffc1703a0d2`;
- 3 YAML reference questions;
- `hash_nabora_kontrolnyh_voprosov=d34d9e8222fa5608d2c4612a2decf5d158b7cbf3dc8fbba8499774639082e70a`;
- `hash_gotovogo_nabora=ad69f88ebbd5c99147cf3c750fcacaa37e4d12ff58366bd53f5573e04b150455`;
- questions не входят в retrieval text;
- LLM 0, embeddings 0, DB fragment/question save false, publish false;
- `podgotovit_versiyu_znaniy` → ожидаемый `dublikat`, version остаётся `chernovik`;
- job → `povtor`.

Детерминизм B-кода дополнительно проверен двумя локальными запусками на идентичном входе: полный JSON совпал побайтово. Это не второй live-claim.

Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.

## Guard по нагрузке на LLM

- parsing/cleaning/chunking/token counting — без generative LLM;
- fragment records — индексные данные, не prompt целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM;
- candidate top-k = 12;
- final evidence максимум 8 fragments, обычно меньше;
- не добавлять LLM reranker в v1 без доказанной пользы;
- позже обязательно зафиксировать общий evidence token budget.

## Текущая задача — KB-03A

Цель: получить document embeddings для final fragments и сохранить fragments/vectors в нормативный DB-04.

Обязательные свойства:
- provider OpenAI;
- model `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- input каждого embedding = exact `tekst_fragmenta` из KB-02B;
- не включать второй splitter, summarizer или LLM rewrite;
- строго проверить HTTP/API result, число embeddings и соответствие порядку fragments;
- каждый vector: array длиной 1024, все значения finite numbers;
- payload `sohranit_fragmenty_znaniy`: `nomer_fragmenta`, `put_razdela`, `tekst_fragmenta`, `kolichestvo_tokenov`, `hash_fragmenta`, `vektor`;
- DB batch 1..100; 6 и 53 fragments укладываются в один batch;
- нормативная функция сама повторно проверяет SHA-256 текста, token max и dimension;
- при external/API/vector/save error publish запрещён, job должен безопасно вернуться в retry/error path под тем же fencing contract;
- после success проверить `sohraneno_fragmentov` и `vsego_fragmentov`;
- reference questions в KB-03A ещё не embedding-ить и не сохранять checks;
- production и рабочий трафик не менять.

## Следующая задача после KB-03A

`KB-03B` — сохранить/векторизовать reference questions тем же профилем, выполнить draft-only search и сохранить проверки. Только полный pass переводит version в `gotova`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
