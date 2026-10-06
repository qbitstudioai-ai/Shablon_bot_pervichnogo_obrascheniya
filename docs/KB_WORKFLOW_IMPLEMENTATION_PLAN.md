# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-06.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Текущий runtime-verified checkpoint KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Единый service Telegram webhook после durable registration принимает только private `.md` от разрешённого user/chat, ограничивает размер, скачивает файл, проверяет actual bytes и регистрирует через `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)`. Runtime 05.10.2026: `uspeshno`, non-null `zagruzka_id`/`zadanie_id`, `status_zagruzki=poluchena`, успешный Telegram-ответ для filename с `_`. |
| [x] KB-01B1 | KB-01A runtime | Изолированный Manual Trigger claim-ит одно durable knowledge job через `zabrat_zadanie_znaniy` с lease/fencing, безопасно разбирает YAML/Markdown без исполнения тегов/кода, проверяет обязательные metadata и heading structure и рассчитывает canonical `hash_soderzhaniya`. Runtime 06.10.2026: реальный зарегистрированный `.md` успешно claim-нут, parser valid, 57 headings, 8 reference questions, deterministic hash `73436107...`, job освобождён обратно в `povtor` тем же worker/fence. |
| [ ] KB-01B2 | KB-01B1 runtime | Зафиксировать фактически доступный processing/index profile и tokenizer, вычислить `otpechatok_obrabotki` + `otpechatok_profilya` и вызвать `podgotovit_versiyu_znaniy` под тем же live lease/fencing. Active version с тем же processing fingerprint останавливается как дубль; новый вариант получает draft `chernovik`. Ошибки/повторы изменяют только текущий fenced job. |
| [ ] KB-02A | KB-01B2 | Детерминированная очистка и chunking сохраняют heading path, FAQ, tables и facts; профиль 600/800/100 считается tokenizer выбранной embedding-модели; reference questions исключены из retrieval text. |
| [ ] KB-02B | KB-02A | 3–10 reference questions извлечены отдельно, окончательные fragments имеют metadata/hash/token count; ошибки безопасно завершают или повторяют только текущий fenced job. |
| [ ] KB-03A | KB-02B | Document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float`; каждый vector length строго проверяется; fragments/vectors сохраняются через normative DB API. Это runtime бывшего PRE-02E. |
| [ ] KB-03B | KB-03A | Reference questions векторизуются тем же профилем; `poisk_chernovika_znaniy` работает только по своей версии; результаты сохраняются через `sohranit_proverki_znaniy`; `gotova` только после полного pass. |
| [ ] KB-03C | KB-03B | `opublikovat_versiyu_znaniy` атомарно переключает active version и архивирует прежнюю; stale publish конфликтует; Telegram report идёт после publish; knowledge job корректно завершается. |

## KB-01A — завершено

Реализовано и runtime-проверено:
- единый существующий service webhook;
- DB-03D1 durable event до KB routing;
- private chat + whitelist + `.md` + declared size;
- Telegram file download;
- actual bytes/size check;
- service Postgres call к `zaregistrirovat_zagruzku_znaniy`;
- `uspeshno` → durable upload + durable knowledge job;
- финальный Telegram report.

Во время первого runtime обнаружено, что filename с `_` ломал Telegram entity parser. Исправлено:
- HTML-escaping dynamic values;
- `parse_mode=HTML`.
Повторный safe `.md` с `_` в имени успешно подтвердил исправление.

Evidence:
`docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## Канонический checkpoint перед KB-01B1

- 196 nodes;
- 161 connection keys;
- 225 edges;
- `active=false`;
- Credential objects отсутствуют;
- whitelist пустой;
- реальные Telegram ID и service group ID отсутствуют;
- restore SHA-256: `6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

## KB-01B1 — завершено / runtime verified

Причина отдельного шага: `podgotovit_versiyu_znaniy` требует уже зафиксированный tokenizer/profile, а runtime-доступность tokenizer в self-hosted n8n ещё не доказана. Поэтому immutable profile/draft нельзя создавать на догадке.

Реализованный scope KB-01B1:
1. отдельный Manual Trigger, не подключённый к рабочим webhook;
2. claim одного `ozhidaet/povtor` job через нормативный `zabrat_zadanie_znaniy`;
3. live lease + worker + `nomer_vladeniya` используются во всех последующих DB-действиях;
4. исходные bytes сверяются с `hash_istochnika`;
5. UTF-8 и front matter разбираются без внешних модулей и без исполнения YAML tags/custom types;
6. принимаются только документированные YAML-поля; duplicate/unknown/unsafe keys отклоняются;
7. проверяются `identifikator_dokumenta`, `nazvanie`, `tip_dokumenta`, optional date/version/questions;
8. Markdown проверяется на один H1, совпадение H1 с `nazvanie` и последовательные уровни H2–H6 вне fenced code;
9. рассчитывается canonical semantic payload и SHA-256 `hash_soderzhaniya` с metadata + structure/content;
10. после B1-проверки job освобождается через `zavershit_zadanie_znaniy(... status='povtor')`.

Runtime 06.10.2026:
- `zadanie_id=0032a78e-b3fa-4cc8-8175-fcc52b53dd64`;
- `zagruzka_id=2d94322c-0347-48ce-8c66-e136e79d54d4`;
- worker `qbit_test_kb_worker_v1`, fence `1`;
- parser `kb01b1_safe_frontmatter_markdown_v1` → `valid=true`, `kod=provereno`;
- 57 структурных заголовков;
- 8 контрольных вопросов;
- warnings 0;
- `hash_soderzhaniya=73436107b06ed1465094f23f785dadbb973adc787e049c04966195ae629e2290`;
- `zavershit_zadanie_znaniy` вернула `uspeshno`, итоговый `status_zadaniya=povtor`.

Фактические bytes из runtime output повторно прогнаны через тот же Code-node parser вне n8n: повторно получены 57 headings, 8 questions и тот же content hash. Предварительный ориентир `be8f4f8d...` был ошибочным и больше не используется.

Evidence:
`docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

Полный v0.5 был import-ready и runtime-проверен, но его новый Git checkpoint ещё отдельно не сохранён. Не считать локальный JSON автоматически каноническим Git-артефактом до отдельного сохранения.

## Следующая задача — KB-01B2

Цель:
- доказать фактически доступный tokenizer/profile в self-hosted n8n;
- вычислить `otpechatok_profilya` и `otpechatok_obrabotki`;
- под тем же live lease/fencing вызвать `podgotovit_versiyu_znaniy`;
- проверить active duplicate stop и создание `chernovik` для нового варианта;
- terminal/retry paths должны менять только текущий fenced job.

Не выполнять chunking, embeddings, reference search или publish в KB-01B2.

Production не менять.
