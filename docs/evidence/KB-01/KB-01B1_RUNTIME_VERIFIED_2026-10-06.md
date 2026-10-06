# KB-01B1 runtime evidence — 2026-10-06

Статус: **VERIFIED в test-контуре**.

Production не менялся. Реальный текст Markdown, Telegram ID, Credential refs и секреты в evidence не сохраняются.

## Что проверено

В n8n 2.41.0 вручную запущена изолированная KB-01B1 worker-ветка полного workflow v0.5.

Проверенный зарегистрированный safe `.md`:
- filename: `QBit_knowledge_base_READY_FOR_UPLOAD.md`;
- `hash_istochnika`: `b6ea99447c55b456e4dcb6392ea2527c6bac077c17cb54189fa732e03f202c29`.

Claim через `zabrat_zadanie_znaniy`:
- `rezultat=uspeshno`;
- `zadanie_id=0032a78e-b3fa-4cc8-8175-fcc52b53dd64`;
- `zagruzka_id=2d94322c-0347-48ce-8c66-e136e79d54d4`;
- `status_zadaniya=v_rabote`;
- `popytki=1`;
- `vladelec_arendy=qbit_test_kb_worker_v1`;
- `nomer_vladeniya=1`;
- lease получен и оставался live на время проверки.

Parser `kb01b1_safe_frontmatter_markdown_v1`:
- `kb01b1_valid=true`;
- `kb01b1_kod=provereno`;
- `identifikator_dokumenta=qbit_klientskaya_baza_znaniy`;
- `tip_dokumenta=opisanie`;
- `versiya_istochnika=1.0`;
- `data_obnovleniya=2026-09-25`;
- структурных заголовков: `57`;
- контрольных вопросов: `8`;
- предупреждений: `0`;
- `hash_soderzhaniya=73436107b06ed1465094f23f785dadbb973adc787e049c04966195ae629e2290`.

После проверки вызван `zavershit_zadanie_znaniy` с теми же worker/fencing:
- `rezultat=uspeshno`;
- `zadanie_id=0032a78e-b3fa-4cc8-8175-fcc52b53dd64`;
- `status_zadaniya=povtor`;
- `povtor_posle=2026-10-06T04:10:06.959Z`.

Таким образом тестовое job не потеряно и не оставлено в `v_rabote`.

## Независимая перепроверка

После runtime-output фактические bytes `ishodnyy_fayl` были повторно прогнаны вне n8n через тот же Code-node parser из v0.5. Повторно получены:
- `57` заголовков;
- `8` контрольных вопросов;
- тот же `hash_soderzhaniya=73436107b06ed1465094f23f785dadbb973adc787e049c04966195ae629e2290`.

Ранее названный до runtime ориентир `be8f4f8d...` признан ошибочным и не используется.

## Вывод

Критерий KB-01B1 выполнен: durable job успешно claim-ится через lease/fencing, bytea читается в фактическом n8n, YAML/Markdown проходит безопасную проверку, canonical semantic hash воспроизводим, а job корректно освобождается обратно в `povtor`.

Следующая задача: **KB-01B2** — зафиксировать фактически доступный processing/index profile и tokenizer, вычислить fingerprints и вызвать `podgotovit_versiyu_znaniy` под тем же live lease/fencing. Chunking/embeddings/publish в KB-01B2 не выполнять.
