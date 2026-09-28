# SESSION HANDOFF

Обновлено: 28 сентября 2026.

## Текущее состояние

WF-02A завершена. WF-02B1 завершена как архитектурная подзадача. PRE-02E и DB-03E остаются незакрытыми runtime/server-проверками.

Фактическая версия амстердамского n8n: **2.41.0**.

### PRE-02E

Candidate OpenAI profile:
- guard/planner: `gpt-6-luna`;
- grounded answer: `gpt-6-sol`;
- document/query embeddings: `text-embedding-3-large`, candidate `dimensions=1024`.

Smoke workflow уже в репозитории:
`workflows/PRE-02E_openai_profile_smoke_n8n_2.41.0.json`.

PRE-02E остаётся `[~]` до реального запуска с test OpenAI Credential и результата:
`pre02e_status=runtime_verified`.

### WF-02B1

Документ:
`docs/WF-02B1_DB03_N8N_ARCHITECTURE.md`.

Зафиксировано:
- durable client ingress отдельно от processing worker;
- processing lease/fencing и expected dialog version;
- outgoing intent отдельно от sender worker;
- service callback commands отдельно от topic/mirror workers;
- два финальных workflow с разными client/service Credentials;
- RAG gated до DB-05.

### DB-03E v0.4

Подготовлены, но **не применены**:
- `sql/DB-03E_runtime_gap_closure.sql`;
- `sql/DB-03E_v0.4_verify.sql`.

DB-03E добавляет шесть narrow API, без выдачи direct table DML:
1. `poluchit_soderzhimoe_zadaniya(jsonb)` — current live worker/fencing получает `identifikator_kanala_id` + source raw text/provider payload своего claimed job для recoverable local rate-limit/guard/PII/STT;
2. `poluchit_sostoyanie_operatora(jsonb)` — service-only narrow state/version по известному dialog или forum topic для CAS Take/Return/manual reply, без client content/PII;
3. `sozdat_preduprezhdenie_tematiky(jsonb)` — durable warning action для exact thematic violation; blocking third warning остаётся sendable только через DB-verified exception;
4. `ustanovit_zapret_iniciativy(jsonb)` — persistent opt-out / explicit opt-in;
5. `zaprosit_cheloveka(jsonb)` — stable group `nuzhen_chelovek`, owner остаётся bot до service Take;
6. `obrabotat_sleduyushchee_napominanie(jsonb)` — один due reminder/loss через SKIP LOCKED и существующую DB-03C4 логику.

Migration v0.2 содержит rollback behavior probes, включая exact source-content read; verifier read-only проверяет 6 функций, metadata, privileges и отсутствие runtime direct DML.

## Что запрещено считать готовым

- DB-03E не server-verified, пока Павел отдельно не разрешил test apply и verifier не прошёл.
- PRE-02E не runtime-verified.
- DB-04/DB-05 не начинать до PRE-02E.
- knowledge/RAG branch workflow не считать рабочей до DB-05.
- production, working traffic и real Credentials не менять без отдельного разрешения.

## Следующая работа

Можно продолжать **WF-02B2 offline**: собрать два полных очищенных JSON по уже зафиксированным DB-03/DB-03E контрактам, оставив OpenAI profile и knowledge branch с явными gates до runtime/server verification. Для фактического test запуска понадобятся два разрешённых действия Павла: PRE-02E smoke в n8n и DB-03E apply в test Supabase.
