# KB-03B0 — runtime verified, 2026-10-07

## Цель

Закрыть DB-контрактный разрыв между `sohranit_kontrolnye_voprosy(jsonb)`, который возвращает только количество сохранённых вопросов, и `sohranit_proverki_znaniy(jsonb)`, которому нужен реальный `vopros_id`.

Production не менялся.

## Реализация

В TEST schema `qbit_bot_pervichnogo_obrascheniya` добавлена SECURITY DEFINER-функция:

`poluchit_kontrolnye_voprosy_znaniy(jsonb)`

Канонический SQL:

`sql/KB-03B0_question_ids_bridge_test.sql`

Финальная версия SQL для runtime-проверки: v0.3.

Функция принимает trusted runtime context `zadanie_id + worker_id + nomer_vladeniya + versiya_id`, проверяет live lease/fencing и version scope, после чего возвращает только 3–10 canonical questions своей версии: `vopros_id`, `nomer`, `vopros`, `ozhidaemyy_razdel`, `ozhidaemyy_fakt`, `istochnik`.

## Runtime result

Павел выполнил финальный TEST-only SQL и получил:

- `kb03b0_status=verified`;
- owner = `qbit_test_owner`;
- schema = `qbit_bot_pervichnogo_obrascheniya`;
- function = `poluchit_kontrolnye_voprosy_znaniy(jsonb)`;
- `service_execute=true`;
- `bot_execute=false`;
- `public_execute=false`;
- `direct_service_select_questions=false`;
- `production_untouched=true`;
- `next_stage=KB-03B1_workflow`.

Первые две подготовительные версии SQL остановились внутри транзакции на ошибочных smoke-проверках роли; финальная v0.3 исправила только способ smoke-test. Runtime-роли и production для исправления не расширялись.

## Итог

**KB-03B0 runtime verified.**

Bridge даёт service worker ровно недостающее чтение question IDs через узкий DB API, не выдавая прямой `SELECT` таблицы и не открывая доступ bot/PUBLIC.

Следующая подзадача: **KB-03B1** — save questions → bridge IDs → one-batch question embeddings → draft-only top-12 search → deterministic threshold/path/fact checks → `sohranit_proverki_znaniy`; publish в B1 запрещён.
