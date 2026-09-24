# DB-контракт шаблона

Статус: нормативный контракт **DB-00 v0.1**. Он фиксирует структуру PostgreSQL, которой должны соответствовать DB-01…DB-05 и draft workflow `client_bot_template_v0.2.json` / `service_telegram_operator_v0.1.json`. DB-01 и DB-02 уже применены и проверены в test-контуре. DB-03 разбит на DB-03A…DB-03D; SQL DB-03A подготовлен, но ещё не применён на сервере.

## Граница контракта

Контракт собран по `DATA_DICTIONARY`, `RELIABILITY_AND_MEMORY`, `BOT_CORE_WORKFLOW`, `OPERATOR_HANDOFF`, `INTEGRATION_CONTRACTS`, `ACCESS_AND_ISOLATION`, `CONVERSATION_LIFECYCLE`, `KNOWLEDGE_INGESTION` и `NAMING_CONVENTIONS`.

Сырые JSON draft из предыдущего чата не находятся в GitHub и недоступны как файл в этой сессии. Поэтому DB-00 проверяет документированный контракт и зафиксированное поведение draft, а не делает повторный побайтовый аудит JSON. Перед runtime-тестами RT-01/RT-02 экспорт фактически импортированных workflow нужно сверить с именами функций и форматом результатов из этого документа.

Основные правила:

- одна компания и одна среда — одна schema одинаковой структуры;
- schema выбирается только доверенной конфигурацией подключения; аргумента `schema` в прикладных функциях нет;
- внутренние ID — `uuid`, внешние идентификаторы — `text`, время — `timestamptz` в UTC;
- бизнес-коды этапов и целей — `text`: БД не зашивает qBit-специфичный список, переносимость проверяет CORE/настройки;
- фиксированные технические статусы имеют `CHECK`, но не PostgreSQL ENUM, чтобы миграции шаблона оставались управляемыми;
- `jsonb` используется только для безопасной структурированной полезной нагрузки; ключевые поля, по которым нужны связи/ограничения/индексы, вынесены в отдельные столбцы;
- секреты, bot token, API keys и DB-пароли в таблицах компании не хранятся;
- прикладные роли не владеют объектами; `PUBLIC`, `anon`, `authenticated` не получают доступ к schema и функциям;
- функции с повышенными правами имеют фиксированный безопасный `search_path`, полностью квалифицированные объекты и точечный `EXECUTE`;
- внешнее действие и его подтверждение — разные состояния; `neizvestno` нельзя автоматически превращать в повтор;
- удаление/очистка данных и сроки хранения не входят в DB-00: их параметры закрывает PRE-03.

## Состав DB-01…DB-05

| Этап | Объекты |
|---|---|
| DB-01 | schema, роли, расширение `vector` уже существует на сервере; grants/default privileges; проверка изоляции test ↔ prod/другая schema |
| DB-02 | пользователи, идентификаторы каналов, диалоги, сообщения, вложения, транскрипции, факты, PII-соответствия, события этапов/целей/диалогов, заявки |
| DB-03 | входная идемпотентность, очередь диалогов, память, guard/блокировка, исходящие действия, напоминания, системные события, операторские темы/менеджеры/зеркало, ручной перехват |
| DB-04 | загрузки знаний, очередь знаний, документы, версии, профили индекса, фрагменты, контрольные вопросы и проверки |
| DB-05 | клиентский поиск только по опубликованным знаниям, проверочный поиск по конкретному черновику, атомарная публикация/отзыв |

Три таблицы дашборда из `DATA_DICTIONARY` (`nastroyki_dashborda`, `dostupy_dashborda`, `versii_ustanovki`) остаются нормативными, но не создаются задачами DB-01…DB-05: они входят в UI-01/UI-04.

## Роли и владение

Для компании `<kod>` и среды `<sreda>` создаются роли:

| Роль | LOGIN | Назначение |
|---|---:|---|
| `<kod>_<sreda>_owner` | нет | владелец schema, таблиц и SECURITY DEFINER-функций; не используется n8n |
| `<kod>_<sreda>_deploy` | по необходимости | применение проверенных миграций; может временно `SET ROLE` в owner; не используется workflow |
| `<kod>_<sreda>_bot` | да | клиентский workflow: ingress, очередь, память/PII, guard, исходящие, напоминания, активный RAG |
| `<kod>_<sreda>_sluzhebnyy` | да | единый служебный Telegram: операторские callback/сообщения, зеркало, личные уведомления, знания |
| `<kod>_<sreda>_dash_read` | да | сервер дашборда: только разрешённые представления/функции чтения |
| `<kod>_<sreda>_dash_admin` | да | сервер административной части: узкие административные функции, без произвольного DDL/SQL |

Для qBit: schema test — `qbit_test`, prod — `qbit`; прикладные роли — `qbit_test_bot`, `qbit_test_sluzhebnyy`, … и `qbit_prod_bot`, `qbit_prod_sluzhebnyy`, … . Production-роли/права не применяются без отдельного разрешения.

Прикладные роли получают `USAGE` только своей schema и `EXECUTE` только перечисленных ниже функций. Прямой `SELECT/INSERT/UPDATE/DELETE` для workflow по умолчанию не выдаётся. Исключения допускаются позже только отдельным решением и тестом изоляции. Служебная роль не получает прямого чтения архива клиентских сообщений: нужный текст/медиа выдаётся ей только узкой функцией очереди зеркала.

## DB-02. Пользователь, диалог и содержимое

DB-02 создаётся раньше DB-03, поэтому две физические внешние связи откладываются до DB-03: `dialogi.tekushchiy_menedzher_id → menedzhery_telegram.id` и `soobshcheniya.sobytie_id → sobytiya_integraciy.id`. В DB-02 поля уже имеют тип `uuid`, индексы/ограничения своей стадии и COMMENT; DB-03 после создания целевых таблиц обязан добавить оба FK и проверить их. Это не разрешает хранить произвольные значения: прикладная запись этих полей начинается через функции DB-03.

### `polzovateli`

