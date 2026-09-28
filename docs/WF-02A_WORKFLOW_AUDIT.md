# WF-02A — аудит workflow после переноса n8n в Амстердам

Дата: 28 сентября 2026.

Статус: **завершено**.

## Цель и границы

Проверить свежий экспорт фактически перенесённого workflow, сохранить согласованную бизнес-логику, сопоставить старый PostgreSQL API с уже реализованным DB-03, определить точки миграции OpenRouter/Qwen → OpenAI и проверить переносимость экспорта.

В этой задаче **не** менялись workflow в n8n, Supabase, Credentials, production, рабочий трафик и серверы. Полный новый JSON относится к WF-02B.

## Проверенный источник

- экспорт: `Шаблон — служебный Telegram и перехват диалогов — версия 0.1.json`;
- 168 нод, 135 ключей connections;
- `active=false`;
- `pinData` пуст;
- workflow объединяет клиентский Telegram pipeline и служебный/операторский pipeline;
- Павел подтвердил фактическую версию амстердамского n8n: **2.41.0**.

Текущую бизнес-логику следует сохранять: durable ingress → очередь → нормализация/медиа/STT → обезличивание → guard → план/RAG → решение → durable outgoing → подтверждение отправки → зеркало/оператор → напоминания; отдельно service ingress → topic/mirror → Take/Return/manual reply.

## Главный вывод по DB-03

Workflow был собран под старый API и **не совместим напрямую** с текущим DB-03. Это не задача простого переименования SQL-функций. В WF-02B соседние Code/IF/Switch-ноды должны формировать/проверять JSONB-пакеты и переносить обязательные значения DB-03: `worker_id`, lease/fencing (`nomer_vladeniya`), ожидаемую `versiya_dialoga`, стабильные idempotency/operation keys и точный результат внешнего действия.

### Карта старых DB-вызовов

| Старый вызов в export | Целевой DB-03 путь | Что важно в WF-02B |
|---|---|---|
| `prinyat_vhod_telegram` | `zaregistrirovat_vhod_klienta(jsonb)` | Новый durable ingress; использовать возвращённые dialog/message/job/version, не собирать их из текста/LLM |
| `vzyat_zadanie_obrabotki`, `vzyat_sleduyushchee_zadanie` | `zabrat_zadanie_obrabotki(jsonb)` | Один lease/fencing API для specific/next due; сохранять worker и `nomer_vladeniya` |
| `zavershit_zadanie_bez_otveta` | `zavershit_zadanie_obrabotki(jsonb)` | Завершать только live lease с expected/current dialog version; stale owner не коммитит |
| `peredat_vhod_menedzheru` | DB-03 mirror events + service `zabrat_sobytie_zerkala(jsonb)` | Старую прямую пересылку убрать; зеркало выдаётся узким service API |
| `sohranit_transkripciyu_golosa` | `sohranit_transkripciyu_golosa(jsonb)` | Имя сохранилось, но старая позиционная сигнатура несовместима; передавать JSONB/status/engine/version |
| `sohranit_lokalnye_dannye` | `sohranit_obezlichivanie(jsonb)` и при необходимости `sohranit_fakty_i_pamyat(jsonb)` | Разделить PII mapping и долговечные AI-safe facts/memory; protected PII не помещать в AI context |
| `zafiksirovat_narushenie` | `zapisat_narushenie_tematiky(jsonb)` | Нарушение привязано к identity/dialog/client message; лимит и блокировка атомарны |
| `peredat_dialog_menedzheru` | service/operator handoff; фактический owner switch только `zabrat_dialog_operatorom(jsonb)` | Не делать bot→human смену локальным флагом; операторский Take — first-commit-wins по expected version |
| `ustanovit_zapret_iniciativy` | Нет отдельного 1:1 вызова в DB-03 API | В WF-02B не оставлять старый прямой вызов; обработать opt-out только через разрешённый DB-03 контракт/отдельное согласованное расширение, если оно действительно требуется |
| `poisk_aktivnyh_znaniy(...vector(1024)...)` | будущий DB-05 `poisk_aktivnyh_znaniy` | Ветку держать недоступной до PRE-02E → DB-04 → DB-05; `1024` не фиксировать заранее |
| `sohranit_ishodyashchee_deystvie` | `sozdat_ishodyashchee_deystvie(jsonb)` | Сохранять logical action до внешнего API; stable key и expected version обязательны |
| `proverit_pravo_otpravki` | `zabrat_ishodyashchee_deystvie(jsonb)` | Право + claim объединены в fenced DB-03 claim; stale/blocked action отменяется внутри контракта |
| `otmenit_ishodyashchee_deystvie` | Нет отдельного blind-cancel вызова | Причины отмены из нового входа/Take/block обрабатывает DB-03; после claim результат фиксировать через result API |
| `podtverdit_otpravku_i_obnovit` | `zafiksirovat_rezultat_ishodyashchego(jsonb)` с confirmed | Confirmed-факт хранится отдельно от эффектов; поздний bot confirmed после Take не возвращает bot ownership |
| `otmetit_neizvestnuyu_otpravku` | `zafiksirovat_rezultat_ishodyashchego(jsonb)` с unknown | Unknown terminal не повторять вслепую |
| `postavit_integraciyu_v_ochered` | `sozdat_ishodyashchee_deystvie(jsonb)` с `vid_deystviya='crm'` | Отдельная привилегированная CRM-функция DB-03 не нужна |
| `vzyat_napominaniya_k_otpravke` | `podgotovit_napominanie(jsonb)` → обычный outgoing claim/result | Напоминание создаёт stable initiative action; само не двигает t0 |
| `vzyat_sobytie_zerkala_operatora` | `zabrat_sobytie_zerkala(jsonb)` | SKIP LOCKED + lease/fencing; service не получает общий SELECT сырой переписки |
| `sohranit_temu_operatora` | `zabrat_sozdanie_operator_temy(jsonb)` → `podtverdit_operator_temu(jsonb)` / `otmetit_temu_neizvestnoy(jsonb)` | createForumTopic — отдельное внешнее действие; ambiguous outcome нельзя повторять вслепую |
| `podtverdit_zerkalo_operatora` | `zafiksirovat_rezultat_zerkala(jsonb)` confirmed | Передавать worker/fencing и внешний Telegram message id |
| `otmetit_oshibku_zerkala_operatora` | `zafiksirovat_rezultat_zerkala(jsonb)` retry/unknown/error | Различать retryable, unknown и terminal error |
| `prinyat_sluzhebny_vhod_telegram` | `zaregistrirovat_sluzhebnoe_sobytie(jsonb)` | Durable idempotent service ingress; не создаёт client dialog |
| `vzyat_sluzhebnoe_zadanie`, `vzyat_sleduyushchee_sluzhebnoe_zadanie` | Специализированные DB-03 service claims | Старую общую service-queue логику убрать; topic/mirror имеют собственные claims, callbacks обрабатываются по persisted service event |
| `zabrat_dialog_operatorom` | `zabrat_dialog_operatorom(jsonb)` | Новая JSONB сигнатура; registered callback, active manager, expected version |
| `vernut_dialog_botu` | `vernut_dialog_botu(jsonb)` | JSONB + expected version; Return не создаёт автоматический client message |
| `podgotovit_ruchnoy_otvet` | `sozdat_ruchnoe_ishodyashchee(jsonb)` | Проверяется confirmed topic/current manager/current human owner; создаётся обычное outgoing action |
| `podtverdit_ruchnoy_otvet`, `otmetit_neizvestnyy_ruchnoy_otvet` | `zabrat_ishodyashchee_deystvie(jsonb)` + `zafiksirovat_rezultat_ishodyashchego(jsonb)` | Ручной ответ использует тот же fenced sender; unknown не повторять вслепую |
| `zaregistrirovat_menedzhera_telegram` | `podtverdit_lichnyy_chat_menedzhera(jsonb)` | `/start` только подтверждает заранее разрешённого active manager; неизвестного пользователя не добавлять автоматически |

