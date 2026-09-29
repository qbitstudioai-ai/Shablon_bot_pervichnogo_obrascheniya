# PRE-02E — OpenAI profile для n8n 2.41.0

Дата актуализации: 29 сентября 2026.

Статус: **candidate profile выбран; отдельный smoke-workflow удалён. Runtime-проверка будет выполняться внутри канонического переделанного workflow.**

## Кандидат профиля

| Назначение | Модель / API | Настройка |
|---|---|---|
| Guard / classifier | `gpt-6-luna` через Responses API | Structured Outputs, `store=false` |
| Planner / структурированный разбор | `gpt-6-luna` через Responses API | Structured Outputs, `store=false` |
| Grounded клиентский ответ / решение | `gpt-6-sol` через Responses API | Structured Outputs, `store=false` |
| Document/query embeddings | `text-embedding-3-large` | candidate `dimensions=1024`, `encoding_format=float` |

Профиль пока не считается runtime-подтверждённым. Если фактический OpenAI account/n8n не поддерживает указанные model IDs или формат ответа, фиксируется реальная ошибка и профиль корректируется по факту.

## Почему candidate embeddings = 1024

`text-embedding-3-large` поддерживает уменьшение размерности через параметр `dimensions`. Candidate 1024 выбран, чтобы использовать один профиль document/query embeddings и оставаться совместимым с планируемым обычным pgvector `vector`/HNSW. Финальная размерность фиксируется только после реальной проверки и последующей retrieval-калибровки.

## Подключение в n8n

Фактическая версия амстердамского n8n: **2.41.0**.

API key хранится только в OpenAI Credential. Канонический workflow не должен содержать API key, Bearer token или Credential ID.

Предпочтительный adapter:
- LLM: `POST https://api.openai.com/v1/responses`;
- embeddings: `POST https://api.openai.com/v1/embeddings`;
- authentication через OpenAI Credential n8n.

## Как выполняется runtime-проверка

Отдельный smoke-workflow больше не используется.

Проверка выполняется прямо на переделанном основном workflow бота:
- guard/planner возвращают ожидаемый Structured Output;
- grounded answer возвращает ожидаемую структуру;
- document/query embeddings создаются моделью `text-embedding-3-large`;
- фактическая длина вектора равна выбранной размерности;
- секреты не попадают в экспорт или execution data.

До этой проверки PRE-02E остаётся `[~]`, а DB-04/DB-05 не начинаются.

## Источники профиля

Ссылки на официальные OpenAI/pgvector материалы сохраняются как основание выбора модели и размерности; перед финальной runtime-проверкой актуальность model IDs проверяется заново.
