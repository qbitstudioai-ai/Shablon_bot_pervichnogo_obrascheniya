# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1 и KB-01B2 завершены и runtime-проверены. Текущая маленькая задача — **KB-02A1**.

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

Ожидаемый SHA-256 этого Git-checkpoint:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — v0.7.1 KB-01B2 с SHA-256:

`e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`

Отдельный Git-checkpoint v0.7.1 ещё не сохранён. Не утверждать обратное.

Для KB-02A1 подготовлен локальный import-ready **v0.8 KB-02A1**, ещё не runtime-проверенный:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.8 KB-02A1.json`

SHA-256:

`cc173a8421fe0b75a9687ceb821d7f0fdd7f9ddedf3cf4f1944b782f89ef4b60`

Статика: 215 nodes, 174 connection keys, 243 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Изменённые Code nodes прошли `node --check`.

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

## KB-02A разбит на две маленькие задачи

Причина: структурно-смысловой алгоритм и точный runtime tokenizer count — разные источники ошибок, их нельзя безопасно отлаживать одновременно.

- **KB-02A1** — structural semantic blocks, без token packing;
- **KB-02A2** — точный `cl100k_base` count и final candidate packing 600/800/100.

## KB-02A1 — IN PROGRESS

В v0.8 добавлено:
- B1 parser сохраняет нормализованный Markdown body только для внутренней A1-ветки; YAML туда не входит;
- `KB-02A1 Сформировать смысловые блоки` детерминированно строит ordered blocks;
- heading hierarchy превращается в полный `put_razdela`;
- типы: `paragraph`, `list`, `table`, `code`;
- heading с `?` маркирует FAQ-раздел; question+answer остаются в одном heading path;
- Markdown table остаётся цельным блоком A1, строки не режутся;
- fenced code остаётся цельным блоком, `#` и `|` внутри него не считаются heading/table;
- HTML comments и script/style удаляются только вне fenced code и отражаются в cleaning report;
- A1 выдаёт `hash_struktury`, counts/types/paths и полный список блоков;
- A1 удаляет временный raw body перед дальнейшими DB-нодами;
- при structural error job возвращается в `povtor` через отдельную service Postgres-ноду;
- ни `sohranit_fragmenty_znaniy`, ни OpenAI embeddings A1 не вызывает.

Локальные проверки:
- safe short Markdown: 6 headings → 10 ordered blocks, 6 paths, structure hash `439716cc8d1c7d2590829c707506193b7e0e06a44fa02a770a7fe84935658577`;
- fixture FAQ/table/code прошёл: FAQ paths корректны, table единый, code не распознаётся как heading/table;
- cleaning fixture: HTML comment/script удалены вне code и сохранены внутри code;
- большая safe Markdown-база формирует 130 ordered blocks без structural error.

### Что нужно от runtime

Импортировать v0.8 как отдельный inactive workflow, назначить service Postgres Credentials только worker-ветке и запустить `KB-02A1 Ручной запуск worker` вручную.

Для доказательства прислать:
1. Output `KB-02A1 Сформировать смысловые блоки`;
2. Output `Служебный_KB_Подготовить версию`;
3. Output `Служебный_KB_Вернуть после B2` либо structural error return, если сработал error path.

Ожидаемо для уже подготовленной той же загрузки `podgotovit_versiyu_znaniy` может вернуть `dublikat` со статусом существующего `chernovik`; это нормальная идемпотентность. Job после dry-run должен вернуться в `povtor`.

## Следующая задача после runtime A1

`KB-02A2` — доказать точный runtime `cl100k_base` count и выполнить final candidate packing: target 600, hard max 800, overlap до 100 только внутри одного смыслового блока/темы. До A2 не сохранять fragments и не выполнять embeddings.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
