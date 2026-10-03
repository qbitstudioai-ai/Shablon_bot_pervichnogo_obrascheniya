# Workflow checkpoint v0.3 — 2026-10-03

Это точная очищенная копия последнего фактического export Павла `Шаблон — служебный Telegram и перехват диалогов — версия 0.2 (6).json`, сохранённая как gzip+base64 из-за ограничения размера единичной записи через текущий GitHub-коннектор.

Состав:
- `workflow_v0.3.json.gz.b64.part00` … `part07` — 8 частей base64 в строгом порядке;
- после объединения base64: 55992 символа;
- gzip: 41994 байта;
- после распаковки получается компактный JSON;
- SHA-256 компактного JSON: `ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7`.

Проверенные свойства исходного очищенного JSON:
- nodes: 189;
- connection keys: 153;
- edges: 215;
- `active=false`;
- duplicate node names: 0;
- dangling connections: 0;
- top-level `id`, `versionId`, `meta.instanceId` удалены;
- node `credentials` удалены;
- реальный ID служебной Telegram-группы заменён на `null`;
- очевидные API keys/Bearer/Telegram bot tokens не найдены.

Восстановление:

```bash
python tools/restore_workflow_checkpoint.py
```

Скрипт создаёт локально:

`workflows/Шаблон — мультиканальный бот и служебный Telegram — версия 0.3.json`

Этот checkpoint — сохранение текущего workflow в Git. Он **не содержит** экспериментальный KB-01 workflow и не означает, что knowledge/RAG готов.
