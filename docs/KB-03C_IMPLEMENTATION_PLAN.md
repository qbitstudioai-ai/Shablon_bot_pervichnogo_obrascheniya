# KB-03C — план публикации знаний

Обновлено: 2026-10-08.

Родительская задача: `KB-03C` из `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

## Исходная точка

KB-03B1 закрыт runtime:
- 53 fragments;
- 9/9 canonical reference checks;
- `status_versii=gotova`;
- positive-reference validation threshold 0.60;
- `publish_vypolnen=false`;
- `next_stage=KB-03C`.

Текущий repository-safe workflow документов:
`workflows/current/Шаблон Загрузка документов Qbit.json`.

В нём нет вызова `opublikovat_versiyu_znaniy`: текущая цепочка заканчивается после KB-03B1 и возвращает job для следующего этапа.

Текущий workflow бота уже использует опубликованный поиск через `poisk_aktivnyh_znaniy`; поэтому на этапе KB-03C1 его не меняем.

Нормативный DB-05 контракт публикации:
- публиковать можно только готовую version;
- `opublikovat_versiyu_znaniy` проверяет ready/fragments/vectors/checks;
- publication одной транзакцией меняет active pointer, переводит новую version в `opublikovana`, предыдущую active version — в `arhiv`, upload — в `zavershena`;
- stale `ozhidaemaya_aktivnaya_versiya_id` должна давать conflict, а не перезаписывать чужую публикацию;
- клиентский `poisk_aktivnyh_znaniy` видит только active published version.

## Почему KB-03C разделена

Atomic publish меняет состояние TEST БД и active pointer. Это отдельный риск от подготовки workflow. Поэтому сначала готовим и статически проверяем publish branch без запуска, затем отдельной задачей выполняем runtime publication и active-only regression.

## [~] KB-03C1 — подготовить publish branch без server execution

### Цель

Подготовить новую repository-safe версию `Шаблон Загрузка документов Qbit.json`, которая после успешного KB-03B1 умеет безопасно перейти к вызову `opublikovat_versiyu_znaniy`, но в рамках KB-03C1 не импортируется и не выполняется на сервере.

### Условия начала

- KB-03B1 runtime verified 9/9;
- version в TEST подтверждённо `gotova`;
- production и рабочий трафик не затрагиваются;
- перед изменением JSON прочитать только фактическую SQL-реализацию/контракт `opublikovat_versiyu_znaniy` и `zavershit_zadanie_znaniy`, чтобы не угадывать payload/status.

### Разрешённый объём

Изменяется только workflow документов и связанные документы состояния.

Нужно:
1. сохранить весь подтверждённый KB-01A…KB-03B1 путь без регрессии;
2. добавить явный gate: publish path доступен только после подтверждённого `full_pass=true` и `status_versii=gotova`;
3. сформировать payload публикации только из доверенного runtime/DB context, включая exact `versiya_id`, expected active version и стабильный operation id по фактическому DB contract;
4. вызвать `opublikovat_versiyu_znaniy` только service Postgres node;
5. отдельно обработать success, stale/conflict и техническую ошибку fail-closed;
6. не считать Telegram/reporting подтверждением публикации: источник истины — результат DB function;
7. не менять workflow клиентского бота в KB-03C1;
8. не выполнять publication, import, activation или server mutation в этой подзадаче.

Названия новых n8n нод — по-русски. Credential bindings и секреты в Git не сохранять.

### Критерий готовности KB-03C1

- создан полный import-ready repository-safe JSON workflow документов;
- JSON валиден;
- нет duplicate node names и dangling connections;
- Code nodes проходят syntax check;
- publish path достижим только после подтверждённого B1 full pass/`gotova`;
- exact DB function name/payload/status взяты из текущей SQL-реализации, а не из предположения;
- stale/conflict не меняет active version и не маскируется как success;
- существующий KB-03B1 путь не изменён по смыслу;
- Credential refs, токены, реальные Telegram ID и документы компаний отсутствуют;
- ничего не импортировано и не запущено на n8n/Supabase;
- подготовлен понятный runtime plan для KB-03C2.

### Откат

Поскольку KB-03C1 не меняет сервер, откат — Git revert кандидата или возврат к текущему `workflows/current/Шаблон Загрузка документов Qbit.json`. Активная версия знаний в TEST не меняется.

## [ ] KB-03C2 — runtime atomic publish + active-only regression

Начинать только после закрытия KB-03C1 и отдельного решения о конкретном TEST publish.

Минимальный будущий критерий:
- готовая version публикуется атомарно;
- stale expected-active даёт conflict без смены active pointer;
- bot search через `poisk_aktivnyh_znaniy` видит новую published version и не видит draft/archive;
- предыдущая active version ведёт себя по DB-05 contract;
- результат publication и client-search подтверждён runtime evidence;
- production untouched.

План отката TEST publication должен быть уточнён по фактическому DB-05 SQL до первого mutating runtime запуска. Прямой DML для отката запрещён.

## Ограничения

- Production не менять.
- Рабочий трафик не переключать.
- KB-03C1 не выполняет публикацию.
- Не использовать старый experimental workflow.
- Не публиковать секреты, Credential refs, Telegram ID, реальные документы или переписку.
- B1 threshold 0.60 не считать финальным client retrieval threshold без negative/no-answer calibration.
