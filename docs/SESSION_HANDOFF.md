# SESSION HANDOFF

Обновлено: 2026-10-10.

## Исходная точка

Рабочая ветка: `main`.

Исходный HEAD перед закрывающим documentation commit KB-03C2:
`f37c05497dabcab9395636ffd371c1d0e21c6124` (`feat: prepare KB-03C1 publish workflow`).

Новая сессия обязана сначала перечитать фактический HEAD `main`; он важнее этого зафиксированного исходного SHA.

Knowledge workflow закрыт до **KB-03C2 runtime verified**.

## Текущие repository-safe workflow

- `workflows/current/Шаблон Загрузка документов Qbit.json` — knowledge pipeline + prepared publish branch;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — client bot + active-only knowledge search.

Credential refs, реальные Telegram ID, секреты и документы компаний в Git не сохраняются.

Отдельные credential-bound TEST workflows, использованные для C2, являются runtime artifacts n8n и в repository-safe JSON не переносились.

## KB-03C2 — CLOSED / runtime verified

Target runtime:
- version `1d610b99-50f9-49b9-bc2d-b443b26e31a5`;
- document `2e26ffd6-b1e7-4e60-b77f-000953b8d3fe`;
- upload `328035d0-6fd7-4af3-83a3-2643a8b24d2f`;
- job `91de6175-da91-471a-be7a-97feffb646a3`.

Перед target claim два конкретных старых due retry jobs были безопасно переведены в `otmeneno` exact-guarded one-shot workflow. Массовая очистка очереди не выполнялась.

Publish path:
- worker забрал exact target;
- resume path использовал уже готовую version без повторного B1 embedding/check cycle;
- `opublikovat_versiyu_znaniy` вернул `uspeshno`;
- version=`opublikovana`;
- upload=`zavershena`;
- previous active=NULL;
- terminal workflow `publish_vypolnen=true`.

Read-only post-publish:
- active pointer = target version;
- job=`zaversheno`;
- lease cleared;
- fragments=53;
- exactly one published version for document;
- `KB03C2_POST_PUBLISH_OK`.

Bot active-only runtime:
- сначала diagnostic выявил, что ошибочно выбранный Credential был service role `qbit_test_sluzhebnyy`; права БД не менялись;
- после выбора правильного bot connection `current_user=qbit_test_bot`;
- bot EXECUTE active search=true;
- bot direct SELECT fragments=false;
- active search returned 12 rows, all 12 from target version;
- other versions=0, known old drafts=0;
- `KB03C2_BOT_ACTIVE_ONLY_OK`.

Stale protection:
- current real target повторно не мутировали ради искусственного stale case;
- DB optimistic concurrency уже runtime verified через `qbit_test_sluzhebnyy` на synthetic V2/V3 в `docs/evidence/KB-01/KB-01R5C_RUNTIME_VERIFIED_2026-10-04.md`: competing publish returned `konflikt/stale_expected_active` and active pointer remained correct;
- current KB-03C1 workflow stale/conflict route static verified.

Evidence:
`docs/evidence/KB-03/KB-03C2_RUNTIME_VERIFIED_2026-10-10.md`.

## Rollback

Supported publication-visibility rollback: `otozvat_dokument_znaniy(jsonb)` through dash-admin role after explicit need/authorization. Direct DML forbidden.

Rollback was not executed because C2 passed. Since this was the first active version, revoke would clear active pointer and archive the version, but would not fully rewind historical job/upload statuses.

## Следующая маленькая задача — WF-02B3C

Не начинать автоматически в этой сессии.

В новой сессии:
1. проверить current `main` HEAD и отсутствие чужих изменений;
2. прочитать `README.md`, `docs/PROJECT_STATE.md`, этот handoff и relevant rows `docs/WORKPLAN_TEMPLATE.md`;
3. прочитать `docs/WF-02B3_SMOKE_CHECKS.md` и связанные WF-02B3C требования;
4. определить один малый runtime smoke шаг event-driven topology без постоянного polling;
5. production и рабочий трафик не трогать.

VSCode/helper до dashboard stage не подключать.
