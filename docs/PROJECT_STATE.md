# Текущее состояние проекта

Обновлено: 2026-10-06.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Фактическая основа workflow — export Павла `(7)`. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний **сохранённый в Git** runtime-verified checkpoint пока остаётся:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

SHA-256 восстановленного JSON:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — **v0.8 KB-02A1**. Его SHA-256:

`cc173a8421fe0b75a9687ceb821d7f0fdd7f9ddedf3cf4f1944b782f89ef4b60`

Статически для v0.8: 215 nodes, 174 connection keys, 243 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Отдельный Git-checkpoint v0.8 ещё не сохранён; не утверждать обратное.

Для активного KB-02A2 подготовлен исправленный **v0.9.1 KB-02A2**, ещё не runtime-проверенный:
- SHA-256 `5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`;
- 220 nodes;
- 178 connection keys;
- 248 edges;
- `active=false`;
- Credential refs 0;
- duplicate names 0;
- dangling connections 0.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test по KB-01R4/R5 для bot/service контура: ingestion queue, lease/fencing, version/profile/fragments/reference checks, `vector(1024)`, draft-only service search, atomic publish и active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

Важно: `fragmenty_znaniy` требуют уже готовый vector(1024), поэтому KB-02A1/KB-02A2 не записывают fragments в БД. Нормативный `sohranit_fragmenty_znaniy` вызывается только после embeddings в KB-03A.

## Ограничение нагрузки на LLM

Постоянный guard проекта:
- ingestion, parsing, cleaning, chunking и token counting не используют generative LLM;
- embeddings используются для индексации/поиска, но не являются генерацией ответа;
- вся база знаний и весь набор structural blocks никогда не отправляются в клиентский LLM;
- сначала vector search + фильтрация + дедупликация;
- текущий retrieval profile: candidate top-k 12, финальный evidence — не более 8 fragments и обычно меньше, если этого достаточно;
- отдельный LLM reranker в v1 не добавлять без доказанной пользы;
- общий evidence token budget должен быть зафиксирован до завершения retrieval-калибровки, чтобы рост базы не раздувал prompt.

130 blocks из KB-02A1 — только промежуточная структура индексации, не prompt для ответа клиенту.

## PRE-02E

Отдельного PRE-02E smoke нет. OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` и строгая проверка длины document vector закрываются внутри `KB-03A`.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Последовательность текущего пути:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## KB-01A — CLOSED / runtime verified

05.10.2026 private `.md` прошёл service ingress → durable event → download → actual bytes check → `zaregistrirovat_zagruzku_znaniy`; DB вернула `uspeshno`, non-null upload/job, `status_zagruzki=poluchena`; Telegram report для filename с `_` подтверждён после HTML escaping fix.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — CLOSED / runtime verified

06.10.2026 реальный job claim-нут через normative lease/fencing API. Parser `kb01b1_safe_frontmatter_markdown_v1` подтвердил metadata/структуру и deterministic content hash; job безопасно возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-01B2 — CLOSED / runtime verified

06.10.2026 processing/index profile зафиксирован, `podgotovit_versiyu_znaniy` создала version 1 `chernovik`, publish не выполнялся, job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A1 — CLOSED / runtime verified

06.10.2026 реальный dry-run v0.8 на test-контуре подтвердил:
- live fence `3`;
- 57 structural headings;
- 130 ordered blocks;
- 90 paragraph + 40 list;
- warnings 0;
- YAML исключён;
- reference questions не входят в retrieval text;
- `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`, совпадает с локальным прогоном;
- token count не выполнялся;
- DB fragments не сохранялись;
- draft остался `chernovik`;
- job тем же worker/fence освобождён обратно в `povtor`.

Ручная A1-ветка не вызывает generative LLM/OpenAI nodes; это детерминированный Code/IF/Postgres путь.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A2 — IN PROGRESS

Runtime-попытка v0.9 06.10.2026 на коротком safe Markdown дошла до A2 packing, но завершилась контролируемой ошибкой `TextEncoder is not defined` в LangChain Code node. Код ошибки — `kb02a2_upakovka_oshibka`, а не tokenizer-gate error; это подтверждает, что начальная проверка встроенного `cl100k_base` tokenizer уже была пройдена. Job тем же worker/fence успешно возвращён в `povtor`; `llm_vyzovov=0`, `embeddings_vyzovov=0`, `db_fragmenty_sohraneny=false`.

Причина: в обычных n8n Code nodes `TextEncoder` доступен, а в LangChain Code sandbox текущего пути — нет. Ошибка была только во вспомогательном SHA-256 UTF-8 преобразовании после tokenization, а не в самом tokenizer.

Подготовлен v0.9.1: A2 больше не использует `TextEncoder`; добавлен собственный deterministic UTF-8 encoder без внешних модулей. Его SHA-256 проверен локально на ASCII, кириллице и emoji против стандартного SHA-256. Изменённый A2 JavaScript проходит `node --check`.

Критерий закрытия A2 остаётся прежним:
- exact `cl100k_base` count на окончательном тексте каждого candidate fragment;
- target 600 / hard max 800 / overlap до 100 только внутри одной темы;
- FAQ/table rules сохранены;
- ни одного fragment >800;
- final candidate count и распределение размеров объяснимы;
- никаких generative LLM вызовов;
- embeddings и DB fragment save ещё не выполнять;
- job после dry-run безопасно вернуть в `povtor`.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
