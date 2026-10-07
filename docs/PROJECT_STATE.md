# Текущее состояние проекта

Обновлено: 2026-10-07.

## Режим

Реализация test-контура разрешена. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Фактическая основа workflow — export Павла `(7)`, raw SHA-256 `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Последний сохранённый в Git восстановимый runtime-verified checkpoint пока:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

Restore:
`python tools/restore_workflow_checkpoint.py`

SHA-256 старого checkpoint:
`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Фактически текущий runtime-проверенный import-ready workflow — **v0.11 KB-03A**, SHA-256 `54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`. Отдельный Git-checkpoint v0.11 ещё не сохранён.

Для активной KB-03B1 подготовлен локальный **v0.12 KB-03B1**, ещё не runtime-проверенный:
- SHA-256 `d562404cdc51788783eaf22b745310b69bcf3b2d07bcb8b5495fffdeffd6597c`;
- 254 nodes;
- 206 connection keys;
- 288 edges;
- `active=false`;
- Credential refs 0;
- duplicate names 0;
- dangling connections 0;
- все Code nodes проходят JS syntax check.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test. KB-03A сохранил реальные `vector(1024)` fragments через `sohranit_fragmenty_znaniy`.

При подготовке KB-03B найден контрактный разрыв между сохранением questions и сохранением checks. Он закрыт задачей KB-03B0.

### KB-03B0 — CLOSED / runtime verified

В TEST применена узкая SECURITY DEFINER-функция:
`qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)`.

Runtime 07.10.2026:
- `kb03b0_status=verified`;
- owner `qbit_test_owner`;
- service execute true;
- bot/public execute false;
- direct service SELECT `kontrolnye_voprosy` false;
- function выдаёт question IDs только при live fenced job/version;
- production untouched.

Evidence: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.

## Ограничение нагрузки на LLM

Постоянный guard:
- ingestion/parsing/cleaning/chunking/token count — без generative LLM;
- embeddings — только индекс/search;
- вся база не передаётся клиентской LLM целиком;
- client path: query embedding → vector search → filter/dedupe → небольшой evidence package → final LLM;
- candidate top-k 12, final evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- общий evidence token budget зафиксировать до окончания retrieval-калибровки.

A2 runtime: 130 blocks → 53 candidates, average 237.1, max 551. KB-03A — один embedding batch fragments. KB-03B1 — один embedding batch только 3–10 questions.

## OpenAI embedding profile — runtime verified

KB-03A доказал `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`, exact input, vector length 1024, finite values, mapping по API index. Успешный safe runtime: 6 fragments, 910 input tokens, DB `sohraneno_fragmentov=6`, `vsego_fragmentov=6`.

## Активный план

Родительский план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.
Подплан: `docs/KB-03B_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B0` → `KB-03B1` → `KB-03C`.

Закрыты и runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0.

## Текущая маленькая задача — KB-03B1

v0.12 путь:
`claim/parser/A1/A2/B → prepare version → A3 idempotent fragment save → save questions → bridge IDs → one OpenAI question batch → draft-only top-12 → threshold grid 0.45..0.85 → deterministic section/fact checks → save checks → release job`.

Критерий:
- canonical YAML questions сохранены, 3..10;
- DB question IDs получены через B0 bridge и совпадают по count/order/content;
- question vectors = `text-embedding-3-large/1024/float`, finite/index mapping true;
- search только через `poisk_chernovika_znaniy` по своей version/profile;
- top-k 12, initial threshold 0;
- grid 0.45..0.85 шаг 0.05 рассчитана по фактическим similarities;
- validation threshold = максимальный grid threshold с full pass positive YAML set, иначе 0.45 и draft remains not-ready;
- expected section и optional fact должны подтверждаться одним fragment детерминированно;
- checks сохраняются через `sohranit_proverki_znaniy`;
- full pass → DB status `gotova`; fail → `chernovik`;
- B1 threshold не является финальным client threshold без negative/no-answer calibration;
- publish false;
- production untouched.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
