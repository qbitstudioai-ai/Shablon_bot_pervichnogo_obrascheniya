# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Последний сохранённый в Git runtime-verified checkpoint пока KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — v0.7.1 KB-01B2, SHA-256 `e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`. Отдельный Git-checkpoint v0.7.1 ещё не сохранён.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует knowledge upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A runtime | Manual worker claim + lease/fencing + safe YAML/Markdown parser + metadata/heading validation + deterministic `hash_soderzhaniya`; job после проверки возвращается в `povtor`. Runtime подтверждён. |
| [x] KB-01B2 | KB-01B1 runtime | Зафиксирован processing/index profile и deterministic fingerprints, `podgotovit_versiyu_znaniy` под live lease/fencing создала version 1 `chernovik`; job безопасно возвращён в `povtor`. `cl100k_base` — contract; точный runtime count переносится в KB-02A2 до финальных candidate fragments. |
| [~] KB-02A1 | KB-01B2 | Детерминированная очистка и структурный разбор создают упорядоченные смысловые блоки с heading path; YAML/reference questions исключены из retrieval text; FAQ, таблицы, списки, code и обычные абзацы сохраняются без переписывания фактов. DB fragments не записываются. |
| [ ] KB-02A2 | KB-02A1 runtime | Для структурных блоков доказан точный runtime `cl100k_base` count и выполнена детерминированная упаковка в final candidate fragments: target 600, hard max 800, overlap до 100 только внутри одной темы/длинного блока; ни одного fragment >800. DB fragments ещё не записываются. |
| [ ] KB-02B | KB-02A2 | 3–10 reference questions извлечены отдельно; окончательные fragments имеют metadata/hash/token count; ошибки безопасно завершают или повторяют только текущий fenced job. |
| [ ] KB-03A | KB-02B | Document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`; каждый vector length строго проверяется; fragments/vectors сохраняются через normative DB API. |
| [ ] KB-03B | KB-03A | Reference questions векторизуются тем же профилем; draft search работает только по своей версии; checks сохраняются; `gotova` только после полного pass. |
| [ ] KB-03C | KB-03B | Atomic publish переключает active version и архивирует прежнюю; stale publish конфликтует; после первой публикации end-to-end regression проверяет active duplicate stop. |

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
- для проверенного документа `otpechatok_obrabotki=b56cd0f39885a576c0c7d04cdb78deceadb01e944713e9aa21b0483910b8abdb`;
- `podgotovit_versiyu_znaniy` → `uspeshno`, non-null document/version/profile IDs, version 1, `status_versii=chernovik`;
- publish не выполнялся;
- job освобождён обратно в `povtor`.

Active duplicate end-to-end до первой публикации проверить невозможно без искусственной публикации. DB guard уже доказан на DB-04/DB-05 уровне; workflow regression выполняется в KB-03C после первой безопасной публикации.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A — декомпозиция текущего этапа

Изначальная KB-02A включает две независимые проверки: качество структурно-смыслового разбиения и точный runtime tokenizer count. Чтобы не смешивать ошибки структуры с техническим способом токенизации, этап разделён на KB-02A1 и KB-02A2. Конечный профиль и правило `600/800/100` не меняются.

### KB-02A1 — текущая задача

Цель: детерминированно превратить уже проверенный Markdown body в упорядоченные **структурно-смысловые блоки**, не переписывая исходные факты моделью.

Обязательные свойства:
1. YAML/front matter и `kontrolnye_voprosy` не входят в retrieval text;
2. сохраняется heading path H1→H6 и исходная последовательность;
3. обычные абзацы, списки, fenced code и Markdown tables распознаются как явные типы блоков;
4. FAQ вопрос+ответ остаются в одном смысловом разделе до будущей token-упаковки;
5. таблица сохраняет header/separator/rows и не режется посередине строки;
6. очистка допускает только документированные операции: BOM/line endings уже нормализованы parser'ом, HTML comments и script/style вне fenced code могут быть удалены с отчётом;
7. содержание не суммаризируется и не исправляется LLM;
8. DB fragments, embeddings, reference search и publish не выполняются;
9. job после dry-run безопасно возвращается в `povtor` тем же worker/fence.

Критерий закрытия KB-02A1: один существующий B2 draft в реальном n8n выдаёт стабильный ordered набор блоков с корректными heading paths; reference questions отсутствуют в retrieval text; dry-run повторяем; job возвращён в `povtor`.

### KB-02A2 — после runtime KB-02A1

Цель: применить к блокам точный token budget выбранного профиля.

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
10. embeddings и DB fragment save пока не выполнять.

После KB-02A2 переходить к KB-02B.

Production не менять.
