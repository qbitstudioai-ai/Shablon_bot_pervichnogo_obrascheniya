# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены. Нормативные DB-04/DB-05 после KB-01R4/R5 существуют в test и runtime-проверены для текущего bot/service контура.

Текущая работа — канонический knowledge workflow.

## Канонические workflow

Текущая repository-safe основа хранится раздельно:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — intake/очередь/обработка документов и knowledge pipeline;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот, поиск знаний и ответы.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Исторический восстановимый checkpoint KB-01A остаётся в:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Старые checkpoints — история и evidence, а не текущая версия для импорта.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0 и KB-03B1 закрыты и runtime-проверены.**

KB-03B1 runtime 08.10.2026 подтвердил:
- 53 fragments;
- 9 canonical YAML reference questions;
- один OpenAI batch для 9 exact question texts;
- `text-embedding-3-large`, 1024, float, finite/index mapping OK;
- draft-only/version-scoped/profile-scoped top-12;
- factual threshold grid 0.45..0.85;
- полный positive pass 9/9 на 0.60;
- `status_versii=gotova`;
- `publish=false`.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

Текущий ID: **KB-03C** — atomic publish + stale-conflict protection + active-only end-to-end regression. KB-03C не считается начатым только из-за наличия его в плане; реализацию выполнять отдельной маленькой задачей.

## Guard по нагрузке на LLM

Рост базы знаний не должен линейно увеличивать prompt клиентской LLM. Клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM. Текущий retrieval profile: candidate top-k 12, evidence максимум 8 fragments и обычно меньше. Отдельный LLM reranker в v1 не добавляется без доказанной пользы.

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
| Runtime evidence | [docs/evidence](docs/evidence/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты, Credential refs и дампы БД в публичный репозиторий не загружаются.