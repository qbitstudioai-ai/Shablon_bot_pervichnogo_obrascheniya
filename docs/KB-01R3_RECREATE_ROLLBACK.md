# KB-01R3 — план применения и отката DB-04/DB-05 recreate

Дата: 2026-10-03.

Статус: **реализация подготовлена, на сервер не применена**.

## Подготовленные файлы

1. `sql/DB-04_05_knowledge_recreate_test.sql` — полный test-only recreate experimental KB → нормативный DB-04/DB-05.
2. `sql/DB-04_05_knowledge_verifier.sql` — обязательный read-only verifier после COMMIT.
3. `sql/DB-04_05_knowledge_rollback_test.sql` — аварийный rollback к состоянию «KB отсутствует/выключена», только пока новые KB-таблицы пустые.

## Что делает recreate

В одной транзакции:

- проверяет, что live experimental state всё ещё совпадает с KB-01R2: три таблицы пустые, B1/B2 имеют известные fingerprints, неожиданных KB-объектов нет;
- проверяет DB-03 prerequisites, pgvector и SHA-256 `digest`;
- без `CASCADE` удаляет только подтверждённые experimental B1/B2 и три experimental таблицы;
- создаёт восемь нормативных DB-04 таблиц;
- добавляет FK `ishodyashchie_deystviya.zagruzka_id → zagruzki_znaniy.id`;
- создаёт ingestion queue/lease API, version/profile/fragments/checks API;
- создаёт DB-05 draft search, active-only bot search, atomic publish и admin revoke;
- отзывает прямой доступ runtime-ролей к KB-таблицам и выдаёт только точечный `EXECUTE`;
- выполняет structural self-check до COMMIT.

Если любая команда до `COMMIT` завершается ошибкой, PostgreSQL откатывает и DROP experimental-объектов, и создание новых объектов одной транзакцией. В этом случае отдельный rollback SQL не запускать.

## Обязательный порядок после разрешения Павла на применение

1. Открыть актуальный `sql/DB-04_05_knowledge_recreate_test.sql` из `main` и запустить файл целиком в test Supabase.
2. Убедиться, что итоговый результат содержит `status=applied` и `migration=KB-01R3_v0.1`.
3. Ничего не импортировать в n8n и не включать client RAG.
4. Запустить целиком `sql/DB-04_05_knowledge_verifier.sql`.
5. Только `status=verified` разрешает перейти к runtime-тестам DB-04/DB-05.

## Rollback до COMMIT

Автоматический: ошибка внутри recreate-транзакции откатывает всё. Повторный ручной SQL удаления не нужен.

## Rollback после COMMIT, если verifier не прошёл

Пока не было реальной KB-загрузки и все восемь новых таблиц пустые, разрешён `sql/DB-04_05_knowledge_rollback_test.sql`.

Он:
- повторно проверяет, что новые таблицы пустые и `ishodyashchie_deystviya` не ссылается на upload;
- удаляет только новые DB-04/DB-05 функции/таблицы/FK;
- оставляет DB-01…DB-03 нетронутыми;
- **не восстанавливает** experimental B1/B2, потому что они признаны неканоническими;
- возвращает безопасное состояние «KB отсутствует/выключена».

Если хотя бы одна нормативная KB-таблица уже содержит реальные данные, автоматический rollback обязан остановиться. Тогда нужен отдельный план сохранения данных; ничего удалять автоматически нельзя.

## Что не является rollback

- Не импортировать старый `Шаблон_мультиканальный_KB-01_v0.3.json`.
- Не восстанавливать experimental B1/B2 только ради возврата к прежнему виду.
- Не трогать production schema `qbit` и production roles.
- Не считать GitHub commit фактом применения SQL на сервере.

## Важная зависимость PRE-02E

SQL фиксирует `vector(1024)`, потому что текущий candidate-профиль использует `text-embedding-3-large` с `dimensions=1024`. Сам факт создания SQL не закрывает runtime-подтверждение PRE-02E. До фактической проверки embedding длины 1024 DB-04/DB-05 нельзя считать runtime-завершёнными.
