# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2, KB-02A1 и KB-02A2 завершены и runtime-проверены. Текущая маленькая задача — **KB-02B**.

Перед продолжением проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/specs/KNOWLEDGE_INGESTION.md`;
6. `docs/specs/MARKDOWN_FORMAT.md`;
7. нужные части `docs/specs/DB_CONTRACT.md` и `docs/specs/PROCESSING_PROFILE.md`.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git runtime-verified checkpoint пока:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

Ожидаемый SHA-256 этого старого Git-checkpoint:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — **v0.9.1 KB-02A2**:

`workflow_v0.9.1_KB-02A2.json`

SHA-256:

`5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`

Статика: 220 nodes, 178 connection keys, 248 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Отдельный Git-checkpoint v0.9.1 ещё не сохранён; не утверждать обратное.

## Доказанный runtime

### KB-01A
Private `.md` прошёл durable service ingress, download, actual bytes validation и DB registration.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Knowledge job успешно claim-нут через lease/fencing; safe YAML/Markdown parser подтвердил metadata/структуру и deterministic `hash_soderzhaniya`; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
Processing/index profile зафиксирован; `podgotovit_versiyu_znaniy` создала version 1 `chernovik`; publish не выполнялся; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A1
Runtime v0.8 на большой safe Markdown-базе: 57 headings, 130 ordered structural blocks, 90 paragraph + 40 list, warnings 0, YAML/reference questions excluded, stable structure hash, DB fragments 0, job `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
Runtime v0.9.1 на той же большой safe Markdown-базе:
- fence `4`;
- exact tokenizer: `cl100k_base`;
- source: `n8n_builtin_TokenTextSplitter_local_encoding`;
- canary `hello world` → 2 tokens;
- `exact_token_count=true`, `tokenizer_object=true`;
- 130 structural blocks → 53 topic groups → 53 final candidate fragments;
- token range 87..551, average 237.1;
- candidates <=80: 0;
- candidates >800: 0;
- split source blocks: 0, поэтому overlap фактически не потребовался;
- `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`;
- LLM 0, embeddings 0, DB fragment save false;
- `podgotovit_versiyu_znaniy` → ожидаемый идемпотентный `dublikat`, существующая version 1 остаётся `chernovik`;
- job возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

## Guard по нагрузке на LLM

Рост базы знаний не должен линейно увеличивать prompt клиентской LLM.

Обязательные правила:
- parsing/cleaning/chunking/token counting — без generative LLM;
- structural blocks и final candidates — индексные данные, не prompt целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM;
- candidate top-k = 12, финальный evidence максимум 8 fragments и обычно меньше;
- не добавлять LLM reranker в v1 без доказанной необходимости;
- до retrieval-калибровки зафиксировать общий evidence token budget.

Важно из A2: target 600 не является минимумом. Нельзя объединять разные темы только ради target; на реальной базе средний final candidate = 237.1 tokens, max = 551.

## Текущая задача — KB-02B

Цель: превратить A2 candidates в окончательные records, готовые к будущему embedding/save, и отдельно подготовить reference questions.

Обязательные свойства:
- стабильный `nomer_fragmenta` по исходному порядку;
- `put_razdela`;
- точный `tekst_fragmenta` формата `qbit_kb_fragment_text_v1`;
- exact `kolichestvo_tokenov`;
- `hash_fragmenta` по точному тексту;
- trace к source blocks сохраняется как runtime metadata до DB save;
- reference questions берутся только из проверенного YAML metadata и остаются отдельным набором;
- reference questions не входят в fragment text/embedding;
- при 3–10 questions набор готов для будущей автоматической проверки, но KB-02B ничего не публикует;
- повторный dry-run должен дать тот же порядок, hashes и questions;
- generative LLM не использовать;
- embeddings и `sohranit_fragmenty_znaniy` не вызывать до KB-03A;
- job после dry-run вернуть в `povtor` тем же worker/fence.

## Следующая задача после KB-02B

`KB-03A` — получить document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, строго проверить длину каждого vector и только затем вызвать нормативный `sohranit_fragmenty_znaniy`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
