# KB-01R2 — выбор безопасного пути для KB

Дата: 2026-10-03.

Статус: **KB-01R2 завершена. Выбран путь recreate для test KB.**

## Исходная точка

KB-01R1 показала, что experimental KB не является частичной реализацией нормативного DB-04/DB-05, которую можно безопасно продолжать через B3:
- `znaniya_dokumenty` только частично соответствует `dokumenty_znaniy`;
- `znaniya_versii` смешивает загрузку, очередь, версию и часть профиля индекса;
- `znaniya_fragmenty` содержит только часть нормативного контракта фрагмента;
- отсутствуют отдельные `zagruzki_znaniy`, `zadaniya_znaniy`, `profili_indeksa`, `kontrolnye_voprosy`, `proverki_znaniy`;
- отсутствуют нормативные DB-05 draft/active search, atomic publish и revoke.

Перед выбором пути нельзя было считать experimental-таблицы пустыми без live-проверки.

## Read-only проверка 03.10.2026

В test PostgreSQL выполнен только файл:

`docs/evidence/KB-01/KB-01R2_READ_ONLY_INVENTORY_v0.1.sql`

Verifier: `KB-01R2_READ_ONLY_v0.1`.

Запрос содержит только SELECT/CTE и чтение `pg_catalog`; DDL/DML и вызовов прикладных функций нет.

Подтверждено live:

### Данные

| Объект | Строк |
|---|---:|
| `znaniya_dokumenty` | 0 |
| `znaniya_versii` | 0 |
| `znaniya_fragmenty` | 0 |

Дополнительно:
- документов с `aktivnaya_versiya_id` — 0;
- версий с арендой — 0;
- версий с ошибкой — 0;
- версий с фрагментами — 0;
- распределение version status пустое.

То есть переносить пользовательские KB-данные из experimental-модели не требуется.

### Фактические experimental KB-объекты

Найдены ровно три KB-таблицы:
- `znaniya_dokumenty`;
- `znaniya_versii`;
- `znaniya_fragmenty`.

Все принадлежат `qbit_test_owner`.

Найдены ровно две experimental KB-функции:
- `kb01_postavit_dokument(p jsonb) RETURNS jsonb`;
- `kb01_zabrat_sleduyushchuyu_versiyu(p jsonb) RETURNS jsonb`.

Обе:
- owner `qbit_test_owner`;
- `SECURITY DEFINER`;
- имеют фиксированный `search_path=pg_catalog, qbit_bot_pervichnogo_obrascheniya, pg_temp`;
- доступны по EXECUTE роли `qbit_test_sluzhebnyy`.

Live fingerprints определений:
- `kb01_postavit_dokument`: `56654d3112113f99acda41df4a53b8e8`;
- `kb01_zabrat_sleduyushchuyu_versiyu`: `4ea8ce93b420723239fbe6fabec868ed`.

У `qbit_test_sluzhebnyy` нет прямых `SELECT`, `INSERT`, `UPDATE`, `DELETE` на всех трёх experimental KB-таблицах.

Структура таблиц, FK, CHECK/UNIQUE и индексы совпала с checkpoint/evidence KB-01R1; дополнительных KB-таблиц или KB-функций verifier не обнаружил.

## Решение

Выбран путь **recreate**:

1. Не пытаться преобразовывать три experimental-таблицы на месте в нормативный DB-04/DB-05.
2. В отдельной задаче KB-01R3 подготовить полный test-only SQL, который сначала безопасно удаляет только подтверждённые experimental KB-объекты, затем создаёт нормативный DB-04/DB-05 с нуля.
3. Перед destructive-частью SQL повторно проверить signatures/row counts, чтобы не удалить объект, который изменился после этой проверки.
4. Подготовить rollback-план и отдельный verifier до применения SQL.
5. Применение SQL на сервере считать отдельным действием после подготовки и проверки файла.

## Почему выбран recreate, а не migration

Главная причина — не только пустые таблицы, а сочетание двух фактов:

- **данных для сохранения нет**: live row counts всех трёх таблиц равны нулю;
- **контракты структурно разные**: `znaniya_versii` смешивает несколько нормативных сущностей, а значительная часть DB-04/DB-05 вообще отсутствует.

Миграция на месте добавила бы сложность, временные переходные состояния и риск оставить старые поля/ограничения/семантику. При отсутствии данных эта сложность не даёт полезного результата.

Recreate позволяет построить DB-04/DB-05 прямо по `docs/specs/DB_CONTRACT.md` и `docs/specs/KNOWLEDGE_INGESTION.md`, не наследуя промежуточный API B1/B2.

## Что НЕ разрешено этим решением

KB-01R2 выбирает архитектурный путь, но **не является разрешением уже сейчас удалять объекты или применять новый SQL**.

До отдельной реализации KB-01R3:
- не удалять experimental KB-объекты;
- не продолжать B3;
- не импортировать `Шаблон_мультиканальный_KB-01_v0.3.json`;
- не включать client RAG;
- не применять evidence SQL повторно;
- production не менять.

## Следующая задача

**KB-01R3 — подготовить полный test-only recreate SQL, verifier и rollback-план для нормативного DB-04/DB-05.**

KB-01R3 должна опираться на live signatures из этой проверки и нормативные `DB_CONTRACT` + `KNOWLEDGE_INGESTION`. SQL не применять автоматически в момент его подготовки.
