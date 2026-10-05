# SESSION HANDOFF

Обновлено: 2026-10-05.

## Исходная точка

Рабочая ветка: `main`.

KB-01A завершён и runtime-проверен. Перед следующей задачей проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. для KB-01B — нужные части `docs/specs/KNOWLEDGE_INGESTION.md`, `docs/specs/MARKDOWN_FORMAT.md`, `docs/specs/DB_CONTRACT.md`.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Текущий runtime-verified checkpoint:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

Ожидаемый SHA-256:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Restore создаёт:

`workflows/Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

Не пересобирать workflow с нуля.

Канонический JSON очищен:
- `active=false`;
- Credential refs отсутствуют;
- runtime whitelist пустой;
- реальные Telegram ID не сохранены;
- service group ID отсутствует.

## KB-01A — доказанный runtime

05.10.2026:
- workflow импортирован в n8n;
- существующие service Telegram/Postgres Credentials назначены в UI;
- runtime whitelist настроен в UI;
- ordinary service text продолжил проходить ingress;
- private `.md` дошёл до DB-04 registration;
- DB вернула `uspeshno`, non-null `zagruzka_id`, non-null `zadanie_id`, `status_zagruzki=poluchena`;
- первый Telegram report выявил Markdown entity error из-за `_` в filename после успешной DB registration;
- formatter исправлен HTML escaping, Telegram node переведён на `parse_mode=HTML`;
- второй safe `.md` с `_` в filename дал успешную DB registration и успешный Telegram report.

Evidence:
`docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

Парсинг/chunking/embedding/check/publish не входят в KB-01A.

## DB-04 / DB-05

Нормативные DB-04/DB-05 уже существуют в test и runtime-проверены для bot/service. Не ориентироваться на старые `[ ]` в `WORKPLAN_TEMPLATE.md`.

`KB-01R5D` dash_admin revoke отложен до dashboard stage.

## Следующая задача — KB-01B

Одна сессия = одна маленькая задача.

Цель KB-01B:
- claim durable knowledge job через lease/fencing;
- безопасный YAML/Markdown parser;
- validate required metadata и heading structure;
- canonical content hash + processing/profile fingerprints;
- `podgotovit_versiyu_znaniy`;
- active duplicate stop.

Критерий закрытия: один safe `.md` из уже зарегистрированной очереди проходит claim/parse/validation до подготовленного draft version либо корректно получает documented rejection; lease/fencing и duplicate path не нарушаются.

Не начинать KB-02A до runtime KB-01B.

## PRE-02E

Отдельный smoke не запускать. OpenAI document embedding `text-embedding-3-large`, `dimensions=1024` будет добавлен и runtime-проверен на `KB-03A`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
