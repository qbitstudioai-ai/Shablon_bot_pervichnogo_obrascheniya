# KB-03B — план reference checks

Обновлено: 2026-10-07.

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

## [~] KB-03B1 — workflow reference checks

Подготовлен локальный import-ready **v0.12 KB-03B1**, ещё не runtime-verified.

SHA-256:
`d562404cdc51788783eaf22b745310b69bcf3b2d07bcb8b5495fffdeffd6597c`

Статика:
- 254 nodes;
- 206 connection keys;
- 288 edges;
- `active=false`;
- Credential refs 0;
- duplicate names 0;
- dangling connections 0;
- все Code nodes проходят syntax check;
- ручной путь содержит только deterministic Code/IF/Postgres, встроенный exact tokenizer и два OpenAI HTTP embeddings вызова: fragments A3 + questions B1; generative LLM nodes нет.

### Путь v0.12

`claim/parser/A1/A2/B → prepare version → A3 idempotent fragment embedding/save → save canonical questions → bridge question IDs → one-batch question embeddings → draft-only top-12 → threshold grid → deterministic section/fact checks → save checks → release job`

Обязательные свойства:
1. questions только из canonical YAML metadata KB-02B;
2. `sohranit_kontrolnye_voprosy` выполняется до получения IDs;
3. B0 bridge подтверждает DB IDs только под текущим live fence;
4. question embeddings: `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
5. exact question text, count/index mapping, vector 1024, finite values;
6. `poisk_chernovika_znaniy` ограничен текущими `versiya_id` + profile;
7. top-k = 12; initial search threshold = 0 для сохранения фактических similarities;
8. grid = 0.45..0.85 шаг 0.05;
9. B1 validation выбирает максимальный grid threshold с full pass всех positive YAML questions; если такого нет, checks сохраняются на 0.45 и version остаётся `chernovik`;
10. ожидаемый section и optional fact должны подтверждаться одним и тем же fragment; normalization детерминированная, без LLM;
11. `sohranit_proverki_znaniy` сохраняет реальные fragment IDs/similarities/results;
12. только full pass всех questions может дать `status_versii=gotova`;
13. selected B1 threshold не считается финальным client threshold: negative/no-answer calibration ещё обязательна;
14. publish запрещён.

## Guard нагрузки

KB-03B1 не использует generative LLM. Question embeddings — один batch на 3–10 вопросов. Draft search — PostgreSQL/pgvector. Reference-check payloads не передаются клиентскому LLM.

## Критерий закрытия KB-03B1

Live n8n должен подтвердить:
- questions saved = expected 3..10;
- bridge IDs count/order/content совпадают с canonical YAML;
- one question embedding batch, vectors ×1024, finite/index mapping true;
- draft-only/version-scoped/profile-scoped top-12;
- calibration matrix 0.45..0.85 фактически получена;
- deterministic expected path/fact evaluation выполнена без LLM;
- DB checks save успешен;
- при full pass DB status = `gotova`; при fail = `chernovik`;
- publish false;
- job безопасно освобождён.

После runtime-verified KB-03B1 переходить к `KB-03C` — atomic publish + active-only regression.
