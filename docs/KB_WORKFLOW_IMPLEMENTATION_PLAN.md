# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Нормативные DB-04/DB-05 уже созданы и runtime-проверены в test-контуре. Production не менять без отдельного явного разрешения Павла.

Каноническая основа workflow — фактический export Павла `(7)` с raw SHA-256 `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний сохранённый в Git восстановимый runtime-checkpoint пока остаётся KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**, SHA-256 `54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`. Отдельный Git-checkpoint v0.11 ещё не сохранён.

## Этапы

| Статус / ID | Зависимости | Результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A | Manual worker claim + lease/fencing + safe YAML/Markdown parser + deterministic `hash_soderzhaniya`; job возвращается в `povtor`. |
| [x] KB-01B2 | KB-01B1 | Зафиксирован processing/index profile; `podgotovit_versiyu_znaniy` создаёт version `chernovik`; job возвращается в `povtor`. |
| [x] KB-02A1 | KB-01B2 | Детерминированный структурный разбор формирует ordered semantic blocks с heading path; YAML/reference questions исключены из retrieval text. |
| [x] KB-02A2 | KB-02A1 | Exact `cl100k_base` + structural packing: target 600, hard max 800, overlap до 100 только внутри реально разрезанного блока; DB save ещё нет. |
| [x] KB-02B | KB-02A2 | Final fragment records + отдельные 3–10 YAML reference questions; exact text/hash/token count/order/trace проверены; LLM/embeddings/DB save/publish = 0. |
| [x] KB-03A | KB-02B | OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`; vectors строго проверены; fragments/vectors сохранены через нормативный `sohranit_fragmenty_znaniy`. |
| [~] KB-03B | KB-03A | Сохранить reference questions, векторизовать их тем же профилем; draft search только по своей версии; checks сохранить; `gotova` только после полного pass. |
| [ ] KB-03C | KB-03B | Atomic publish переключает active version и архивирует прежнюю; stale publish конфликтует; затем end-to-end regression. |

## Guard по нагрузке на LLM

Постоянное правило knowledge/RAG:
- ingestion, parsing, cleaning, chunking и token counting выполняются без generative LLM;
- embeddings используются только для индексации/semantic search;
- вся база знаний, все structural blocks и весь candidate set никогда не передаются клиентской LLM целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → ограниченный evidence-пакет → финальная LLM;
- candidate top-k = 12; evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- до завершения retrieval-калибровки зафиксировать общий evidence token budget.

Runtime A2 показал, что target 600 — не минимальный размер: разные темы нельзя объединять только ради приближения к 600. На большой safe-базе 130 structural blocks → 53 candidates, 87..551 tokens, average 237.1, >800 = 0.

KB-03A использует один OpenAI embedding batch для полного набора fragments, а не отдельный запрос на каждый fragment. Это индексная операция, не generative LLM.

## Доказанный runtime

### KB-01A
Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A1
На большой safe Markdown-базе: 57 headings, 130 ordered blocks, warnings 0, stable structure hash, DB fragments 0, job → `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
На той же большой базе: exact `cl100k_base`; 130 blocks → 53 candidates; token range 87..551; average 237.1; `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`; LLM/embeddings/DB save = 0; job → `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02B
Live runtime v0.10 на safe документе подтвердил 6 final fragment records, exact text/hash/token count/order/trace и 3 отдельные YAML reference questions. LLM/embeddings/DB save/publish = 0; job → `povtor`.

Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-03A
Первая попытка на большой safe-базе дошла до 53 fragments / 12568 input tokens, но была безопасно остановлена из-за `Credentials not found`; DB save/publish не выполнялись, job → `povtor`.

После привязки TEST OpenAI Credential успешный live-run на safe документе подтвердил:
- 6 final fragments;
- один OpenAI embedding batch;
- `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- usage 910 input tokens;
- 6 vectors, каждый length 1024;
- все vector values finite;
- mapping по API index подтверждён;
- exact `tekst_fragmenta` использован как embedding input;
- generative LLM calls = 0;
- `sohranit_fragmenty_znaniy` → `uspeshno`;
- `sohraneno_fragmentov=6`, `vsego_fragmentov=6`;
- version остаётся `chernovik`;
- reference questions ещё не embedded/saved;
- publish = false;
- job fence 5 → `povtor`.

Evidence: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-03B — текущая задача

Цель: сохранить canonical YAML reference questions, получить embeddings вопросов тем же profile и выполнить draft-only retrieval checks по version 1.

Обязательные свойства:
1. questions берутся только из проверенного YAML набора KB-02B;
2. сохранить их через нормативный `sohranit_kontrolnye_voprosy` до checks;
3. embedding каждого `vopros` — OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
4. каждый question vector length ровно 1024 и все значения finite;
5. draft search выполняется только через `poisk_chernovika_znaniy` и только по своей `versiya_id`/profile;
6. для каждого question проверить ожидаемый `ozhidaemyy_razdel`; если задан `ozhidaemyy_fakt`, он должен быть подтверждён найденным evidence без LLM-самооценки;
7. сохранить результаты через `sohranit_proverki_znaniy`;
8. версия может перейти в `gotova` только при полном pass всех canonical questions;
9. при любом fail версия остаётся draft/not-ready, publish не выполняется;
10. retrieval limits и similarity threshold не назначать по памяти: использовать документированный калибровочный диапазон и сохранять фактические результаты;
11. production не менять.

После KB-03B переходить к KB-03C.
