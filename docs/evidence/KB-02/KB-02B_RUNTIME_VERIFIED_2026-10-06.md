# KB-02B — runtime verified, 2026-10-06

## Что проверялось

KB-02B превращает runtime-проверенные KB-02A2 candidates в окончательные fragment records и отдельно готовит reference questions из проверенного YAML. На этом этапе нет generative LLM, embeddings, записи fragments/questions в DB или publish.

Проверен import-ready workflow **v0.10 KB-02B**, SHA-256:

`f19b8f7189f71fe92a67e1331628da6df9dbf10df26483ae8575bf41d77048b7`

## Live runtime

Реальный test-run прошёл на safe документе `qbit_podgotovka_k_pervichnomu_razboru`.

Подтверждено:
- live job claim с fence `4`;
- A1: 10 structural blocks / 6 headings;
- A2: 6 candidates, exact `cl100k_base`, token range 102..211, average 151.7, `prevyshenie_max=0`;
- A2 candidate fingerprint: `1808f182d52a56bf1f4dc4f3066ac70f3e0c2c9b8555fb2c436e9a42bfe5cbab`;
- B: 6 final fragment records;
- `nomera_posledovatelny=true`;
- source-block trace сохранён в runtime metadata;
- 3 reference questions взяты из YAML;
- `kontrolnye_gotovy_dlya_avtoproverki=true`;
- reference questions не входят в retrieval text;
- `hash_nabora_fragmentov=d367f0824cee817d498778f95815b4175a3e47cebd2facebdcacaffc1703a0d2`;
- `hash_nabora_kontrolnyh_voprosov=d34d9e8222fa5608d2c4612a2decf5d158b7cbf3dc8fbba8499774639082e70a`;
- `hash_gotovogo_nabora=ad69f88ebbd5c99147cf3c750fcacaa37e4d12ff58366bd53f5573e04b150455`;
- `llm_vyzovov=0`;
- `embeddings_vyzovov=0`;
- `db_fragmenty_sohraneny=false`;
- `db_kontrolnye_sohraneny=false`;
- `publish_vypolnen=false`.

`podgotovit_versiyu_znaniy` вернула ожидаемый идемпотентный `dublikat`: версия для этой загрузки уже существовала и осталась `chernovik`.

После dry-run job тем же worker/fence успешно освобождён обратно в `status_zadaniya=povtor`.

## Проверка детерминизма

Второй live-claim не выполнялся. Вместо лишнего server-run тот же код ноды `KB-02B Подготовить финальные записи` был дважды локально выполнен на идентичном контролируемом входе. Полный JSON двух запусков совпал побайтово, включая fragment-set hash, question-set hash и ready-set hash.

Это подтверждает отсутствие случайности/времени в самом B-преобразовании. Live runtime отдельно подтвердил работу этого кода в n8n на реальном fenced job.

## Нагрузка

KB-02B не добавляет LLM-нагрузку. Fragment records — индексные данные, а не prompt целиком. После B-compression полные arrays удаляются из дальнейшего execution payload; остаются отчёт, четыре samples и summary вопросов.

## Итог

**KB-02B runtime verified.**

Доказано:
- DB-compatible fragment records до vector-поля готовы;
- exact text/hash/token count/order согласованы;
- reference questions отделены от retrieval text;
- 3–10 question guard работает на live документе;
- deterministic B-transform подтверждён;
- LLM/embeddings/DB save/publish не выполнялись;
- job не потерян.

Следующая задача: **KB-03A** — получить document embeddings OpenAI `text-embedding-3-large`, `dimensions=1024`, строго проверить каждый vector и только затем вызвать нормативный `sohranit_fragmenty_znaniy`.

Production и рабочий трафик не менялись. Полный v0.10 пока не сохранён отдельным восстановимым Git-checkpoint; не утверждать обратное.
