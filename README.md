# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. DB-01, DB-02, DB-03/DB-03E и rename qBit schema были завершены ранее. Checkpoint 03.10.2026 зафиксировал последний фактический workflow и остановил дальнейшую реализацию KB до сверки с нормативным DB-04/DB-05.

Последний фактический workflow Павла сохранён в очищенном виде как точный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Внутри — gzip+base64 части и `MANIFEST.md`; восстановление в обычный import-ready JSON выполняет `tools/restore_workflow_checkpoint.py`. Старый canonical workflow v0.2 удалён из текущего дерева, чтобы его не принять за актуальный. История остаётся в Git.

03.10.2026 в test schema была экспериментально применена часть KB-01 (таблицы + B1/B2). Runtime B1/B2 проверен служебной ролью, но после сверки обнаружено расхождение с нормативным DB-04/DB-05. Поэтому ранее сгенерированный KB workflow в n8n **не импортируется**, B3 остановлен, а текущая задача — [KB-01R](docs/KB-01_RECONCILIATION_PLAN.md).

Supabase один. Компании используют разные schema одной PostgreSQL. Production, рабочий трафик и production schema/roles не меняются без отдельного разрешения Павла.

## С чего начинает новая сессия

1. [Инструкция ChatGPT](docs/CHATGPT_INSTRUCTIONS.md).
2. [Текущее состояние](docs/PROJECT_STATE.md).
3. [Активный план KB-01R](docs/KB-01_RECONCILIATION_PLAN.md) и при необходимости [общий план](docs/WORKPLAN_TEMPLATE.md).
4. [Правила передачи](docs/SESSION_HANDOFF.md).
5. Только документы, необходимые для одной выбранной задачи.

Одна задача — одна сессия — один проверяемый результат. GitHub хранит файлы и подтверждения; факт наличия файла не означает, что он применён на сервере.

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
| Текущая сверка KB | [KB-01R](docs/KB-01_RECONCILIATION_PLAN.md), [evidence](docs/KB-01_APPLIED_TEST_STATE_2026-10-03.md) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты и дампы БД в этот публичный репозиторий не загружаются.
