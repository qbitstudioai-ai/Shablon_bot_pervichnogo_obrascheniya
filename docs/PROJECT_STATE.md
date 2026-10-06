# Текущее состояние проекта

Обновлено: 2026-10-06.

## Режим

Реализация test-контура разрешена. Изменение production, удаление рабочих данных и переключение рабочего трафика требуют отдельного явного разрешения Павла.

Каноническая schema qBit: `qbit_bot_pervichnogo_obrascheniya`.

## Git и канонический workflow

Фактическая основа workflow — export Павла `(7)`. Raw SHA-256 `(7)`: `2ebd7d7b44e42fc941bb70bdc8e01ce44f9e5a1472beb653e7e4331e77da1fb3`.

Текущий runtime-verified checkpoint:

`workflows/checkpoints/2026-10-06_v0.7.1_KB-01B2_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

SHA-256 восстановленного import-ready JSON:

`e5a94534c45ab77ec318b4ecf258eefcad702feeb1048fe659b35f0d2a9136f4`

Checkpoint: 212 nodes, 172 connection keys, 240 edges, `active=false`, Credential refs 0, реальные Telegram ID/whitelist в Git не сохраняются.

Предыдущий runtime-verified KB-01A checkpoint сохранён для истории. Отдельный v0.5 KB-01B1 checkpoint больше не требуется: KB-01B1 доказан evidence, а v0.7.1 является его прямым runtime-проверенным продолжением.

## DB-04 / DB-05

Нормативные DB-04/DB-05 созданы и runtime-проверены в test по KB-01R4/R5 для bot/service контура: ingestion queue, lease/fencing, version/profile/fragments/reference checks, `vector(1024)`, draft-only service search, atomic publish и active-only bot search.

`KB-01R5D` для отдельного `dash_admin` остаётся отложен до dashboard stage.

## PRE-02E

Отдельного PRE-02E smoke нет. OpenAI `text-embedding-3-large`, `dimensions=1024`, `encoding_format=float` и строгая проверка длины document vector закрываются внутри `KB-03A`.

## Активный план

Активный план: `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`.

Последовательность:
`KB-01A` → `KB-01B1` → `KB-01B2` → `KB-02A` → `KB-02B` → `KB-03A` → `KB-03B` → `KB-03C`.

## KB-01A — CLOSED / runtime verified

05.10.2026 private `.md` прошёл service ingress → durable event → download → actual bytes check → `zaregistrirovat_zagruzku_znaniy`; DB вернула `uspeshno`, non-null upload/job, `status_zagruzki=poluchena`; Telegram report для filename с `_` подтверждён после HTML escaping fix.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

## KB-01B1 — CLOSED / runtime verified

06.10.2026 реальный job claim-нут через normative lease/fencing API. Parser `kb01b1_safe_frontmatter_markdown_v1` подтвердил metadata/структуру и deterministic content hash; job безопасно возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

## KB-01B2 — CLOSED / runtime verified

06.10.2026 на test-контуре:
1. второй реальный knowledge job claim-нут с live worker/fence;
2. parser повторно вернул valid metadata, 6 headings, 3 reference questions;
3. зафиксирован processing/index profile: OpenAI `text-embedding-3-large`, dimension 1024, cosine, `cl100k_base`, structural chunk profile 600/800/100;
4. `otpechatok_profilya=917b776877263b60b809fa0376cce8ae62937d2d44cdb0badc2e07bea2ceec3c`;
5. `otpechatok_obrabotki=b56cd0f39885a576c0c7d04cdb78deceadb01e944713e9aa21b0483910b8abdb`;
6. `podgotovit_versiyu_znaniy` вернула `uspeshno`, созданы non-null document/version/profile IDs, `nomer_versii=1`, `status_versii=chernovik`;
7. publish не выполнялся;
8. job тем же worker/fence освобождён обратно в `povtor`.

Важно: `cl100k_base` в B2 — зафиксированный tokenizer/encoding contract. Точный runtime token count на финальном тексте fragments и сам структурно-смысловой chunking обязательно проверяются в KB-02A до сохранения fragments. Никакой отдельный npm `tiktoken` в Code node не требуется как условие B2.

Active duplicate end-to-end не мог быть проверен до первой публикации. DB guard уже runtime-проверен на DB-04/DB-05 уровне; повтор после первой публикации добавить в regression KB-03C.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

## Следующая маленькая задача

`KB-02A` — структурно-смысловой chunking.

Критерий: детерминированно очистить и разделить Markdown по структуре/смысловым блокам с сохранением heading path, FAQ, таблиц и фактов; применять token budget `600/800/100` только как ограничение размера; доказать точный runtime token count `cl100k_base` на финальном тексте до сохранения fragments. Контрольные вопросы не входят в retrieval text.

Не начинать KB-02B/embeddings до runtime-проверки KB-02A.

## Постоянные ограничения

- Production не менять.
- Не переключать рабочий трафик.
- Не импортировать старый experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL повторно.
- `sql/KB-01R5C_service_publish_prepare.sql` не запускать.
- `KB-01R5D` оставить до dashboard stage.
- Не публиковать реальные документы компаний, переписки, Telegram ID, Credential refs или секреты.
