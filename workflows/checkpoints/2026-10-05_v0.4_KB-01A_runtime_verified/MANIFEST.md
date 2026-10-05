# Workflow checkpoint v0.4 KB-01A — runtime verified — 2026-10-05

Это точная очищенная import-ready копия канонического workflow после runtime-проверки KB-01A.

Основа: ранее сохранённый v0.4 KB-01A, дополненный только исправлением финального Telegram-ответа:
- `KB-01A Сформировать результат регистрации` экранирует `&`, `<`, `>` в динамических значениях;
- `KB-01A Ответить про загрузку знаний` явно использует `parse_mode=HTML`.

Runtime whitelist и Credential refs в Git не сохраняются. Канонические whitelist-массивы пустые.

Состав:
- `workflow_v0.4_KB-01A.json.gz.b64.part00` … `part04` — 5 частей base64 в строгом порядке;
- после объединения base64: 64308 символов;
- после распаковки получается полный import-ready JSON;
- размер JSON: 279355 байт;
- SHA-256 JSON: `6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`.

Проверенные свойства JSON:
- nodes: 196;
- connection keys: 161;
- edges: 225;
- `active=false`;
- duplicate node names: 0;
- dangling connections: 0;
- top-level `id`, `versionId`, `meta.instanceId` отсутствуют;
- node `credentials` отсутствуют;
- реальные Telegram user/chat/group ID отсутствуют;
- очевидные API keys/Bearer/Telegram bot tokens не найдены;
- изменённый Code node проходит JS syntax check.

Runtime KB-01A на test-контуре подтверждён 2026-10-05:
- разрешённый private `.md` принят через существующий service webhook;
- DB registration вернула `uspeshno`, non-null `zagruzka_id` и `zadanie_id`, `status_zagruzki=poluchena`;
- после исправления parse mode Telegram-ответ успешно отправлен для имени файла с `_`;
- production не менялся;
- YAML/Markdown parse, chunking, document embeddings, reference checks и publish ещё не входят в KB-01A.

Восстановление:

```bash
python tools/restore_workflow_checkpoint.py
```

Скрипт создаёт локально:

`workflows/Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

и проверяет SHA-256.