| Поле | Тип | Обяз. | Смысл |
|---|---|---:|---|
| `id` | uuid | да | внутренний ID |
| `vremya_pervogo_obrashcheniya` | timestamptz | да | никогда не перезаписывается возвратом |
| `vremya_poslednego_obrashcheniya` | timestamptz | да | последний клиентский вход |
| `pervyy_kanal` | text | да | первый известный канал |
| `testovyy` | boolean | да | тестовая идентичность |
| `sluzhebnyy` | boolean | да | служебная идентичность, если применимо |
| `tekushchaya_metka` | text | нет | текущая бизнес-метка |
| `byl_vozvrat` | boolean | да | исторический признак |
| `kolichestvo_vozvratov` | integer | да | `>= 0` |
| `vremya_poslednego_vozvrata` | timestamptz | нет | последний `vozvrat` |
| `vremya_sozdaniya` | timestamptz | да | запись создана |
| `vremya_obnovleniya` | timestamptz | да | запись изменена |

Индексы: `ix_polzovateli_pervoe` (`vremya_pervogo_obrashcheniya`), `ix_polzovateli_poslednee` (`vremya_poslednego_obrashcheniya`), `ix_polzovateli_metka` (`tekushchaya_metka`).

### `identifikatory_kanalov`

| Поле | Тип | Обяз. | Смысл |
|---|---|---:|---|
| `id` | uuid | да | ID идентичности |
| `polzovatel_id` | uuid FK | да | пользователь |
| `kanal` | text | да | `telegram`, `site`, … |
| `akkaunt_kanala_id` | text | да | конкретный bot/account |
| `vneshniy_polzovatel_id` | text | да | внешний пользователь |
| `vneshniy_dialog_id` | text | да | адрес ответа в канале |
| `sposob_vosstanovleniya` | text | нет | подтверждённый способ продолжения |
| `dannye_vosstanovleniya` | jsonb | нет | только безопасные данные сессии, без секретов |
| `vozmozhna_otlozhennaya_otpravka` | boolean | да | канал допускает её |
| `zapret_iniciativnyh_soobshcheniy` | boolean | да | устойчивый opt-out |
| `vremya_zapreta_iniciativy` | timestamptz | нет | когда установлен opt-out |
| `logicheski_zablokirovan` | boolean | да | блокировка CORE |
| `vremya_blokirovki` | timestamptz | нет | момент блокировки |
| `prichina_blokirovki` | text | нет | безопасный код |
| `schetchik_narusheniy` | integer | да | `>= 0` |
| `vremya_sozdaniya` | timestamptz | да | создано |
| `vremya_obnovleniya` | timestamptz | да | обновлено |

Индексы: `uq_idkanal_kanal_akkaunt_polz` UNIQUE (`kanal`,`akkaunt_kanala_id`,`vneshniy_polzovatel_id`); `ix_idkanal_vnesh_dialog` (`kanal`,`akkaunt_kanala_id`,`vneshniy_dialog_id`); `ix_idkanal_polz` (`polzovatel_id`); `ix_idkanal_blok` partial по `logicheski_zablokirovan=true`.

### `dialogi`

| Поле | Тип | Обяз. | Смысл |
|---|---|---:|---|
| `id` | uuid | да | диалог |
| `polzovatel_id` | uuid FK | да | пользователь |
| `identifikator_kanala_id` | uuid FK | да | канал/адрес |
| `predydushchiy_dialog_id` | uuid FK self | нет | предыдущий диалог |
| `vremya_nachala` | timestamptz | да | начало |
| `vremya_zaversheniya` | timestamptz | нет | завершение |
| `etap` | text | да | конфигурируемый бизнес-код |
| `status` | text | да | `aktivnyy`, `ozhidaet_otveta`, `peredan_cheloveku`, `zavershen` |
| `rezultat` | text | нет | `zayavka_prinyata`, `konsultaciya_zavershena`, `otkaz`, `net_otveta`, `tehnicheski_prervan` |
| `prichina_zaversheniya` | text | нет | безопасная причина |
| `poslednee_vhodyashchee_id` | uuid FK | нет | последнее входящее |
| `poslednee_ishodyashchee_id` | uuid FK | нет | последнее подтверждённое исходящее |
| `versiya_dialoga` | bigint | да | CAS-версия, старт `1` |
| `ozhidaetsya_otvet` | boolean | да | действует ли ожидание |
| `t0` | timestamptz | нет | подтверждённое основное сообщение, от которого идут сроки |
| `pokolenie_ozhidaniya` | bigint | да | меняется при каждом новом/отменённом ожидании |
| `vladelec` | text | да | `bot` или `chelovek` |
| `tekushchiy_menedzher_id` | uuid FK | нет | обязателен только при `chelovek` |
| `versiya_workflow` | text | да | версия CORE |
| `versiya_prompta` | text | да | версия prompts/config |
| `vremya_sozdaniya` | timestamptz | да | создано |
| `vremya_obnovleniya` | timestamptz | да | обновлено |

Ограничение владельца: `bot` → `tekushchiy_menedzher_id IS NULL`; `chelovek` → manager не `NULL`. Этап и цель не получают жёсткий отраслевой `CHECK`.

Индексы: `ix_dialogi_polz_nachalo` (`polzovatel_id`,`vremya_nachala DESC`); `ix_dialogi_idkanal_status` (`identifikator_kanala_id`,`status`); `ix_dialogi_menedzher` partial (`tekushchiy_menedzher_id`,`vremya_obnovleniya`) при `vladelec='chelovek'`; `ix_dialogi_ozhidanie` partial (`t0`,`pokolenie_ozhidaniya`) при `ozhidaetsya_otvet=true`.

### `soobshcheniya`

| Поле | Тип | Обяз. | Смысл |
|---|---|---:|---|
| `id` | uuid | да | логическое сообщение |
| `dialog_id` | uuid FK | да | диалог |
| `sobytie_id` | uuid FK | нет | входное integration event |
| `napravlenie` | text | да | `vhodyashchee` / `ishodyashchee` |
| `avtor` | text | да | `klient`, `bot`, `menedzher`, `sistema` |
| `vid` | text | да | `text`, `voice`, `photo`, `video`, `document`, `sticker`, `system` |
| `tekst_ishodnyy` | text | нет | неизменяемый сырой текст; защищённое чтение |
| `tekst_obezlichennyy` | text | нет | текст для памяти/внешнего AI |
| `vneshnee_soobshchenie_id` | text | нет | ID провайдера после приёма/отправки |
| `otvet_na_id` | uuid FK self | нет | логическая связь ответа |
| `redakciya_dlya_id` | uuid FK self | нет | новая редакция исходного сообщения |
| `vremya_istochnika` | timestamptz | нет | время канала |
| `vremya_priema` | timestamptz | да | локальный приём |
| `vremya_otpravki` | timestamptz | нет | подтверждённое принятие каналом |
| `vremya_dostavki` | timestamptz | нет | доставка, только если канал подтверждает |
| `status_otpravki` | text | нет | состояние связанного исходящего сообщения |
| `ozhidaetsya_otvet` | boolean | да | только для логического исходящего |
| `tip_zaversheniya` | text | нет | решение CORE по завершению/ожиданию |
| `prichina_resheniya` | text | нет | безопасная причина |
| `trassirovka_id` | text | нет | связь с n8n/журналом |
| `vremya_sozdaniya` | timestamptz | да | запись создана |

