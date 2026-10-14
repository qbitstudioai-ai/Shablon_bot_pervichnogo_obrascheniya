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

Evidence: `docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## Активная задача

Родитель: **WF-02B3C** — controlled TEST runtime event-driven topology без постоянного polling.

Малый план: [WF-02B3C E2E](docs/WF-02B3C_E2E_PLAN.md).

Закрыты runtime:
- **WF-02B3C-E2E-01** — client → guard → RAG → grounded Telegram answer;
- **WF-02B3C-E2E-02A** — human-needed → служебная тема/сигнал;
- **WF-02B3C-E2E-02B** — atomic Take + bot stop + ручной ответ менеджера;
- **WF-02B3C-E2E-02C** — private manager alerts + работа менеджера только через forum topic.

Актуальная операторская модель: private chat служебного бота используется для важных уведомлений, рабочая переписка менеджера идёт только в общей теме клиента; обязательного completion и Return сейчас нет.

Следующий один ID: **WF-02B3C-E2E-03A** — confirmed outbound → ожидание ответа → reminder lifecycle. Нужно доказать, что reminder создаётся только после подтверждённой отправки сообщения, требующего ответа, новый client input отменяет ожидание, а Wait wake делает final DB recheck и не отправляет устаревший reminder.

TEST-only utility `sql/Сбросить забранные диалоги.sql` v0.3 позволяет вручную вернуть захваченные TEST-диалоги конкретного менеджера в `bot/aktivnyy` без удаления истории. Реальные Telegram ID в Git не сохраняются.

Основной широкий план: [WORKPLAN_TEMPLATE](docs/WORKPLAN_TEMPLATE.md).
Перед новой сессией также прочитать [PROJECT_STATE](docs/PROJECT_STATE.md) и [SESSION_HANDOFF](docs/SESSION_HANDOFF.md).

## Guard по нагрузке на LLM

Рост базы знаний не должен линейно увеличивать prompt клиентской LLM. Клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM. Текущий retrieval profile: candidate top-k 12, evidence максимум 8 fragments и обычно меньше. Отдельный LLM reranker в v1 не добавляется без доказанной пользы.

## С чего начинает новая сессия

1. [Инструкция ChatGPT](docs/CHATGPT_INSTRUCTIONS.md).
2. [Текущее состояние](docs/PROJECT_STATE.md).
3. [WF-02B3C E2E plan](docs/WF-02B3C_E2E_PLAN.md).
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