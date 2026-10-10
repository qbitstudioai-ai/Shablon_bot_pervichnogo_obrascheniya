# Шаблон бота первичного обращения

Шаблон для быстрого внедрения бота, базы знаний и дашборда в новую компанию. При обычном внедрении меняются настройки компании и подключения; общая логика не переписывается.

## Статус и границы

Реализация TEST-контура разрешена. Production, рабочий трафик и рабочие данные не меняются без отдельного явного разрешения Павла.

DB-01, DB-02, DB-03/DB-03E и canonical schema `qbit_bot_pervichnogo_obrascheniya` завершены. Нормативные DB-04/DB-05 существуют в TEST и runtime-проверены для текущего bot/service контура.

Канонический knowledge workflow закрыт по плану KB-WF вплоть до KB-03C2: реальная TEST-version опубликована, active pointer подтверждён, клиентский поиск под `qbit_test_bot` видит только active published version.

## Канонические workflow

Текущая repository-safe основа хранится раздельно:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — intake/очередь/обработка документов и publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот, поиск знаний и ответы.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Исторический восстановимый checkpoint KB-01A остаётся в:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Старые checkpoints — история и evidence, а не текущая версия для импорта.

## Завершённый knowledge-блок

План: [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md).

**KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1, KB-03C1 и KB-03C2 закрыты.**

KB-03C2 runtime 10.10.2026 подтвердил:
- atomic TEST publish target version `1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- version=`opublikovana`, upload=`zavershena`, job=`zaversheno`;
- active pointer указывает на exact target version;
- 53 fragments и одна published version у logical document;
- поиск выполнен реально под `qbit_test_bot`;
- 12/12 найденных результатов относятся только к target version;
- старые draft versions в active-only поиск не попали;
- direct table SELECT у bot role отсутствует.

Evidence: `docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## Активная задача

Следующий небольшой ID по широкому плану: **WF-02B3C** — controlled TEST runtime import/smoke event-driven topology без постоянного polling.

Основной план: [WORKPLAN_TEMPLATE](docs/WORKPLAN_TEMPLATE.md).
Перед новой сессией также прочитать [WF-02B3 smoke checks](docs/WF-02B3_SMOKE_CHECKS.md) и актуальный [PROJECT_STATE](docs/PROJECT_STATE.md).

WF-02B3C в этой сессии не начинался.

## Guard по нагрузке на LLM

Рост базы знаний не должен линейно увеличивать prompt клиентской LLM. Клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM. Текущий retrieval profile: candidate top-k 12, evidence максимум 8 fragments и обычно меньше. Отдельный LLM reranker в v1 не добавляется без доказанной пользы.

## С чего начинает новая сессия

1. [Инструкция ChatGPT](docs/CHATGPT_INSTRUCTIONS.md).
2. [Текущее состояние](docs/PROJECT_STATE.md).
3. [Основной план](docs/WORKPLAN_TEMPLATE.md).
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
| Завершённая реализация knowledge workflow | [KB-WF](docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md) |
| Runtime evidence | [docs/evidence](docs/evidence/) |
| Передача между сессиями | [SESSION_HANDOFF](docs/SESSION_HANDOFF.md) |

Реальные документы компаний, переписки, секреты, Credential refs и дампы БД в публичный репозиторий не загружаются.
