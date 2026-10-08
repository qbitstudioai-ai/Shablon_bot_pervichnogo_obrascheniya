# KB-03B1 — runtime verified, 2026-10-08

## Статус

KB-03B1 **CLOSED / runtime verified**.

Финальный safe retry execution дал полный positive-reference pass. Version переведена в `gotova`. Publish не выполнялся. Production и рабочий трафик не менялись.

## Подтверждённый runtime

На большой safe Markdown-базе:
- fragments = 53;
- canonical YAML reference questions = 9;
- `Служебный_KB_Сохранить вопросы`: `rezultat=uspeshno`, `kolichestvo_voprosov=9`;
- question IDs получены через runtime-verified KB-03B0 bridge под live fenced job/version;
- один OpenAI batch для 9 exact question texts;
- model `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- vectors = 9;
- vector dimension min/max = 1024/1024;
- все vector values finite;
- mapping по OpenAI index подтверждён;
- exact question text input подтверждён;
- API usage = 237 input/prompt tokens;
- generative LLM calls = 0.

Draft search:
- top-k = 12;
- `draft_only=true`;
- `version_scoped=true`;
- `profile_scoped=true`;
- expected section + expected fact проверяются в одном fragment детерминированно.

## Калибровка positive reference set

Фактическая grid:
- 0.45 → 9/9, full pass;
- 0.50 → 9/9, full pass;
- 0.55 → 9/9, full pass;
- 0.60 → 9/9, full pass;
- 0.65 → 8/9;
- 0.70 → 6/9;
- 0.75 → 3/9;
- 0.80 → 0/9;
- 0.85 → 0/9.

По правилу B1 выбран максимальный grid threshold с полным positive pass: **0.60**.

Этот threshold не является финальным client retrieval threshold. Для клиентского threshold позже всё ещё нужен negative/no-answer набор.

## Сохранение checks

`Служебный_KB_Сохранить проверки` подтвердил:
- `rezultat=uspeshno`;
- `uspeshnyh=9`;
- `vsego=9`;
- `status_versii=gotova`;
- `publish_vypolnen=false`.

Это удовлетворяет fail-closed контракту: только полный pass всех canonical questions переводит version в `gotova`.

## Release job

`Служебный_KB_Вернуть после 03B` подтвердил:
- DB result = `uspeshno`;
- `kb03b_rezultat.kod=kb03b_gotova`;
- `full_pass=true`;
- `next_stage=KB-03C`;
- `publish_vypolnen=false`.

Внешний `status_zadaniya=povtor` здесь ожидаем для текущей ручной test-цепочки: нода `Служебный_KB_Вернуть после 03B` намеренно вызывает `zavershit_zadanie_znaniy` со `status='povtor'` и будущим `sleduyushchiy_zapusk`, освобождая fenced lease и оставляя job для следующего этапа. Это не означает провал KB-03B1.

## История предыдущего fail

Предыдущий runtime 07.10.2026 дал 6/8 и корректно оставил version в `chernovik`. После исправления safe YAML reference set число canonical questions стало 9, и финальный retry прошёл 9/9.

Исторический evidence сохранён отдельно:
`docs/evidence/KB-03/KB-03B1_PARTIAL_RUNTIME_2026-10-07.md`.

## Итог

Критерий KB-03B1 выполнен полностью:
- canonical questions сохранены;
- B0 IDs bridge отработал;
- question embeddings валидны;
- draft-only/version/profile search подтверждён;
- calibration grid рассчитана;
- deterministic checks сохранены;
- full pass 9/9;
- DB status `gotova`;
- publish=false;
- production untouched.

Следующий этап: **KB-03C — atomic publish + stale-conflict protection + active-only end-to-end regression**.