# SESSION HANDOFF

Обновлено: 2026-10-08.

## Исходная точка

Рабочая ветка: `main`.

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1.

Следующая маленькая задача — **KB-03C**.

Перед продолжением проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. только связанные с KB-03C publish/active-search контракты.

Не загружать без необходимости весь репозиторий.

## Текущие workflow

Repository-safe текущие файлы:
- `workflows/current/Шаблон Загрузка документов Qbit.json`;
- `workflows/current/Шаблон — Workflow бота Qbit.json`.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Исторический checkpoint KB-01A остаётся только для восстановления/сравнения и не является текущей workflow-истиной.

## KB-03B1 — CLOSED / runtime verified

Safe retry execution 08.10.2026 подтвердил полный критерий B1:
- 53 fragments;
- 9 canonical YAML reference questions;
- `Служебный_KB_Сохранить вопросы`: `rezultat=uspeshno`, `kolichestvo_voprosov=9`;
- one OpenAI question embedding batch;
- model `text-embedding-3-large`, dimensions 1024, float;
- 9 vectors, finite values true, dimension min/max 1024/1024, index mapping true;
- OpenAI usage 237 tokens;
- draft-only/version-scoped/profile-scoped top-12;
- calibration grid 0.45..0.85;
- 9/9 pass на 0.45, 0.50, 0.55, 0.60;
- selected positive validation threshold = 0.60;
- `Служебный_KB_Сохранить проверки`: `rezultat=uspeshno`, `uspeshnyh=9`, `vsego=9`, `status_versii=gotova`;
- publish=false;
- generative LLM calls = 0;
- `full_pass=true`, `next_stage=KB-03C`.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

Предыдущий проход 6/8 остаётся историческим evidence:
`docs/evidence/KB-03/KB-03B1_PARTIAL_RUNTIME_2026-10-07.md`.

## Почему после успешного B1 job = `povtor`

Это ожидаемо для текущей ручной test-цепочки. Нода `Служебный_KB_Вернуть после 03B` вызывает `zavershit_zadanie_znaniy` со `status='povtor'` и будущим `sleduyushchiy_zapusk`, чтобы освободить fenced lease и оставить job доступным следующему этапу. Успех B1 определяется не этим техническим статусом, а `kb03b_gotova`, `full_pass=true`, `status_versii=gotova`, `next_stage=KB-03C`, `publish=false`.

Отдельное продуктовое наблюдение: manual worker забирает due job из очереди, а не обязательно самый недавно отправленный файл. В production UX ручного запуска быть не должно; worker должен запускаться автоматически, а пользователю показываются статусы обработки.

## Следующая задача — KB-03C

Цель: atomic publish готовой версии + stale-conflict protection + active-only end-to-end regression.

Начинать с отдельной небольшой подзадачи: прочитать нормативный publish/active-search contract, определить точный ID, условия начала и критерий готовности. Не публиковать ничего автоматически только потому, что B1 закрыт.

KB-03B1 threshold 0.60 — только positive-reference validation threshold. Финальный client retrieval threshold требует negative/no-answer calibration.

## Запреты

- Production не менять.
- Рабочий трафик не переключать.
- Не публиковать версию без отдельной задачи KB-03C и проверяемого плана отката.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.

## Текст передачи в новую сессию

Продолжаем `Shablon_bot_pervichnogo_obrascheniya` с задачи KB-03C. KB-03B1 закрыт runtime 08.10.2026: 53 fragments, 9/9 canonical reference checks, one OpenAI question embedding batch `text-embedding-3-large/1024/float`, draft-only top-12, positive grid full pass до 0.60, DB `status_versii=gotova`, publish=false, next_stage=KB-03C. Сначала проверь актуальный `main` HEAD, прочитай README, PROJECT_STATE, SESSION_HANDOFF, KB_WORKFLOW_IMPLEMENTATION_PLAN и только связанные publish/active-search контракты. Не начинай publication/production changes без точной маленькой подзадачи и разрешённого test-объёма.