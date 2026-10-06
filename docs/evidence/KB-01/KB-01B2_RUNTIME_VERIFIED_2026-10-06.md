# KB-01B2 — runtime verified, 2026-10-06

## Что проверялось

KB-01B2 фиксирует неизменяемый processing/index profile для будущей обработки знания и вызывает нормативную DB-функцию `podgotovit_versiyu_znaniy` под живым lease/fencing. Chunking, embeddings, reference search и publish сюда не входят.

После обсуждения архитектуры отдельная npm-зависимость `tiktoken` из Code node исключена. Профиль фиксирует tokenizer/encoding contract `cl100k_base`; фактический точный подсчёт токенов и структурно-смысловой chunking проверяются в KB-02A до сохранения fragments.

## Runtime

На test-контуре существующее durable knowledge job было claim-нуто worker `qbit_test_kb_worker_v1` с fence `2`.

Проверенный документ:
- `identifikator_dokumenta=qbit_podgotovka_k_pervichnomu_razboru`;
- parser result `valid=true`;
- 6 структурных заголовков;
- 3 контрольных вопроса;
- `hash_soderzhaniya=57b533d17983f44b1393bf57138309fcc729fa91f71ea4359f120d97ec283c18`.

Зафиксированный профиль:
- embedding model: `text-embedding-3-large`;
- dimension: `1024`;
- metric: `cosine`;
- parser: `kb01b1_safe_frontmatter_markdown_v1`;
- clean: `kb02a_clean_v1`;
- chunking: `kb02a_structural_chunk_600_800_100_v1`;
- tokenizer/encoding contract: `cl100k_base`;
- target/max/overlap: `600/800/100` tokens.

Deterministic fingerprints:
- `otpechatok_profilya=917b776877263b60b809fa0376cce8ae62937d2d44cdb0badc2e07bea2ceec3c`;
- `otpechatok_obrabotki=b56cd0f39885a576c0c7d04cdb78deceadb01e944713e9aa21b0483910b8abdb`.

`podgotovit_versiyu_znaniy` вернула:
- `rezultat=uspeshno`;
- non-null `dokument_id`;
- non-null `versiya_id`;
- `nomer_versii=1`;
- non-null `profil_indeksa_id`;
- `ozhidaemaya_aktivnaya_versiya_id=null`;
- `status_versii=chernovik`.

После подготовки версия осталась черновиком, публикация не выполнялась. Job освобождён тем же worker/fence через `zavershit_zadanie_znaniy` и вернулся в `status_zadaniya=povtor`.

## Что не доказано этим этапом

- Точный runtime token count `cl100k_base` ещё не доказан на финальном тексте fragments. Это обязательный guard KB-02A до сохранения fragments.
- Структурно-смысловой chunking ещё не реализован. KB-02A должен сохранять heading path, смысловые блоки, FAQ, таблицы и факты; token budget лишь ограничивает размер.
- Document embeddings OpenAI не выполнялись.
- Reference search и publish не выполнялись.
- End-to-end active-duplicate path не мог быть вызван, потому что у этого документа ещё нет опубликованной активной версии. Сам guard уже существует и runtime-проверялся на DB-04/DB-05 уровне; после первой публикации его нужно включить в regression KB-03C.

## Workflow artifact

Фактически runtime-проверенный import-ready workflow — v0.7.1 KB-01B2.

SHA-256 локального JSON:
`e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`.

Статическая проверка source:
- 212 nodes;
- 172 connection keys;
- 240 edges;
- duplicate node names: 0;
- dangling connections: 0;
- `active=false`;
- Credential refs: 0;
- top-level `id`, `versionId`, `meta` отсутствуют.

Отдельный Git-checkpoint v0.7.1 на момент этого evidence ещё не сохранён. Последний восстановимый checkpoint Git остаётся KB-01A; это не отменяет runtime evidence KB-01B2.

Production не менялся.
