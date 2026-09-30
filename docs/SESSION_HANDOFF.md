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

## Следующая задача

**WF-02B2K — статический аудит оставшихся старых DB-вызовов.**

Просмотреть PostgreSQL function calls всего канонического workflow и выбрать следующий узкий участок. Массово workflow не переписывать.

DB-03E подготовлен, но не применён на Supabase; production/traffic/Credentials не менять без отдельного разрешения Павла.
