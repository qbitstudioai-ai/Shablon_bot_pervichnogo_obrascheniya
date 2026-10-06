# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Текущий runtime-verified checkpoint:
`workflows/checkpoints/2026-10-06_v0.7.1_KB-01B2_runtime_verified/`.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует knowledge upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A runtime | Manual worker claim + lease/fencing + safe YAML/Markdown parser + metadata/heading validation + deterministic `hash_soderzhaniya`; job после проверки возвращается в `povtor`. Runtime подтверждён. |
| [x] KB-01B2 | KB-01B1 runtime | Зафиксирован processing/index profile и deterministic fingerprints, `podgotovit_versiyu_znaniy` под live lease/fencing создала version 1 `chernovik`; job безопасно возвращён в `povtor`. `cl100k_base` — contract; точный runtime count переносится в KB-02A до fragment save. |
| [~] KB-02A | KB-01B2 | Детерминированная очистка и **структурно-смысловой chunking** сохраняют heading path, FAQ, tables и facts. Смысловые границы первичны; token budget 600/800/100 вторичен. Точный runtime count `cl100k_base` доказан до сохранения fragments. Reference questions исключены из retrieval text. |
| [ ] KB-02B | KB-02A | 3–10 reference questions извлечены отдельно; окончательные fragments имеют metadata/hash/token count; ошибки безопасно завершают или повторяют только текущий fenced job. |
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
- реальный структурно-смысловой chunker и точный runtime count реализовать в KB-02A до fragment save.

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

Checkpoint:
`workflows/checkpoints/2026-10-06_v0.7.1_KB-01B2_runtime_verified/`, restore SHA-256 `e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`.

## KB-02A — текущая задача

Цель: реализовать собственный детерминированный **структурно-смысловой chunker с token budget**.

Порядок:
1. использовать уже проверенный Markdown AST/структуру, не переписывать исходные факты моделью;
2. отделить YAML и reference questions от retrieval text;
3. сохранить heading path H1→H6 и исходную последовательность;
4. сформировать смысловые блоки по разделам, абзацам, спискам, FAQ и таблицам;
5. небольшие блоки можно объединять только внутри одной темы;
6. слишком длинный блок делить сначала по абзацам, затем по предложениям;
7. FAQ question+answer не разрывать, пока помещается;
8. таблицы делить по группам строк, повторяя header/units/context;
9. overlap до 100 tokens использовать только между соседними частями одного смыслового блока, не через границу другой темы;
10. target 600, hard max 800 tokens;
11. доказать точный runtime count `cl100k_base` для финального текста каждого candidate fragment до сохранения;
12. KB-02A пока не вызывает embeddings и не публикует.

### Критерий закрытия KB-02A

Один уже созданный B2 draft должен в реальном n8n дать детерминированный набор candidate fragments с:
- стабильным порядком;
- корректным heading path;
- сохранёнными FAQ/tables/facts;
- отсутствием reference questions в retrieval text;
- точным token count каждого финального текста;
- ни одного fragment >800 tokens;
- объяснимым overlap только внутри одной темы.

До этого fragments в DB не считать runtime-ready.

Production не менять.
