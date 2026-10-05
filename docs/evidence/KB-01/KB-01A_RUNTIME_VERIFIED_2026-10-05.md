# KB-01A — runtime verified — 2026-10-05

## Объём проверки

Проверен test-контур канонического workflow v0.4 KB-01A. Production и рабочий трафик не менялись.

В Git не сохраняются реальные Telegram user/chat ID, Credential refs, переписка или содержимое рабочих документов.

## Фактический runtime

1. Канонический workflow импортирован в n8n.
2. В UI n8n назначены существующие service Telegram/Postgres Credentials.
3. Runtime whitelist заполнен разрешённым Telegram user ID и private chat ID.
4. Обычные служебные текстовые сообщения из private chat и service group продолжили проходить через существующий service ingress и durable registration.
5. Первый `.md` успешно дошёл до DB registration:
   - `rezultat=uspeshno`;
   - получены non-null `zagruzka_id` и `zadanie_id`;
   - `status_zagruzki=poluchena`.
6. Финальный Telegram-ответ первого прогона выявил отдельную ошибку presentation-слоя: имя файла с `_` разбиралось Telegram как Markdown entity. DB registration при этом уже была успешной и не откатывалась.
7. Исправление:
   - dynamic filename/error text HTML-escaped (`&`, `<`, `>`);
   - Telegram node `KB-01A Ответить про загрузку знаний` использует `parse_mode=HTML`.
8. Второй безопасный `.md` с `_` в имени успешно прошёл:
   - `rezultat=uspeshno`;
   - non-null `zagruzka_id`;
   - non-null `zadanie_id`;
   - `status_zagruzki=poluchena`;
   - Telegram успешно отправил подтверждение постановки файла в очередь;
   - execution завершился зелёным.

`zaregistrirovat_zagruzku_znaniy` создаёт durable knowledge job со статусом `ozhidaet` в той же транзакции, в которой возвращает `zadanie_id`; этот DB-04 контракт ранее отдельно runtime-проверен.

## Что НЕ проверяет KB-01A

KB-01A не выполняет YAML/Markdown parse, canonical content hash, version preparation, chunking, document embeddings, reference checks или publish. Эти шаги идут дальше по `KB-01B` → `KB-03C`.

## Результат

KB-01A: **runtime verified**.

Следующая маленькая задача: `KB-01B` — claim durable job с lease/fencing, безопасный разбор YAML/Markdown, валидация metadata/структуры и вызов `podgotovit_versiyu_znaniy`.
