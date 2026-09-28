# SESSION HANDOFF

Обновлено: 28 сентября 2026.

## Где остановились

**WF-02A завершена. PRE-02E подготовлена, но ещё не закрыта runtime-проверкой.**

Актуальный main до этого изменения: `6aa6ebefa0e7f0fe46f2b5ba1622fc01bc294a94`.

Фактическая версия амстердамского n8n подтверждена Павлом: **2.41.0**.

По актуальной официальной документации подготовлен candidate OpenAI profile:
- guard/planner — `gpt-6-luna`;
- grounded клиентский ответ — `gpt-6-sol`;
- document/query embeddings — `text-embedding-3-large`, `dimensions=1024`.

1024 теперь является осознанным candidate, а не наследием старого Qwen workflow: OpenAI поддерживает параметр `dimensions`, а обычный pgvector HNSW `vector` индексирует до 2000 dimensions. Default 3072 для `text-embedding-3-large` поэтому не подходит текущей HNSW-архитектуре. Окончательно 1024 фиксируется только после runtime.

Подготовлены:
- `docs/PRE-02E_OPENAI_PROFILE.md`;
- `workflows/PRE-02E_openai_profile_smoke_n8n_2.41.0.json`.

Smoke workflow:
- `active=false`;
- 10 нод;
- синтетические тестовые данные;
- LLM через `POST /v1/responses`;
- Structured Outputs;
- `store=false`;
- embeddings через `POST /v1/embeddings`;
- два отдельных embedding-вызова;
- финальная проверка dimension=1024;
- API key, Bearer/Authorization, Credential IDs и `instanceId` отсутствуют.

В n8n 2.41.0 штатный OpenAI Credential type — `openAiApi`. В четырёх HTTP Request нодах после импорта нужно выбрать один и тот же **test OpenAI Credential**. Ключ хранится только в Credentials UI.

## Текущий блокирующий критерий

PRE-02E остаётся `[~]` до фактического запуска smoke workflow в амстердамском n8n и результата последней ноды:

`pre02e_status = runtime_verified`.

Если модель недоступна account-у или API возвращает ошибку, не подменять её автоматически: сохранить точный error и пересмотреть profile по фактической доступности.

## После успешного runtime

1. Зафиксировать PRE-02E как `[x]` и dimension=1024 как проверенный profile.
2. Перейти к PRE-02C tokenizer/chunking.
3. Затем PRE-02D retrieval calibration.
4. Только после закрытия PRE-02 проектировать DB-04/DB-05 и интегрировать knowledge branch.
5. WF-02B может готовиться только с учётом проверенного OpenAI profile и DB-03; не считать knowledge/RAG ветку рабочей до DB-05.

Supabase, production, рабочий трафик, реальные Credentials и серверы в подготовке PRE-02E не менялись.
