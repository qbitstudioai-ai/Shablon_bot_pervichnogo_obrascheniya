# SESSION HANDOFF

Обновлено: 2026-10-06.

## Исходная точка

Рабочая ветка: `main`.

KB-01A, KB-01B1, KB-01B2, KB-02A1 и KB-02A2 завершены и runtime-проверены. Текущая маленькая задача — **KB-02B**.

Перед продолжением проверить актуальный `main` HEAD и прочитать:
1. `README.md`;
2. `docs/PROJECT_STATE.md`;
3. этот файл;
4. `docs/KB_WORKFLOW_IMPLEMENTATION_PLAN.md`;
5. `docs/specs/KNOWLEDGE_INGESTION.md`;
6. `docs/specs/MARKDOWN_FORMAT.md`;
7. нужные части `docs/specs/DB_CONTRACT.md` и `docs/specs/PROCESSING_PROFILE.md`.

## Канонический workflow

Фактическая основа: export Павла `(7)`.

Последний сохранённый в Git runtime-verified checkpoint пока:

`workflows/checkpoints/2026-10-05_v0.4_KB-01A_runtime_verified/`

Restore:

`python tools/restore_workflow_checkpoint.py`

Ожидаемый SHA-256 этого старого Git-checkpoint:

`6f7205bb9c062139ff22d01c9d62b4b71c7619dbe5d5264121ee338b0a72bea5`

Фактически текущий runtime-проверенный import-ready workflow — **v0.9.1 KB-02A2**:

`workflow_v0.9.1_KB-02A2.json`

SHA-256:

`5c3667fe84462be019d49c5560cc9f3c07e6cc10b666b665e9583f5c2f89a81c`

Отдельный Git-checkpoint v0.9.1 ещё не сохранён; не утверждать обратное.

Для KB-02B подготовлен локальный import-ready **v0.10 KB-02B**, ещё не runtime-проверенный:

`Шаблон — мультиканальный бот и служебный Telegram — версия 0.10 KB-02B.json`

SHA-256:

`f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`

Статика v0.10: 223 nodes, 180 connection keys, 251 edges, `active=false`, Credential refs 0, duplicate names 0, dangling connections 0. JavaScript всех Code/LangChain Code nodes проходит syntax check при async wrapper. v0.10 не является runtime-verified и не является Git-checkpoint.

## Доказанный runtime

### KB-01A
Private `.md` прошёл durable service ingress, download, actual bytes validation и DB registration.

Evidence: `docs/evidence/KB-01/KB-01A_RUNTIME_VERIFIED_2026-10-05.md`.

### KB-01B1
Knowledge job успешно claim-нут через lease/fencing; safe YAML/Markdown parser подтвердил metadata/структуру и deterministic `hash_soderzhaniya`; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-01B2
Processing/index profile зафиксирован; `podgotovit_versiyu_znaniy` создала version 1 `chernovik`; publish не выполнялся; job возвращён в `povtor`.

