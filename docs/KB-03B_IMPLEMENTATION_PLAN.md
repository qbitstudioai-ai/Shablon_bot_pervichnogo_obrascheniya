# KB-03B — план reference checks

Обновлено: 2026-10-07.

Родительская задача: `KB-03B` из `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

## Почему задача разделена

При сверке DB-контракта найден обязательный разрыв: `sohranit_kontrolnye_voprosy(jsonb)` сохраняет 3–10 вопросов, но возвращает только `kolichestvo_voprosov`. Нормативный `sohranit_proverki_znaniy(jsonb)` требует реальный `vopros_id` для каждой проверки. Прямой `SELECT` таблицы `kontrolnye_voprosy` служебной роли запрещён архитектурой.

Поэтому KB-03B разделена на две постоянные подзадачи.

## [~] KB-03B0 — узкий DB bridge для ID вопросов

Файл реализации:

`sql/KB-03B0_question_ids_bridge_test.sql`

Цель: добавить TEST-only SECURITY DEFINER-функцию

`qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)`

которая возвращает `vopros_id`, номер и canonical поля вопроса только для своей текущей live fenced knowledge job/version.

Ограничения:
- schema фиксирована в SQL;
- нужен `zadanie_id + worker_id + nomer_vladeniya + versiya_id`;
- job обязан быть `v_rabote`, lease не истёк, worker/fence совпадают;
- version должна быть `chernovik` или `gotova`;
- возвращаются только 3–10 вопросов своей версии;
- `PUBLIC` и bot role не получают EXECUTE;
- `qbit_test_sluzhebnyy` получает только EXECUTE функции, прямой SELECT таблицы не выдаётся;
- production не затрагивается.

Критерий закрытия KB-03B0:
- SQL применён в test без ошибки;
- smoke возвращает `otkaz / nekorrektnyy_vhod`, а не permission error;
- финальный `kb03b0_result.kb03b0_status = verified`;
- owner = `qbit_test_owner`;
- service execute = true;
- bot/public execute = false;
- direct service SELECT questions = false.

## [ ] KB-03B1 — workflow reference checks

Зависимость: KB-03B0 runtime verified.

Цель:
1. заново получить canonical YAML questions через deterministic parser/KB-02B;
2. `sohranit_kontrolnye_voprosy` сохраняет вопросы в draft;
3. новый bridge возвращает DB `vopros_id` под текущим lease/fencing;
4. один OpenAI embeddings batch получает только тексты `vopros`, model `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
5. каждый vector строго проверяется: length 1024, finite, mapping по API index;
6. `poisk_chernovika_znaniy` выполняется только для своей `versiya_id`/profile;
7. search собирает top-12 при `porog_shodstva=0`, чтобы сохранить фактические similarities до выбора порога;
8. калибровочная сетка 0.45..0.85 с шагом 0.05 оценивается на фактических результатах; порог не назначается по памяти;
9. ожидаемый `ozhidaemyy_razdel` проверяется детерминированно по path найденных fragments;
10. optional `ozhidaemyy_fakt` проверяется детерминированно по найденному evidence text, без LLM-самооценки;
11. `sohranit_proverki_znaniy` сохраняет фактические fragment IDs/similarities/result;
12. только полный pass всех canonical questions может перевести version в `gotova`;
13. publish в KB-03B1 запрещён.

## Guard нагрузки

KB-03B1 не использует generative LLM. Для 3–10 questions используется один embeddings batch. Draft search выполняется PostgreSQL/pgvector. В клиентский LLM эти reference-check payloads не передаются.

## Следующий этап

После runtime-verified KB-03B1 переходить к `KB-03C` — atomic publish + active-only regression.
