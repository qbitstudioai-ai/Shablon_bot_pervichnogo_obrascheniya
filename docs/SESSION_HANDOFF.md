# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2 и KB-02A1 завершены и runtime-проверены. Текущая маленькая задача — **KB-02A2**.

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

Фактически текущий runtime-проверенный import-ready workflow — **v0.8 KB-02A1**:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.8 KB-02A1.json`

SHA-256:

`cc173a8421fe0b75a9687ceb821d7f0fdd7f9ddedf3cf4f1944b782f89ef4b60`

Для повторного runtime KB-02A2 подготовлен локальный **v0.9.1 KB-02A2**:

`workflow_v0.9.1_KB-02A2.json`

SHA-256:

`5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`

Статика v0.9.1: 220 nodes, 178 connection keys, 248 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Изменённый A2 JavaScript проходит `node --check`. v0.9.1 ещё не runtime-verified и не Git-checkpoint.

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
Runtime v0.8 на большой safe Markdown-базе:
- fence `3`;
- 57 headings;
- 130 ordered structural blocks;
- 90 paragraph + 40 list;
- warnings 0;
- YAML excluded;
- reference questions excluded from retrieval text;
- structure hash `fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`, совпадает с локальным прогоном;
- token count не выполнялся;
- DB fragments не сохранялись;
- draft остался `chernovik`;
- job возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

## Guard по нагрузке на LLM

Павел отдельно подтвердил: рост базы знаний не должен линейно увеличивать нагрузку на клиентскую LLM.

Обязательные правила:
- parsing/cleaning/chunking/token counting — без generative LLM;
- 130 structural blocks A1 — промежуточные данные индексации, не prompt;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM;
- candidate top-k = 12, финальный evidence максимум 8 fragments, обычно меньше;
- не добавлять LLM reranker в v1 без доказанной необходимости;
- до retrieval-калибровки зафиксировать общий evidence token budget, а не только max fragment count.

## Текущая задача — KB-02A2

Цель: доказать точный runtime `cl100k_base` count и упаковать A1 structural blocks в final candidate fragments.

### Что уже произошло

Runtime v0.9 на коротком safe Markdown:
- A1 снова успешно сформировал 10 blocks / 6 headings и контрольный `hash_struktury=439716cc8d1c7d2590829c707506193b7e0e06a44fa02a770a7fe84935658577`;
- A2 прошёл первоначальный tokenizer gate и дошёл до candidate packing;
- затем LangChain Code node упала на вспомогательном SHA-256: `TextEncoder is not defined`;
- ошибка классифицирована как `kb02a2_upakovka_oshibka`, не tokenizer error;
- service error path успешно вернул job в `povtor` тем же fence `3`;
- LLM 0, embeddings 0, DB fragments 0.

Причина локализована: `TextEncoder` доступен в обычных Code nodes, но не в используемом LangChain Code sandbox. Сам встроенный `cl100k_base` tokenizer не требует серверной перенастройки для этого исправления.

В v0.9.1 только в A2 LangChain Code node `TextEncoder` заменён собственным deterministic UTF-8 encoder. SHA-256 проверен локально на ASCII, кириллице и emoji против стандартного результата. Внешние модули не добавлены.

### Следующая проверка

Импортировать v0.9.1 как отдельный inactive workflow, назначить те же service Postgres Credentials и запустить `KB-02A2 Ручной запуск worker`.

Для доказательства прислать:
1. `KB-02A2 Сжать dry-run результат`, если путь успешен;
2. `Служебный_KB_Подготовить версию`;
3. `Служебный_KB_Вернуть после B2`.

Если снова сработает error path — прислать `Служебный_KB_Вернуть после ошибки A2`; job должен снова безопасно вернуться в `povtor`.

Критерий A2:
- exact token count рядом с каждым candidate;
- target 600, hard max 800, overlap до 100 только внутри темы/длинного блока;
- ни одного candidate >800;
- candidate count и размеры объяснимы;
- никаких generative LLM вызовов;
- embeddings и DB fragment save не выполнять;
- job после dry-run вернуть в `povtor`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
