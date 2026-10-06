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

`python tools/restore_workflow_checkpoint.py` восстанавливает этот checkpoint с SHA-256:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — **v0.7.1 KB-01B2**, SHA-256 `e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`. Отдельный Git-checkpoint v0.7.1 ещё не сохранён. Credential refs, runtime whitelist и реальные Telegram ID в Git не сохраняются.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A, KB-01B1 и KB-01B2 закрыты и runtime-проверены.**

KB-01B2 создал реальный test draft version `chernovik` через normative `podgotovit_versiyu_znaniy`, зафиксировав profile/fingerprints. Публикации и embeddings ещё нет.

Следующий ID: **KB-02A** — собственный детерминированный структурно-смысловой chunker. Смысловые/структурные границы первичны; token budget `600/800/100` используется только как ограничение размера. Точный runtime `cl100k_base` count должен быть доказан до сохранения fragments.

PRE-02E отдельно не тестируется: OpenAI document embeddings `text-embedding-3-large`, `dimensions=1024` будут встроены и runtime-проверены в KB-03A.

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
| Runtime evidence KB-01 | [evidence](docs/evidence/KB-01/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты, Credential refs и дампы БД в публичный репозиторий не загружаются.