Индексы: `ix_soobshcheniya_dialog_vremya` (`dialog_id`,`vremya_priema`,`id`); `ix_soobshcheniya_sobytie` (`sobytie_id`); `ix_soobshcheniya_vnesh` (`dialog_id`,`vneshnee_soobshchenie_id`) с UNIQUE для ненулевых внешних ID; `ix_soobshcheniya_redakciya` (`redakciya_dlya_id`).

### `vlozheniya_soobshcheniy`

| Поле | Тип | Обяз. | Смысл |
|---|---|---:|---|
| `id` | uuid | да | вложение |
| `soobshchenie_id` | uuid FK | да | исходное сообщение |
| `tip_vlozheniya` | text | да | voice/photo/video/document/sticker/... |
| `vneshniy_file_id` | text | нет | provider file_id |
| `vneshniy_file_unique_id` | text | нет | provider stable unique id, если есть |
| `imya_fayla` | text | нет | безопасное имя |
| `mime` | text | нет | фактически/заявленно проверенный MIME |
| `razmer_bayt` | bigint | нет | фактический размер |
| `dlitelnost_sekund` | integer | нет | медиа |
| `shirina` | integer | нет | медиа |
| `vysota` | integer | нет | медиа |
| `sha256` | text | нет | хэш скачанных байтов |
| `status_sohraneniya` | text | да | `tolko_metadannye`, `sohraneno`, `oshibka`, `udaleno` |
| `hranilishche_tip` | text | нет | v1 `postgres_bytea`; позволяет будущую замену |
| `soderzhimoe` | bytea | нет | локальные байты в schema v1, только после лимитов |
| `hranilishche_klyuch` | text | нет | резерв для будущего защищённого object storage |
| `razresheno_ai` | boolean | да | policy flag; фото/видео v1=false |
| `bezopasnye_metadannye` | jsonb | да | без секретов |
| `vremya_sozdaniya` | timestamptz | да | запись |

`status_sohraneniya='sohraneno'` требует либо `soderzhimoe`, либо `hranilishche_klyuch`; оба одновременно не требуются. Внешний `file_id` одного Telegram-бота не считается переносимым на другого.

Индексы: `ix_vlozheniya_soobshchenie` (`soobshchenie_id`); `ix_vlozheniya_file_unique` (`vneshniy_file_unique_id`) partial not null; `ix_vlozheniya_sha256` (`sha256`) partial not null.

### `transkripcii_golosa`

Поля: `id uuid`; `soobshchenie_id uuid FK`; `status text` (`zaplanirovana`,`v_rabote`,`gotova`,`oshibka`); `tekst_transkripcii text`; `tekst_obezlichennyy text`; `dvizhok text`; `versiya_dvizhka text`; `popytki integer`; `vremya_nachala timestamptz`; `vremya_zaversheniya timestamptz`; `kod_oshibki text`; `opisanie_oshibki text`; `vremya_sozdaniya timestamptz`; `vremya_obnovleniya timestamptz`.

Индексы: `uq_transkripcii_soobshchenie` UNIQUE (`soobshchenie_id`); `ix_transkripcii_status` (`status`,`vremya_obnovleniya`).

### `fakty_dialoga`

Это отсутствовавший в старом словаре долговечный слой подтверждённых фактов; `pamyat_dialoga` хранит только быстрый снимок.

Поля: `id uuid`; `dialog_id uuid FK`; `polzovatel_id uuid FK`; `kod_polya text`; `znachenie_zashchishchennoe jsonb`; `znachenie_dlya_ai jsonb`; `eto_pii boolean`; `podtverzhden boolean`; `istochnik text`; `soobshchenie_dokazatelstvo_id uuid FK`; `vremya_fakta timestamptz`; `deystvitelno_do timestamptz`; `zamenen_faktom_id uuid FK self`; `vremya_sozdaniya timestamptz`.

Индексы: `ix_fakty_dialog_kod` (`dialog_id`,`kod_polya`,`vremya_fakta DESC`); `ix_fakty_polz_kod` (`polzovatel_id`,`kod_polya`,`vremya_fakta DESC`); `ix_fakty_dokazatelstvo` (`soobshchenie_dokazatelstvo_id`); `ix_fakty_tekushchie` partial (`dialog_id`,`kod_polya`) where `zamenen_faktom_id IS NULL`.

### `sootvetstviya_pii`

Локальная таблица обратного соответствия псевдометок. Не читается служебным workflow, дашбордом руководителя или внешним AI.

Поля: `id uuid`; `dialog_id uuid FK`; `polzovatel_id uuid FK`; `soobshchenie_id uuid FK`; `tip_pii text`; `psevdometka text`; `znachenie_zashchishchennoe text`; `hash_normalizovannogo_znacheniya text`; `vremya_sozdaniya timestamptz`; `deystvitelno_do timestamptz`.

Индексы: `uq_pii_dialog_metka` UNIQUE (`dialog_id`,`psevdometka`); `ix_pii_soobshchenie` (`soobshchenie_id`); `ix_pii_hash` (`tip_pii`,`hash_normalizovannogo_znacheniya`) partial not null.

### `narusheniya_tematiky`

Поля: `id uuid`; `identifikator_kanala_id uuid FK`; `dialog_id uuid FK`; `soobshchenie_id uuid FK`; `klassifikaciya text` (`ne_po_teme`/`ataka_ili_injection`); `nomer_narusheniya integer`; `istochnik text`; `uverennost numeric`; `prichina text`; `vremya_sobytiya timestamptz`; `privelo_k_blokirovke boolean`.

Индексы: `ix_narusheniya_idkanal_vremya` (`identifikator_kanala_id`,`vremya_sobytiya DESC`); `uq_narusheniya_soobshchenie` UNIQUE (`soobshchenie_id`) для подтверждённого нарушения.

### Исторические бизнес-события

