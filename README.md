# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены ранее. Нормативные DB-04/DB-05 после KB-01R4/R5 существуют в test и runtime-проверены для текущего bot/service контура. Старые `[ ] DB-04/DB-05` в `WORKPLAN_TEMPLATE.md` — отставшая сводная отметка.

Текущая работа — канонический knowledge workflow поверх полного фактического workflow, без отдельного skeleton.

## Канонический workflow

Фактическая основа: export Павла `(7)`, более свежий, чем checkpoint 03.10.2026 из `(6)`.

KB-01A реализован в полном workflow:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

После runtime-проверки исправлен финальный Telegram-ответ: динамические значения HTML-экранируются, Telegram node использует `parse_mode=HTML`.

Текущий канонический checkpoint:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

`python tools/restore_workflow_checkpoint.py` восстанавливает полный import-ready JSON с SHA-256:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Предыдущие checkpoints 03.10 и 04.10 сохранены для истории. Runtime whitelist и Credential refs в Git не сохраняются.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A закрыт и runtime-проверен 05.10.2026.** Подтверждено: private `.md` от разрешённого user/chat, durable service event, фактическое скачивание, DB registration `uspeshno`, non-null `zagruzka_id`/`zadanie_id`, `status_zagruzki=poluchena` и успешное Telegram-подтверждение для имени файла с `_`.

Следующий ID: **KB-01B** — claim durable knowledge job с lease/fencing, безопасный parse YAML/Markdown, проверка metadata/структуры, canonical hash/processing fingerprint и `podgotovit_versiyu_znaniy`.

PRE-02E отдельно не тестируется: OpenAI document embeddings `text-embedding-3-large`, `dimensions=1024` будут встроены и runtime-проверены внутри канонического workflow на `KB-03A`.

## С чего начинает новая сессия

1. [Инструкция ChatGPT](docs/CHATGPT_INSTRUCTIONS.md).
2. [Текущее состояние](docs/PROJECT_STATE.md).
3. [Активный план KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).
4. [Передача](docs/SESSION_HANDOFF.md).
5. Только спецификации, необходимые текущему ID.

Одна небольшая задача — одна сессия. Наличие JSON или SQL в Git не означает само по себе, что он импортирован, применён на сервере или runtime-проверен.

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
| Runtime evidence KB-01A | [KB-01A evidence](docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md) |
| Завершённая сверка DB-04/DB-05 | [KB-01R](docs/KB-01_RECONCILIATION_PLAN.md), [evidence](docs/evidence/KB-01/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты, Credential refs и дампы БД в публичный репозиторий не загружаются.
