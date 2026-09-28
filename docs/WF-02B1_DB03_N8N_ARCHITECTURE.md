# WF-02B1 — DB-03 runtime-архитектура n8n

Дата: 28 сентября 2026.

Статус: **завершено как архитектурная подзадача.**

## Главное решение

Свежий export сохраняется как источник бизнес-логики, но runtime orchestration меняется под фактически применённый DB-03. Финальная установка использует **два логических workflow** с разными Credentials:

1. **Client CORE / Telegram adapter** — durable webhook ingress, processing worker, OpenAI, outgoing sender, reminders и позднее active RAG.
2. **Service Telegram / operator / documents** — durable service ingress, Take/Return/manual reply, forum topic worker, mirror/private notifications и позднее knowledge upload.

Client и service Telegram Credentials не смешиваются. Client PostgreSQL работает под `qbit_test_bot`, service PostgreSQL — под `qbit_test_sluzhebnyy`.

## Client webhook

Цепочка приёма:

`Webhook → проверить Telegram secret header → нормализовать → zaregistrirovat_vhod_klienta(jsonb) → после commit ответить HTTP 200`.

После HTTP 200 нельзя пытаться забрать «именно созданный job». `zabrat_zadanie_obrabotki(jsonb)` намеренно не принимает `zadanie_id`: отдельный worker атомарно выбирает следующий due job через `SKIP LOCKED`, lease и fencing.

## Processing worker

Schedule worker вызывает `zabrat_zadanie_obrabotki({operaciya_id, worker_id, arenda_sekund})`.

До конца обработки сохраняются:
- `zadanie_id`;
- `dialog_id`;
- `worker_id`;
- `nomer_vladeniya`;
- `versiya_dialoga`;
- `arenda_do`.

Долгий вызов при необходимости продлевает аренду через `prodlit_arendu_zadaniya(jsonb)`. Завершение/повтор — только через `zavershit_zadanie_obrabotki(jsonb)`. Stale worker/version не переписывает новый state.

## PII / context / guard

Используются текущие DB-03 API:
- `sohranit_vlozhenie`;
- `sohranit_transkripciyu_golosa`;
- `sohranit_obezlichivanie`;
- `poluchit_kontekst_dialoga`;
- `proverit_limit_chastoty`;
- `zapisat_narushenie_tematiky`;
- `sohranit_fakty_i_pamyat`.

Protected PII не уходит в OpenAI. Voice остаётся через локальный STT adapter; сырой voice автоматически в OpenAI не отправляется.

## Guard outcomes

`razresheno`, smalltalk и уточнение идут в обычный decision pipeline. Knowledge branch до DB-05 gated.

`ne_po_teme` / injection пишутся через `zapisat_narushenie_tematiky`; ответ клиенту создаётся как ordinary outgoing action.

`zapret_iniciativy` требует persistent identity flag и отмену wait/reminders. Для этого подготовлен DB-03E API `ustanovit_zapret_iniciativy(jsonb)`.

`peredat_cheloveku` **не меняет owner сам**. DB-03E `zaprosit_cheloveka(jsonb)` создаёт durable group event `nuzhen_chelovek`, прекращает bot wait и переводит этап в `peredacha_cheloveku`; owner остаётся `bot`. Только зарегистрированный service callback Take вызывает `zabrat_dialog_operatorom(jsonb)` и меняет `bot → chelovek`.

## Outgoing sender

AI processing не вызывает Telegram напрямую.

Сначала `sozdat_ishodyashchee_deystvie(jsonb)`. Затем отдельный sender:
1. `zabrat_ishodyashchee_deystvie(jsonb)`;
2. вызывает внешний API;
3. `zafiksirovat_rezultat_ishodyashchego(jsonb)` со статусом `podtverzhdeno`, `povtor`, `neizvestno` или `oshibka`.

`neizvestno` не повторяется вслепую. In-flight факт не стирается при пересечении с новым input/Take; stale dependent effects подавляются БД.

Ручной manager reply создаётся service workflow через `sozdat_ruchnoe_ishodyashchee(jsonb)`, а отправляет его тот же client outgoing sender клиентским Telegram Credential.

## Reminders / loss

Существующие DB-03C4 функции умеют безопасно обработать конкретный `napominanie_id`, но runtime role не имеет SELECT таблицы. DB-03E добавляет `obrabotat_sleduyushchee_napominanie(jsonb)`: функция сама выбирает один due reminder/loss-check через `FOR UPDATE SKIP LOCKED` и делегирует существующим final-recheck функциям.

После подготовки reminder создаётся ordinary outgoing action; его отправляет общий sender.

## Service workflow

Service webhook сначала вызывает `zaregistrirovat_sluzhebnoe_sobytie(jsonb)`, затем выполняет idempotent command:
- `/start` → `podtverdit_lichnyy_chat_menedzhera`;
- Take → `zabrat_dialog_operatorom`;
- Return → `vernut_dialog_botu`;
- manager text → `sozdat_ruchnoe_ishodyashchee`;
- knowledge upload — только после DB-04/DB-05.

HTTP 200 — после durable registration и соответствующего DB command.

Отдельные service workers:
- topic: `zabrat_sozdanie_operator_temy` → Telegram `createForumTopic` → confirm/unknown;
- mirror: `zabrat_sobytie_zerkala` → Telegram send → `zafiksirovat_rezultat_zerkala`.

## Client callback

DB ingress не принимает `callback` как message type. Известные client inline callbacks нормализуются детерминированно в safe text intent, сохраняя raw callback payload внутри durable provider event:
- `media_take` → «Позвать менеджера»;
- `media_no` → «Продолжить без менеджера».

Произвольный callback не превращается в trusted DB action.

## DB-03E

Выявленные runtime gaps закрываются без прямого DML:
- persistent opt-out/explicit opt-in;
- stable group `nuzhen_chelovek` intent без преждевременной смены owner;
- due reminder/loss discovery.

Файлы:
- `sql/DB-03E_runtime_gap_closure.sql`;
- `sql/DB-03E_v0.1_verify.sql`.

Они подготовлены в репозитории, но **не применяются к Supabase без отдельного разрешения Павла**.

## Критерий WF-02B1

Определены durable ingress, processing lease/fencing, outgoing sender, service commands, topic/mirror workers, callback normalization и DB-03E boundary. Production, Supabase и Credentials не менялись.