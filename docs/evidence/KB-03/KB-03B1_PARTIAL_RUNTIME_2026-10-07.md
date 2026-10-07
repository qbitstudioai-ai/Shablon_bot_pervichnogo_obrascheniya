# KB-03B1 — partial runtime, 2026-10-07

## Статус

KB-03B1 пока **не закрыт**. Runtime v0.12 дошёл до сохранения reference checks, но полный positive-reference pass не получен: 6/8.

Production и рабочий трафик не менялись. Publish не выполнялся.

## Что доказано runtime

На большой safe Markdown-базе:
- 53 fragments уже были сохранены через KB-03A path;
- 8 canonical YAML reference questions сохранены через `sohranit_kontrolnye_voprosy`;
- question IDs получены через runtime-verified KB-03B0 bridge под live fence;
- один OpenAI batch для 8 exact question texts;
- model `text-embedding-3-large`;
- `dimensions=1024`, `encoding_format=float`;
- API usage: 206 input tokens;
- 8 vectors, dimension min/max 1024/1024;
- все vector values finite;
- mapping по OpenAI index подтверждён;
- generative LLM calls = 0;
- draft search: top-k 12, только текущие version/profile;
- threshold grid 0.45..0.85 рассчитана по фактическим similarities;
- при 0.45..0.60 проходят 6/8; выше pass count уменьшается;
- full-pass threshold отсутствует;
- `sohranit_proverki_znaniy` вернул `uspeshno`, но `uspeshnyh=6`, `vsego=8`, `status_versii=chernovik`;
- job безопасно возвращён в `povtor`;
- publish=false.

Это корректное fail-closed поведение: отсутствие полного pass не переводит version в `gotova`.

## Найденный дефект контрольного набора

Детерминированная сверка safe source показала, что у canonical question №8 `ozhidaemyy_fakt` является составным пересказом двух отдельных формулировок source section и не встречается как одна точная нормализованная фраза. Текущий verifier намеренно требует подтверждение expected section + optional expected fact одним fragment без LLM-самооценки, поэтому такой expected fact не должен считаться точным подтверждением.

Остальные 7 expected facts существуют в своих заявленных source sections при той же детерминированной normalization.

Следовательно, один из двух fail уже объяснён дефектом positive reference metadata. Второй fail нужно определить по сохранённому execution без повторного OpenAI-вызова: сопоставить `vopros_id -> nomer` из `Служебный_KB_Получить вопросы с ID` с `kb03b_proverki` из `KB-03B1 Оценить draft search`.

## Runtime UI patch

До успешного запуска в IF node `KB-03B1 Fragments сохранены?` была исправлена expression-опечатка:

`={{ $json.kb03a_db_save_ok === true }}`

Изначальный вариант был воспринят n8n как string. После точечной правки workflow продолжил выполнение. Полный workflow заново не импортировался.

## Следующий безопасный шаг

1. Не менять threshold и не ослаблять verifier наугад.
2. Из уже выполненного n8n execution получить два outputs без vectors/full draft text:
   - `Служебный_KB_Получить вопросы с ID`;
   - `KB-03B1 Оценить draft search`.
3. Определить второй failed question и причину: retrieval miss top-12 либо metadata mismatch.
4. Только после диагноза решить, исправлять safe reference YAML или retrieval/check logic.

KB-03C не начинать до полного pass KB-03B1.
