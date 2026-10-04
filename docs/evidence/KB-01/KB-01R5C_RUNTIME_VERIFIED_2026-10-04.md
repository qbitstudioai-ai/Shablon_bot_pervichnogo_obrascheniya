# KB-01R5C — runtime verification evidence — 2026-10-04

Статус: **publish/active-search runtime verified; synthetic rows cleaned; dash_admin runtime leg deferred**.

## Контур

- schema: `qbit_bot_pervichnogo_obrascheniya`;
- service Credential: `qbit_test_sluzhebnyy`;
- bot Credential: `qbit_test_bot`;
- n8n: `2.41.0 (Self Hosted)`;
- Postgres node: `2.7`;
- production schema `qbit` не изменялась;
- реальная база знаний компании не использовалась;
- OpenAI embeddings не использовались.

## Почему проверка была разбита на отдельные executions

Ранний probe v0.2 пытался сделать два успешных active-version switch внутри одной SQL transaction. Deferred integrity check корректно проверяет финальное состояние, поэтому такой искусственный сценарий не моделирует нормальный n8n runtime. Финальная проверка выполнялась отдельными committed executions: один успешный switch на транзакцию.

`sql/KB-01R5C_service_publish_prepare.sql` поэтому помечен `OBSOLETE_DO_NOT_RUN`.

## Phase 1 — первая публикация

Через фактический `qbit_test_sluzhebnyy`:

- probe: `KB-01R5C_PHASE1_v0.1`;
- status: `v1_published`;
- logical document: `kb01r5c_probe_20261004`;
- V1 была успешно опубликована отдельной транзакцией.

## Phase 2A — competing ready versions

Через фактический `qbit_test_sluzhebnyy`:

- probe: `KB-01R5C_PHASE2A_v0.1`;
- status: `v2_v3_ready`;
- V2 и V3 подготовлены как `gotova` при одной и той же ожидаемой active V1.

## Phase 2B — publish V2 + stale V3

Через фактический `qbit_test_sluzhebnyy`:

- probe: `KB-01R5C_PHASE2B_v0.1`;
- status: `v2_published_v3_stale`;
- V2 стала active published version;
- V1 стала предыдущей/архивной;
- попытка публикации V3 со stale expected-active вернула:
  - `rezultat=konflikt`;
  - `kod_oshibki=stale_expected_active`.

Это подтверждает optimistic concurrency и атомарное переключение active version в обычной runtime-модели с отдельными транзакциями.

## Bot active-only search

Через фактический Credential `qbit_test_bot` выполнен `KB-01R5C_BOT_v0.2`.

Фактический PASS:

- `status=verified`;
- `session_user=qbit_test_bot`;
- `active_v2_found=true`;
- `archived_v1_hidden=true`;
- `unpublished_v3_hidden=true`;
- `draft_search_denied=true`.

Подтверждено, что client search видит только active published version; архивная V1 и ready-but-unpublished V3 не попадают в результат; bot role не может использовать draft-search API.

## dash_admin

В ходе R5C выяснилось, что отдельный n8n Credential `qbit_test_dash_admin` фактически не создан. В n8n сейчас есть только bot и service Credentials. Попытка запуска dash probe с bot Credential была остановлена собственным guard до вызова revoke API (`session_user=qbit_test_bot`), поэтому состояние KB не изменилось.

Структурная EXECUTE matrix для `qbit_test_dash_admin` уже проверена в KB-01R4, но **runtime revoke через реальный dash_admin connection не проверялся**. Этот leg вынесен в отдельную будущую задачу `KB-01R5D` на этапе подключения dashboard; создавать третий n8n Credential только ради текущего теста не требуется.

## Guarded cleanup

После runtime-проверок синтетические rows были удалены в trusted Supabase SQL Editor.

Фактический результат:

`KB-01R5C_CLEANUP_v0.3 status=cleaned`

Удалено:

- versions: 3;
- uploads: 3;
- jobs: 3;
- events: 3;
- fragments: 3;
- questions: 9;
- checks: 9.

`production_untouched_informational=true`.

## Вывод

R5C подтверждает publish concurrency protection, atomic active switch и bot active-only search на реальных service/bot Credentials. Синтетические данные очищены. Runtime revoke через dash_admin не объявляется проверенным и отдельно перенесён в `KB-01R5D` на dashboard stage.
