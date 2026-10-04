# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены ранее. Нормативные DB-04/DB-05 после KB-01R4/R5 также существуют в test и runtime-проверены для текущего bot/service контура. Старые `[ ] DB-04/DB-05` в `WORKPLAN_TEMPLATE.md` — отставшая сводная отметка, а не текущее фактическое состояние.

Текущая работа — реальный knowledge workflow поверх полного фактического workflow, без отдельного skeleton.

## Канонический workflow

Павел передал более поздний фактический export `(7)`, тогда как checkpoint 03.10.2026 был сделан из `(6)`. `(7)` принят как более свежая фактическая основа.

В этой сессии подготовлен полный очищенный import-ready файл:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

SHA-256 файла: `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.

Из-за ограничения текущего GitHub-коннектора большой локальный JSON/checkpoint ещё не записан в Git. Помощник VSCode должен сохранить **ровно этот подготовленный файл** в `workflows/`, создать checkpoint `workflows/checkpoints/2026-10-04_v0.4_KB-01A/`, обновить restore script, проверить hashes и сделать commit+push. До этого Git-источником полного workflow остаётся checkpoint 03.10.2026 из `(6)`.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

Текущий ID: **KB-01A** — реальный приём `.md` через существующий служебный Telegram webhook до нормативного DB-04 upload + durable knowledge job.

JSON подготовлен и статически проверен, но ещё не сохранён в Git и не импортирован. Сначала помощник VSCode должен сохранить ровно подготовленный файл/checkpoint и сделать commit+push; реальный import/runtime test с безопасным `.md` выполняется следующей сессией. KB-01A пока не закрыт.

PRE-02E отдельно не тестируется: document embeddings OpenAI `text-embedding-3-large` с `dimensions=1024` будут встроены и runtime-проверены внутри того же канонического workflow на `KB-03A`.

## С чего начинает новая сессия

1. [Инструкция ChatGPT](docs/CHATGPT_INSTRUCTIONS.md).
2. [Текущее состояние](docs/PROJECT_STATE.md).
3. [Активный план KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).
4. [Передача](docs/SESSION_HANDOFF.md).
5. Только спецификации, необходимые текущему ID.

Одна небольшая задача — одна сессия. Наличие JSON или SQL в Git не означает, что он импортирован, применён на сервере или runtime-проверен.

## Карта документации

| Вопрос | Документ |
|---|---|
| Архитектура продукта | [ARCHITECTURE](docs/ARCHITECTURE.md) |
| Имена таблиц/полей | [DATA_DICTIONARY](docs/DATA_DICTIONARY.md), [NAMING_CONVENTIONS](docs/NAMING_CONVENTIONS.md) |
| Нормативный DB-01…DB-05 | [DB_CONTRACT](docs/specs/DB_CONTRACT.md) |
| SQL реализации | [sql/](sql/) |
| Подключение n8n к PostgreSQL | [N8N_POSTGRES_CONNECTION](docs/N8N_POSTGRES_CONNECTION.md) |
| CORE и RAG | [BOT_CORE_WORKFLOW](docs/specs/BOT_CORE_WORKFLOW.md) |
| Операторский Telegram | [OPERATOR_HANDOFF](docs/specs/OPERATOR_HANDOFF.md) |
| Загрузка знаний | [KNOWLEDGE_INGESTION](docs/specs/KNOWLEDGE_INGESTION.md), [MARKDOWN_FORMAT](docs/specs/MARKDOWN_FORMAT.md) |
| Активная реализация knowledge workflow | [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md) |
| Завершённая сверка DB-04/DB-05 | [KB-01R](docs/KB-01_RECONCILIATION_PLAN.md), [evidence](docs/evidence/KB-01/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты и дампы БД в публичный репозиторий не загружаются.
