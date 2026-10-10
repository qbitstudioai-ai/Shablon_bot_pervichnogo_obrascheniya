# KB-03C — план публикации знаний

Обновлено: 2026-10-10.

Родительская задача: `KB-03C` из `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

## Исходная точка

KB-03B1 был закрыт runtime: 53 fragments, 9/9 canonical checks, `status_versii=gotova`, publish=false.

Текущий repository-safe workflow документов:
`workflows/current/Шаблон Загрузка документов Qbit.json`.

Workflow бота использует `poisk_aktivnyh_znaniy`.

Нормативный DB-05 contract:
- publish разрешён только готовой version;
- `opublikovat_versiyu_znaniy` проверяет fragments/vectors/checks;
- success атомарно меняет active pointer, новую version → `opublikovana`, прежнюю active → `arhiv`, upload → `zavershena`, knowledge job → `zaversheno`;
- stale expected-active даёт `konflikt / stale_expected_active`;
- `poisk_aktivnyh_znaniy` видит только active published version.

## [x] KB-03C1 — publish branch prepared / static verified

Repository-safe workflow документов дополнен безопасной publish-веткой без server execution.

Read-only preflight TEST version подтвердил:
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5` = `gotova`;
- 53 fragments, bad dimensions = 0;
- 9/9 latest checks successful;
- expected active NULL и current active NULL;
- service execute publish = true;
- bot execute publish = false;
- итог `READY_FOR_KB03C1_WORKFLOW_PREP`.

В workflow добавлены resume gate, publish gate, trusted expected-active context, service publish call, DB-success validation, stale/conflict fail-closed path и terminal success только после `opublikovana/zavershena`.

Static verification:
- JSON valid;
- 67 nodes, 9 C1/publish nodes;
- duplicate names/IDs = 0;
- dangling connections = 0;
- 21 Code-node syntax checks PASS;
- workflow inactive;
- Credential bindings/secrets absent.

Evidence:
`docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

## [x] KB-03C2 — TEST runtime atomic publish + active-only regression

### Runtime preparation

- C1 workflow импортирован как отдельная inactive TEST-копия, старый workflow не перезаписан;
- runtime copy получила существующие Credentials только внутри n8n; repository-safe JSON не менял policy по secrets/Credential refs;
- перед mutating publish exact target queue проверен read-only;
- два старых retry jobs, стоявших перед target, были отменены только exact-guarded one-shot worker path; массовой очистки не было;
- после этого next claim стал exact target.

### Atomic publish PASS

Target:
- job `91de6175-da91-471a-be7a-97feffb646a3`;
- upload `328035d0-6fd7-4af3-83a3-2643a8b24d2f`;
- document `2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5`.

DB publish output:
- `rezultat=uspeshno`;
- `predydushchaya_aktivnaya_versiya_id=NULL`;
- `status_versii=opublikovana`;
- `status_zagruzki=zavershena`.

Workflow validation:
- `kb03c_publish_success=true`;
- `kb03c_stale_conflict=false`;
- `publish_vypolnen=true`;
- next stage=`KB-03C2_active_only_regression`.

Terminal result: `kb03c_status=opublikovana`.

### Post-publish state PASS

Read-only verification `KB-03C2_POST_PUBLISH_READ_ONLY_v0.1`:
- document active pointer = exact target version;
- version=`opublikovana`;
- upload=`zavershena`;
- job=`zaversheno`;
- lease owner/deadline=NULL;
- fragments=53;
- published versions for document=1;
- result `KB03C2_POST_PUBLISH_OK`.

### Bot active-only regression PASS

Preflight:
- profile=`text-embedding-3-large/1024/cosine`;
- `qbit_test_bot` can EXECUTE `poisk_aktivnyh_znaniy(jsonb)`;
- `qbit_test_bot` cannot direct SELECT `fragmenty_znaniy`.

Credential diagnostic first exposed accidental service-role selection; DB grants were not changed. With the correct bot connection:
- `current_user=qbit_test_bot`;
- EXECUTE active search=true;
- direct fragment SELECT=false;
- diagnostic result `BOT_CREDENTIAL_OK`.

Active search result `KB-03C2_BOT_ACTIVE_SEARCH_v0.1`:
- `executed_as=qbit_test_bot`;
- results=12;
- target-version results=12;
- other-version results=0;
- known old draft results=0;
- max similarity=`0.793885026323472`;
- result `KB03C2_BOT_ACTIVE_ONLY_OK`.

### Stale expected-active criterion

На current target искусственный stale call не выполнялся: same-active published target в DB function возвращает idempotent `dublikat` до stale comparison, поэтому такой повтор не проверил бы concurrency guard.

Сам DB-05 optimistic-concurrency path уже runtime-проверен ранее на реальном service Credential в `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`: competing ready V3 после публикации V2 вернула `rezultat=konflikt`, `kod_oshibki=stale_expected_active`, active pointer остался на V2. C1 current-workflow stale routing отдельно static verified.

Повторную мутацию реального target только ради дублирования уже доказанного DB guard не делали.

### Rollback

До publish был подтверждён поддерживаемый API `otozvat_dokument_znaniy(jsonb)`. Прямой DML не используется.

Rollback не понадобился. Для текущего first-active case revoke означал бы active pointer → NULL и version → `arhiv`; это publication-visibility rollback, а не полное восстановление job/upload state.

### Evidence

`docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## Итог KB-03C

KB-03C1 static + KB-03C2 runtime закрыты. Atomic publish, committed post-state и bot active-only search подтверждены на TEST. Optimistic concurrency/stale protection подтверждён комбинацией ранее runtime-проверенного DB-05 path и current workflow static stale handling.

Production и рабочий трафик не затронуты.
