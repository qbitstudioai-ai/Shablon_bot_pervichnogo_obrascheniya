# KB-02A1 — runtime verified, 2026-10-06

## Что проверялось

KB-02A1 — dry-run структурно-смыслового разбора Markdown до token packing. На этом этапе нет embeddings, записи fragments в БД, reference search или publish.

Цель: доказать, что уже проверенный Markdown детерминированно превращается в упорядоченные смысловые блоки с сохранением heading path, а YAML и контрольные вопросы не попадают в retrieval text.

## Runtime

На test-контуре существующее durable knowledge job было claim-нуто worker `qbit_test_kb_worker_v1` с live fence `3`.

Результат `KB-02A1 Сформировать смысловые блоки`:
- `blokov=130`;
- `zagolovkov=57`;
- `paragraph=90`;
- `list=40`;
- warnings: 0;
- `yaml_isklyuchen=true`;
- `kontrolnye_voprosy_v_retrieval=false`;
- `token_count_vypolnen=false`;
- `db_fragmenty_sohraneny=false`;
- `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`.

Этот hash и counts совпали с предварительным локальным прогоном того же v0.8, то есть ordered structural result воспроизводим между локальной проверкой и n8n runtime.

`podgotovit_versiyu_znaniy` завершилась `uspeshno`; draft остался `status_versii=chernovik`. После dry-run job освобождён тем же worker/fence и вернулся в `status_zadaniya=povtor`.

## Что доказано дополнительно

Ветка ручного KB-02A1 не вызывает generative LLM/OpenAI nodes: runtime-путь состоит из Manual Trigger, Code/IF и service Postgres nodes. Структурное разбиение выполняется детерминированным кодом.

130 blocks — промежуточные единицы индексации, а не 130 кусков, которые будут передаваться клиентскому LLM. В KB-02A2 они должны быть упакованы в final candidate fragments в пределах смысловых границ и token budget.

## Ограничение нагрузки на LLM

Архитектурный guard проекта:
- ingestion/chunking/token counting не должны использовать generative LLM;
- embeddings выполняются при индексации и для поискового запроса, но не являются генерацией ответа;
- клиентскому LLM никогда не передаётся вся база знаний или весь набор structural blocks;
- сначала выполняются vector search, фильтрация и дедупликация;
- текущий retrieval profile использует candidate top-k 12 и не более 8 evidence fragments для финального ответа; фактически передавать следует только достаточный релевантный набор, а не автоматически все 8;
- отдельный LLM reranker в v1 не добавлять без доказанной необходимости на контрольном наборе.

## Что остаётся для KB-02A2

- доказать точный runtime `cl100k_base` count для окончательного текста candidate fragments;
- детерминированно упаковать structural blocks с target/max/overlap `600/800/100`;
- не объединять разные темы ради достижения target;
- FAQ и таблицы обрабатывать по правилам `MARKDOWN_FORMAT.md`;
- ни одного candidate fragment >800 tokens;
- embeddings и запись fragments в БД пока не выполнять.

Production и рабочий трафик не менялись.
