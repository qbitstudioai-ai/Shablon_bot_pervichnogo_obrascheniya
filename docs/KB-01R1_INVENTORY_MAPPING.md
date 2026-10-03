# KB-01R1 — read-only инвентаризация и mapping experimental KB → DB-04/DB-05

Дата: 2026-10-03.

Статус: **KB-01R1 завершена как сверка подтверждённого checkpoint-состояния**.

## Граница проверки

Исходный checkpoint: `bb729507ba1ccfc33e2a93c009b37fd3010df191` (`main`).

Использованы только зафиксированные в GitHub доказательства фактически применённых test-команд и нормативные документы:
- `docs/KB-01_APPLIED_TEST_STATE_2026-10-03.md`;
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_tables_2026-10-03.sql`;
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B1_v0.9.sql`;
- `docs/evidence/KB-01/EXPERIMENTAL_DO_NOT_APPLY_KB-01_B2_v0.10.sql`;
- `docs/specs/DB_CONTRACT.md`;
- `docs/specs/KNOWLEDGE_INGESTION.md`.

В этой сессии нет подключённого прямого доступа к test PostgreSQL/Supabase, поэтому **новый live `pg_catalog` snapshot не выполнялся**. Ни один SQL на сервер не запускался. Ниже инвентаризируется подтверждённое checkpoint-состояние 03.10.2026; оно не подменяется утверждением о новом live-аудите.

Production не проверялась и не изменялась.

## 1. Подтверждённые experimental KB-объекты test schema

Schema: `qbit_bot_pervichnogo_obrascheniya`.

### Таблицы

1. `znaniya_dokumenty`
   - owner: `qbit_test_owner`;
   - ключевые поля: `id`, `kompaniya_kod`, `sreda`, `put_logicheskiy`, `nazvanie`, `aktivnaya_versiya_id`, timestamps;
   - UNIQUE: `(kompaniya_kod, sreda, put_logicheskiy)`.

2. `znaniya_versii`
   - owner: `qbit_test_owner`;
   - объединяет поля версии, входящего Telegram-файла и очереди/lease;
   - содержит `dokument_id`, `nomer_versii`, `status`, `klyuch_idempotentnosti`, Telegram file/event fields, `model_embedding`, `razmernost_embedding=1024`, lease/fencing, attempts, error fields и timestamps;
   - UNIQUE: `klyuch_idempotentnosti`, `(dokument_id, nomer_versii)`.

3. `znaniya_fragmenty`
   - owner: `qbit_test_owner`;
   - поля: `id`, `versiya_id`, `nomer_fragmenta`, `put_razdela`, `soderzhanie`, `embedding vector(1024)`, `metadannye`, `vremya_sozdaniya`;
   - UNIQUE: `(versiya_id, nomer_fragmenta)`.

### Связи и индексы

Подтверждены:
- FK `znaniya_dokumenty_aktivnaya_versiya_fk`;
- FK `znaniya_versii.dokument_id → znaniya_dokumenty.id` из применённого evidence DDL;
- FK `znaniya_fragmenty.versiya_id → znaniya_versii.id` из применённого evidence DDL;
- индекс `znaniya_versii_status_idx`;
- индекс `znaniya_fragmenty_versiya_idx`.

Также применялся `GRANT USAGE ON SCHEMA extensions TO qbit_test_owner`, необходимый экспериментальной таблице с `extensions.vector(1024)`.

### Функции

1. `kb01_postavit_dokument(jsonb) RETURNS jsonb`
   - owner `qbit_test_owner`;
   - `SECURITY DEFINER`;
   - фиксированный `search_path`;
   - `PUBLIC EXECUTE` отозван;
   - `EXECUTE` выдан `qbit_test_sluzhebnyy`;
   - runtime checkpoint: first → `uspeshno/ozhidaet`, repeat same idempotency key → `dublikat`, IDs совпали; runtime-тест завершён `ROLLBACK`.

