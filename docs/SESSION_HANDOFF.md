# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1 и KB-01B2 завершены и runtime-проверены. Перед следующей задачей проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. для KB-02A — `docs/specs/KNOWLEDGE_INGESTION.md`, `docs/specs/MARKDOWN_FORMAT.md`, нужные части `docs/specs/DB_CONTRACT.md` и processing profile.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git runtime-verified checkpoint пока:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

Ожидаемый SHA-256 этого Git-checkpoint:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — v0.7.1 KB-01B2 с SHA-256:

`e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`

Он является прямым продолжением v0.5/v0.7, но отдельный Git-checkpoint v0.7.1 ещё не сохранён. Не пересобирать workflow с нуля и не утверждать, что v0.7.1 уже восстановим из Git.

## Доказанный runtime

### KB-01A
Private `.md` прошёл durable service ingress, download, actual bytes validation и DB registration. Telegram report подтверждён после HTML escaping fix.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Knowledge job успешно claim-нут через lease/fencing; safe YAML/Markdown parser подтвердил metadata/структуру и deterministic `hash_soderzhaniya`; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
На test-контуре:
- job claim-нут worker `qbit_test_kb_worker_v1`, fence `2`;
- parser valid, 6 headings, 3 reference questions;
- profile fingerprint `917b776877263b60b809fa0376cce8ae62937d2d44cdb0badc2e07bea2ceec3c`;
- processing fingerprint `b56cd0f39885a576c0c7d04cdb78deceadb01e944713e9aa21b0483910b8abdb`;
- profile: `text-embedding-3-large`, dimension 1024, cosine, `cl100k_base`, structural chunking 600/800/100;
- `podgotovit_versiyu_znaniy` → `uspeshno`, version 1, `status_versii=chernovik`;
- publish не выполнялся;
- job освобождён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

`cl100k_base` пока является зафиксированным tokenizer/encoding contract. Точный token count на финальном тексте fragments должен быть runtime-проверен в KB-02A до любого сохранения fragments. Отдельный npm `tiktoken` не является обязательным архитектурным требованием.

## DB-04 / DB-05

Нормативные DB-04/DB-05 уже существуют в test и runtime-проверены для bot/service. `KB-01R5D` dash_admin revoke отложен до dashboard stage.

## Следующая задача — KB-02A

Цель: реализовать детерминированный структурно-смысловой chunker, а не механический token splitter.

Обязательные свойства:
- Markdown hierarchy H1→H6 сохраняется как heading path;
- смысловые границы первичны, token budget вторичен;
- FAQ вопрос+ответ остаются вместе, пока помещаются;
- таблицы делятся по строкам с повтором заголовка/единиц;
- длинный смысловой блок делится по абзацам, затем предложениям;
- overlap не переносится через другую тему;
- target/max/overlap = 600/800/100 tokens;
- точный runtime token count `cl100k_base` доказан до сохранения fragments;
- reference questions исключены из retrieval text;
- embeddings ещё не выполнять.

Не начинать KB-02B или KB-03A до runtime KB-02A.

## PRE-02E

Отдельный smoke не запускать. OpenAI document embedding `text-embedding-3-large`, `dimensions=1024` будет добавлен и runtime-проверен в KB-03A.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
