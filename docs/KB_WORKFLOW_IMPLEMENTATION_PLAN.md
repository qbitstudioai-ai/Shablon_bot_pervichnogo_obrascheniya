# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Нормативные DB-04/DB-05 уже созданы и runtime-проверены в test-контуре. Production не менять без отдельного явного разрешения Павла.

Каноническая основа workflow — фактический export Павла `(7)` с raw SHA-256 `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний сохранённый в Git восстановимый runtime-checkpoint пока остаётся KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.10 KB-02B**, SHA-256 `f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`. Отдельный Git-checkpoint v0.10 ещё не сохранён.

## Этапы

| Статус / ID | Зависимости | Результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает разрешённый private `.md`, проверяет actual bytes и долговечно регистрирует upload/job. Runtime подтверждён. |
| [x] KB-01B1 | KB-01A | Manual worker claim + lease/fencing + safe YAML/Markdown parser + deterministic `hash_soderzhaniya`; job возвращается в `povtor`. |
| [x] KB-01B2 | KB-01B1 | Зафиксирован processing/index profile; `podgotovit_versiyu_znaniy` создаёт version `chernovik`; job возвращается в `povtor`. |
| [x] KB-02A1 | KB-01B2 | Детерминированный структурный разбор формирует ordered semantic blocks с heading path; YAML/reference questions исключены из retrieval text. |
| [x] KB-02A2 | KB-02A1 | Exact `cl100k_base` + structural packing: target 600, hard max 800, overlap до 100 только внутри реально разрезанного блока; DB save ещё нет. |
| [x] KB-02B | KB-02A2 | Final fragment records + отдельные 3–10 YAML reference questions; exact text/hash/token count/order/trace проверены; LLM/embeddings/DB save/publish = 0. |
| [~] KB-03A | KB-02B | Document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`; строгая проверка каждого vector; затем нормативный `sohranit_fragmenty_znaniy`. |
| [ ] KB-03B | KB-03A | Reference questions векторизуются тем же профилем; draft search только по своей версии; checks сохраняются; `gotova` только после полного pass. |
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

## Доказанный runtime

### KB-01A
Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A1
На большой safe Markdown-базе: 57 headings, 130 ordered blocks, 90 paragraph + 40 list, warnings 0, stable `hash_struktury=fdb26ff9a95b0cfeee5c4f2909859d148c268bfcec2bd308b16e9cf0f6910d85`, DB fragments 0, job → `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
На той же большой базе: exact `cl100k_base`; 130 blocks → 53 candidates; token range 87..551; average 237.1; `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`; LLM/embeddings/DB save = 0; job → `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02B
Live runtime v0.10 выполнен на safe документе `qbit_podgotovka_k_pervichnomu_razboru`:
- 6 final fragment records;
- token range 102..211, average 151.7, >800 = 0;
- `hash_a2_kandidatov=1808f182d52a56bf1f4dc4f3066ac70f3e0c2c9b8555fb2c436e9a42bfe5cbab`;
- `hash_nabora_fragmentov=d367f0824cee817d498778f95815b4175a3e47cebd2facebdcacaffc1703a0d2`;
- 3 YAML reference questions, готовы к будущей автопроверке;
- `hash_nabora_kontrolnyh_voprosov=d34d9e8222fa5608d2c4612a2decf5d158b7cbf3dc8fbba8499774639082e70a`;
- `hash_gotovogo_nabora=ad69f88ebbd5c99147cf3c750fcacaa37e4d12ff58366bd53f5573e04b150455`;
- LLM/embeddings/DB fragment save/question save/publish = 0;
- `podgotovit_versiyu_znaniy` → ожидаемый `dublikat`, version остаётся `chernovik`;
- job fence 4 возвращён в `povtor`.

Детерминизм B-кода дополнительно проверен двумя локальными запусками на идентичном входе: полный JSON совпал побайтово. Это не второй live-claim и в evidence так и записано.

Evidence: `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-03A — текущая задача

Цель: впервые выполнить document embeddings и сохранить final fragments через нормативный DB API.

Обязательные свойства:
1. использовать только OpenAI `text-embedding-3-large`;
2. запрос: `dimensions=1024`, `encoding_format=float`;
3. embedding получает **точный `tekst_fragmenta` из KB-02B**, без дополнительного splitter/переписывания;
4. каждый ответ OpenAI должен содержать vector length ровно 1024 и только конечные числа;
5. порядок vectors должен однозначно соответствовать `nomer_fragmenta`; нельзя подставить vector/metadata первого item всем остальным;
6. формировать payload нормативного `sohranit_fragmenty_znaniy`: `nomer_fragmenta`, `put_razdela`, `tekst_fragmenta`, `kolichestvo_tokenov`, `hash_fragmenta`, `vektor`;
7. DB повторно проверяет SHA-256 текста, token max и vector dimension;
8. пакет функции: 1..100 fragments; текущие 6/53 укладываются в один batch;
9. при частичной/внешней ошибке не публиковать версию и не терять fenced job;
10. после успешного save проверить `sohraneno_fragmentov` / `vsego_fragmentov` и только затем безопасно освободить job для KB-03B;
11. reference questions в KB-03A ещё не векторизовать и проверки не запускать;
12. production не менять.

После KB-03A переходить к KB-03B.
