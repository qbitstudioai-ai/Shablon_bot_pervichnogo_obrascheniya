# Подключение n8n к self-hosted Supabase/PostgreSQL

Статус: проверено в test-контуре 30 сентября 2026 года на n8n 2.41.0.

## Базовое правило

n8n подключается к PostgreSQL не под `postgres`, не через общий `service_role` и не через Supabase API key. Для каждого workflow используется ограниченная PostgreSQL LOGIN-роль своей компании и среды, например:

- клиентский workflow → `<company>_<env>_bot`;
- служебный workflow → `<company>_<env>_sluzhebnyy`.

Schema не выбирается из текста клиента, LLM или входного HTTP-параметра. Роль заранее имеет `CONNECT` к базе, `USAGE` только на свою schema и `EXECUTE` только на разрешённые функции. Runtime-роли не получают административные права и прямой произвольный DML.

## Транспорт между n8n и PostgreSQL

Для текущей архитектуры, где n8n и Supabase находятся на разных серверах, проверенный путь такой:

`n8n Postgres Credential → SSH tunnel по Private Key → loopback-порт сервера Supabase → прямой PostgreSQL`.

PostgreSQL нельзя публиковать на `0.0.0.0` только ради n8n. В Docker Compose разрешён локальный bind вида:

```yaml
services:
  db:
    ports:
      - "127.0.0.1:<HOST_DB_PORT>:5432"
```

`<HOST_DB_PORT>` выбирается свободным локальным портом хоста. В первой test-установке использован отдельный локальный порт, а внешний доступ к нему отсутствует.

SSH-ключ относится к транспортному каналу между экземпляром n8n и сервером БД. Его не нужно создавать заново для каждой компании на тех же двух серверах. Изоляция компаний обеспечивается отдельными PostgreSQL-ролями и их паролями.

## Поля Postgres Credential в n8n

Для прямого PostgreSQL через SSH Tunnel:

| Поле | Значение |
|---|---|
| Host | `127.0.0.1` |
| Database | `postgres` |
| User | ограниченная роль, например `<company>_<env>_bot` |
| Password | пароль только этой PostgreSQL-роли |
| Maximum Number of Connections | стартово `5` |
| SSL | `Disable`, если весь DB-трафик идёт внутри SSH tunnel |
| Port | локальный `<HOST_DB_PORT>`, проброшенный на container `5432` |
| SSH Tunnel | включён |
| SSH Authenticate with | `Private Key` |
| SSH Host | адрес сервера Supabase |
| SSH Port | SSH-порт сервера |
| SSH User | системный SSH-пользователь сервера |
| Private Key | отдельный приватный ключ инфраструктурного канала n8n → DB server |
| Passphrase | пусто только если ключ создан без passphrase |

Приватный ключ, пароль PostgreSQL и другие секреты не сохраняются в workflow JSON, GitHub или документации.

## Supavisor и tenant suffix

Имя вида `role.<POOLER_TENANT_ID>` относится только к подключению через Supavisor. Для прямого PostgreSQL через loopback bind используется обычное имя роли без tenant suffix:

`<company>_<env>_bot`

В test-установке 30.09.2026 встроенная роль `postgres.<tenant>` через Supavisor работала, но custom runtime-роль не прошла password authentication, хотя прямой PostgreSQL принимал ту же роль. Поэтому Supavisor не используется как базовый runtime-путь n8n для этой установки. Это зафиксированный результат конкретной проверки, а не утверждение о невозможности custom roles в Supavisor вообще.

## Права schema

Добавление custom schema в Supabase `Exposed schemas` для этого подключения не требуется: n8n работает напрямую с PostgreSQL, а не через Data API/PostgREST.

Перед созданием Credential нужно проверить как минимум:

- роль существует и имеет `LOGIN`;
- роль имеет `CONNECT` к нужной базе;
- роль имеет `USAGE` только на свою schema;
- нужные SECURITY DEFINER / прикладные функции дают роли точечный `EXECUTE`;
- `PUBLIC`, `anon`, `authenticated` и `service_role` не получают доступ к schema по умолчанию;
- runtime direct DML запрещён там, где контракт требует работу только через функции.

## Проверка подключения

Порядок проверки:

1. Проверить роль напрямую через локальный TCP-порт PostgreSQL на сервере БД.
2. Убедиться, что Docker публикует порт только как `127.0.0.1:<HOST_DB_PORT>->5432/tcp`.
3. Проверить SSH Private Key отдельно.
4. Создать Postgres Credential в n8n и выполнить встроенный connection test.
5. Только после успешного connection test назначать Credential нужным test-нодам.
6. Клиентский и служебный workflow используют разные DB Credentials и разные PostgreSQL-роли.

Факт успешного подключения Credential не доказывает корректность workflow. Ingress, queue, outgoing и operator runtime проверяются отдельно по WF-02B3.

## Что не делать

- не использовать `postgres` в обычном workflow;
- не использовать общий Supabase `service_role` как замену PostgreSQL-изоляции компаний;
- не открывать PostgreSQL на `0.0.0.0` без отдельного архитектурного решения;
- не хранить private key, DB password, API key или реальные connection strings в GitHub;
- не переносить tenant suffix из Supavisor в прямое PostgreSQL-подключение;
- не добавлять schema в Data API только ради Postgres-ноды n8n.


## Автоматическая проверка workflow

После назначения двух seed Credentials runtime-export проверяется:

```bash
python3 tools/check_n8n_postgres_credentials.py "<runtime-export.json>"
```

Seed nodes:
- bot: `Сохранить вход и поставить в очередь`;
- service: `Служебный_Сохранить служебный вход`.

Скрипт не выводит Credential IDs или секреты. Он завершает проверку ошибкой, если service node получила bot Credential, bot node получила service Credential, legacy service block снова достижим от trigger/webhook или нарушены WF-02B3A execution gates.

Канонический шаблон проверяется отдельно:

```bash
python3 tools/check_n8n_postgres_credentials.py --template "workflows/Шаблон — служебный Telegram и перехват диалогов — версия 0.2.json"
```
