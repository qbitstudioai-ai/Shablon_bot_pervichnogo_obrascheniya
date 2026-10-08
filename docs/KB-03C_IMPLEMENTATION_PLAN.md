# KB-03C — план публикации знаний

Обновлено: 2026-10-08.

Родительская задача: `KB-03C` из `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

## Исходная точка

KB-03B1 закрыт runtime: 53 fragments, 9/9 canonical checks, `status_versii=gotova`, publish=false.

Текущий workflow документов:
`workflows/current/Шаблон Загрузка документов Qbit.json`.

Workflow бота уже использует `poisk_aktivnyh_znaniy`; в KB-03C его меняем только если будущая runtime-проверка выявит реальный дефект.

Нормативный DB-05 contract:
- publish разрешён только готовой version;
- `opublikovat_versiyu_znaniy` проверяет fragments/vectors/checks;
- success атомарно меняет active pointer, новую version → `opublikovana`, прежнюю active → `arhiv`, upload → `zavershena`, knowledge job → `zaversheno`;
- stale expected-active даёт `konflikt / stale_expected_active`;
- `poisk_aktivnyh_znaniy` видит только active published version.

## [x] KB-03C1 — publish branch prepared / static verified

Цель выполнена: repository-safe workflow документов дополнен безопасной publish-веткой без импорта и без server execution.

Read-only preflight текущей TEST version подтвердил:
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5` = `gotova`;
- 53 fragments, bad dimensions = 0;
- 9/9 latest checks successful;
- expected active = NULL и current active = NULL;
- service execute publish = true;
- bot execute publish = false;
- итог `READY_FOR_KB03C1_WORKFLOW_PREP`.

В workflow добавлено:
1. resume gate для уже существующей `gotova`/`opublikovana` version;
2. gate после нового B1 full pass/`gotova`;
3. trusted publish context из DB outputs;
4. service Postgres call `opublikovat_versiyu_znaniy`;
5. явная проверка DB success;
6. отдельный stale/conflict/error fail-closed путь;
7. terminal success только после DB-confirmed `opublikovana` + `zavershena`.

Static verification:
- JSON валиден;
- 67 nodes, 9 новых C1/publish nodes;
- duplicate names/IDs = 0;
- dangling connections = 0;
- syntax 21 Code nodes PASS;
- workflow `active=false`;
- Credential bindings и token patterns отсутствуют.

Evidence:
`docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

Откат C1: Git revert/возврат к предыдущему workflow. Server state в C1 не менялся.

## [ ] KB-03C2 — TEST runtime atomic publish + active-only regression

### Условия начала

- KB-03C1 static verified;
- repository-safe JSON импортирован как отдельная **неактивная TEST-копия**, старый workflow не перезаписан;
- на нужных runtime-нодаx выбраны существующие service Postgres Credentials;
- перед mutating Execute Павел отдельно подтверждает конкретную TEST publication;
- production и рабочий трафик не затрагиваются.

### Подготовительный n8n шаг без публикации

После импорта новой TEST-копии для текущего resume-пути достаточно привязать service Postgres Credential `qbit_test_sluzhebnyy` как минимум к:
- `Служебный_KB_Забрать задание`;
- `Служебный_KB_Подготовить версию`;
- `Служебный_KB_Опубликовать версию`;
- `Служебный_KB_Завершить после ошибки публикации`.

Workflow не активировать и Execute до отдельного разрешения не нажимать.

### Runtime criterion

- нужный job/version захвачен;
- publish DB result = success/deduplicated same active version;
- version = `opublikovana`, upload = `zavershena`;
- active pointer указывает на exact version;
- bot `poisk_aktivnyh_znaniy` на TEST видит published version;
- unpublished/draft/archive не попадают в active search;
- stale expected-active проверяется безопасно без перезаписи active pointer;
- сохранено runtime evidence;
- production untouched.

### Rollback

До первого mutating run отдельно определить безопасный rollback по существующему DB-05 API. Прямой DML для отката не использовать. Если это первая active version и потребуется снять её с публикации, использовать только поддерживаемый DB API после проверки его контракта и роли.

## Ограничения

- Production не менять.
- Рабочий трафик не переключать.
- Не выполнять mutating publish без отдельного подтверждения Павла.
- Не использовать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- Не публиковать секреты, Credential refs, Telegram ID, реальные документы или переписку.
- B1 threshold 0.60 не считать финальным client retrieval threshold без negative/no-answer calibration.
