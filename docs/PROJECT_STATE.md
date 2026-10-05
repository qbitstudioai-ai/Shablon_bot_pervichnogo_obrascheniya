# Текущее состояние проекта

Обновлено: 2026-10-05.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Исходный HEAD перед runtime-закрытием KB-01A: `9903df6afd7de00d3873ad70bffa598498841526` (`feat: save KB-01A workflow checkpoint`).

Фактическая основа workflow — export Павла `(7)`. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

После runtime-проверки KB-01A канонический v0.4 дополнен только исправлением Telegram presentation-layer:
- dynamic filename/error text HTML-escaped (`&`, `<`, `>`);
- `KB-01A Ответить про загрузку знаний` использует `parse_mode=HTML`.

Текущий checkpoint:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

SHA-256 восстановленного import-ready JSON:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Канонический JSON остаётся `active=false`, без Credential refs и с пустыми whitelist-массивами. Реальные Telegram ID в Git не сохраняются.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test по KB-01R4/R5 для текущего bot/service контура:
- ingestion upload + durable knowledge queue, lease/fencing/idempotency/conflict;
- canonical version/profile/fragments/reference checks;
- `vector(1024)` и dimension/profile guards;
- draft-only service search;
- atomic publish со stale conflict;
- active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

Старые `[ ] DB-04/DB-05` в `WORKPLAN_TEMPLATE.md` не отражают фактическое состояние.

## PRE-02E

Отдельного PRE-02E smoke нет. OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` и строгая проверка длины document vector закрываются внутри `KB-03A`.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B` → `KB-02A` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## KB-01A — CLOSED / runtime verified

05.10.2026 на test-контуре подтверждено:
1. существующий service Telegram webhook принимает private `.md`;
2. DB-03D1 durable service event остаётся до knowledge branch;
3. private chat + runtime whitelist + `.md` + declared size проверяются;
4. файл скачивается служебным Telegram Credential;
5. фактические bytes и лимит 5 MiB проверяются;
6. `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)` вернула `rezultat=uspeshno`;
7. получены non-null `zagruzka_id` и `zadanie_id`;
8. `status_zagruzki=poluchena`;
9. после исправления `parse_mode=HTML` Telegram успешно подтвердил постановку файла с `_` в имени в очередь;
10. обычные служебные текстовые сообщения до и во время проверки продолжили проходить существующий service ingress.

Первый real `.md` выявил только Telegram formatting issue после успешной DB registration; DB результат не откатился. Второй безопасный `.md` подтвердил исправление.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

KB-01A не включает YAML/Markdown parse, canonical hash, chunking, document embeddings, checks или publish.

## Следующая маленькая задача

`KB-01B`.

Критерий: knowledge worker забирает durable job через lease/fencing, безопасно разбирает YAML/Markdown, валидирует обязательные metadata и структуру, рассчитывает canonical content hash + processing/profile fingerprints и вызывает `podgotovit_versiyu_znaniy`. Дубль активной версии не должен идти дальше.

Не начинать `KB-02A` до runtime-проверки KB-01B.

## Постоянные ограничения

- Production не менять.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
