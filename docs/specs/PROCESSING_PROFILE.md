# Профиль обработки PRE-02

Обновлено: 2026-10-06.

Статус: processing profile knowledge ingestion runtime-проверен до document embeddings включительно. Нормативные DB-04/DB-05 созданы и проверены на test-контуре. Структурный chunking, exact `cl100k_base` и document embeddings OpenAI подтверждены runtime. Draft retrieval/reference checks ещё впереди.

## Внешний AI-провайдер

28 сентября 2026 года Павел выбрал **OpenAI** как целевого внешнего провайдера для LLM и embeddings. Рабочий n8n находится в Амстердаме; Supabase/pgvector остаётся на российском сервере.

Для test и production используются разные OpenAI API keys. Секреты не сохраняются в GitHub и не вставляются в workflow. Credentials подключаются в n8n UI.

LLM не получает права выбирать schema, Credential, адресата или выполнять исходящее действие самостоятельно. Внешние вызовы получают только минимально необходимый пакет.

## Embeddings — document runtime verified

Зафиксированный document/query embedding profile:
- provider: OpenAI;
- model: `text-embedding-3-large`;
- dimensions: `1024`;
- similarity metric: cosine;
- encoding format API: `float`.

Один и тот же model/dimension profile используется для document fragments и query/reference embeddings. Векторы разных профилей не смешиваются в одном активном индексе.

KB-03A runtime 06.10.2026 подтвердил document embedding path:
- input = exact `tekst_fragmenta` из KB-02B, без второго splitter/переписывания;
- один OpenAI batch request на набор fragments;
- успешный safe-run: 6 fragments, usage 910 input tokens;
- 6 embeddings;
- каждый vector length = 1024;
- все значения finite;
- mapping по OpenAI `index` подтверждён;
- normative DB save → `sohraneno_fragmentov=6`, `vsego_fragmentov=6`.

Первая попытка на большой safe-базе дошла до 53 fragments / 12568 input tokens, но была безопасно остановлена на `Credentials not found`; fragments не сохранялись и publish не выполнялся. После привязки TEST Credential новый JSON не потребовался.

Reference-question embeddings и retrieval quality проверяются в KB-03B.

## Подключение n8n

Фактическая версия n8n: **2.41.0**.

Knowledge ingestion/chunking не требует generative LLM или внешних npm tokenizer-пакетов. OpenAI Credentials подключаются через n8n UI; Credential IDs/API keys в Git-export не сохраняются.

## Markdown, YAML и parser

Текущая runtime-реализация не зависит от внешних Markdown/YAML npm-пакетов:
- safe front matter/YAML subset и Markdown structure обрабатываются self-contained deterministic Code node;
- parser version: `kb01b1_safe_frontmatter_markdown_v1`;
- cleaning version: `kb02a_clean_v1`;
- structural chunking profile: `kb02a_structural_chunk_600_800_100_v1`.

YAML/reference questions отделяются от retrieval text. Содержание документа не переписывается LLM.

## Tokenizer — runtime verified

Encoding contract: **`cl100k_base`**.

KB-02A2 runtime 06.10.2026 подтвердил exact token count через встроенный tokenizer n8n:
- runtime source: `n8n_builtin_TokenTextSplitter_local_encoding`;
- `exact_token_count=true`;
- canary `hello world` → 2 tokens;
- tokenizer object реально доступен;
- character estimate не используется как подтверждённый count.

Отдельно устанавливать `js-tiktoken`, `@dqbd/tiktoken`, `tiktoken` или `@huggingface/transformers` для текущего knowledge chunking не требуется.

Штатный Token Splitter не является основным смысловым chunker. Он используется как tokenizer/runtime primitive; границы смысловых фрагментов определяет детерминированный проектный алгоритм.

## Chunking — runtime verified

Стартовый immutable profile:
- target: 600 tokens;
- hard max: 800 tokens;
- overlap limit: 100 tokens только внутри одной темы/разрезаемого длинного блока.

Порядок:
1. safe Markdown parse;
2. heading path и structural blocks;
3. группировка только внутри одной темы;
4. точный token count окончательного текста candidate fragment;
5. длинный блок при необходимости делится по документированным смысловым правилам;
6. другой topic не объединяется только ради достижения target;
7. hard max 800 имеет приоритет без потери содержания.

KB-02A2 на большой safe базе дал:
- 130 structural blocks;
- 53 topic groups;
- 53 final candidates;
- tokens min/max/average: 87 / 551 / 237.1;
- candidates <=80: 0;
- candidates >800: 0;
- split source blocks: 0;
- overlap фактически 0, потому что ни один source block не потребовал разрезания;
- deterministic `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`.

Target 600 — ориентир, **не минимум**. Нельзя ухудшать семантические границы ради заполнения fragment до 600.

## RAG и нагрузка на клиентскую LLM

Рост базы не должен линейно увеличивать prompt.

Обязательный путь:

`query embedding → vector search → фильтрация/дедупликация → ограниченный evidence package → финальная LLM`

Стартовые retrieval limits:
- candidate top-k = 12 на один атомарный поисковый запрос;
- в финальный evidence package — максимум 8 fragments и только столько, сколько действительно нужно;
- общий evidence token budget должен быть зафиксирован по результатам retrieval-калибровки;
- отдельный LLM reranker в v1 не добавлять без доказанной пользы на контрольном наборе.

Structural blocks и весь candidate set никогда не передаются клиентскому LLM целиком.

Similarity threshold не назначается по памяти. Для первой калибровки проверяется диапазон 0.45–0.85 с шагом 0.05; финальное значение фиксируется только после контрольного набора.

## Ограничения вызовов

Стартовые ограничения для будущего клиентского runtime:
- guard/classifier: максимум 500 output tokens;
- planner/структурированный разбор: максимум 1000 output tokens;
- grounded клиентский ответ: максимум 1200 output tokens;
- короткая память qBit: 5 последних обезличенных сообщений + резюме + подтверждённые важные факты;
- не выполнять query embedding, если CORE уже определил, что knowledge search не нужен.

Точные timeouts/retries и бюджет затрат измеряются на фактическом runtime.

## Голос и локальный STT

Текст и голос являются поддерживаемыми входами клиентского Telegram v1. Исходное голосовое не отправляется напрямую во внешний transcription API, если может содержать PII.

Целевой путь:

`Telegram voice → локальный STT → транскрипция → PII-очистка → OpenAI`

Конкретный STT runtime остаётся отдельной задачей и не является частью KB-03.

## Контрольный набор

До финальной retrieval-калибровки нужен обезличенный набор сценариев, включая прямые факты, перефразирование/опечатки, составные вопросы, похожие товары/услуги, отсутствие ответа, prompt injection и PII.

Для retrieval измеряются как минимум попадание ожидаемого раздела в top-12 и ложные срабатывания на вопросах без ответа. Для финального ответа обязательны отсутствие неподтверждённых технических фактов и PII leak.

## Что осталось по knowledge profile

1. **KB-03B** — сохранить/reference question embeddings, draft-only retrieval checks и калибровка качества.
2. **KB-03C** — atomic publish и end-to-end regression active-only search.
3. До завершения retrieval-калибровки зафиксировать similarity threshold и общий evidence token budget.

Production не менять без отдельного явного разрешения.
