# KB-03B — план reference checks

Обновлено: 2026-10-08.

Родительская задача: `KB-03B` из `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

## Почему задача разделена

`sohranit_kontrolnye_voprosy(jsonb)` сохраняет 3–10 questions, но возвращает только количество. `sohranit_proverki_znaniy(jsonb)` требует реальный `vopros_id`. Прямой `SELECT` таблицы `kontrolnye_voprosy` служебной роли запрещён архитектурой. Поэтому KB-03B разделена на B0 и B1.

## [x] KB-03B0 — узкий DB bridge для ID вопросов

Канонический файл:
`sql/KB-03B0_question_ids_bridge_test.sql`.

Финальная runtime-версия SQL: v0.3.

Создана TEST-only SECURITY DEFINER-функция:
`qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)`.

Runtime 07.10.2026 подтвердил:
- `kb03b0_status=verified`;
- owner `qbit_test_owner`;
- service execute true;
- bot/public execute false;
- direct service SELECT questions false;
- function требует `zadanie_id + worker_id + nomer_vladeniya + versiya_id` и проверяет live lease/fencing/version scope;
- production untouched.

Evidence: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.

## [x] KB-03B1 — workflow reference checks

KB-03B1 runtime-verified 08.10.2026.

Путь:
`claim/parser/A1/A2/B → prepare version → A3 idempotent fragment embedding/save → save canonical questions → bridge question IDs → one-batch question embeddings → draft-only top-12 → threshold grid → deterministic section/fact checks → save checks → release job`

Обязательные свойства и runtime:
1. questions только из canonical YAML metadata KB-02B — подтверждено;
2. `sohranit_kontrolnye_voprosy` выполняется до получения IDs — подтверждено;
3. B0 bridge подтверждает DB IDs только под текущим live fence — подтверждено;
4. question embeddings: `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` — подтверждено;
5. exact question text, count/index mapping, vector 1024, finite values — подтверждено;
6. `poisk_chernovika_znaniy` ограничен текущими `versiya_id` + profile — подтверждено;
7. top-k = 12; initial search threshold = 0 — подтверждено;
8. grid = 0.45..0.85 шаг 0.05 — подтверждено;
9. B1 validation выбирает максимальный grid threshold с full pass positive questions — runtime selected 0.60;
10. expected section + optional fact подтверждаются одним fragment после deterministic normalization, без LLM — подтверждено;
11. `sohranit_proverki_znaniy` сохранил фактические checks — подтверждено;
12. full pass всех questions дал `status_versii=gotova` — 9/9;
13. selected B1 threshold не считать финальным client threshold — правило сохраняется;
14. publish в B1 не выполнялся — `publish_vypolnen=false`.

## Финальный runtime 08.10.2026

Safe retry execution:
- fragments = 53;
- canonical questions = 9;
- question embedding batch = 1;
- vectors = 9 × 1024;
- vector dimension min/max = 1024/1024;
- finite values = true;
- index mapping = true;
- OpenAI usage = 237 input/prompt tokens;
- generative LLM calls = 0;
- search `draft_only=true`, `version_scoped=true`, `profile_scoped=true`;
- top-k = 12;
- 0.45 → 9/9;
- 0.50 → 9/9;
- 0.55 → 9/9;
- 0.60 → 9/9;
- 0.65 → 8/9;
- 0.70 → 6/9;
- 0.75 → 3/9;
- 0.80 → 0/9;
- 0.85 → 0/9;
- selected positive threshold = 0.60;
- DB checks save = `uspeshno`;
- DB `uspeshnyh=9`, `vsego=9`, `status_versii=gotova`;
- `full_pass=true`;
- `next_stage=KB-03C`;
- publish=false.

`Служебный_KB_Вернуть после 03B` в текущем test workflow намеренно завершает lease через `status='povtor'` и будущий `sleduyushchiy_zapusk`. Для B1 это техническое освобождение job для следующего этапа; оно не отменяет `full_pass=true` и `status_versii=gotova`.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

Предыдущий 6/8 runtime остаётся историческим evidence:
`docs/evidence/KB-03/KB-03B1_PARTIAL_RUNTIME_2026-10-07.md`.

## Guard нагрузки

KB-03B1 не использует generative LLM. Question embeddings — один batch на canonical questions. Draft search — PostgreSQL/pgvector. Reference-check payloads не передаются клиентскому LLM.

## Критерий закрытия KB-03B1 — выполнен

Подтверждены:
- questions saved = expected 9;
- bridge IDs count/order/content соответствуют canonical set;
- one question embedding batch, vectors ×1024, finite/index mapping true;
- draft-only/version-scoped/profile-scoped top-12;
- calibration matrix 0.45..0.85;
- deterministic expected path/fact evaluation без LLM;
- DB checks save успешен;
- full pass 9/9 → DB status `gotova`;
- publish false;
- job безопасно освобождён.

KB-03B1 закрыт. Следующий этап — `KB-03C`: atomic publish + active-only regression.