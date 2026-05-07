# Tytosmag Blog

Личный блог на Jekyll + Chirpy + Docker + Docker Compose

## Структура
```text
_posts/       опубликованные статьи
_drafts/      черновики
_tabs/        страницы меню
_templates/   шаблоны статей
assets/       изображения, CSS, favicon
_config.yml   основной конфиг Jekyll/Chirpy
```

## Правила именования статей
```text
_posts/YYYY-MM-DD-topic-name.md
```
Примеры:
```text
_posts/2026-05-09-docker-compose-for-jekyll.md
_posts/2026-05-10-github-actions-pages-deploy.md
_posts/2026-05-11-linux-systemd-logs.md
```

## Внутри статьи:
```text
categories: [Docker, DevOps]
tags: [docker, docker-compose, jekyll, local-development]
```

Правило:
```text
Категории — крупные разделы.
Теги — конкретные технологии.
```

## Локальный запуск через Compose/Make

```bash
docker compose up --build
make up
```

## Локальный down через Compose/Make
```bash
docker compose down
make down
```

# Авторский workflow

В проект добавлен набор файлов для удобного ведения блога:

```text
scripts/new-post.sh       генератор новых статей
scripts/check-blog.sh     проверка сборки
_templates/post.md        шаблон статьи
```

---

### Генератор новых статей

Файл:

```text
scripts/new-post.sh
```

Скрипт создаёт новый пост в директории `_posts/`.

Формат имени файла:

```text
_posts/YYYY-MM-DD-slug.md
```

Например команда:

```bash
./scripts/new-post.sh "Docker Compose для Jekyll-блога" "Docker,DevOps" "docker,docker-compose,jekyll,chirpy"
```

создаст файл примерно такого вида:

```text
_posts/2026-05-09-docker-compose-dlya-jekyll-bloga.md
```

Внутри файла будет готовый шаблон статьи:

- заголовок;
- дата;
- категории;
- теги;
- описание;
- структура статьи;
- блоки для команд;
- раздел проверки;
- раздел возможных ошибок;
- итог.

---

### Создание статьи через Makefile

Рекомендуемый способ — использовать `make post`:

```bash
make post POST_TITLE="Docker Compose для Jekyll-блога" CATEGORIES="Docker,DevOps" TAGS="docker,docker-compose,jekyll,chirpy"
```

Параметры:

| Параметр | Описание |
|---|---|
| `POST_TITLE` | Заголовок статьи |
| `CATEGORIES` | Категории через запятую |
| `TAGS` | Теги через запятую |

Пример для Linux-статьи:

```bash
make post POST_TITLE="Как найти, что заняло порт в Linux" CATEGORIES="Linux,Notes" TAGS="linux,network,ss,lsof,troubleshooting"
```

Пример для Docker-статьи:

```bash
make post POST_TITLE="Docker Compose для Node.js и PostgreSQL" CATEGORIES="Docker,DevOps" TAGS="docker,docker-compose,nodejs,postgresql"
```

Пример для статьи про блог:

```bash
make post POST_TITLE="Как я запустил блог на Jekyll, Chirpy и Docker" CATEGORIES="Blog,DevOps" TAGS="jekyll,chirpy,docker,docker-compose,blog"
```

---

### Проверка сборки блога

Файл:

```text
scripts/check-blog.sh
```

Скрипт проверяет, что блог корректно собирается.

Он выполняет:

1. очистку старой сборки;
2. проверку обязательных файлов;
3. сборку Jekyll-сайта;
4. проверку сгенерированных файлов:
   - `_site/index.html`;
   - `_site/sitemap.xml`;
   - `_site/feed.xml`;
   - `_site/robots.txt`, если в проекте есть `robots.txt`.

Запуск напрямую:

```bash
./scripts/check-blog.sh
```

Рекомендуемый запуск через Makefile:

```bash
make check
```

Если всё хорошо, в конце будет сообщение:

```text
Build check completed successfully
```

---

### Шаблон статьи

Файл:

```text
_templates/post.md
```

Это базовый шаблон технической статьи.

Он нужен, чтобы все статьи в блоге имели единую структуру:

```text
Задача
Исходные данные
Решение
Проверка
Возможные ошибки
Итог
```

Шаблон можно использовать вручную:

```bash
cp _templates/post.md _posts/2026-05-09-example-post.md
```

Но удобнее использовать генератор:

```bash
make post POST_TITLE="Название статьи" CATEGORIES="DevOps,Linux" TAGS="devops,linux"
```

---

### Рекомендуемый процесс написания статьи

1. Создать новую ветку:

```bash
git switch -c feature/article-name
```

2. Создать пост:

```bash
make post POST_TITLE="Название статьи" CATEGORIES="Docker,DevOps" TAGS="docker,devops"
```

3. Открыть созданный файл в `_posts/`.

4. Заполнить разделы статьи.

5. Запустить блог локально:

```bash
make up
```

6. Проверить статью в браузере:

```text
http://localhost:4000
```

7. Проверить сборку:

```bash
make check
```

8. Закоммитить изменения:

```bash
git add .
git commit -m "Add article about topic"
```

---

### Быстрые команды

| Команда | Назначение |
|---|---|
| `make up` | Запустить блог локально |
| `make down` | Остановить контейнеры |
| `make restart` | Перезапустить блог |
| `make rebuild` | Полная пересборка |
| `make drafts` | Запуск с черновиками |
| `make check` | Проверить сборку |
| `make shell` | Зайти в контейнер |
| `make post ...` | Создать новую статью |