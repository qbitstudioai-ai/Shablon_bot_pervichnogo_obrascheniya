# KB-03A — runtime verified, 2026-10-06

## Цель

Получить document embeddings OpenAI для final fragment records KB-02B, строго проверить vectors и только после этого сохранить fragments/vectors через нормативный `sohranit_fragmenty_znaniy` в test schema.

Production и рабочий трафик не менялись. Publish и reference-question checks не выполнялись.

## Workflow

Runtime проверен на import-ready **v0.11 KB-03A**.

Локальный SHA-256 файла:

`54f5d276cbd2092fee4e0fcf8d768a73b5b5b81077c064645b3803966bc36a8b`

Отдельного восстановимого Git-checkpoint v0.11 на момент этой записи нет; не утверждать обратное.

## Первая попытка — безопасная ошибка Credential

Первая попытка на большой safe-базе дошла до embedding stage с 53 fragments и total input tokens 12568, но OpenAI-нода вернула `Credentials not found`.

Защитный путь подтвердил:
- `db_fragmenty_sohraneny=false`;
- `publish_vypolnen=false`;
- reference questions не сохранялись;
- fenced job успешно возвращён в `povtor`.

После привязки TEST OpenAI Credential новый JSON не потребовался.

## Успешный runtime

Повторный live-run прошёл на safe документе `qbit_podgotovka_k_pervichnomu_razboru`.

Job:
- `zadanie_id=013470c6-439e-4f1d-92d1-0276e91723b6`;
- fence `5`;
- version 1 осталась `chernovik`.

OpenAI embedding profile:
- provider: OpenAI;
- model: `text-embedding-3-large`;
- `dimensions=1024`;
- `encoding_format=float`;
- один batch request;
- 6 input fragments;
- API usage: 910 input/prompt tokens;
- vectors returned: 6;
- vector dimension min/max: 1024 / 1024;
- все значения finite;
- сопоставление по API `index` подтверждено;
- embedding input = exact `tekst_fragmenta` из KB-02B;
- generative LLM calls = 0;
- reference questions не embedding-ились.

## DB save

Нормативный `sohranit_fragmenty_znaniy` вернул:
- `rezultat=uspeshno`;
- `versiya_id=3bfa23cb-05e2-4c1d-8045-d3f49b6a2745`;
- `sohraneno_fragmentov=6`;
- `vsego_fragmentov=6`.

Это подтверждает, что DB приняла exact text/path/token/hash + `vector(1024)` и полный набор версии сохранён.

Важно: поле `kb03a_otchet.db_fragmenty_sohraneny=false` в контексте save-ноды является snapshot отчёта **до выполнения DB save**. Фактический результат после save определяется ответом DB и финальным `db_save_ok=true`; это не противоречие.

## Завершение job

После успешного DB save:
- `db_save_ok=true`;
- `next_stage=KB-03B`;
- publish не выполнялся;
- reference questions не сохранялись;
- job тем же worker/fence успешно возвращён в `povtor`.

## Итог

**KB-03A runtime verified.**

Доказано:
- batch OpenAI embedding без generative LLM;
- `text-embedding-3-large / 1024 / float`;
- exact fragment input;
- строгая проверка количества, порядка, размерности и finite values;
- нормативный DB save полного набора fragments/vectors;
- безопасный retry path при внешней/Credential ошибке;
- draft остаётся `chernovik`, publish отсутствует.

Следующая задача: **KB-03B** — сохранить отдельные YAML reference questions, получить их embeddings тем же профилем, выполнить draft-only search и сохранить проверки; только полный pass может перевести version в `gotova`.
