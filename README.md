# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены ранее. Нормативные DB-04/DB-05 после KB-01R4/R5 существуют в test и runtime-проверены для текущего bot/service контура.

Текущая работа — канонический knowledge workflow поверх полного фактического workflow.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git runtime-verified checkpoint пока:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

`python tools/restore_workflow_checkpoint.py` восстанавливает этот старый checkpoint с SHA-256:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — **v0.9.1 KB-02A2**, SHA-256 `5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`. Отдельный Git-checkpoint v0.9.1 ещё не сохранён. Credential refs, runtime whitelist и реальные Telegram ID в Git не сохраняются.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A, KB-01B1, KB-01B2, KB-02A1 и KB-02A2 закрыты и runtime-проверены.**

KB-02A2 доказал exact `cl100k_base` и структурно-смысловую упаковку: на большой safe Markdown-базе 130 structural blocks → 53 final candidates, диапазон 87–551 токен, среднее 237.1, превышений hard max 800 нет. LLM, embeddings и DB fragment save на этом этапе не выполнялись.

Текущий ID: **KB-02B** — превратить A2 candidates в окончательные fragment records (`nomer_fragmenta`, путь, точный текст, exact token count, hash и runtime trace) и отдельно подготовить 3–10 reference questions из проверенного YAML. Вопросы не входят в retrieval text/embeddings. Embeddings и `sohranit_fragmenty_znaniy` начинаются только в KB-03A.

PRE-02E отдельно не тестируется: OpenAI document embeddings `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` будут встроены и runtime-проверены в KB-03A.

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
| Runtime evidence KB-01/KB-02 | [evidence](docs/evidence/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты, Credential refs и дампы БД в публичный репозиторий не загружаются.
