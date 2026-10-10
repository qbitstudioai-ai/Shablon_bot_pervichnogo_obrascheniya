# KB-03C2 — runtime verification evidence — 2026-10-10

Статус: **TEST atomic publish + committed post-state + bot active-only search runtime verified**.

## Контур

- schema: `qbit_bot_pervichnogo_obrascheniya`;
- n8n: `2.41.0 (Self Hosted)`;
- service PostgreSQL role: `qbit_test_sluzhebnyy`;
- bot PostgreSQL role: `qbit_test_bot`;
- OpenAI embedding profile used by bot-search probe: `text-embedding-3-large`, dimensions 1024;
- production schema/traffic не менялись;
- repository-safe workflow не получил Credential refs или secrets.

Исходный Git HEAD перед закрывающей документацией:
`f37c05497dabcab9395636ffd371c1d0e21c6124`.

## Target

- job: `91de6175-da91-471a-be7a-97feffb646a3`;
- upload: `328035d0-6fd7-4af3-83a3-2643a8b24d2f`;
- document: `2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- logical document identifier: `qbit_klientskaya_baza_znaniy`;
- version: `1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- pre-publish version status: `gotova`;
- pre-publish expected active: NULL;
- pre-publish current active: NULL.

## Queue safety before publish

Read-only next-claim probes showed two older due TEST retry jobs before the target. Каждый был retired отдельно через exact-guarded one-shot workflow, который:
- штатно claim-ил только next job;
- жёстко сверял exact job ID и ожидаемое имя файла;
- завершал только совпавший job как `otmeneno`;
- при несовпадении падал до cancel path.

После двух guarded retire операций read-only queue probe вернул exact target как `poryadok_claim=1` и `READY_TO_EXECUTE_KB03C2`.

Массовой очистки очереди и direct DML не было.

## Atomic publish runtime

Current C1 TEST-copy была запущена один раз по manual worker path.

`Служебный_KB_Опубликовать версию` вернул:
- operation `kb:worker:c1-publish:91de6175-da91-471a-be7a-97feffb646a3:2`;
- `rezultat=uspeshno`;
- `kod_oshibki=NULL`;
- document=target;
- version=target;
- `predydushchaya_aktivnaya_versiya_id=NULL`;
- `status_versii=opublikovana`;
- `status_zagruzki=zavershena`.

Workflow result validation:
- `kb03c_publish_success=true`;
- `kb03c_stale_conflict=false`;
- `kb03c_kod=kb03c_opublikovana`;
- `publish_vypolnen=true`.

Terminal `KB-03C1 Итог публикации`:
- `kb03c_status=opublikovana`;
- `rezultat=uspeshno`;
- target document/version retained;
- upload=`zavershena`;
- `publish_vypolnen=true`;
- `next_stage=KB-03C2_active_only_regression`.

Successful publish did not call a second finish-job API; DB publish function itself completed the knowledge job by contract.

## Committed post-state

Read-only probe `KB-03C2_POST_PUBLISH_READ_ONLY_v0.1` returned:
- document active pointer=`1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- version status=`opublikovana`;
- upload status=`zavershena`;
- job status=`zaversheno`;
- attempts=2;
- lease owner=NULL;
- lease deadline=NULL;
- fragments=53;
- published versions for document=1;
- result `KB03C2_POST_PUBLISH_OK`.

## Bot privilege boundary

Read-only preflight for target profile:
- profile id `8699918a-59b0-40c1-b3f4-99ca4c31df63`;
- model=`text-embedding-3-large`;
- dimensions=1024;
- metric=`cosine`;
- `qbit_test_bot` function EXECUTE=true;
- direct SELECT on `fragmenty_znaniy`=false;
- result `READY_FOR_BOT_ACTIVE_SEARCH`.

Первый active-search attempt завершился `permission denied` потому, что в n8n был ошибочно выбран service connection. Diagnostic workflow показал `current_user=qbit_test_sluzhebnyy`, active-search EXECUTE=false. Права БД не менялись.

После выбора правильного bot connection diagnostic вернул:
- `current_user=qbit_test_bot`;
- `session_user=qbit_test_bot`;
- active-search EXECUTE=true;
- direct fragments SELECT=false;
- `BOT_CREDENTIAL_OK`.

Это подтвердило и routing Credentials, и intended privilege split.

## Bot active-only runtime regression

Probe `KB-03C2_BOT_ACTIVE_SEARCH_v0.1` был выполнен с реальным `qbit_test_bot` connection.

Фактический результат:
- `executed_as=qbit_test_bot`;
- results=12;
- target-version results=12;
- non-target results=0;
- known old-draft results=0;
- max similarity=`0.793885026323472`;
- found versions array содержит только target version;
- `kod_oshibki=NULL`;
- result `KB03C2_BOT_ACTIVE_ONLY_OK`.

Следовательно, client active-only path после реальной публикации видит target published version и не смешивает известные старые draft versions.

## Stale expected-active protection

Current target не использовался для искусственного stale call после публикации. Причина: в фактическом DB contract same-current published version сначала возвращает idempotent `dublikat`, поэтому такой вызов не проверяет stale branch.

Optimistic concurrency уже runtime-проверен отдельно через фактическую service role в:
`docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`.

Там competing ready V2/V3 имели одну expected active V1; после успешной публикации V2 попытка V3 вернула:
- `rezultat=konflikt`;
- `kod_oshibki=stale_expected_active`;
- active version осталась корректной.

Current KB-03C1 workflow routing для stale/conflict также static verified в:
`docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

Таким образом DB stale guard доказан runtime, а current workflow handler — static; повторно мутировать реальный target ради дублирования уже проверенного guard не требовалось.

## Rollback

До mutating publish был подтверждён supported DB-05 API:
`otozvat_dokument_znaniy(jsonb)`.

Для этого first-active target безопасный publication-visibility rollback означал бы:
- document active pointer → NULL;
- current version → `arhiv`.

Rollback не является полным rewind исторических job/upload statuses. Direct DML для rollback не используется.

Rollback в KB-03C2 не выполнялся, потому что publish и post-state regression прошли успешно.

## Вывод

KB-03C2 закрыт как runtime verified:
- exact TEST target published atomically;
- committed DB state verified read-only;
- target job closed and lease cleared;
- bot role privilege split verified;
- real bot active-only search returned only target published version;
- stale concurrency guard covered existing DB runtime evidence + current workflow static handling;
- production и рабочий трафик не затронуты.
