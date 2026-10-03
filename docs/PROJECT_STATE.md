# Текущее состояние проекта

Обновлено: 2026-10-03.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический export Павла `Шаблон — служебный Telegram и перехват диалогов — версия 0.2 (6).json` очищен и сохранён как точный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки:
- 189 нод;
- 153 connection keys;
- 215 edges;
- `active=false`;
- duplicate node names = 0;
- dangling connections = 0;
- Credential refs удалены;
- top-level n8n `id`, `versionId`, `meta.instanceId` удалены;
- реальный ID служебной Telegram-группы удалён;
- очевидные API keys/Bearer/Telegram bot tokens не найдены;
- SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Восстановление обычного JSON: `python tools/restore_workflow_checkpoint.py`.

Старый `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json` удалён из текущего дерева; история остаётся в Git.

## KB-01 — experimental checkpoint

03.10.2026 в test schema экспериментально применена часть KB-01:
- созданы `znaniya_dokumenty`, `znaniya_versii`, `znaniya_fragmenty`;
- B1 `kb01_postavit_dokument(jsonb)` runtime VERIFIED настоящей ролью `qbit_test_sluzhebnyy`;
- B2 `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)` runtime VERIFIED с lease/fencing и вторым worker=`net_zadaniya`;
- runtime-тесты завершались `ROLLBACK`;
- production не менялась.

После сверки с `docs/specs/DB_CONTRACT.md` и `docs/specs/KNOWLEDGE_INGESTION.md` подтверждено, что промежуточный KB-контракт не совпадает с нормативным DB-04/DB-05.

Поэтому:
- B3 не начинать;
- ранее сгенерированный `Шаблон_мультиканальный_KB-01_v0.3.json` в n8n **не импортировать**;
- экспериментальные SQL не считать каноническими DB-04/DB-05;
- клиентский RAG не включать.

Подробности checkpoint: [KB-01_APPLIED_TEST_STATE_2026-10-03](KB-01_APPLIED_TEST_STATE_2026-10-03.md).

## KB-01R1 — завершённая сверка

KB-01R1 выполнена без SQL-изменений на сервере и без изменений production.

Результат: [KB-01R1_INVENTORY_MAPPING](KB-01R1_INVENTORY_MAPPING.md).

Главный вывод mapping:
- `znaniya_dokumenty` только частично соответствует `dokumenty_znaniy`;
- `znaniya_versii` смешивает нормативные `zagruzki_znaniy`, `zadaniya_znaniy`, `versii_dokumentov_znaniy` и часть `profili_indeksa`;
- `znaniya_fragmenty` только частично соответствует `fragmenty_znaniy`;
- `kontrolnye_voprosy`, `proverki_znaniy`, нормативные publish/search функции DB-05 отсутствуют;
- B1/B2 нельзя считать готовыми DB-04 функциями и нельзя продолжать B3 поверх текущего контракта.

## KB-01R2 — путь выбран

03.10.2026 выполнен live read-only verifier:

`docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`

Подтверждено:
- `znaniya_dokumenty` — 0 строк;
- `znaniya_versii` — 0 строк;
- `znaniya_fragmenty` — 0 строк;
- документов с активной версией — 0;
- версий с арендой/ошибкой/фрагментами — 0;
- найдены ровно три experimental KB-таблицы и две функции B1/B2;
- дополнительных KB-объектов verifier не обнаружил;
- у `qbit_test_sluzhebnyy` нет прямых `SELECT/INSERT/UPDATE/DELETE` на этих трёх таблицах.

Решение KB-01R2: **recreate** — не мигрировать несовместимую experimental-модель на месте, а в отдельной реализации безопасно удалить только подтверждённые experimental KB-объекты test schema и создать нормативный DB-04/DB-05 с нуля.

Причина: переносить данные не требуется, а структурное несовпадение существенное. Простая migration-on-place добавила бы риск переходного состояния без пользы.

Подробности решения: [KB-01R2_DECISION](KB-01R2_DECISION.md).

## Текущая одна задача

**KB-01R3 — подготовить полный test-only recreate SQL, verifier и rollback-план для нормативного DB-04/DB-05.**

Активный план: [KB-01_RECONCILIATION_PLAN](KB-01_RECONCILIATION_PLAN.md).

Важно: KB-01R2 выбрала путь, но не является разрешением уже сейчас удалять объекты или применять новый SQL. Сначала KB-01R3 должна подготовить полный проверяемый файл и защитные проверки live signatures/row counts.

## Ограничения

- Production не изменялась.
- Experimental KB-объекты пока не удалялись.
- Новый DB-04/DB-05 SQL на сервер пока не применялся.
- B3 не продолжать.
- Старый KB workflow не импортировать.
- Client RAG не включать.
- Реальные документы компаний, переписки, пароли, токены и дампы БД в репозиторий не сохраняются.
- GitHub push и применение на сервере — разные действия.
- Evidence SQL в `docs/evidence/KB-01/` с пометкой `DO NOT APPLY` сохранён только для истории фактически выполненных test-команд и не запускается повторно.