2. `kb01_zabrat_sleduyushchuyu_versiyu(jsonb) RETURNS jsonb`
   - owner `qbit_test_owner`;
   - `SECURITY DEFINER`;
   - фиксированный `search_path`;
   - `PUBLIC EXECUTE` отозван;
   - `EXECUTE` выдан `qbit_test_sluzhebnyy`;
   - прямая `UPDATE`-привилегия на `znaniya_versii` у `qbit_test_sluzhebnyy` отсутствует;
   - runtime checkpoint: первый worker → `v_rabote`, `nomer_vladeniya=1`, `popytki=1`; второй worker → `net_zadaniya`; runtime-тест завершён `ROLLBACK`.

### Не создано в experimental KB

Не созданы B3/publish/error/search-функции. Полный KB workflow в n8n не импортирован. Первая реальная `.md` загрузка не выполнялась.

## 2. Mapping таблиц к нормативному DB-04

| Experimental object | Нормативный объект | Соответствие | Ключевые расхождения |
|---|---|---|---|
| `znaniya_dokumenty` | `dokumenty_znaniy` | Частичное | Норматив использует один `identifikator_dokumenta` внутри schema компании. Experimental хранит `kompaniya_kod` и `sreda` внутри строки и строит `put_logicheskiy` из имени файла. `nazvanie` по нормативу относится к версии. FK активной версии сам по себе не гарантирует «эта же версия этого же документа + status=opublikovana». |
| `znaniya_versii` | `zagruzki_znaniy` | Частичное и смешанное | Telegram/event/file/error-поля частично похожи на загрузку, но нет отдельной записи загрузки, исходных `.md` bytes, `hash_istochnika`, `hash_soderzhaniya`, `poryadok_priema`, нормативного lifecycle загрузки и связей upload→document/version. |
| `znaniya_versii` | `zadaniya_znaniy` | Частичное и смешанное | Lease/fencing/attempts встроены в версию. Нет отдельного job ID, `zagruzka_id`, `tip_zadaniya`, `prioritet`, `sleduyushchiy_zapusk`, `ozhidaemaya_aktivnaya_versiya_id`, payload и независимого lifecycle durable-очереди. |
| `znaniya_versii` | `versii_dokumentov_znaniy` | Частичное | Есть `dokument_id`, номер и часть статусов, но `ozhidaet/v_rabote` являются состояниями очереди, а не нормативной версии. Нет `zagruzka_id`, metadata source, content hash, processing fingerprint, profile FK, expected active version, verification/archive timestamps. |
| `model_embedding` + `razmernost_embedding` внутри `znaniya_versii` | `profili_indeksa` | Недостаточное | Норматив требует отдельный неизменяемый профиль с fingerprint, parser/cleanup/chunking/tokenizer параметрами и размерностью. Модель+размерность в строке версии не заменяют профиль. |
| `znaniya_fragmenty` | `fragmenty_znaniy` | Частичное | Базовые ID/version/number/path/text/vector совпадают по смыслу, но отсутствуют `kolichestvo_tokenov`, `hash_fragmenta`, нормативный HNSW cosine index и проверяемая связь с immutable index profile. Поле `metadannye jsonb` не заменяет обязательные структурные поля. |
| отсутствует | `kontrolnye_voprosy` | Нет | Норматив требует отдельные 3–10 контрольных вопросов для первой публикации с expected section/fact. |
| отсутствует | `proverki_znaniy` | Нет | Нет долговечного результата draft-search проверки, threshold/top-k, найденных fragment IDs/similarities и результата приёмки. |

Итого: три experimental-таблицы **не являются трёмя переименовываемыми нормативными таблицами**. `znaniya_versii` физически смешивает минимум три разных нормативных сущности и часть четвёртой.

## 3. Mapping функций к нормативному DB-04/DB-05