Дополнительно в client processing должны использоваться текущие DB-03 функции `poluchit_kontekst_dialoga(jsonb)`, `sohranit_fakty_i_pamyat(jsonb)`, `proverit_limit_chastoty(jsonb)` и при долгой обработке `prodlit_arendu_zadaniya(jsonb)` там, где это требуется временем выполнения.

## Карта AI-замены

В export найдено четыре HTTP-вызова OpenRouter:

1. `Выполнить тематический контроль` — chat completions;
2. `Построить план поиска` — chat completions;
3. `Создать вектор поискового запроса` — embeddings;
4. `Сформировать решение менеджера` — chat completions.

В WF-02B они должны использовать OpenAI, но **после PRE-02E**. До PRE-02E не фиксировать:

- конкретный LLM model ID;
- embedding model ID;
- vector dimension;
- окончательный вариант n8n node vs HTTP adapter.

Структурированные ответы guard/planner/decision нужно сохранить с проверяемой схемой, а не разбирать произвольный текст.

Текущий блок настроек содержит старые значения `deepseek/deepseek-v4.1-flash`, `qwen/qwen3-embedding-8b` и `razmernost:1024`; все три являются наследием старого профиля и не считаются решением для OpenAI.

## RAG и DB-04/DB-05

DB-04 и DB-05 ещё не реализованы. Поэтому старый SQL cast `extensions.vector(1024)` нельзя переносить в новый canonical workflow. Правильная последовательность:

`WF-02A (done) → PRE-02E → DB-04/DB-05 profile/vector design → WF-02B integration`.

Если WF-02B будет готовиться раньше DB-05, knowledge branch должен быть явно gated/disabled и не должен притворяться рабочим.

## STT после переноса n8n

В настройках export указан `http://stt-local:8000/v1/transcriptions`. После переноса n8n в Амстердам этот hostname относится к сетевому окружению амстердамского runtime, если отдельно не настроен маршрут к российскому/local STT. Доступность не доказана.

Сырой Telegram voice может содержать PII. Поэтому WF-02B не должен молча заменить local STT на OpenAI transcription; это отдельное архитектурное/PII решение и runtime-проверка.

## Secrets и переносимость export

Проверка JSON дала:

- явные `api_key`/`apikey`/Authorization/Bearer/password не найдены;
- `credentials` objects с IDs/именами в export отсутствуют;
- `pinData` пуст;
- реальная клиентская переписка и реальные документы не найдены;
- `meta.instanceId` присутствует;
- workflow `id`, `versionId`, webhook/node IDs являются instance/export metadata и должны быть отдельно нормализованы только настолько, насколько это допускает импорт n8n.

Минимальное обязательное очищение canonical export WF-02B: убрать `meta.instanceId`, не встраивать секреты/Authorization в expressions и повторно проверить файл перед GitHub.

## Критерий WF-02A

- свежий JSON прочитан полностью — **да**;
- бизнес-порядок pipeline зафиксирован — **да**;
- карта DB-03 замен составлена — **да**;
- OpenRouter/OpenAI точки составлены — **да**;
- DB-04/DB-05 gating зафиксирован — **да**;
- secrets/metadata проверены — **да**;
- фактическая версия n8n подтверждена — **да, 2.41.0, подтверждено Павлом 28.09.2026**;
- production/Supabase/Credentials/workflow изменены — **нет**.

**WF-02A закрыта. Следующий отдельный ID: PRE-02E.**
