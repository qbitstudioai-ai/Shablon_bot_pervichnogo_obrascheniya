# KB-01 — фактическое состояние test-контура на 03.10.2026

Этот файл — **evidence/checkpoint**, а не нормативный DB-04 SQL.

Нормативные источники остаются:
- `docs/specs/DB_CONTRACT.md`;
- `docs/specs/KNOWLEDGE_INGESTION.md`;
- `docs/specs/MARKDOWN_FORMAT.md`.

## Подтверждённые результаты

### Таблицы

В test schema существуют и принадлежат `qbit_test_owner`:
- `znaniya_dokumenty`;
- `znaniya_versii`;
- `znaniya_fragmenty`.

`znaniya_fragmenty.embedding` имеет тип `vector(1024)`.
FK `znaniya_dokumenty_aktivnaya_versiya_fk` существует.
Индексы `znaniya_versii_status_idx` и `znaniya_fragmenty_versiya_idx` существуют.

### B1

`kb01_postavit_dokument(jsonb)`:
- function owner: `qbit_test_owner`;
- SECURITY DEFINER: true;
- service EXECUTE: true;
- runtime под `qbit_test_sluzhebnyy`: `uspeshno/ozhidaet`;
- повтор того же idempotency key: `dublikat`;
- IDs первого и повторного вызова совпали;
- тест завершён `ROLLBACK`.

### B2

`kb01_zabrat_sleduyushchuyu_versiyu(jsonb)`:
- function owner: `qbit_test_owner`;
- SECURITY DEFINER: true;
- service EXECUTE: true;
- прямой UPDATE `znaniya_versii` у служебной роли: false;
- runtime: первый worker получил `v_rabote`, `nomer_vladeniya=1`, `popytki=1`;
- второй worker получил `net_zadaniya`;
- тест завершён `ROLLBACK`.

## Важное ограничение

После этих проверок обнаружено расхождение с нормативным DB-04/DB-05. Эти объекты нельзя автоматически объявлять канонической реализацией знаний.

Сгенерированный локально workflow `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировался** и не должен импортироваться до KB-01R:
- он вызывает ещё не существующие функции B3/publish/error/search;
- он был собран под промежуточный API;
- его B1/B2 Postgres-ноды ожидают row-shaped результат, тогда как фактически установленные B1/B2 возвращают `jsonb`;
- он допускает форматы сверх нормативного `.md` v1.

Production и рабочий трафик этим экспериментальным блоком не менялись.
