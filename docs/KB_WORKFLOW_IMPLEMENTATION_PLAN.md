# KB-WF — план канонического workflow загрузки знаний

Обновлено: 2026-10-05.

Этот план — активный план реализации knowledge workflow. Нормативные DB-04/DB-05 уже созданы и runtime-проверены на test-контуре через KB-01R4/R5.

Каноническая основа workflow: фактический export Павла `(7)`. Текущий runtime-verified checkpoint KB-01A:
`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`.

## Разбиение KB-01 / KB-02 / KB-03

| Статус / ID | Зависимости | Один результат и критерий |
|---|---|---|
| [x] KB-01A | DB-03D1, DB-04 | Единый service Telegram webhook после durable registration принимает только private `.md` от разрешённого user/chat, ограничивает размер, скачивает файл, проверяет actual bytes и регистрирует через `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)`. Runtime 05.10.2026: `uspeshno`, non-null `zagruzka_id`/`zadanie_id`, `status_zagruzki=poluchena`, успешный Telegram-ответ для filename с `_`. |
| [ ] KB-01B | KB-01A runtime | Knowledge worker claim-ит durable job с lease/fencing, безопасно разбирает YAML/Markdown, проверяет обязательные поля/структуру, рассчитывает canonical hash/processing fingerprint и вызывает `podgotovit_versiyu_znaniy`. Дубль активной версии не идёт дальше. |
| [ ] KB-02A | KB-01B | Детерминированная очистка и chunking сохраняют heading path, FAQ, tables и facts; профиль 600/800/100 считается tokenizer выбранной embedding-модели; reference questions исключены из retrieval text. |
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

## Статическая проверка текущего checkpoint

- 196 nodes;
- 161 connection keys;
- 225 edges;
- `active=false`;
- duplicate names 0;
- dangling connections 0;
- Credential objects отсутствуют;
- whitelist пустой;
- top-level `id`, `versionId`, `meta.instanceId` отсутствуют;
- реальные Telegram ID и service group ID отсутствуют;
- obvious API key / Bearer / Telegram bot token не найдены;
- изменённый Code node проходит `node --check`;
- restore SHA-256: `6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

## KB-01B — следующая задача

Начать только в новой сессии после чтения `PROJECT_STATE` и `SESSION_HANDOFF`.

Scope:
1. claim `zadaniya_znaniy` через нормативный lease/fencing API;
2. безопасно прочитать YAML без исполнения custom types/tags;
3. проверить `identifikator_dokumenta`, `nazvanie`, `tip_dokumenta`, optional version/date/questions;
4. проверить один H1 и последовательные H2–H6 без пропусков;
5. вычислить canonical semantic content hash и processing/profile fingerprints;
6. вызвать `podgotovit_versiyu_znaniy`;
7. корректно остановить duplicate active version;
8. сохранить ошибки/повторы только в рамках fenced job.

Не выполнять chunking, embeddings, reference search или publish в KB-01B.

Production не менять.
