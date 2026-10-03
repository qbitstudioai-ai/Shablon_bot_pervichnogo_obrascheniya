# Текущее состояние проекта

Обновлено: 2026-10-03.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки: 189 нод, 153 connection keys, 215 edges, `active=false`, duplicate names 0, dangling connections 0; credentials/instance ID/реальный ID служебной группы удалены. SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый canonical workflow v0.2 удалён из текущего дерева; история остаётся в Git. Старый сгенерированный `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировать**.

## Experimental KB checkpoint

03.10.2026 в test schema были экспериментально созданы:
- `znaniya_dokumenty`;
- `znaniya_versii`;
- `znaniya_fragmenty`;
- `kb01_postavit_dokument(jsonb)`;
- `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)`.

B1/B2 ранее runtime VERIFIED служебной ролью, но контракт признан несовместимым с нормативным DB-04/DB-05. B3 не продолжался. Production не менялась.

## KB-01R1 — mapping завершён

`docs/KB-01R1_INVENTORY_MAPPING.md` зафиксировал, что experimental модель смешивает загрузку, durable job, версию и часть index profile; нормативные контрольные вопросы, проверки и DB-05 publish/search/revoke отсутствуют. Продолжать B3 поверх B1/B2 нельзя.

## KB-01R2 — выбран recreate

Live read-only `KB-01R2_READ_ONLY_v0.1` подтвердил:
- все три experimental KB-таблицы содержат 0 строк;
- active/leased/error/fragmented counts = 0;
- существуют ровно три experimental таблицы и две B1/B2 функции;
- дополнительных KB-объектов не обнаружено;
- у `qbit_test_sluzhebnyy` нет прямого DML/SELECT к этим таблицам.

Решение: **recreate**, а не migration-on-place. Подробности: `docs/KB-01R2_DECISION.md`.

## KB-01R3 — реализация подготовлена

Подготовлены и сохранены в `main`, но **не применены на Supabase**:

- `sql/DB-04_05_knowledge_recreate_test.sql` — canonical recreate **KB-01R3 v0.2**;
- `sql/DB-04_05_knowledge_verifier.sql` — read-only verifier **KB-01R3_VERIFIER v0.2**;
- `sql/DB-04_05_knowledge_rollback_test.sql` — guarded rollback к состоянию «KB отсутствует» пока новые таблицы пустые;
- `docs/KB-01R3_RECREATE_ROLLBACK.md` — порядок применения и отката.

Recreate v0.2:
- перед DROP повторно сверяет пустоту experimental tables, точный набор объектов и fingerprints B1/B2;
- не использует `CASCADE`;
- в одной транзакции удаляет только подтверждённый experimental KB и создаёт нормативные восемь DB-04 таблиц и DB-05 API;
- реализует durable queue/lease/fencing, immutable index profile, fragments `vector(1024)`, reference checks, draft search, active-only bot search, atomic publish и admin revoke;
- не выдаёт runtime-ролям прямой доступ к KB-таблицам;
- ограничивает изменения sequence только новой KB identity-sequence;
- при ошибке до COMMIT транзакционно возвращает исходное состояние.

Отдельный verifier проверяет владельцев, отсутствие experimental объектов, HNSW/vector(1024), права и компиляционный вход всех прикладных функций под реальными runtime-ролями в READ ONLY транзакции.

**Важно:** GitHub-файлы созданы; на сервере experimental KB пока остаётся как была. DB-04/DB-05 ещё не applied и не verified.

## Текущая одна задача

**KB-01R4 — применить `KB-01R3 v0.2` только в test Supabase и сразу выполнить `KB-01R3_VERIFIER v0.2`.**

Это отдельный server-step. До него:
- не запускать recreate SQL самостоятельно;
- не удалять experimental объекты вручную;
- не импортировать старый KB workflow;
- не включать client RAG;
- production не менять.

После `applied + verified` отдельной задачей понадобятся runtime-тесты DB-04/DB-05 и подтверждение PRE-02E embedding 1024; факт structural verifier сам по себе их не заменяет.

## Ограничения

- Production не изменялась.
- GitHub push и применение SQL на сервер — разные факты.
- Реальные документы компаний, переписки, пароли, токены и дампы БД в репозиторий не сохраняются.
- Experimental evidence SQL из `docs/evidence/KB-01/` не запускать повторно.
