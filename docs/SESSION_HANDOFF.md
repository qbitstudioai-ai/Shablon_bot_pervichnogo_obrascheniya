# SESSION HANDOFF

Обновлено: 2026-10-07.

## Исходная точка

Рабочая ветка: `main`.

Runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0.

Текущая маленькая задача — **KB-03B1**.

Перед продолжением проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/KB-03B_IMPLEMENTATION_PLAN.md`;
6. `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`;
7. `sql/KB-03B0_question_ids_bridge_test.sql`;
8. DB reference-question/search/check contract.

## Канонический workflow

Последний Git-восстановимый runtime checkpoint пока KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore SHA-256:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**:
SHA-256 `54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`.

Для KB-03B1 подготовлен локальный **v0.12 KB-03B1**:
SHA-256 `d562404cdc51788783eaf22b745310b69bcf3b2d07bcb8b5495fffdeffd6597c`.

Статика v0.12: 254 nodes, 206 connection keys, 288 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0, Code syntax check pass. v0.12 ещё не runtime-verified и не Git-checkpoint.

## KB-03A доказанный runtime

Safe document: 6 exact fragments → one OpenAI batch → 6 vectors ×1024, finite, exact input/index mapping → normative DB save `sohraneno_fragmentov=6`, `vsego_fragmentov=6`; version `chernovik`, publish false, job → `povtor`.

Evidence: `docs/evidence/KB-03/KB-03A_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-03B0 доказанный runtime

TEST bridge `poluchit_kontrolnye_voprosy_znaniy(jsonb)` применён и verified:
- owner `qbit_test_owner`;
- service execute true;
- bot/public execute false;
- direct service SELECT questions false;
- production untouched.

Evidence: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.

## v0.12 KB-03B1

Путь:
`claim/parser/A1/A2/B → prepare version → A3 idempotent fragment embedding/save → save YAML questions → bridge IDs → one question embedding batch → draft-only top-12 → grid 0.45..0.85 → deterministic section/fact checks → save checks → release job`.

Новые ключевые ноды:
- `Служебный_KB_Сохранить вопросы`;
- `Служебный_KB_Получить вопросы с ID`;
- `KB-03B1 OpenAI embeddings вопросов`;
- `Служебный_KB_Draft поиск вопросов`;
- `KB-03B1 Оценить draft search`;
- `Служебный_KB_Сохранить проверки`;
- `Служебный_KB_Вернуть после 03B`;
- `Служебный_KB_Вернуть после ошибки 03B`.

Question embeddings: один batch 3..10 exact `vopros`, model `text-embedding-3-large`, dimensions 1024, float. Generative LLM = 0.

Search: нормативный `poisk_chernovika_znaniy`, только своя `versiya_id`/profile, top-k 12, initial threshold 0.

Calibration: grid 0.45..0.85 step 0.05. Для B1 positive-reference validation выбирается максимальный grid threshold с full pass; если full pass отсутствует, checks сохраняются на 0.45 и version должна остаться `chernovik`. Этот threshold не считать финальным client threshold без negative/no-answer набора.

Expected section + optional fact должны подтверждаться одним fragment после deterministic normalization. LLM-самооценки нет.

`sohranit_proverki_znaniy` сама переводит version в `gotova` только при полном pass всех canonical questions и наличии fragments нужного profile. Publish в B1 отсутствует.

## Runtime запуск v0.12

Импортировать отдельным inactive workflow. Назначить TEST OpenAI Credential обеим embedding HTTP nodes. Назначить service Postgres Credential всем Postgres nodes manual worker branch, включая четыре новые B1 service nodes.

Для успешного доказательства прислать compact outputs:
- `Служебный_KB_Сохранить вопросы`;
- `Служебный_KB_Получить вопросы с ID` можно не присылать целиком, если много rows; предпочтительнее финальные outputs ниже;
- `Служебный_KB_Сохранить проверки`;
- `Служебный_KB_Вернуть после 03B`.

Если B1 error path — прислать `Служебный_KB_Вернуть после ошибки 03B`.

Не присылать full vectors или полный draft search output без необходимости.

## Следующий этап

После runtime-verified KB-03B1: `KB-03C` — atomic publish + active-only end-to-end regression.

## Запреты

- Production не менять.
- Рабочий трафик не переключать.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