| Experimental function | Ближайший нормативный контракт | Соответствие | Расхождение |
|---|---|---|---|
| `kb01_postavit_dokument(jsonb)` | `zaregistrirovat_zagruzku_znaniy` + частично `podgotovit_versiyu_znaniy` | Неполное, объединённое | Одна функция сразу создаёт/находит документ и создаёт «версию-очередь». Нет отдельной загрузки, отдельной job-записи, сохранения bytes/hash, parsed document identity, processing fingerprint и expected active version. |
| `kb01_zabrat_sleduyushchuyu_versiyu(jsonb)` | `zabrat_zadanie_znaniy` | Частичное | Claim выполняется прямо по строке версии. Нет отдельного `zadaniya_znaniy`, task type/priority/next run/expected active; нет нормативных `prodlit_arendu_zadaniya_znaniy` и `zavershit_zadanie_znaniy`. |
| отсутствует | `podgotovit_versiyu_znaniy` | Нет | Отдельного атомарного создания/нахождения документа, назначения next version и фиксации expected active version нет. |
| отсутствует | `sohranit_fragmenty_znaniy` | Нет | B3 не создана; batch/profile/dimension/count/hash readiness не реализованы. |
| отсутствует | `sohranit_kontrolnye_voprosy` | Нет | Контрольные вопросы не хранятся. |
| отсутствует | `sohranit_proverki_znaniy` | Нет | Результаты проверочного поиска не хранятся. |
| отсутствует | `poisk_chernovika_znaniy` | Нет | Нормативный draft-only search DB-05 отсутствует. |
| отсутствует | `poisk_aktivnyh_znaniy` | Нет | Клиентский поиск только через `aktivnaya_versiya_id` и `opublikovana` отсутствует. |
| отсутствует | `opublikovat_versiyu_znaniy` | Нет | Нет атомарного active-pointer switch + new published + old archive + upload complete + stale expectation conflict. |
| отсутствует | `otozvat_dokument_znaniy` | Нет | Явный административный отзыв без физического удаления отсутствует. |

## 4. Контрактные расхождения, влияющие на выбор миграции

1. **Изоляция компании.** Нормативная компания определяется schema/credential. Experimental B1/B2 дополнительно принимают `kompaniya_kod` и `sreda` из JSON и хранят их в `znaniya_dokumenty`. Это не должно становиться механизмом выбора tenant.
2. **Идентичность документа.** Experimental использует `lower(imya_fayla)` как `put_logicheskiy`; норматив требует постоянный `identifikator_dokumenta`, извлечённый из проверенного содержимого/метаданных. Переименование файла не меняет идентичность.
3. **Загрузка, job и версия смешаны.** Это главное структурное несовпадение; простое переименование таблиц не исправляет контракт.
4. **Не хранится нормативный вход.** Нет защищённого `ishodnyy_fayl bytea`, source/content hashes и отдельного lifecycle загрузки `.md` UTF-8 до 5 MiB.
5. **Нет immutable index profile.** `model_embedding` и `razmernost_embedding` недостаточны для воспроизводимости parser/cleanup/chunking/tokenizer.
6. **Нет acceptance layer.** Отсутствуют контрольные вопросы и сохранённые результаты draft-проверок.
7. **Публикация не реализована.** Нельзя доказать атомарное переключение активной версии и защиту от stale worker.
8. **DB-05 отсутствует.** Нет ни draft search, ни client active-only search.
9. **Фрагменты неполные.** Нет token count/hash и HNSW cosine индекса, требуемых нормативной моделью.
10. **Active FK недостаточен.** Наличие ссылки `aktivnaya_versiya_id` без нормативной publish-функции не доказывает, что active version опубликована и принадлежит тому же документу.

## 5. Вывод KB-01R1

Mapping завершён. Experimental KB нельзя продолжать через B3 как будто B1/B2 уже являются DB-04: дальнейшее наращивание закрепило бы несовместимый контракт.

На текущем шаге **не выбран** путь «мигрировать» или «пересоздать». Это отдельная задача **KB-01R2**. До неё:
- experimental объекты не удалять;
- новый SQL на сервер не применять;
- B3 не продолжать;
- старый KB workflow не импортировать;
- client RAG не включать;
- production не менять.

Для выбора пути в KB-01R2 нужно исходить из этой таблицы соответствия и, если потребуется актуальное состояние данных, получить отдельное read-only подтверждение текущих row counts/object signatures в test schema. Нельзя предполагать, что таблицы пусты, только потому что runtime-тесты B1/B2 завершались `ROLLBACK`.
