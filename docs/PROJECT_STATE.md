# Текущее состояние проекта

Обновлено: 2026-10-08.

## Режим

Реализация test-контура разрешена. Production, рабочие данные и рабочий трафик не менять без отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и текущие workflow

Текущая repository-safe основа разделена на два workflow:
- `workflows/current/Шаблон Загрузка документов Qbit.json` — service intake + knowledge processing;
- `workflows/current/Шаблон — Workflow бота Qbit.json` — клиентский бот и RAG-ответ.

Credential refs, runtime whitelist, реальные Telegram ID, секреты и реальные документы компаний в Git не сохраняются.

Исторический восстановимый checkpoint KB-01A остаётся в `workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`; старые checkpoints не считать текущей версией для импорта.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test. KB-03A сохранил реальные `vector(1024)` fragments через `sohranit_fragmenty_znaniy`.

При подготовке KB-03B контрактный разрыв между сохранением questions и checks был закрыт задачей KB-03B0.

### KB-03B0 — CLOSED / runtime verified

В TEST применена узкая SECURITY DEFINER-функция:
`qbit_bot_pervichnogo_obrascheniya.poluchit_kontrolnye_voprosy_znaniy(jsonb)`.

Подтверждено:
- owner `qbit_test_owner`;
- service execute true;
- bot/public execute false;
- direct service SELECT `kontrolnye_voprosy` false;
- function выдаёт question IDs только при live fenced job/version;
- production untouched.

Evidence: `docs/evidence/KB-03/KB-03B0_RUNTIME_VERIFIED_2026-10-07.md`.

### KB-03B1 — CLOSED / runtime verified

Runtime 08.10.2026 на safe retry Markdown:
- 53 fragments;
- 9 canonical YAML questions сохранены;
- one-batch question embeddings: OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`;
- 9 vectors, dimension min/max 1024/1024, finite values true, index mapping true;
- OpenAI usage: 237 input/prompt tokens;
- draft search: top-k 12, только своя version/profile;
- positive threshold grid 0.45..0.85 рассчитана по фактическим similarities;
- full pass 9/9 на 0.45, 0.50, 0.55 и 0.60;
- максимальный grid threshold с full pass = 0.60;
- при 0.65 проходит 8/9, при 0.70 — 6/9, при 0.75 — 3/9;
- `sohranit_proverki_znaniy` вернул `uspeshno`, `uspeshnyh=9`, `vsego=9`, `status_versii=gotova`;
- `publish_vypolnen=false`;
- generative LLM calls = 0;
- `next_stage=KB-03C`.

`Служебный_KB_Вернуть после 03B` намеренно освобождает текущий knowledge job через `status='povtor'` и следующий запуск. Для успешного B1 это stage handoff, а не fail: внутри результата `full_pass=true`, `kb03b_gotova`, `status_versii=gotova`, `next_stage=KB-03C`.

Evidence: `docs/evidence/KB-03/KB-03B1_RUNTIME_VERIFIED_2026-10-08.md`.

Исторический неуспешный проход 6/8 сохранён отдельно в `docs/evidence/KB-03/KB-03B1_PARTIAL_RUNTIME_2026-10-07.md` и не является текущим статусом.

## Ограничение нагрузки на LLM

Постоянный guard:
- ingestion/parsing/cleaning/chunking/token count — без generative LLM;
- embeddings — только индекс/search;
- вся база не передаётся клиентской LLM целиком;
- client path: query embedding → vector search → filter/dedupe → небольшой evidence package → final LLM;
- candidate top-k 12, final evidence максимум 8 fragments и обычно меньше;
- LLM reranker в v1 не добавлять без доказанной пользы;
- общий evidence token budget зафиксировать до окончания retrieval-калибровки.

B1 threshold 0.60 является только positive-reference validation threshold. Финальный client threshold ещё требует negative/no-answer calibration.

## Активный план

Родительский план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.
Подплан завершённой задачи: `docs/KB-03B_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A1` → `KB-02A2` → `KB-02B` → `KB-03A` → `KB-03B0` → `KB-03B1` → `KB-03C`.

Закрыты и runtime verified: KB-01A, KB-01B1, KB-01B2, KB-02A1, KB-02A2, KB-02B, KB-03A, KB-03B0, KB-03B1.

## Следующая маленькая задача — KB-03C

Цель: безопасно спроектировать и проверить atomic publish готовой версии с stale-conflict protection и active-only end-to-end regression.

До начала реализации новой сессии нужно прочитать только связанные контракты publish/active search и определить небольшой постоянный ID/критерий готовности. Наличие KB-03C в плане само по себе не означает, что publication или production-развёртывание разрешены.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.