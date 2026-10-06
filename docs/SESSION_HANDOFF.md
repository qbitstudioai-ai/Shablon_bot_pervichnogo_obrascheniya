# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A и KB-01B1 завершены и runtime-проверены. Перед следующей задачей проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. для KB-01B2 — нужные части `docs/specs/KNOWLEDGE_INGESTION.md`, `docs/specs/MARKDOWN_FORMAT.md`, `docs/specs/DB_CONTRACT.md` и processing profile.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Текущий сохранённый runtime-verified checkpoint Git:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

Ожидаемый SHA-256:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Для KB-01B1 подготовлен и реально запущен полный workflow v0.5 KB-01B1 поверх точного v0.4. Import SHA-256:

`12430374e26711a32067d096884c4672dda061861e3f27030c38711829ed56f9`

v0.5 runtime-проверен, но отдельный checkpoint v0.5 ещё не сохранён в Git. Не утверждать обратное.

## KB-01A — доказанный runtime

05.10.2026 private `.md` прошёл durable service event → Telegram download → actual bytes check → `zaregistrirovat_zagruzku_znaniy`; получены non-null upload/job и успешный Telegram report после HTML escaping fix.

Evidence:
`docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — доказанный runtime

06.10.2026 существующее knowledge job успешно claim-нуто через normative lease/fencing API:
- `zadanie_id=0032a78e-b3fa-4cc8-8175-fcc52b53dd64`;
- `zagruzka_id=2d94322c-0347-48ce-8c66-e136e79d54d4`;
- worker `qbit_test_kb_worker_v1`;
- fence `1`;
- статус при claim `v_rabote`.

Parser `kb01b1_safe_frontmatter_markdown_v1`:
- `valid=true`, `kod=provereno`;
- `identifikator_dokumenta=qbit_klientskaya_baza_znaniy`;
- 57 headings;
- 8 reference questions;
- warnings 0;
- `hash_soderzhaniya=73436107b06ed1465094f23f785dadbb973adc787e049c04966195ae629e2290`.

Те же фактические bytes повторно прогнаны через тот же parser вне n8n и дали тот же hash/counts. Предварительный ориентир `be8f4f8d...` был ошибочным и исключён.

После проверки `zavershit_zadanie_znaniy` вернула `uspeshno`, job освобождён обратно в `povtor` тем же worker/fence.

Evidence:
`docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## DB-04 / DB-05

Нормативные DB-04/DB-05 уже существуют в test и runtime-проверены для bot/service. Не ориентироваться на старые `[ ]` в `WORKPLAN_TEMPLATE.md`.

`KB-01R5D` dash_admin revoke отложен до dashboard stage.

## Следующая задача — KB-01B2

Цель:
- доказать фактически доступный tokenizer/profile в self-hosted n8n;
- зафиксировать processing/index profile;
- вычислить `otpechatok_profilya` и `otpechatok_obrabotki`;
- под тем же live lease/fencing вызвать `podgotovit_versiyu_znaniy`;
- проверить active duplicate stop либо создание новой draft version `chernovik`;
- terminal/retry paths должны менять только текущий fenced job.

Не выполнять chunking, document embeddings, reference search или publish в KB-01B2.

## PRE-02E

Отдельный smoke не запускать. OpenAI document embedding `text-embedding-3-large`, `dimensions=1024` будет добавлен и runtime-проверен на `KB-03A`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
