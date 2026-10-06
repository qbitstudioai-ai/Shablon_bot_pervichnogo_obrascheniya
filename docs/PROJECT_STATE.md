# Текущее состояние проекта

Обновлено: 2026-10-06.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Фактическая основа workflow — export Павла `(7)`. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Текущий сохранённый runtime-verified checkpoint Git остаётся:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

SHA-256 восстановленного import-ready JSON:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Канонический JSON остаётся `active=false`, без Credential refs и с пустыми whitelist-массивами. Реальные Telegram ID в Git не сохраняются.

Для KB-01B1 был подготовлен и реально запущен полный v0.5 KB-01B1 поверх точного runtime-verified v0.4. SHA-256 import JSON: `12430374e26711a32067d096884c4672dda061861e3f27030c38711829ed56f9`. Этот v0.5 runtime-проверен, но отдельный Git checkpoint для него ещё не сохранён; не путать runtime evidence с наличием checkpoint-файла в репозитории.

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
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

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

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — CLOSED / runtime verified

06.10.2026 на test-контуре:
1. isolated Manual Trigger успешно claim-нул существующее durable knowledge job через `zabrat_zadanie_znaniy`;
2. DB вернула live `zadanie_id=0032a78e-b3fa-4cc8-8175-fcc52b53dd64`, `zagruzka_id=2d94322c-0347-48ce-8c66-e136e79d54d4`, worker `qbit_test_kb_worker_v1`, fence `1`;
3. bytea фактически читается в n8n в Buffer-совместимом формате;
4. parser `kb01b1_safe_frontmatter_markdown_v1` вернул `valid=true`, `kod=provereno`;
5. извлечены документированные metadata, 57 структурных заголовков и 8 контрольных вопросов;
6. warnings отсутствуют;
7. canonical `hash_soderzhaniya=73436107b06ed1465094f23f785dadbb973adc787e049c04966195ae629e2290`;
8. те же фактические bytes повторно прогнаны через тот же parser вне n8n и дали тот же hash, 57 headings и 8 questions;
9. `zavershit_zadanie_znaniy` с теми же worker/fence вернула `uspeshno`; job освобождён в `status_zadaniya=povtor`.

Предварительный до-runtime ориентир `be8f4f8d...` был ошибочным и больше не используется.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

KB-01B1 не создаёт draft version и не выполняет tokenizer/chunking/embeddings/search/publish.

## Следующая маленькая задача

`KB-01B2`.

Критерий: доказать фактически доступный processing/index profile и tokenizer в self-hosted n8n, вычислить `otpechatok_profilya` + `otpechatok_obrabotki`, вызвать `podgotovit_versiyu_znaniy` под live lease/fencing, проверить duplicate stop или создание `chernovik` и корректное состояние fenced job.

Не начинать `KB-02A` до runtime-проверки KB-01B2.

## Постоянные ограничения

- Production не менять.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
