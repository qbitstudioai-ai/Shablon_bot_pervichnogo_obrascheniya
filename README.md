# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация test-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены. Нормативные DB-04/DB-05 после KB-01R4/R5 существуют в test и runtime-проверены для текущего bot/service контура.

Текущая работа — канонический knowledge workflow поверх полного фактического workflow.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

`python tools/restore_workflow_checkpoint.py` восстанавливает этот старый checkpoint с SHA-256:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**, SHA-256:
`54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`.

Отдельный Git-checkpoint v0.11 ещё не сохранён. Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` не импортировать.

## Активная задача

Активный план: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B и KB-03A закрыты и runtime-проверены.**

Что уже доказано:
- безопасный `.md` intake и durable knowledge job;
- safe YAML/Markdown parser и deterministic content hash;
- draft version/profile/fingerprints;
- структурно-смысловой chunking;
- exact `cl100k_base` token count;
- final fragment records с exact text/hash/token count/order/trace;
- отдельные YAML reference questions, не входящие в retrieval text;
- document embeddings OpenAI `text-embedding-3-large/1024/float`;
- strict vector validation и нормативный DB save fragments/vectors;
- ingestion/chunking этапы не используют generative LLM.

Текущий ID: **KB-03B** — сохранить canonical reference questions, векторизовать их тем же OpenAI profile, выполнить draft-only search по конкретной версии и сохранить проверки. Только полный pass всех контрольных вопросов может перевести version в `gotova`.

Publish относится к KB-03C.

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