Evidence: `docs/evidence/KB-01/KB-01B2_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A1
Runtime v0.8 на большой safe Markdown-базе: 57 headings, 130 ordered structural blocks, 90 paragraph + 40 list, warnings 0, YAML/reference questions excluded, stable structure hash, DB fragments 0, job `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A1_RUNTIME_VERIFIED_2026-10-06.md`.

### KB-02A2
Runtime v0.9.1 на той же большой safe Markdown-базе:
- fence `4`;
- exact tokenizer: `cl100k_base`;
- source: `n8n_builtin_TokenTextSplitter_local_encoding`;
- canary `hello world` → 2 tokens;
- `exact_token_count=true`, `tokenizer_object=true`;
- 130 structural blocks → 53 topic groups → 53 final candidate fragments;
- token range 87..551, average 237.1;
- candidates <=80: 0;
- candidates >800: 0;
- split source blocks: 0, поэтому overlap фактически не потребовался;
- `hash_kandidatov=e87704afce40351fec6432860689e1af6dc3666823733cf22c327d97a7fa45a4`;
- LLM 0, embeddings 0, DB fragment save false;
- `podgotovit_versiyu_znaniy` → ожидаемый идемпотентный `dublikat`, существующая version 1 остаётся `chernovik`;
- job возвращён в `povtor`.

Evidence: `docs/evidence/KB-02/KB-02A2_RUNTIME_VERIFIED_2026-10-06.md`.

## Guard по нагрузке на LLM

Рост базы знаний не должен линейно увеличивать prompt клиентской LLM.

Обязательные правила:
- parsing/cleaning/chunking/token counting — без generative LLM;
- structural blocks/final candidates/final fragment records — индексные данные, не prompt целиком;
- клиентский путь: query embedding → vector search → фильтрация/дедупликация → небольшой evidence-пакет → финальная LLM;
- candidate top-k = 12, финальный evidence максимум 8 fragments и обычно меньше;
- не добавлять LLM reranker в v1 без доказанной необходимости;
- до retrieval-калибровки зафиксировать общий evidence token budget.

Важно из A2: target 600 не является минимумом. Нельзя объединять разные темы только ради target; на реальной базе средний final candidate = 237.1 tokens, max = 551.

## Текущая задача — KB-02B

Цель: превратить A2 candidates в окончательные records, готовые к будущему embedding/save, и отдельно подготовить reference questions.

### Что добавлено в v0.10

- `KB-02B Подготовить финальные записи` повторно валидирует exact fragment text/hash/order и A2 fingerprint;
- final record: `nomer_fragmenta`, `put_razdela`, `tekst_fragmenta`, `kolichestvo_tokenov`, `hash_fragmenta`, runtime trace к source blocks;
- reference questions берутся только из canonical YAML metadata и преобразуются в отдельный DB-compatible массив: `nomer`, `vopros`, `ozhidaemyy_razdel`, optional `ozhidaemyy_fakt`, `istochnik=yaml`;
- questions не добавляются в fragment text и не входят в retrieval embeddings;
- 3–10 questions → `kontrolnye_gotovy_dlya_avtoproverki=true`; 0–2 не портят fragment records, но автоматическая проверка считается неготовой;
- считаются deterministic `hash_nabora_fragmentov`, `hash_nabora_kontrolnyh_voprosov`, `hash_gotovogo_nabora`;
- DB batch limit 100 отражается только в отчёте; current 53 fragments поместятся в один будущий DB batch после embeddings;
- `KB-02B Сжать dry-run результат` удаляет полные arrays перед дальнейшими Postgres нодами и оставляет только report + 4 fragment samples + question summary;
- `Служебный_KB_Вернуть после ошибки B` безопасно возвращает current fenced job в `povtor` при validation error;
- LLM/OpenAI embeddings/`sohranit_fragmenty_znaniy`/`sohranit_kontrolnye_voprosy`/publish не вызываются.

### Runtime-проверка v0.10

Импортировать v0.10 как отдельный inactive workflow. Назначить service Postgres Credential `Служебный. Qbit_bot_pervichnogo_obrascheniya` только worker-ветке и вручную запустить `KB-02B Ручной запуск worker`.

На ручном пути Credentials нужны нодам:
1. `Служебный_KB_Забрать задание`;
2. `Служебный_KB_Вернуть после ошибки проверки`;
3. `Служебный_KB_Вернуть после ошибки профиля`;
4. `Служебный_KB_Вернуть после ошибки структуры`;
5. `Служебный_KB_Вернуть после ошибки A2`;
6. `Служебный_KB_Вернуть после ошибки B`;
7. `Служебный_KB_Подготовить версию`;
8. `Служебный_KB_Вернуть после B2`.

Для доказательства успешного пути прислать outputs:
1. `KB-02B Сжать dry-run результат`;
2. `Служебный_KB_Подготовить версию`;
3. `Служебный_KB_Вернуть после B2`.

Не присылать полный output `KB-02B Подготовить финальные записи`: он содержит все fragments/questions и специально сжимается следующей нодой.

Если сработал error path, прислать только `Служебный_KB_Вернуть после ошибки B`; job должен вернуться в `povtor`.

### Критерий KB-02B

- fragment records готовы и порядок стабилен;
- hash каждого fragment соответствует точному тексту;
- reference questions отдельны и не входят в retrieval text;
- для текущей большой базы ожидаются 8 questions и готовность к будущей автоматической проверке;
- LLM/embeddings/DB save/publish = 0;
- job после dry-run возвращён в `povtor`.

## Следующая задача после KB-02B

`KB-03A` — получить document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, строго проверить длину каждого vector и только затем вызвать нормативный `sohranit_fragmenty_znaniy`.

## Запреты

- Не менять production.
- Не переключать рабочий трафик.
- Не импортировать experimental KB workflow.
- Не продолжать старый B3.
- Не запускать experimental evidence SQL.
- Не публиковать реальные документы, Telegram ID, Credential refs, переписку или секреты.
