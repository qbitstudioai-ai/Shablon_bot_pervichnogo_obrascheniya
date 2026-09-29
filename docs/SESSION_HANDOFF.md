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

## Следующая задача

**WF-02B2F — query embedding OpenAI.**

Менять только embedding поискового запроса и parser вектора. DB-05 search, основной answer/outgoing пока не включать.

DB-03E подготовлен, но не применён на Supabase; production/traffic/Credentials не менять без отдельного разрешения Павла.
