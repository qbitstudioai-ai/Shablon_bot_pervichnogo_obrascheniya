# KB-02A2 — runtime verified, 2026-10-06

## Что проверялось

KB-02A2 применяет точный token budget к structural blocks KB-02A1 и формирует final candidate fragments. На этом этапе нет generative LLM, document embeddings, записи fragments в DB или publish.

Цель: доказать точный runtime `cl100k_base` count и детерминированную упаковку при профиле target/max/overlap `600/800/100`, где смысловая граница первична, а token budget вторичен.

## Runtime

Проверен import-ready workflow **v0.9.1 KB-02A2**, локальный SHA-256:

`5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`

На большой safe Markdown-базе:
- live job: `0032a78e-b3fa-4cc8-8175-fcc52b53dd64`;
- fence: `4`;
- исходная A1 структура повторилась: 130 blocks, 57 headings, 90 paragraph + 40 list;
- `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`;
- warnings: 0.

## Точный tokenizer

Runtime отчёт A2:
- tokenizer: `cl100k_base`;
- источник: `n8n_builtin_TokenTextSplitter_local_encoding`;
- `exact_token_count=true`;
- canary `hello world` → 2 tokens;
- `tokenizer_object=true`.

Первая попытка v0.9 ранее упала после tokenizer gate на `TextEncoder is not defined` во вспомогательном SHA-256 коде LangChain Code sandbox. v0.9.1 заменила только это UTF-8 преобразование собственным детерминированным encoder без внешних модулей. Повторный runtime прошёл.

## Candidate packing

Из 130 structural blocks сформировано:
- topic groups: 53;
- final candidates: 53;
- source blocks, потребовавших разрезания: 0;
- tokens min: 87;
- tokens max: 551;
- tokens average: 237.1;
- candidates <=80 tokens: 0;
- candidates >800 tokens: 0;
- overlap применён: 0 candidates;
- фактический max overlap: 0.

`hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`

Отсутствие overlap в этом runtime является нормальным результатом: ни один смысловой source block не потребовал разрезания по hard max, поэтому искусственно добавлять overlap нельзя. Аналогично средний размер 237.1 ниже target 600 допустим: разные темы не объединяются только ради достижения target.

Финальный формат текста: `qbit_kb_fragment_text_v1`. Candidate включает название документа, `put_razdela` и исходное содержание без LLM-суммаризации.

## Нагрузка на LLM

Runtime отчёт подтвердил:
- `llm_vyzovov=0`;
- `embeddings_vyzovov=0`;
- `db_fragmenty_sohraneny=false`.

53 candidates — индексные единицы, а не prompt клиентской LLM. Клиентский путь остаётся: query embedding → vector search → фильтрация/дедупликация → ограниченный evidence-пакет → финальная LLM.

## DB / lease / version

`podgotovit_versiyu_znaniy` вернула ожидаемый идемпотентный результат `dublikat` с описанием «Версия для этой загрузки уже подготовлена». Существующая version 1 осталась `chernovik`.

После dry-run job тем же worker/fence успешно освобождён обратно в `status_zadaniya=povtor`.

## Итог

**KB-02A2 runtime verified.**

Доказано:
- exact `cl100k_base` runtime count;
- deterministic structural packing;
- hard max 800 соблюдён;
- смысловые границы не нарушаются ради target 600;
- нет generative LLM/embeddings/DB fragment save/publish;
- job не потерян.

Production и рабочий трафик не менялись.

Следующая задача: **KB-02B** — подготовить окончательные fragment records/metadata/hash/token count и отдельный набор reference questions, сохраняя их раздельно до embeddings в KB-03A.

Отдельный Git-checkpoint полного v0.9.1 на момент этой evidence-записи ещё не сохранён; не утверждать обратное.
