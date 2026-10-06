# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Последний сохранённый в Git runtime-verified checkpoint пока KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — v0.8 KB-02A1, SHA-256 `cc173a8421fe0b75a9687ceb821d7f0fdd7f9ddedf3cf4f1944b782f89ef4b60`. Отдельный Git-checkpoint v0.8 ещё не сохранён.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует knowledge upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A runtime | Manual worker claim + lease/fencing + safe YAML/Markdown parser + metadata/heading validation + deterministic `hash_soderzhaniya`; job после проверки возвращается в `povtor`. Runtime подтверждён. |
| [x] KB-01B2 | KB-01B1 runtime | Зафиксирован processing/index profile и deterministic fingerprints, `podgotovit_versiyu_znaniy` под live lease/fencing создала version 1 `chernovik`; job безопасно возвращён в `povtor`. `cl100k_base` — contract; точный runtime count переносится в KB-02A2 до финальных candidate fragments. |
| [x] KB-02A1 | KB-01B2 | Детерминированная очистка и структурный разбор создают упорядоченные смысловые блоки с heading path; YAML/reference questions исключены из retrieval text; DB fragments не записываются. Runtime подтверждён: 130 blocks, 57 headings, 90 paragraph + 40 list, warnings 0, стабильный `hash_struktury=fdb26ff...`, job возвращён в `povtor`. |
| [~] KB-02A2 | KB-02A1 runtime | Для structural blocks доказать точный runtime `cl100k_base` count и выполнить детерминированную упаковку в final candidate fragments: target 600, hard max 800, overlap до 100 только внутри одной темы/длинного блока; ни одного fragment >800. DB fragments ещё не записываются. |
| [ ] KB-02B | KB-02A2 | 3–10 reference questions извлечены отдельно; окончательные fragments имеют metadata/hash/token count; ошибки безопасно завершают или повторяют только текущий fenced job. |
| [ ] KB-03A | KB-02B | Document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`; каждый vector length строго проверяется; fragments/vectors сохраняются через normative DB API. |
| [ ] KB-03B | KB-03A | Reference questions векторизуются тем же профилем; draft search работает только по своей версии; checks сохраняются; `gotova` только после полного pass. |
| [ ] KB-03C | KB-03B | Atomic publish переключает active version и архивирует прежнюю; stale publish конфликтует; после первой публикации end-to-end regression проверяет active duplicate stop. |

## Архитектурный guard по нагрузке на LLM

Это постоянное правило knowledge/RAG пути:
- ingestion, parsing, cleaning, structural chunking и token counting выполняются детерминированно без generative LLM;
- embeddings при индексации и для поискового запроса не являются генерацией ответа;
- клиентскому LLM никогда не передаётся вся база знаний, все structural blocks или все найденные candidates;
- сначала выполняются vector search, фильтрация и дедупликация;
- текущий retrieval profile: candidate top-k = 12, в финальный evidence-пакет — не более 8 fragments и только столько, сколько действительно нужно;
- не добавлять отдельный LLM reranker в v1 без доказанной пользы на контрольном наборе;
- кроме лимита количества fragments позднее зафиксировать общий evidence token budget, чтобы рост базы не увеличивал prompt линейно.

130 blocks из KB-02A1 — промежуточная структура индексации. Они не являются 130 фрагментами prompt для клиентского ответа.

## KB-01A — завершено

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — завершено / runtime verified

Runtime 06.10.2026 подтвердил claim реального job, safe parser, 57 headings, 8 reference questions, deterministic content hash и освобождение job обратно в `povtor` тем же worker/fence.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-01B2 — завершено / runtime verified

Архитектурное решение:
- не делать механический token splitter основным chunker;
- не требовать отдельный npm `tiktoken` в Code node;
- фиксировать `cl100k_base` как tokenizer/encoding contract выбранной embedding-модели;
- структурно-смысловые границы реализовывать отдельно от token budget.

Runtime 06.10.2026:
- реальный job claim-нут, parser valid;
- profile: `text-embedding-3-large`, 1024, cosine, parser `kb01b1_safe_frontmatter_markdown_v1`, clean `kb02a_clean_v1`, chunking `kb02a_structural_chunk_600_800_100_v1`, tokenizer `cl100k_base`, target/max/overlap `600/800/100`;
- `otpechatok_profilya=917b776877263b60b809fa0376cce8ae62937d2d44cdb0badc2e07bea2ceec3c`;
- `podgotovit_versiyu_znaniy` → `uspeshno`, version 1, `status_versii=chernovik`;
- publish не выполнялся;
- job освобождён обратно в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A1 — завершено / runtime verified

Цель A1 — отделить структурно-смысловой разбор от tokenizer packing.

Runtime 06.10.2026 на большой safe Markdown-базе:
- live worker/fence: fence `3`;
- 57 structural headings;
- 130 ordered blocks;
- типы: 90 `paragraph`, 40 `list`;
- warnings 0;
- YAML исключён;
- reference questions не входят в retrieval text;
- token counting не выполнялся;
- fragments в DB не сохранялись;
- `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85` совпал с локальным прогоном v0.8;
- draft остался `chernovik`;
- job возвращён в `povtor` тем же worker/fence.

Ручная A1-ветка не вызывает generative LLM/OpenAI nodes: только Manual Trigger, Code/IF и service Postgres.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A2 — текущая задача

Цель: применить к structural blocks точный token budget выбранного профиля и получить final candidate fragments без embeddings и без записи fragments в БД.

Порядок:
1. доказать воспроизводимый runtime count `cl100k_base` для окончательного текста;
2. небольшие блоки объединять только внутри одной темы;
3. длинный блок делить сначала по абзацам, затем предложениям;
4. FAQ question+answer не разрывать, пока помещается;
5. таблицы делить по группам строк с повтором header/context;
6. overlap до 100 tokens только между соседними частями одного смыслового блока, не через другую тему;
7. target 600, hard max 800 tokens;
8. финальный текст каждого candidate fragment включает нужный title/heading path/context и имеет точный token count;
9. ни одного candidate fragment >800 tokens;
10. количество final fragments должно быть объяснимым и не использоваться как prompt целиком;
11. embeddings и DB fragment save пока не выполнять.

После KB-02A2 переходить к KB-02B.

Production не менять.
