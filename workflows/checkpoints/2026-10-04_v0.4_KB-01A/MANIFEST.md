# Workflow checkpoint v0.4 KB-01A — 2026-10-04

Это точная очищенная копия подготовленного import-ready workflow
`Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`.

Основа: фактический export Павла `Шаблон — служебный Telegram и перехват диалогов — версия 0.2 (7).json`, дополненный только подзадачей KB-01A.

Состав:
- `workflow_v0.4_KB-01A.json.gz.b64.part00` … `part09` — 10 частей base64 в строгом порядке;
- после объединения base64: 64148 символов;
- после распаковки получается полный import-ready JSON;
- размер JSON: 278964 байта;
- SHA-256 JSON: `4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959`.

Проверенные свойства JSON:
- nodes: 196;
- connection keys: 161;
- edges: 225;
- `active=false`;
- duplicate node names: 0;
- dangling connections: 0;
- top-level `id`, `versionId`, `meta.instanceId` отсутствуют;
- node `credentials` отсутствуют;
- реальный ID служебной Telegram-группы отсутствует;
- очевидные API keys/Bearer/Telegram bot tokens не найдены.

KB-01A добавляет intake `.md` через существующий единый служебный Telegram webhook до `zaregistrirovat_zagruzku_znaniy(jsonb, bytea)` и durable knowledge job. Парсинг Markdown, chunking, document embeddings, reference checks и публикация не входят в этот checkpoint.

Восстановление:

```bash
python tools/restore_workflow_checkpoint.py
```

Скрипт создаёт локально:

`workflows/Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json`

Этот checkpoint доказывает сохранность подготовленного файла в Git. Он не доказывает импорт или runtime-проверку в n8n.
