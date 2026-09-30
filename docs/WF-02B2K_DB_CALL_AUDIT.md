# WF-02B2K — аудит оставшихся DB-вызовов канонического workflow

Дата: 30 сентября 2026.

Канонический файл: `workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json`.

## Итог

В workflow 34 PostgreSQL-ноды.

- 16 нод уже вызывают текущие DB-03/DB-03E API;
- 1 нода — намеренно отключённая no-op заглушка после webhook;
- 17 нод ещё содержат старые/будущие DB-вызовы или старую сигнатуру.

Этот аудит не меняет runtime. Processing и sender gates остаются `disabled=true`.

## Уже приведено к текущему контракту

Client ingress/processing, exact source/context, rate-limit, STT/PII, thematic guard actions, handoff/opt-out, durable outgoing intent, sender claim/final recheck/result и fenced processing finish используют текущие DB-03/DB-03E функции.

## Оставшиеся 17 нод

| Зона | Нода | Старый вызов/состояние | Текущий путь | Решение |
|---|---|---|---|---|
| RAG | `Найти опубликованные знания` | `poisk_aktivnyh_znaniy(...vector(1024)...)` | будущий DB-05 | Не трогать до DB-05. Сейчас путь закрыт `rag.porog_pohozhesti=null`. |
| Интеграция | `Поставить внешнюю интеграцию в очередь` | `postavit_integraciyu_v_ochered(...)` | `sozdat_ishodyashchee_deystvie(jsonb)` с `vid_deystviya='crm'` | Отдельная старая DB-функция не нужна. Выделить позже отдельным блоком после определения payload/подтверждения интеграции. |
| Напоминания | `Взять допустимые напоминания` | `vzyat_napominaniya_k_otpravke(integer)` | DB-03E `obrabotat_sleduyushchee_napominanie(jsonb)` → обычный sender | Следующий узкий блок WF-02B2L. |
| Service mirror | `Взять событие зеркала оператору` | `vzyat_sobytie_zerkala_operatora(integer)` | `zabrat_sobytie_zerkala(jsonb)` | Перевести на lease/fencing. |
| Service topic | `Сохранить тему оператора` | `sohranit_temu_operatora(...)` | `zabrat_sozdanie_operator_temy(jsonb)` → `podtverdit_operator_temu(jsonb)` | Старый один шаг разделить на claim/external result. |
| Service mirror | `Подтвердить зеркало оператору` | `podtverdit_zerkalo_operatora(uuid)` | `zafiksirovat_rezultat_zerkala(jsonb)` confirmed | Нужны worker/fencing/external id. |
| Service mirror | `Отметить ошибку зеркала оператору` | `otmetit_oshibku_zerkala_operatora(...)` | `zafiksirovat_rezultat_zerkala(jsonb)` retry/unknown/error | Не делать blind retry. |
| Service topic | `Отметить ошибку создания темы` | старый mirror-error API | `otmetit_temu_neizvestnoy(jsonb)` либо подтверждение topic API по факту результата | Тему и зеркало не смешивать. |
| Service ingress | `Сохранить служебный вход` | `prinyat_sluzhebny_vhod_telegram(jsonb)` | `zaregistrirovat_sluzhebnoe_sobytie(jsonb)` | Durable idempotent service ingress. |
| Service queue | `Взять служебное задание` | `vzyat_sluzhebnoe_zadanie(uuid)` | специализированные D1/D2 API | Старую общую service queue убрать. |
| Service queue | `Взять следующее служебное задание` | `vzyat_sleduyushchee_sluzhebnoe_zadanie()` | специализированные D1/D2 API | Старую общую service queue убрать. |
| Operator Take | `Забрать диалог оператором` | имя совпадает, но вызов `(uuid,bigint)` | `zabrat_dialog_operatorom(jsonb)` | Обязательны persisted callback/manager/expected version. |
| Operator Return | `Вернуть диалог боту` | имя совпадает, но вызов `(uuid,bigint)` | `vernut_dialog_botu(jsonb)` | Обязательна current expected version. |
| Manual reply | `Подготовить ручной ответ` | `podgotovit_ruchnoy_otvet(...)` | `sozdat_ruchnoe_ishodyashchee(jsonb)` | Создаёт обычное outgoing action. |
| Manual reply | `Подтвердить ручной ответ` | `podtverdit_ruchnoy_otvet(...)` | общий `zabrat_ishodyashchee_deystvie` + `zafiksirovat_rezultat_ishodyashchego` | Использовать тот же fenced sender. |
| Manual reply | `Отметить неизвестный ручной ответ` | `otmetit_neizvestnyy_ruchnoy_otvet(...)` | общий outgoing result `status='neizvestno'` | Blind retry запрещён. |
| Manager registration | `Зарегистрировать менеджера` | `zaregistrirovat_menedzhera_telegram(...)` | `podtverdit_lichnyy_chat_menedzhera(jsonb)` | `/start` только подтверждает заранее разрешённого active manager. |

## Группировка следующих работ

1. **WF-02B2L — reminders**: один старый runtime-вызов; заменить на `obrabotat_sleduyushchee_napominanie(jsonb)` и передавать созданные reminder actions в уже готовый общий sender.
2. После reminders — отдельный блок service ingress/topic/mirror.
3. Затем отдельный блок Take/Return/manual reply/manager registration.
4. RAG не реализовывать до DB-05.
5. CRM/external integration не переносить механически: целевой путь уже определён как обычное outgoing action с `vid_deystviya='crm'`, но payload и внешний подтверждающий sender требуют отдельной задачи.

## Проверки

- Канонический workflow не изменён этим аудитом.
- 168 нод и 139 connection keys остаются как после WF-02B2J.
- DB-03E не применялся к Supabase.
- Production/traffic/Credentials не менялись.