`sobytiya_dialogov`: `id`, `dialog_id`, `polzovatel_id`, `tip_sobytiya`, `vremya_sobytiya`, `vremya_zapisi`, `prichina`, `rezultat`, `predydushchaya_poterya_id`, `istochnik`, `trassirovka_id`. Индексы `ix_sobdialog_dialog_vremya`, `ix_sobdialog_polz_tip`.

`sobytiya_etapov`: `id`, `dialog_id`, `staryy_etap`, `novyy_etap`, `vremya_sobytiya`, `prichina`, `istochnik`, `uverennost`, `soobshchenie_dokazatelstvo_id`. Индекс `ix_sobetap_dialog_vremya`.

`celevye_sobytiya`: `id`, `polzovatel_id`, `dialog_id`, `kod_celi`, `vremya_sobytiya`, `istochnik`, `podtverzhdenie_id`, `dokazatelnye_soobshcheniya uuid[]`, `podtverzhdeno boolean`. Индексы `ix_celi_dialog_kod`, `ix_celi_polz_vremya`; уникальность подтверждённой цели не навязывается глобально, так как одна цель может повторяться в новом бизнес-цикле.

`zayavki`: `id`, `dialog_id`, `polzovatel_id`, `kontakt_zashchishchennyy jsonb`, `potrebnost jsonb`, `vneshniy_klyuch text`, `otvetstvennyy text`, `lokalnyy_status text`, `crm_tip text`, `crm_id text`, `status_sinhronizacii text`, `vremya_sozdaniya`, `vremya_obnovleniya`. Индексы: `uq_zayavki_vnesh_klyuch` UNIQUE (`vneshniy_klyuch`), `ix_zayavki_dialog`, `ix_zayavki_crm`.

## DB-03. Надёжность, память и операторский Telegram

Для реализации DB-03 делится без изменения итогового контракта: DB-03A создаёт девять core-таблиц надёжности и добавляет FK `soobshcheniya.sobytie_id`; DB-03B создаёт три операторские таблицы и добавляет FK `dialogi.tekushchiy_menedzher_id`; DB-03C реализует клиентские/очередные/исходящие функции; DB-03D — функции служебного Telegram и конкурентного ручного перехвата. Родительский DB-03 закрывается только после всех четырёх подзадач и интегральных проверок.

### `sobytiya_integraciy`

Поля: `id uuid`; `versiya_formata integer`; `operaciya_id text`; `istochnik text`; `akkaunt_istochnika_id text`; `vneshnee_sobytie_id text`; `tip_sobytiya text`; `klyuch_idempotentnosti text`; `hash_soderzhaniya text`; `payload_ishodnyy jsonb`; `vremya_istochnika timestamptz`; `vremya_priema timestamptz`; `vremya_zapisi timestamptz`; `status text`; `kod_oshibki text`; `trassirovka_id text`.

Индексы: `uq_sobint_istochnik_sobytie` UNIQUE (`istochnik`,`akkaunt_istochnika_id`,`vneshnee_sobytie_id`); `uq_sobint_idempotentnost` UNIQUE (`klyuch_idempotentnosti`); `ix_sobint_priem` (`vremya_priema`); `ix_sobint_account_time` (`istochnik`,`akkaunt_istochnika_id`,`vremya_priema DESC`) для rate-limit/аудита.

Повтор того же ключа с тем же hash возвращает прежний результат; иной hash — `konflikt`.

### `zadaniya_obrabotki`

Поля: `id uuid`; `dialog_id uuid FK`; `sobytie_id uuid FK`; `tip_zadaniya text`; `status text` (`ozhidaet`,`v_rabote`,`povtor`,`zaversheno`,`otmeneno`,`oshibka`); `prioritet integer`; `popytki integer`; `sleduyushchiy_zapusk timestamptz`; `vladelec_arendy text`; `arenda_do timestamptz`; `nomer_vladeniya bigint`; `versiya_dialoga bigint`; `payload jsonb`; `kod_oshibki text`; `opisanie_oshibki text`; `vremya_sozdaniya timestamptz`; `vremya_obnovleniya timestamptz`.

Индексы: `ix_zadaniya_gotovy` partial (`prioritet DESC`,`sleduyushchiy_zapusk`,`vremya_sozdaniya`) where status in (`ozhidaet`,`povtor`); `ix_zadaniya_dialog` (`dialog_id`,`vremya_sozdaniya`); `ix_zadaniya_arenda` partial (`arenda_do`) where status=`v_rabote`; `uq_zadaniya_dialog_vrabote` UNIQUE partial (`dialog_id`) where status=`v_rabote`.

### `ishodyashchie_deystviya`

Поля: `id uuid`; `dialog_id uuid FK`; `zagruzka_id uuid`; `soobshchenie_id uuid FK`; `vid_deystviya text` (`soobshchenie`,`crm`,`uvedomlenie`,`otchet`); `istochnik text` (`bot`,`menedzher`,`sistema`); `klyuch_povtora text`; `kanal text`; `akkaunt_kanala_id text`; `vneshniy_dialog_id text`; `vneshnee_otvet_na_id text`; `payload jsonb`; `status text` (`zaplanirovano`,`v_rabote`,`podtverzhdeno`,`povtor`,`neizvestno`,`otmeneno`,`oshibka`); `popytki integer`; `sleduyushchiy_zapusk timestamptz`; `vladelec_arendy text`; `arenda_do timestamptz`; `nomer_vladeniya bigint`; `versiya_dialoga bigint`; `vneshniy_id text`; `vremya_zaprosa timestamptz`; `vremya_podtverzhdeniya timestamptz`; `povtor_posle timestamptz`; `kod_oshibki text`; `opisanie_oshibki text`; `vremya_sozdaniya`; `vremya_obnovleniya`.

`zagruzka_id` получает FK на `zagruzki_znaniy.id` только в DB-04 после создания таблицы знаний; до этого поле остаётся nullable UUID и прикладные функции DB-03C не используют его для несуществующей загрузки.

Индексы: `uq_ishod_klyuch_povtora` UNIQUE (`klyuch_povtora`); `ix_ishod_gotovy` partial (`sleduyushchiy_zapusk`,`vremya_sozdaniya`) where status in (`zaplanirovano`,`povtor`); `ix_ishod_dialog_status` (`dialog_id`,`status`,`vremya_sozdaniya`); `ix_ishod_arenda` partial (`arenda_do`) where status=`v_rabote`; `ix_ishod_vnesh` (`kanal`,`akkaunt_kanala_id`,`vneshniy_id`) partial not null.

### `napominaniya`

