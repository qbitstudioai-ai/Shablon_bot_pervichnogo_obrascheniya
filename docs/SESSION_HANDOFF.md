# SESSION HANDOFF

Обновлено: 29 сентября 2026.

## Канонический workflow

`workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

Это полный пользовательский workflow, а не новый skeleton: 168 нод, 135 connection keys. В WF-02B2A изменён только первый участок DB-взаимодействия.

## WF-02B2A завершён offline

- client ingress → `zaregistrirovat_vhod_klienta(jsonb)`;
- HTTP 200 только после `uspeshno/dublikat`;
- конкретный job больше не забирается прямо после webhook;
- queue branch настроен на `zabrat_zadanie_obrabotki(jsonb)`;
- queue claim временно disabled, потому что downstream пока старого формата;
- AI/STT/media/outgoing/reminders/service часть не менялась;
- `instanceId`, secrets и Credential IDs в канонический export не добавлены.

## WF-02B2B завершён offline

В том же каноническом полном JSON:
- source → `poluchit_soderzhimoe_zadaniya(jsonb)`;
- context/owner/block → `poluchit_kontekst_dialoga(jsonb)`;
- rate-limit → `proverit_limit_chastoty(jsonb)`;
- denied rate-limit → fenced retry через `zavershit_zadanie_obrabotki`;
- 168 нод сохранены; connection keys = 138;
- media/STT/AI/outgoing не менялись.

Queue claim остаётся disabled до DB-03E apply+verify. Значения rate-limit оставлены обязательными null-настройками, их нельзя угадывать.

## WF-02B2C завершён offline

В том же полном JSON:
- successful local STT → `sohranit_transkripciyu_golosa(jsonb)`;
- local PII detector адаптирован к DB reverse-map;
- de-identification → `sohranit_obezlichivanie(jsonb)`;
- `bezopasnost.region_telefona` добавлен как обязательная trusted null-настройка;
- 168 нод / 138 connection keys сохранены;
- AI/outgoing/media transport не менялись.

## WF-02B2D завершён offline

В том же полном JSON:
- thematic guard → OpenAI Responses API;
- model: `gpt-6-luna`;
- `store=false`;
- strict Structured Output через `text.format/json_schema`;
- parser адаптирован к Responses output и fail-closed handoff;
- OpenAI Credential ID/API key в export отсутствуют;
- planner, embedding, основной answer и outgoing не менялись;
- 168 нод / 138 connection keys сохранены.

PRE-02E остаётся runtime-unverified до фактического запуска с OpenAI Credential в n8n.

## WF-02B2E завершён offline

В том же полном JSON:
- planner → OpenAI Responses API;
- model: `gpt-6-luna`;
- `store=false`;
- strict Structured Output: 1–3 queries, 1–5 required_points;
- parser адаптирован к Responses output и сохраняет fallback на обезличенный исходный запрос;
- OpenAI Credential ID/API key в export отсутствуют;
- guard остаётся OpenAI;
- query embedding остаётся OpenRouter/Qwen;
- основной answer/outgoing не менялись;
- 168 нод / 138 connection keys сохранены.

PRE-02E остаётся runtime-unverified.

## WF-02B2F завершён offline

В том же полном JSON:
- query embedding → OpenAI `/v1/embeddings`;
- model: `text-embedding-3-large`;
- candidate `dimensions=1024`, `encoding_format=float`;
- parser проверяет точную размерность и числовые значения;
- DB-05 search node не менялся и search не включался;
- guard/planner остаются OpenAI;
- основной answer/outgoing не менялись;
- 168 нод / 138 connection keys сохранены.

PRE-02E остаётся runtime-unverified; 1024 и retrieval quality ещё должны быть подтверждены фактическим запуском.

## WF-02B2G завершён offline

В том же полном JSON:
- основной answer → OpenAI Responses API;
- model: `gpt-6-sol`;
- `store=false`;
- strict Structured Output сохранён по полям текущего решения;
- parser адаптирован к Responses output и fail-closed handoff;
- OpenRouter/DeepSeek полностью удалены из workflow;
- guard/planner/answer = OpenAI Responses; query embedding = OpenAI embeddings;
- outgoing/DB-03C4 не менялись;
- RAG search остаётся gated до DB-05;
- 168 нод / 138 connection keys сохранены.

PRE-02E остаётся runtime-unverified до запуска в n8n.

## WF-02B2H завершён offline

В том же полном JSON:
- outgoing intent → `sozdat_ishodyashchee_deystvie(jsonb)`;
- sender claim → `zabrat_ishodyashchee_deystvie(jsonb)`;
- final pre-send recheck → DB-03E `poluchit_soderzhimoe_ishodyashchego(jsonb)`;
- external confirmed/unknown → `zafiksirovat_rezultat_ishodyashchego(jsonb)`;
- unknown result не retry-ится вслепую;
- `Взять исходящее действие` остаётся disabled до DB-03E apply+verify;
- processing claim также disabled;
- добавлена обязательная trusted-настройка `napominaniya.okno_napominaniya_minut=null`;
- ручной manager send не менялся;
- 168 нод / 139 connection keys.

## WF-02B2I завершён offline

В том же полном JSON:
- thematic violation → `zapisat_narushenie_tematiky(jsonb)`;
- exact warning → `sozdat_preduprezhdenie_tematiky(jsonb)` без второго generic outgoing;
- non-block warning завершает current job; blocking warning оставляет stale job для безопасного DB cleanup;
- handoff → `zaprosit_cheloveka(jsonb)`; current job отменяется внутри DB, owner остаётся bot до Take;
- opt-out → `ustanovit_zapret_iniciativy(jsonb)`; current job/ожидание/не начатые actions отменяются внутри DB;
- клиентское handoff/opt-out подтверждение создаётся только после `uspeshno/dublikat`;
- AI, sender, service Telegram не менялись;
- processing/sender gates остаются disabled;
- 168 нод / 139 connection keys.

## WF-02B2J завершён offline

В `Сохранить намерение отправки`:
- сначала durable intent → `sozdat_ishodyashchee_deystvie(jsonb)`;
- затем при `uspeshno/dublikat` обычный current job → fenced `zavershit_zadanie_obrabotki(status=zaversheno)`;
- handoff/opt-out finish не дублируется, потому что их DB-03E функции уже закрывают current job;
- warning остаётся отдельным special path;
- 168 нод / 139 connection keys;
- processing/sender gates остаются disabled.

## WF-02B2K завершён

Статически проверены все 34 PostgreSQL-ноды канонического workflow.
- 16 текущих DB-03/DB-03E вызовов;
- 1 disabled no-op;
- 17 остаточных: reminders 1, service ingress/topic/mirror 8, Take/Return/manual/manager 6, RAG 1, integration 1.
- Подробная карта: `docs/WF-02B2K_DB_CALL_AUDIT.md`.
- Workflow в этом блоке не менялся: 168 нод / 139 connection keys.
- DB-03E не применялся.

## WF-02B2L завершён offline

В reminder-ветке:
- `Взять допустимые напоминания` → `Обработать следующее напоминание`;
- old `vzyat_napominaniya_k_otpravke` → DB-03E `obrabotat_sleduyushchee_napominanie(jsonb)`;
- trusted reminder texts + loss timeout передаются из настроек;
- DB сама выбирает один due reminder/loss-check и делает final recheck;
- если нужен send, создаётся обычный outgoing action;
- прямое соединение reminder → sender удалено; общий sender забирает action отдельно;
- reminder node disabled до DB-03E apply+verify;
- workflow: 168 нод / 139 connection keys.

## WF-02B2M завершён offline

Service webhook ingress:
- normalizer строит DB-03D1 packet с trusted account, update_id, idempotency и raw payload;
- `prinyat_sluzhebny_vhod_telegram` → `zaregistrirovat_sluzhebnoe_sobytie(jsonb)`;
- HTTP 200 только после `uspeshno/dublikat`;
- немедленная связь к legacy `Взять служебное задание` удалена;
- сами old service queue/topic/mirror/Take/Return/manual ноды не менялись;
- 168 нод / 139 connection keys; workflow inactive.

## WF-02B2N завершён offline

Service mirror runtime:
- claim → `zabrat_sobytie_zerkala(jsonb)` с lease/fencing;
- DB-03D1 event types нормализованы;
- target chat/thread только из claim;
- media → локальные DB bytes, не client Telegram file_id;
- confirmed/unknown/error → `zafiksirovat_rezultat_zerkala(jsonb)`;
- confirmed только при точном Telegram message_id;
- ambiguous = terminal `neizvestno`; local missing media bytes = `oshibka`;
- mirror claim disabled до topic migration;
- topic/Take/Return/manual не менялись;
- 168 нод / 139 connection keys.

## Следующая задача

**WF-02B2O — создание operator forum-topic по DB-03D1.**

Менять только topic claim → createForumTopic → confirm/unknown с worker/fencing. Mirror/Take/Return/manual не расширять.

DB-03E подготовлен, но не применён на Supabase; production/traffic/Credentials не менять без отдельного разрешения Павла.


## Передача после WF-02B2O — 30.09.2026

WF-02B2O завершён offline на `main`. Канонический workflow переведён с legacy direct topic/save/error на DB-03D1 topic claim → `createForumTopic` → confirm/unknown с worker/lease/fencing. Blind HTTP retry удалён; ambiguous result terminal `neizvestno`. Initial card создаётся через DB-03D1 mirror event после confirm. Topic и mirror claim disabled; production/traffic/Credentials не менялись. Статика: 167 нод, 140 connection keys, dangling connections нет. Следующий ID: WF-02B3 — test import/smoke в отдельной сессии.


## DB-03E v0.6 correction — 30.09.2026

- Первый разрешённый запуск DB-03E v0.5 в test Supabase завершился ошибкой `42501: permission denied for function poluchit_soderzhimoe_zadaniya` до COMMIT; ожидается полный rollback транзакции.
- Причина: disposable behavior probe выполнялся после `RESET ROLE` от `postgres`, тогда как `PUBLIC EXECUTE` на новых SECURITY DEFINER функциях уже отозван.
- В v0.6 probe выполняется под `qbit_test_owner`; статическая проверка runtime privilege split остаётся неизменной.
- Дополнительно исправлен итоговый `functions_ok`: ожидаются 7 функций, а не 4.
- Новый verifier: `sql/DB-03E_v0.6_verify.sql`.
- Следующее действие Павла: повторно выполнить целиком `sql/DB-03E_runtime_gap_closure.sql` v0.6 в test Supabase и прислать полный результат; verifier запускать после разбора результата.


## DB-03E v0.7 correction — 30.09.2026
- v0.6 повторила 42501 до COMMIT.
- Точная причина уточнена: ACL REVOKE/GRANT выполнялись как postgres после RESET ROLE, а новые функции owned by qbit_test_owner.
- v0.7: SET LOCAL ROLE qbit_test_owner перед section 9 ACL, owner role сохраняется через disposable probe, RESET ROLE только перед COMMIT.
- Следующее действие Павла: выполнить целиком v0.7 в test Supabase и прислать полный результат; verifier запускать только после разбора migration result.
