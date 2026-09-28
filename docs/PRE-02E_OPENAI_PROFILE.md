# PRE-02E — OpenAI profile для n8n 2.41.0

Дата подготовки: 28 сентября 2026.

Статус: **кандидат выбран, smoke workflow подготовлен; runtime-проверка в амстердамском n8n ещё не выполнена. PRE-02E не закрыта.**

## Кандидат профиля

| Назначение | Модель / API | Настройка |
|---|---|---|
| Guard / classifier | `gpt-6-luna` через Responses API | Structured Outputs, `store=false`, reasoning `none`, до 500 output tokens |
| Planner / структурированный разбор | `gpt-6-luna` через Responses API | Structured Outputs, `store=false`, стартово reasoning `low`, до 1000 output tokens |
| Grounded клиентский ответ / решение | `gpt-6-sol` через Responses API | Structured Outputs, `store=false`, стартово reasoning `low`, до 1200 output tokens |
| Document embeddings | `text-embedding-3-large` | `dimensions=1024`, `encoding_format=float` |
| Query embeddings | `text-embedding-3-large` | тот же профиль `dimensions=1024` |

Это **кандидат**, а не доказанный runtime-профиль. Если OpenAI account не даёт доступ к указанным model IDs либо фактический API/n8n runtime возвращает несовместимый ответ, профиль не считается принятым: ошибка фиксируется, затем модель выбирается заново по фактической доступности и актуальной документации.

## Почему embeddings = text-embedding-3-large / 1024

OpenAI указывает `text-embedding-3-large` как наиболее способную embedding-модель для English и non-English задач. Параметр `dimensions` официально поддерживается для `text-embedding-3`; документация прямо приводит уменьшение `text-embedding-3-large` до 1024 как допустимый сценарий.

Для pgvector HNSW обычный тип `vector` индексируется до 2000 dimensions. Поэтому default 3072 для `text-embedding-3-large` не подходит выбранной обычной `vector`/HNSW архитектуре без смены типа/индекса. 1024 укладывается в лимит и оставляет один одинаковый профиль для document/query embeddings.

Это решение ещё должно пройти PRE-02E runtime и PRE-02D retrieval-калибровку. Порог cosine similarity здесь не выбирается.

Официальные источники:
- OpenAI GPT-6 models: https://developers.openai.com/api/docs/models
- GPT-6 Luna: https://developers.openai.com/api/docs/models/gpt-6-luna
- GPT-6 Sol: https://developers.openai.com/api/docs/models/gpt-6-sol
- Structured Outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- Embeddings guide: https://developers.openai.com/api/docs/guides/embeddings
- text-embedding-3-large: https://developers.openai.com/api/docs/models/text-embedding-3-large
- pgvector HNSW limits: https://github.com/pgvector/pgvector

## Способ подключения в n8n

Фактическая версия амстердамского n8n подтверждена Павлом: **2.41.0**.

В исходниках n8n 2.41.0 штатный OpenAI Credential имеет внутренний тип `openAiApi`. Он хранит API key в Credentials и сам добавляет Authorization header. Поэтому smoke workflow и будущий переносимый workflow не должны содержать API key, Bearer token или Credential ID.

Для текущей архитектуры PRE-02E использует обычные HTTP Request nodes:
- LLM: `POST https://api.openai.com/v1/responses`;
- embeddings: `POST https://api.openai.com/v1/embeddings`;
- authentication: `predefinedCredentialType`;
- credential type: `openAiApi`.

Так сохраняется существующий явный adapter-подход workflow и можно строго контролировать JSON request/response. Если именно этот способ даст runtime-ошибку n8n, фиксируется фактическая ошибка и только после неё рассматривается штатная OpenAI node как fallback.

## Smoke workflow

Файл:
`workflows/PRE-02E_openai_profile_smoke_n8n_2.41.0.json`.

Workflow:
- неактивен;
- использует только синтетические данные;
- не обращается к Supabase;
- не меняет production/traffic;
- не содержит API key, Authorization header, Credential ID или `instanceId`;
- отдельно вызывает GPT-6 Luna и GPT-6 Sol;
- отдельно создаёт document embedding и query embedding;
- проверяет, что оба вектора содержат ровно 1024 конечных чисел;
- считает cosine similarity только как диагностическое значение, **не как выбранный retrieval threshold**.

Успешная финальная нода должна вернуть:
`pre02e_status = runtime_verified`.

## Что должен подтвердить runtime

PRE-02E можно закрыть только после фактического выполнения smoke workflow в амстердамском n8n 2.41.0 и получения финального результата без ошибок:

- `pre02e_status=runtime_verified`;
- Luna Structured Output валиден;
- Sol grounded Structured Output валиден;
- document embedding model = `text-embedding-3-large`, dimension = 1024;
- query embedding model = `text-embedding-3-large`, dimension = 1024;
- секреты не попали в экспорт/результат.

После подтверждения runtime можно зафиксировать dimension=1024 как профиль для проектирования DB-04/DB-05. До этого SQL vector-поля не менять.

## Короткое действие Павла

Импортировать `PRE-02E_openai_profile_smoke_n8n_2.41.0.json` в тестовый n8n 2.41.0, в четырёх HTTP Request нодах выбрать **один и тот же test OpenAI Credential**, затем нажать Execute Workflow.

API key в чат, JSON или GitHub не передавать. Если Credential ещё не создан, создать его через интерфейс n8n как OpenAI Credential и вставить ключ только в защищённое поле Credentials.

После запуска достаточно передать результат последней ноды `Собрать результат PRE-02E` или точный текст ошибки первой упавшей ноды.
