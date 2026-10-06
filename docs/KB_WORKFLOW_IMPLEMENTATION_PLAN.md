# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Последний сохранённый в Git runtime-verified checkpoint пока KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.9.1 KB-02A2**, SHA-256 `5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`. Отдельный Git-checkpoint v0.9.1 ещё не сохранён.

Для текущего KB-02B подготовлен локальный, ещё не runtime-проверенный **v0.10 KB-02B**, SHA-256 `f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`. Статика: 223 nodes, 180 connection keys, 251 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует knowledge upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A runtime | Manual worker claim + lease/fencing + safe YAML/Markdown parser + metadata/heading validation + deterministic `hash_soderzhaniya`; job после проверки возвращается в `povtor`. Runtime подтверждён. |
| [x] KB-01B2 | KB-01B1 runtime | Зафиксирован processing/index profile и deterministic fingerprints, `podgotovit_versiyu_znaniy` под live lease/fencing создала version 1 `chernovik`; job безопасно возвращён в `povtor`. |
| [x] KB-02A1 | KB-01B2 | Детерминированная очистка и структурный разбор создают упорядоченные смысловые блоки с heading path; YAML/reference questions исключены из retrieval text; DB fragments не записываются. Runtime: 130 blocks, 57 headings, warnings 0. |
| [x] KB-02A2 | KB-02A1 runtime | Runtime доказал exact `cl100k_base` и final candidate packing: 130 blocks → 53 candidates, 87..551 tokens, average 237.1, >800 = 0, LLM/embeddings/DB save = 0; job возвращён в `povtor`. |
| [~] KB-02B | KB-02A2 runtime | Подготовить окончательные fragment records с metadata/hash/exact token count и отдельные 3–10 reference questions; не смешивать reference questions с retrieval text; ошибки безопасно относятся только к текущему fenced job. Embeddings/DB fragment save ещё не выполнять. |
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

Runtime KB-02A2 дополнительно подтвердил, что target 600 — не минимальный размер. Нельзя объединять разные темы только ради приближения к 600. На реальной базе средний candidate = 237.1 tokens, при этом коротких <=80 нет и hard max 800 не нарушен.

## KB-01A — завершено

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — завершено / runtime verified

Runtime 06.10.2026 подтвердил claim реального job, safe parser, 57 headings, 8 reference questions, deterministic content hash и освобождение job обратно в `povtor` тем же worker/fence.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-01B2 — завершено / runtime verified

Архитектурное решение:
- не делать механический token splitter основным chunker;
- не требовать отдельный npm `tiktoken` в обычном Code node;
- фиксировать `cl100k_base` как tokenizer/encoding contract выбранной embedding-модели;
- структурно-смысловые границы реализовывать отдельно от token budget.

Runtime 06.10.2026: profile `text-embedding-3-large`, 1024, cosine, structural chunking 600/800/100 зафиксирован; `podgotovit_versiyu_znaniy` создала version 1 `chernovik`; publish не выполнялся; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A1 — завершено / runtime verified

Runtime 06.10.2026 на большой safe Markdown-базе:
- 57 structural headings;
- 130 ordered blocks;
- 90 `paragraph` + 40 `list`;
- warnings 0;
- YAML исключён;
- reference questions не входят в retrieval text;
- `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`;
- fragments в DB не сохранялись;
- draft остался `chernovik`;
- job возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02A2 — завершено / runtime verified

После исправления `TextEncoder` в v0.9.1 runtime на той же большой safe Markdown-базе подтвердил:
- exact tokenizer: `cl100k_base`;
- источник: `n8n_builtin_TokenTextSplitter_local_encoding`;
- canary `hello world` → 2 tokens, `tokenizer_object=true`;
- 130 structural blocks → 53 topic groups → 53 final candidates;
- source blocks requiring split: 0;
- token range: 87..551;
- average: 237.1 tokens;
- candidates <=80: 0;
- candidates >800: 0;
- overlap фактически не потребовался, потому что ни один смысловой блок не пересёк hard max;
- `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`;
- `llm_vyzovov=0`, `embeddings_vyzovov=0`, `db_fragmenty_sohraneny=false`;
- `podgotovit_versiyu_znaniy` вернула ожидаемый идемпотентный `dublikat`, version 1 осталась `chernovik`;
- job fence 4 успешно возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-02B — текущая задача

Цель: превратить runtime-проверенные A2 candidates в окончательные записи, готовые к будущему embedding/save, и отдельно подготовить reference questions.

Обязательные свойства:
1. каждый fragment получает стабильный `nomer_fragmenta`, `put_razdela`, точный `tekst_fragmenta`, `kolichestvo_tokenov`, `hash_fragmenta` и прослеживаемость к source blocks;
2. `hash_fragmenta` считается по точному тексту, который позже будет отправлен на embeddings;
3. reference questions берутся только из проверенного YAML metadata и остаются отдельным набором; они не входят в fragment embeddings;
4. 3–10 questions обязательны для автоматической первой публикации, но отсутствие 3 вопросов не должно уничтожать уже валидные fragment records; workflow должен явно отметить, что автоматическая проверка не готова;
5. candidate order и hashes должны быть детерминированны при повторном прогоне;
6. generative LLM не использовать;
7. embeddings, `sohranit_fragmenty_znaniy` и `sohranit_kontrolnye_voprosy` не выполнять до следующих этапов;
8. job после dry-run безопасно вернуть в `povtor`.

Подготовленный v0.10 дополнительно:
- независимо пересчитывает SHA-256 каждого exact `tekst_fragmenta` и сверяет A2 `hash_kandidatov`;
- формирует DB-compatible fragment records без поля vector и отдельный DB-compatible question array;
- сохраняет runtime trace source blocks, но не пытается записать его в текущую DB-таблицу fragments;
- считает deterministic hashes fragment set / question set / общего ready set;
- после проверки сжимает execution payload: полные arrays удаляются, остаются report + 4 samples + question summary;
- ручной путь не содержит generative LLM или embeddings nodes.

Критерий runtime v0.10:
- `kb02b_zapisi_gotovy=true`;
- для текущей большой базы `fragmentov=53`, `kontrolnyh_voprosov=8`, `kontrolnye_gotovy_dlya_avtoproverki=true`;
- `hash_a2_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4` при обработке той же большой загрузки;
- `prevyshenie_max=0`;
- LLM/embeddings/DB save/publish = 0;
- `podgotovit_versiyu_znaniy` может вернуть ожидаемый идемпотентный `dublikat`;
- job возвращён в `povtor`.

После KB-02B переходить к KB-03A.

Production не менять.
