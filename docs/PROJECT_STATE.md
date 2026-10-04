# Текущее состояние проекта

Обновлено: 2026-10-04.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Workflow checkpoint

Последний фактический workflow Павла сохранён как очищенный checkpoint:

`workflows/checkpoints/2026-10-03_v0.3/`

Проверено до упаковки: 189 нод, 153 connection keys, 215 edges, `active=false`, duplicate names 0, dangling connections 0; credentials/instance ID/реальный ID служебной группы удалены. SHA-256 восстановленного compact JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Старый experimental `Шаблон_мультиканальный_KB-01_v0.3.json` **не импортировать**.

## KB-01R1…R3

KB-01R1 выполнила mapping experimental KB к нормативному DB-04/DB-05. KB-01R2 live read-only инвентаризация подтвердила нулевые row counts и выбрала путь **recreate**. KB-01R3 подготовила canonical test-only recreate `KB-01R3 v0.2`, verifier и guarded rollback.

## KB-01R4 — applied + structurally verified

04.10.2026 Павел запустил `sql/DB-04_05_knowledge_recreate_test.sql` в test Supabase.

Фактический результат:
- `status=applied`;
- `migration=KB-01R3_v0.2`;
- schema `qbit_bot_pervichnogo_obrascheniya`.

Experimental B1/B2 и три experimental KB-таблицы больше не являются live test state. На их месте создан нормативный DB-04/DB-05.

Первый verifier с `SET ROLE qbit_test_sluzhebnyy` не смог переключить роль (`42501`). Эта ошибка была только в verifier и не откатывала уже committed recreate. Для проверки без изменения membership создан `sql/DB-04_05_knowledge_verifier_v0.4_no_role_switch.sql`.

Фактический успешный verifier `KB-01R4_VERIFIER_v0.4_NO_ROLE_SWITCH` подтвердил:
- `status=verified`;
- experimental objects absent;
- normative tables present and empty;
- owners OK;
- SECURITY DEFINER/search_path OK;
- PUBLIC EXECUTE denied;
- direct runtime table DML denied;
- EXECUTE matrix OK;
- `vector(1024)` + HNSW OK;
- integrity triggers OK;
- role switch не использовался.

Evidence: `docs/evidence/KB-01/KB-01R4_APPLIED_VERIFIED_2026-10-04.md`.

## Что ещё не проверено

Structural verifier **не** проверял выполнение функций через реальные n8n Postgres Credentials. Также не подтверждён PRE-02E OpenAI embedding `dimensions=1024`.

Пока отдельно не проверены:
- service ingestion и duplicate semantics;
- queue claim/lease/fencing/retry;
- version/profile/fragments/reference checks;
- draft isolation/search;
- stale/parallel publish и atomic active switch;
- bot active-only search;
- admin revoke.

Реальная `.md` база компании не загружалась. Client RAG не включался. Production не менялась.

## Текущая одна задача

**KB-01R5A — runtime-проверить ingestion и knowledge queue под реальным Credential `qbit_test_sluzhebnyy`, используя только синтетические test-данные и завершая тест откатом/очисткой согласно подготовленному сценарию.**

Цель KB-01R5A: доказать реальное выполнение `zaregistrirovat_zagruzku_znaniy`, duplicate/conflict semantics, `zabrat_zadanie_znaniy`, lease/fencing и корректное завершение/retry без перехода к embeddings/publish.

Следующие подэтапы после R5A, не начинать автоматически:
- **KB-01R5B** — version/profile/fragments/reference checks + draft search;
- **KB-01R5C** — publish concurrency/active-only search/revoke;
- **PRE-02E** — фактический OpenAI embedding `dimensions=1024` в каноническом workflow.

## Ограничения

- Production не изменялась.
- Старый B3 не продолжать.
- Старый KB workflow не импортировать.
- Client RAG не включать до нужных runtime-тестов.
- Experimental evidence SQL повторно не запускать.
- `sql/DB-04_05_knowledge_rollback_test.sql` теперь является только аварийным rollback; после появления реальных/нужных KB-данных его нельзя запускать без отдельного плана.