Поля: `id uuid`; `dialog_id uuid FK`; `tip text` (`napominanie_1`,`napominanie_2`,`proverka_poteri`); `t0 timestamptz`; `soobshchenie_osnovanie_id uuid FK`; `pokolenie_ozhidaniya bigint`; `srok timestamptz`; `aktualno_do timestamptz`; `status text` (`zaplanirovano`,`v_rabote`,`podtverzhdeno`,`propushcheno`,`otmeneno`,`neizvestno`,`oshibka`); `prichina text`; `ishodyashchee_deystvie_id uuid FK`; `vremya_fakticheskoy_otpravki timestamptz`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_napominaniya_dialog_pok_tip` UNIQUE (`dialog_id`,`pokolenie_ozhidaniya`,`tip`); `ix_napominaniya_srok` partial (`srok`) where status=`zaplanirovano`; `ix_napominaniya_dialog` (`dialog_id`,`pokolenie_ozhidaniya`).

### `pamyat_dialoga`

Поля: `dialog_id uuid PK/FK`; `rezyume text`; `poslednie_soobshcheniya jsonb`; `podtverzhdennye_fakty jsonb`; `obrabotano_do_id uuid FK`; `versiya_pamyati bigint`; `kolichestvo_tokenov integer`; `predydushchiy_dialog_id uuid FK`; `vremya_obnovleniya timestamptz`.

`podtverzhdennye_fakty` — кэш для быстрого контекста; нормализованный источник — `fakty_dialoga`.

### `analiz_dialogov`

Поля: `id`, `dialog_id`, `rezyume`, `tema`, `reakciya`, `predpolagaemye_oshibki jsonb`, `probely_znaniy jsonb`, `dokazatelstva uuid[]`, `uverennost numeric`, `versiya_modeli`, `versiya_prompta`, `podtverzhdeno_chelovekom`, `vremya_sozdaniya`. Индекс `ix_analiz_dialog_vremya`.

### `obratnaya_svyaz`

Поля: `id`, `dialog_id`, `polzovatel_id`, `ocenka smallint` (1–5), `tekst`, `vremya`, `kanal`, `predydushchaya_redakciya_id`. Индексы `ix_feedback_dialog`, `ix_feedback_vremya`.

### `sistemnye_sobytiya`

Поля: `id`; `kompaniya_kod`; `sreda`; `komponent`; `operaciya_id`; `trassirovka_id`; `vremya_sobytiya`; `uroven`; `kod`; `opisanie`; `klyuch_gruppirovki`; `status_uvedomleniya`; `kolichestvo_povtorov`; `poslednee_povtorenie`; `vremya_sozdaniya`. Для DB-03A фиксируются коды уведомления: `ne_trebuetsya`, `ozhidaet`, `otpravleno`, `povtor`, `oshibka`, `zakryto`; технические уровни: `info`, `preduprezhdenie`, `oshibka`, `kritichno`.

Индексы: `ix_sissob_vremya_uroven`; `ix_sissob_gruppa`; `ix_sissob_uvedomlenie` partial по состояниям, требующим обработки уведомления: `ozhidaet`, `povtor`, `oshibka`.

### `zhurnal_administrirovaniya`

Поля: `id`; `tip_avtora`; `avtor_id`; `deystvie`; `tip_obekta`; `obekt_id`; `vremya`; `izmeneniya jsonb`; `rezultat`; `trassirovka_id`. Индексы `ix_admin_objekt`, `ix_admin_avtor_vremya`, `ix_admin_vremya`.

### `operator_telegram_temy`

Поля: `dialog_id uuid PK/FK`; `sluzhebnyy_chat_id text`; `message_thread_id text`; `vneshniy_id_kartochki text`; `status text` (`nuzhno_sozdat`,`sozdaetsya`,`gotova`,`neizvestno`,`oshibka`,`zakryta`); `operaciya_sozdaniya_id text`; `popytki integer`; `sleduyushchiy_zapusk timestamptz`; `vladelec_arendy text`; `arenda_do timestamptz`; `nomer_vladeniya bigint`; `vremya_sozdaniya timestamptz`; `vremya_podtverzhdeniya timestamptz`; `vremya_posledney_sinhronizacii timestamptz`; `kod_oshibki text`; `opisanie_oshibki text`.

Индексы: `uq_operator_tema_chat_thread` UNIQUE (`sluzhebnyy_chat_id`,`message_thread_id`) where `message_thread_id IS NOT NULL`; `ix_operator_tema_status` (`status`,`sleduyushchiy_zapusk`); `ix_operator_tema_arenda` partial по `status='sozdaetsya'`.

Если `createForumTopic` мог выполниться, но подтверждение потеряно, статус становится `neizvestno`; второй topic вслепую не создаётся. DB-идемпотентность не выдаётся за exactly-once гарантию Telegram API.

### `menedzhery_telegram`

Поля: `id uuid`; `telegram_user_id text`; `private_chat_id text`; `private_chat_podtverzhden boolean`; `vremya_podtverzhdeniya timestamptz`; `otobrazhaemoe_imya text`; `aktiven boolean`; `mozhet_zabirat boolean`; `mozhet_vozvrashchat boolean`; `lichnye_uvedomleniya boolean`; `prioritet_naznacheniya integer`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_menedzhery_tg_user` UNIQUE (`telegram_user_id`); `uq_menedzhery_private_chat` UNIQUE (`private_chat_id`) partial not null; `ix_menedzhery_aktivnye` partial (`prioritet_naznacheniya`,`id`) where `aktiven=true`.

### `sobytiya_zerkala_operatora`

