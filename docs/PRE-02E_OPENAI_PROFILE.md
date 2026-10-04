# PRE-02E — OpenAI profile для n8n 2.41.0

Обновлено: 2026-10-04.

Статус: **профиль выбран; отдельной задачи/smoke-workflow PRE-02E больше нет. Фактическая проверка document embeddings встроена в активный knowledge workflow и закрывается на KB-03A.**

## Профиль

| Назначение | Модель / API | Настройка |
|---|---|---|
| Guard / classifier | `gpt-6-luna` через Responses API | Structured Outputs, `store=false` |
| Planner / структурированный разбор | `gpt-6-luna` через Responses API | Structured Outputs, `store=false` |
| Grounded клиентский ответ / решение | `gpt-6-sol` через Responses API | Structured Outputs, `store=false` |
| Document/query embeddings | `text-embedding-3-large` | `dimensions=1024`, `encoding_format=float` |

Фактическая версия амстердамского n8n: **2.41.0**.

API key хранится только в OpenAI Credential. Канонический workflow не содержит API key, Bearer token или Credential ID.

## Что уже есть

В каноническом клиентском RAG сохранён query embedding adapter:
- `POST https://api.openai.com/v1/embeddings`;
- модель из trusted settings `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- parser отклоняет отсутствующий, нечисловой или не ровно 1024-мерный вектор.

Это статическая часть существующего workflow и не является доказательством document embedding runtime.

## Где будет фактическая проверка

Отдельный smoke-workflow не создаётся.

На `KB-03A` в том же полном каноническом workflow:
1. каждый окончательный document fragment отправляется в `/v1/embeddings`;
2. явно передаётся `text-embedding-3-large` + `dimensions=1024`;
3. фактическая длина каждого ответа проверяется `=== 1024`;
4. только после этого vector вместе с точным embedding text/hash сохраняется через DB-04 API;
5. execution подтверждает используемую модель/размерность без записи API key в export;
6. тем же профилем затем векторизуются reference questions в KB-03B.

Таким образом бывший критерий PRE-02E становится частью runtime-критерия KB-03A, а не отдельной блокирующей задачей перед KB-01.

## Активный план

См. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Production не меняется без отдельного разрешения.
