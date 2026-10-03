# KB-01R — сверка фактического KB-01 с нормативным DB-04/DB-05

Статус: **активная задача после checkpoint 03.10.2026**.

## Почему нужна эта задача

03.10.2026 в test schema `qbit_bot_pervichnogo_obrascheniya` были экспериментально созданы три таблицы знаний и две SECURITY DEFINER-функции KB-01. Их B1/B2 runtime-поведение проверено настоящей ролью `qbit_test_sluzhebnyy`.

После сверки с нормативными документами репозитория обнаружено, что этот экспериментальный контракт не совпадает с DB-04/DB-05:

- нормативный DB-04 разделяет загрузку, очередь знаний, документ, версию, профиль индекса, фрагменты, контрольные вопросы и проверки;
- нормативный v1 принимает только `.md` UTF-8 до 5 MiB;
- публикация и клиентский поиск относятся к DB-05 и должны работать только через опубликованную активную версию;
- сгенерированный локально workflow `Шаблон_мультиканальный_KB-01_v0.3.json` использует другой промежуточный API и поэтому **не является каноническим и не должен импортироваться в n8n**.

## Фактически применено в test Supabase

Только test schema; production не изменялась.

1. `qbit_test_owner` получил `USAGE` на schema `extensions`.
2. Созданы экспериментальные таблицы:
   - `znaniya_dokumenty`;
   - `znaniya_versii`;
   - `znaniya_fragmenty` с `extensions.vector(1024)`.
3. Добавлены FK активной версии и два индекса.
4. Создана `kb01_postavit_dokument(jsonb)`:
   - owner `qbit_test_owner`;
   - `SECURITY DEFINER`;
   - `EXECUTE` у `qbit_test_sluzhebnyy`;
   - runtime VERIFIED: первый вызов `uspeshno / ozhidaet`, повтор по тому же idempotency key — `dublikat`; тест завершён `ROLLBACK`.
5. Создана `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)`:
   - owner `qbit_test_owner`;
   - `SECURITY DEFINER`;
   - `EXECUTE` у `qbit_test_sluzhebnyy`;
   - runtime VERIFIED: первый worker получает `v_rabote`, `nomer_vladeniya=1`, `popytki=1`; второй worker получает `net_zadaniya`; тест завершён `ROLLBACK`.

## Что не сделано в experimental KB

- `kb01_sohranit_fragment(jsonb)` не создана.
- функция публикации не создана.
- функция ошибки не создана.
- DB-05 поиск не реализован.
- полномасштабный KB workflow в n8n не импортирован.
- первая реальная `.md` загрузка не выполнялась.
- экспериментальные таблицы/функции не признаны DB-04/DB-05.

## Подзадачи KB-01R

### KB-01R1 — read-only инвентаризация и mapping — **ГОТОВО**

Результат: [KB-01R1_INVENTORY_MAPPING](KB-01R1_INVENTORY_MAPPING.md).

Зафиксировано:
- подтверждённый checkpoint-набор experimental таблиц/связей/индексов/функций;
- field/role mapping к восьми нормативным DB-04 сущностям;
- mapping B1/B2 к нормативным функциям DB-04/DB-05;
- перечень отсутствующих DB-04/DB-05 объектов;
- контрактные причины, почему B3 нельзя продолжать поверх текущей модели.

### KB-01R2 — выбрать безопасный путь — **ГОТОВО**

Read-only verifier:

`docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`

Live-проверка 03.10.2026 подтвердила:
- `znaniya_dokumenty` = 0 строк;
- `znaniya_versii` = 0 строк;
- `znaniya_fragmenty` = 0 строк;
- active/leased/error/fragmented state counts = 0;
- существуют ровно три experimental KB-таблицы и две функции B1/B2;
- дополнительных KB-таблиц/функций verifier не обнаружил;
- у `qbit_test_sluzhebnyy` нет прямого DML/SELECT к трём таблицам.

Выбран путь **recreate**:
- данные мигрировать не требуется;
- experimental-модель не переделывается на месте;
- в KB-01R3 готовится безопасное удаление только подтверждённых experimental KB-объектов test schema и создание нормативного DB-04/DB-05 с нуля.

Решение: [KB-01R2_DECISION](KB-01R2_DECISION.md).

KB-01R2 не давала разрешения выполнить destructive SQL: на сервере ничего не удалялось и нормативный DB-04/DB-05 ещё не применялся.

### KB-01R3 — подготовить реализацию recreate — **СЛЕДУЮЩАЯ ЗАДАЧА**

Подготовить, но не применять автоматически:

1. полный test-only SQL recreate;
2. preflight, который до destructive-части проверяет schema, owner, точный набор experimental объектов, function fingerprints и `row_counts=0`;
3. удаление только подтверждённых experimental B1/B2 и трёх experimental таблиц в безопасном порядке;
4. создание нормативных объектов DB-04/DB-05 по `docs/specs/DB_CONTRACT.md` и `docs/specs/KNOWLEDGE_INGESTION.md`;
5. grants/owners/SECURITY DEFINER/search_path по действующим правилам изоляции;
6. отдельный verifier результата;
7. rollback-план с чётким описанием, что можно откатить транзакционно и что должно быть восстановлено при неуспешной runtime-проверке.

SQL не применять на сервер в момент подготовки без отдельного шага применения и проверки.

## Ограничения до реализации KB-01R3

- не продолжать B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать клиентский RAG;
- не менять production;
- не удалять test KB-объекты вручную;
- не применять evidence SQL повторно;
- не считать подготовленный SQL применённым, пока нет фактического server result и verifier.

## Критерий готовности KB-01R

Есть:
1. проверяемая таблица соответствия experimental и нормативных объектов — **готово в KB-01R1**;
2. выбран путь migration/recreate — **готово в KB-01R2: recreate**;
3. подготовлен полный SQL с verifier и rollback-планом — **ожидает KB-01R3**;
4. `PROJECT_STATE` однозначно указывает следующий ID — **KB-01R3**.