Поля: `id uuid`; `dialog_id uuid FK`; `soobshchenie_id uuid FK`; `vlozhenie_id uuid FK`; `tip_sobytiya text` (`obespechit_temu`,`soobshchenie_klienta`,`otvet_bota`,`media_klienta`,`nuzhen_chelovek`,`zabran`,`vozvrashchen`,`lichnoe_uvedomlenie`,`obnovit_kartochku`); `klyuch_idempotentnosti text`; `prioritet integer`; `cel_chat_id text`; `cel_thread_id text`; `cel_menedzher_id uuid FK`; `bezopasnaya_podpis_klienta text`; `tekst text`; `payload jsonb`; `status text` (`zaplanirovano`,`v_rabote`,`podtverzhdeno`,`povtor`,`neizvestno`,`otmeneno`,`oshibka`); `popytki integer`; `sleduyushchiy_zapusk timestamptz`; `vladelec_arendy text`; `arenda_do timestamptz`; `nomer_vladeniya bigint`; `vneshniy_message_id text`; `vremya_podtverzhdeniya`; `kod_oshibki`; `opisanie_oshibki`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_zerkalo_klyuch` UNIQUE (`klyuch_idempotentnosti`); `ix_zerkalo_gotovy` partial (`prioritet DESC`,`sleduyushchiy_zapusk`,`vremya_sozdaniya`) where status in (`zaplanirovano`,`povtor`); `ix_zerkalo_dialog` (`dialog_id`,`vremya_sozdaniya`); `ix_zerkalo_arenda` partial (`arenda_do`) where status=`v_rabote`.

## DB-04. Знания

### `zagruzki_znaniy`

Поля: `id uuid`; `sobytie_integracii_id uuid FK`; `vneshnee_sobytie_id text`; `otpravitel_user_id text`; `chat_id text`; `vneshniy_file_id text`; `imya_fayla text`; `ishodnyy_fayl bytea`; `razmer_bayt bigint`; `hash_istochnika text`; `hash_soderzhaniya text`; `vremya_priema timestamptz`; `poryadok_priema bigint`; `status text` (`poluchena`,`proverka`,`obrabotka`,`ozhidaet_proverki`,`zavershena`,`dublikat`,`oshibka`); `kod_oshibki text`; `opisanie_oshibki text`; `dokument_id uuid FK`; `versiya_id uuid FK`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_zagruzki_sobytie` UNIQUE (`sobytie_integracii_id`); `ix_zagruzki_hash_istochnika` (`hash_istochnika`); `ix_zagruzki_status` (`status`,`vremya_priema`); `ix_zagruzki_dokument` (`dokument_id`,`poryadok_priema`).

### `zadaniya_znaniy`

Отдельная долговечная очередь закрывает требование «одна задача загрузки логического документа одновременно» и не использует execution history n8n.

