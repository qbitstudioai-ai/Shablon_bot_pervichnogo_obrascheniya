# SESSION HANDOFF

Обновлено: 2026-10-08.

## Исходная точка

Рабочая ветка: `main`.

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1.

KB-03C1 закрыт как **static verified**. Следующая маленькая задача — **KB-03C2**.

## Текущие workflow

Repository-safe:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — теперь содержит подготовленный publish branch KB-03C1;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — уже содержит `Найти опубликованные знания` → `poisk_aktivnyh_znaniy`.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

## KB-03B1

Final runtime 08.10.2026:
- 53 fragments;
- 9/9 reference checks;
- `status_versii=gotova`;
- publish=false;
- selected positive validation threshold = 0.60.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

## KB-03C1 — CLOSED / static verified

Read-only preflight текущей TEST version:
- `versiya_id=1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- `dokument_id=2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- `status_versii=gotova`;
- fragments 53, bad dimensions 0;
- checks 9/9;
- expected active NULL = current active NULL;
- service can publish = true;
- bot can publish = false;
- result `READY_FOR_KB03C1_WORKFLOW_PREP`.

Publish workflow построен по фактическому `opublikovat_versiyu_znaniy(jsonb)` contract. Есть resume path для уже готовой version, trusted expected-active, explicit stale handling и fail-closed error path.

Static checks PASS: JSON, nodes/IDs/connections, 21 Code-node syntax checks, inactive workflow, no Credential bindings/secrets.

Evidence: `docs/evidence/KB-03/KB-03C1_STATIC_VERIFIED_2026-10-08.md`.

Ничего не импортировано и не опубликовано на сервере в рамках C1.

## KB-03C2 — следующий шаг

Сначала выполнить только безопасную подготовку n8n:
- импортировать current docs workflow как **новую отдельную TEST-копию**;
- не перезаписывать старый workflow;
- не активировать новую копию;
- для текущего resume path выбрать существующий service Postgres Credential `qbit_test_sluzhebnyy` минимум на нодах:
  - `Служебный_KB_Забрать задание`;
  - `Служебный_KB_Подготовить версию`;
  - `Служебный_KB_Опубликовать версию`;
  - `Служебный_KB_Завершить после ошибки публикации`.

После импорта Execute не нажимать до отдельного подтверждения конкретной TEST publication.

Перед mutating run:
- ещё раз подтвердить exact target version/document;
- уточнить поддерживаемый rollback DB API;
- прямой DML для rollback не использовать.

После разрешения C2: worker должен забрать нужный job, existing gotova version пройти resume gate, DB atomic publish подтвердить `opublikovana/zavershena`, затем bot active-only search должен увидеть эту version.

## Запреты

- Production не менять.
- Рабочий трафик не переключать.
- Не нажимать mutating Execute без отдельного подтверждения.
- Не использовать obsolete `sql/KB-01R5C_service_publish_prepare.sql`.
- VSCode/helper не подключать до dashboard stage.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
