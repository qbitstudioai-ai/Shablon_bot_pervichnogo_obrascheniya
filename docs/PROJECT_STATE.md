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

Фактически текущий runtime-проверенный import-ready workflow — **v0.9.1 KB-02A2**. Его SHA-256:

`5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`

Статика v0.9.1: 220 nodes, 178 connection keys, 248 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. Отдельный Git-checkpoint v0.9.1 ещё не сохранён; не утверждать обратное.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test по KB-01R4/R5 для bot/service контура: ingestion queue, lease/fencing, version/profile/fragments/reference checks, `vector(1024)`, draft-only service search, atomic publish и active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

Важно: `fragmenty_znaniy` требуют уже готовый vector(1024), поэтому KB-02A1/KB-02A2/KB-02B не записывают fragments в БД. Нормативный `sohranit_fragmenty_znaniy` вызывается только после embeddings в KB-03A.

## Ограничение нагрузки на LLM

Постоянный guard проекта:
- ingestion, parsing, cleaning, chunking и token counting не используют generative LLM;
- embeddings используются для индексации/поиска, но не являются генерацией ответа;
- вся база знаний и весь набор structural blocks/candidates никогда не отправляются в клиентский LLM;
- сначала vector search + фильтрация + дедупликация;
- текущий retrieval profile: candidate top-k 12, финальный evidence — не более 8 fragments и обычно меньше, если этого достаточно;
- отдельный LLM reranker в v1 не добавлять без доказанной пользы;
- общий evidence token budget должен быть зафиксирован до завершения retrieval-калибровки, чтобы рост базы не раздувал prompt.

Runtime KB-02A2 показал 53 final candidates из 130 structural blocks. Средний candidate 237.1 tokens, максимум 551; разные темы не объединяются ради искусственного достижения target 600.

## PRE-02E / tokenizer

Отдельного PRE-02E smoke нет. OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` и строгая проверка длины document vector закрываются внутри `KB-03A`.

Tokenizer runtime для chunking теперь доказан в KB-02A2: встроенный n8n `TokenTextSplitter` использует локальный `cl100k_base`; A2 подтверждает exact count и не использует приблизительный character count.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Последовательность текущего пути:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## KB-01A — CLOSED / runtime verified

05.10.2026 private `.md` прошёл service ingress → durable event → download → actual bytes check → `zaregistrirovat_zagruzku_znaniy`; DB вернула `uspeshno`, non-null upload/job, `status_zagruzki=poluchena`; Telegram report для filename с `_` подтверждён после HTML escaping fix.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — CLOSED / runtime verified

06.10.2026 реальный job claim-нут через normative lease/fencing API. Parser `kb01b1_safe_frontmatter_markdown_v1` подтвердил metadata/структуру и deterministic `hash_soderzhaniya`; job безопасно возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-01B2 — CLOSED / runtime verified

06.10.2026 processing/index profile зафиксирован, `podgotovit_versiyu_znaniy` создала version 1 `chernovik`, publish не выполнялся, job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A1 — CLOSED / runtime verified

06.10.2026 реальный dry-run v0.8 на test-контуре подтвердил 57 headings, 130 ordered blocks, 90 paragraph + 40 list, warnings 0, YAML/reference questions исключены из retrieval text, стабильный `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`; DB fragments не сохранялись; draft остался `chernovik`; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A2 — CLOSED / runtime verified

06.10.2026 v0.9.1 на большой safe Markdown-базе подтвердил:
- exact `cl100k_base` runtime count;
- canary `hello world` → 2 tokens, tokenizer object доступен;
- 130 structural blocks → 53 topic groups → 53 final candidates;
- token min/max/average = 87 / 551 / 237.1;
- candidates <=80 = 0;
- candidates >800 = 0;
- source blocks requiring split = 0, поэтому overlap фактически 0;
- `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`;
- LLM = 0, embeddings = 0, DB fragment save = false;
- существующая version 1 осталась `chernovik`;
- job fence 4 возвращён в `povtor`.

Отсутствие overlap является корректным результатом этого документа: overlap применяется только когда длинный смысловой блок реально режется. Target 600 не является минимумом.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

## Следующая маленькая задача — KB-02B

Подготовить окончательные fragment records и отдельные reference questions без embeddings и без записи fragments в DB.

Критерий:
- каждый fragment имеет стабильные `nomer_fragmenta`, `put_razdela`, точный `tekst_fragmenta`, exact `kolichestvo_tokenov`, `hash_fragmenta` и trace к source blocks;
- reference questions остаются отдельным массивом и не входят в retrieval embeddings;
- 3–10 questions сохранены для будущей автоматической проверки;
- повторный прогон даёт тот же порядок/hashes;
- generative LLM не вызывается;
- embeddings/DB fragment save/publish не выполняются;
- job после dry-run возвращается в `povtor`.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