Поля: `id uuid`; `zagruzka_id uuid FK`; `dokument_id uuid FK`; `tip_zadaniya text`; `status text` (`ozhidaet`,`v_rabote`,`povtor`,`zaversheno`,`otmeneno`,`oshibka`); `prioritet integer`; `popytki integer`; `sleduyushchiy_zapusk timestamptz`; `vladelec_arendy text`; `arenda_do timestamptz`; `nomer_vladeniya bigint`; `ozhidaemaya_aktivnaya_versiya_id uuid`; `payload jsonb`; `kod_oshibki`; `opisanie_oshibki`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_zadaniya_znaniy_zag_tip` UNIQUE (`zagruzka_id`,`tip_zadaniya`); `ix_zadaniya_znaniy_gotovy` partial (`prioritet DESC`,`sleduyushchiy_zapusk`,`vremya_sozdaniya`) where status in (`ozhidaet`,`povtor`); `uq_zadaniya_znaniy_vrabote` UNIQUE partial (`dokument_id`) where `status='v_rabote' AND dokument_id IS NOT NULL`; `ix_zadaniya_znaniy_arenda` partial (`arenda_do`) where status=`v_rabote`.

### `dokumenty_znaniy`

Поля: `id uuid`; `identifikator_dokumenta text`; `aktivnaya_versiya_id uuid FK`; `vremya_sozdaniya`; `vremya_obnovleniya`.

Индексы: `uq_dokumenty_identifikator` UNIQUE (`identifikator_dokumenta`); `ix_dokumenty_aktivnaya` (`aktivnaya_versiya_id`) partial not null.

`aktivnaya_versiya_id` может ссылаться только на `opublikovana` версию того же `dokument_id`; это проверяет атомарная функция публикации и ограничение целостности будущего SQL.

### `versii_dokumentov_znaniy`

Поля: `id uuid`; `dokument_id uuid FK`; `zagruzka_id uuid FK`; `nomer_versii integer`; `nazvanie text`; `tip_dokumenta text`; `versiya_istochnika text`; `data_obnovleniya date`; `hash_soderzhaniya text`; `otpechatok_obrabotki text`; `profil_indeksa_id uuid FK`; `status text` (`chernovik`,`gotova`,`opublikovana`,`arhiv`,`oshibka`); `ozhidaemaya_aktivnaya_versiya_id uuid`; `vremya_proverki`; `vremya_publikacii`; `vremya_arhivirovaniya`; `vremya_sozdaniya`.

Индексы: `uq_versii_dokument_nomer` UNIQUE (`dokument_id`,`nomer_versii`); `ix_versii_dokument_status` (`dokument_id`,`status`,`nomer_versii DESC`); `ix_versii_otpechatok` (`dokument_id`,`otpechatok_obrabotki`); `ix_versii_profil` (`profil_indeksa_id`).

### `profili_indeksa`

Поля: `id uuid`; `otpechatok_profilya text`; `embedding_model text`; `razmernost integer`; `metrika text` (`cosine`); `versiya_parsera text`; `versiya_ochistki text`; `versiya_chunkinga text`; `tokenizer text`; `cel_fragmenta_tokenov integer`; `maks_fragmenta_tokenov integer`; `overlap_tokenov integer`; `vremya_sozdaniya timestamptz`.

Индекс: `uq_profili_indeksa_otpechatok` UNIQUE (`otpechatok_profilya`). Строка после использования версией неизменяема.

Для текущего профиля ожидается размерность `1024`, но DB-04 нельзя считать готовой до runtime-подтверждения PRE-02. Если PRE-02 изменит размерность, SQL DB-04 корректируется до применения; векторы разных профилей не смешиваются.

### `fragmenty_znaniy`

Поля: `id uuid`; `versiya_id uuid FK`; `nomer_fragmenta integer`; `put_razdela text`; `tekst_fragmenta text`; `kolichestvo_tokenov integer`; `hash_fragmenta text`; `vektor vector(1024)` для подтверждённого v1-профиля; `vremya_sozdaniya timestamptz`.

Индексы: `uq_fragmenty_versiya_nomer` UNIQUE (`versiya_id`,`nomer_fragmenta`); `ix_fragmenty_versiya` (`versiya_id`,`nomer_fragmenta`); `ix_fragmenty_hnsw_cos` HNSW (`vektor vector_cosine_ops`). Публикация запрещена при `NULL`/неверной размерности вектора.

### `kontrolnye_voprosy`

Поля: `id uuid`; `versiya_id uuid FK`; `nomer integer`; `vopros text`; `ozhidaemyy_razdel text`; `ozhidaemyy_fakt text`; `istochnik text`; `vremya_sozdaniya`. Индексы: `uq_kontrolnye_versiya_nomer` UNIQUE (`versiya_id`,`nomer`); `ix_kontrolnye_versiya`.

### `proverki_znaniy`

Поля: `id uuid`; `versiya_id uuid FK`; `vopros_id uuid FK`; `profil_indeksa_id uuid FK`; `porog_shodstva numeric`; `limit_rezultatov integer`; `poluchennye_fragmenty uuid[]`; `shodstva numeric[]`; `rezultat text` (`uspeshno`,`neuspeshno`,`oshibka`); `opisanie text`; `vremya_proverki timestamptz`.

Индексы: `ix_proverki_versiya_vremya`; `ix_proverki_vopros`.

## PostgreSQL-функции: прикладной API

Все функции возвращают `operaciya_id`, `rezultat`, `kod_oshibki`, `opisanie`, при необходимости `povtor_posle`, плюс предметные ID. Повтор `operaciya_id`/идемпотентного ключа с тем же содержимым возвращает прежний результат; с другим содержимым — `konflikt`.

### Клиентский ingress и диалог

| Функция | Роль | Вход / атомарный результат |
|---|---|---|
| `zaregistrirovat_vhod_klienta` | bot | нормализованный вход v1, вложения-метаданные; одной транзакцией integration event → identity/user → dialog/message → job; увеличивает `versiya_dialoga`, отменяет старое ожидание/напоминания; для первого сообщения ставит `obespechit_temu`, для текста — зеркало; возвращает user/dialog/message/job/version |
| `sohranit_vlozhenie` | bot | message + проверенные байты/метаданные/hash; соблюдает лимиты, создаёт media mirror job; не передаёт файл наружу |
| `sohranit_transkripciyu_golosa` | bot | message, status, локальный engine/version, raw transcript и deidentified transcript; ошибка STT не создаёт нарушение |
| `sohranit_obezlichivanie` | bot | message, `tekst_obezlichennyy`, набор PII placeholder↔protected value; атомарно обновляет сообщение и `sootvetstviya_pii` |
| `poluchit_kontekst_dialoga` | bot | dialog/job/version; возвращает owner/block/status, память 3–5, факты, новые обезличенные сообщения; сырые PII только отдельными локальными полями, не смешанными с AI-пакетом |
| `sohranit_fakty_i_pamyat` | bot | CAS по `versiya_dialoga` и `versiya_pamyati`; upsert новых подтверждённых фактов с evidence, summary/window/processed pointer |
| `proverit_limit_chastoty` | bot | channel identity + окно/лимит из доверенной конфигурации; считает сохранённые входы, не меняя тематический счётчик |
| `zapisat_narushenie_tematiky` | bot | identity/dialog/message/classification; под row lock создаёт ровно одно нарушение, увеличивает счётчик, при лимите блокирует; возвращает номер предупреждения и block flag |
| `razblokirovat_polzovatelya` | dash_admin | identity + причина + admin operation; снимает логическую блокировку, сбрасывает/корректирует счётчик по политике, пишет admin journal |

### Очередь обработки

| Функция | Роль | Контракт |
|---|---|---|
| `zabrat_zadanie_obrabotki` | bot | атомарный claim следующего due job через row locking/SKIP LOCKED; не даёт двум worker один dialog |
| `prodlit_arendu_zadaniya` | bot | job + worker + ownership number; продлевает только текущему владельцу |
| `zavershit_zadanie_obrabotki` | bot | job + worker + ownership number + expected dialog version; `zaversheno/povtor/otmeneno/oshibka`, retry time/error; stale owner/version получает `konflikt` |

### Исходящие действия и напоминания

| Функция | Роль | Контракт |
|---|---|---|
| `sozdat_ishodyashchee_deystvie` | bot | создаёт logical message + action до внешнего API; повтор по stable key не создаёт дубль; проверяет owner/version/block/opt-out |
| `zabrat_ishodyashchee_deystvie` | bot | claim due action с арендой |
| `zafiksirovat_rezultat_ishodyashchego` | bot | action + ownership + результат API; переводит в confirmed/retry/unknown/error; **только confirmed** атомарно применяет разрешённые stage/goal/memory/t0/reminder changes и создаёт mirror bot-response event |
| `podgotovit_napominanie` | bot | reminder id/generation; под lock повторно проверяет owner/status/block/opt-out/new input/window; возвращает `otpravit/propustit/otmenit` и при `otpravit` создаёт outgoing action |
| `zafiksirovat_poteryu_bez_otveta` | bot | loss-check reminder; закрывает `net_otveta` только при подтверждённом reminder2 и отсутствии более нового входа |

CRM использует `sozdat_ishodyashchee_deystvie` с `vid_deystviya='crm'`; отдельной привилегированной CRM-функции БД не требуется.

### Служебный Telegram и оператор

| Функция | Роль | Контракт |
|---|---|---|
| `zaregistrirovat_sluzhebnoe_sobytie` | sluzhebnyy | durable idempotent ingress одного service-bot webhook; не создаёт клиентский dialog; возвращает зарегистрированный event для внутренней маршрутизации |
| `podtverdit_lichnyy_chat_menedzhera` | sluzhebnyy | `/start`: обновляет private chat только у заранее разрешённого active `telegram_user_id`; неизвестного пользователя не добавляет |
| `zabrat_sobytie_zerkala` | sluzhebnyy | claim mirror event; возвращает только узкий payload, topic/media bytes, нужные для конкретной отправки; не открывает общий SELECT архива |
| `zafiksirovat_rezultat_zerkala` | sluzhebnyy | confirmed/retry/unknown/error; сохраняет external message id; unknown не повторяет вслепую |
| `zabrat_sozdanie_operator_temy` | sluzhebnyy | claim `nuzhno_sozdat`; если topic уже gotova — возвращает его; конкурент получает занято/дубликат |
| `podtverdit_operator_temu` | sluzhebnyy | dialog + creation operation + thread id/card id; записывает mapping один раз; конфликт другого thread запрещён |
| `otmetit_temu_neizvestnoy` | sluzhebnyy | ambiguous createForumTopic; запрещает blind recreate, создаёт системное событие |
| `zabrat_dialog_operatorom` | sluzhebnyy | callback + manager Telegram ID + expected dialog version; проверяет allowed manager; `bot→chelovek` first-commit-wins; отменяет wait/reminders/planned bot reply, increment version/generation, пишет dialog+mirror events |
| `vernut_dialog_botu` | sluzhebnyy | current manager/admin + expected version; `chelovek→bot`, manager=NULL, wait=false, без автосообщения; пишет события |
| `sozdat_ruchnoe_ishodyashchee` | sluzhebnyy | service event/message, chat/thread, manager user id, text; resolves topic→dialog, verifies current manager/owner, creates `soobshcheniya` author=manager + ordinary outgoing action; idempotent |
| `sozdat_lichnoe_uvedomlenie` | bot | manager id + dialog + reason; only confirmed private chat + setting enabled; creates mirror/notification event, not direct Telegram call |

Разрешение `sozdat_lichnoe_uvedomlenie` у bot не даёт ему произвольный chat_id: адрес берётся из `menedzhery_telegram`.

### Знания

| Функция | Роль | Контракт |
|---|---|---|
| `zaregistrirovat_zagruzku_znaniy` | sluzhebnyy | registered service event + verified sender/file/bytes/hash; создаёт upload и первый knowledge job; повтор event возвращает старую загрузку |
| `zabrat_zadanie_znaniy` | sluzhebnyy | claim due job; один `v_rabote` на logical document |
| `prodlit_arendu_zadaniya_znaniy` | sluzhebnyy | CAS lease |
| `zavershit_zadanie_znaniy` | sluzhebnyy | finish/retry/error with ownership check |
| `podgotovit_versiyu_znaniy` | sluzhebnyy | parsed document ID/metadata/hashes/profile; под lock создаёт/находит document, атомарно назначает next version, фиксирует expected active version; active fingerprint duplicate → `dublikat` |
| `sohranit_fragmenty_znaniy` | sluzhebnyy | version + batch fragments + vectors; проверяет profile/dimension/count/unique chunk no/hash; partial batch does not mark version ready |
| `sohranit_kontrolnye_voprosy` | sluzhebnyy | 3–10 reference questions for first publication; не добавляет их в fragment text |
| `sohranit_proverki_znaniy` | sluzhebnyy | сохраняет фактические test-search results and threshold/top-k |
| `poisk_chernovika_znaniy` | sluzhebnyy | explicit `versiya_id` + vector/profile/limit/threshold; ищет только указанную draft/version, не меняя active pointer |
| `poisk_aktivnyh_znaniy` | bot | vector/profile/limit/threshold; внутри функции join only `dokumenty_znaniy.aktivnaya_versiya_id`, version must be `opublikovana`; аргумента draft нет |
| `opublikovat_versiyu_znaniy` | sluzhebnyy | version + `ozhidaemaya_aktivnaya_versiya_id` + operation id; проверяет ready/fragments/vectors/checks; одной транзакцией active pointer, new `opublikovana`, old `arhiv`, upload `zavershena`; stale expectation → conflict |
| `otozvat_dokument_znaniy` | dash_admin | document + expected active + reason; атомарно убирает active pointer, пишет admin event; физически данные не удаляет |

В `poisk_*` сходство = `1 - cosine distance`; фильтр версии выполняется до выдачи лимита. Для pgvector 0.8.2 SQL может использовать HNSW iterative scan при фильтрации, но конкретные параметры производительности утверждаются только тестом DB-05/PRE-02.

## Матрица EXECUTE

| Группа функций | bot | sluzhebnyy | dash_read | dash_admin |
|---|---:|---:|---:|---:|
| клиентский ingress/очередь/PII/память/guard | да | нет | нет | только `razblokirovat_polzovatelya` через admin |
| исходящие клиента/напоминания | да | только `sozdat_ruchnoe_ishodyashchee` создаёт действие через узкий definer | нет | нет |
| операторские темы/зеркало/callback | только создание narrow events/личного сигнала | да | нет | разрешённые admin-операции позже |
| active RAG | да | нет | нет | нет |
| draft RAG/ingestion/publish | нет | да | нет | `otozvat_dokument_znaniy` |
| dashboard reporting views/functions | нет | нет | да | да |
| DDL/grants | нет | нет | нет | нет |

`deploy` работает отдельно от этой матрицы; `owner` не имеет LOGIN. У всех вновь создаваемых функций `EXECUTE` у `PUBLIC` отзывается в той же миграции.

## Обязательные проверки контракта перед отметкой DB-01…DB-05

1. **DB-01:** test role не видит prod/другую schema; bot/service roles не создают объекты; `PUBLIC/anon/authenticated` не получают доступ; функция одной компании не открывается ролью другой.
2. **DB-02:** два одинаковых входа дают один event/message/job; тот же idempotency key с другим hash даёт conflict; новая редакция не переписывает исходный текст; media bytes остаются локальными.
3. **DB-03:** два worker не забирают один dialog; истёкшая lease восстанавливается; stale owner/version не пишет результат; новый input отменяет старое ожидание; `neizvestno` не повторяется; три подтверждённых нарушения блокируют, а STT error/unsupported media — нет.
4. **Оператор DB-03:** первый вход создаёт один topic intent; два «Забрать» дают одного owner; чужой manager не пишет клиенту; захват отменяет bot/reminders; «Вернуть» не создаёт автоответ; service role не может общий SELECT сырых client messages; mirror/media выдаются только конкретному claimed event.
5. **DB-04:** version number/processing queue устойчивы к конкурентным загрузкам; векторная размерность и profile совпадают; без reference checks version не публикуется.
6. **DB-05:** bot search никогда не видит draft/archive; service test search видит только explicit version; parallel/stale publish конфликтует; old active knowledge остаётся при любой ошибке до commit; report Telegram failure не откатывает publication.

## Расхождения, закрытые DB-00

DB-00 добавляет к прежнему `DATA_DICTIONARY` четыре обязательных элемента, которые следовали из спецификаций, но не были выделены структурно:

- `fakty_dialoga` — долговечные подтверждённые факты с evidence/PII/expiry;
- `sootvetstviya_pii` — локальное обратное соответствие псевдометок;
- `narusheniya_tematiky` — отдельный аудит предупреждений/блокировки;
- `zadaniya_znaniy` — долговечная последовательная очередь ingestion.

Кроме того, `vlozheniya_soobshcheniy` получает локальное содержимое/абстракцию хранилища, иначе отдельный служебный workflow не сможет надёжно повторно отправить фото/видео/голос через другой Telegram-бот после завершения клиентского выполнения.

## Что DB-00 не доказывает

Документ не означает, что таблицы/роли/функции уже существуют, что импортированные workflow работают, что OpenRouter Credentials/API проверены, что локальный STT развёрнут или что production готов. Эти факты закрываются последующими DB/RT/BOT/PRE задачами.
