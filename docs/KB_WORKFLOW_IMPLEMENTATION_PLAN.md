# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-08.

Нормативные DB-04/DB-05 созданы и runtime-проверены в TEST. Production не менять без отдельного явного разрешения Павла.

Текущая repository-safe основа:
- `workflows/current/Шаблон Загрузка документов Qbit.json`;
- `workflows/current/Шаблон — Workflow бота Qbit.json`.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

Подпланы:
- завершённая KB-03B: `docs/KB-03B_IMPLEMENTATION_PLAN.md`;
- активная KB-03C: `docs/KB-03C_IMPLEMENTATION_PLAN.md`.

## Этапы

| Статус / ID | Зависимости | Результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Service Telegram принимает `.md` и долговечно регистрирует upload/job. |
| [x] KB-01B1 | KB-01A | Manual worker claim + lease/fencing + safe YAML/Markdown parser. |
| [x] KB-01B2 | KB-01B1 | Processing/index profile + draft version. |
| [x] KB-02A1 | KB-01B2 | Ordered semantic blocks; YAML/reference questions исключены из retrieval text. |
| [x] KB-02A2 | KB-02A1 | Exact `cl100k_base` + structural packing. |
| [x] KB-02B | KB-02A2 | Final fragment records + отдельные YAML reference questions. |
| [x] KB-03A | KB-02B | OpenAI `text-embedding-3-large/1024/float`, vectors сохранены. |
| [x] KB-03B0 | KB-03A | Fenced bridge для question IDs без прямого table SELECT runtime-роли. |
| [x] KB-03B1 | KB-03B0 runtime | Runtime 9/9, version `gotova`, publish=false. |
| [x] KB-03C1 | KB-03B1 runtime | Publish branch подготовлен и статически проверен; server mutation не выполнялась. |
| [ ] KB-03C2 | KB-03C1 static | TEST runtime atomic publish + stale protection + active-only regression. |

## Guard по нагрузке на LLM

- ingestion/parsing/cleaning/chunking/token count — без generative LLM;
- embeddings — только индекс/search;
- вся база не передаётся клиентской LLM целиком;
- client path: query embedding → vector search → filter/dedupe → ограниченный evidence package → final LLM;
- candidate top-k = 12; final evidence максимум 8 fragments;
- LLM reranker в v1 не добавлять без доказанной пользы.

B1 threshold 0.60 — только positive-reference validation threshold; финальный client threshold требует negative/no-answer calibration.

## Evidence

Runtime:
- `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`;
- `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-02/KB-02B_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`;
- `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`;
- `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

Static:
- `docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

## KB-03C2 — следующая задача

Сначала безопасно импортировать новый workflow документов как отдельную неактивную TEST-копию и привязать только нужные service Credentials. Это не является публикацией.

Перед Execute, который может вызвать `opublikovat_versiyu_znaniy`, требуется отдельное подтверждение Павла на конкретную TEST publication и уточнённый rollback. После публикации проверить active-only поиск через уже существующий `poisk_aktivnyh_znaniy`.

Production и рабочий трафик не менять.
