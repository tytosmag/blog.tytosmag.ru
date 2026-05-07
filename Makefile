.RECIPEPREFIX := >
SHELL := /usr/bin/env bash

POST_TITLE ?=
CATEGORIES ?= DevOps,Notes
TAGS ?= devops,notes

.PHONY: up down restart build rebuild clean drafts logs shell check post new help

help:
> @echo "Tytosmag Blog author workflow"
> @echo
> @echo "Основные команды:"
> @echo "  make up                         Запустить блог локально"
> @echo "  make down                       Остановить контейнеры"
> @echo "  make restart                    Перезапустить блог"
> @echo "  make rebuild                    Полная пересборка Docker/Jekyll"
> @echo "  make drafts                     Запуск с черновиками"
> @echo "  make check                      Проверить сборку блога"
> @echo "  make shell                      Зайти в контейнер"
> @echo
> @echo "Создание статьи:"
> @echo '  make post POST_TITLE="Docker Compose для Jekyll" CATEGORIES="Docker,DevOps" TAGS="docker,jekyll"'

up:
> docker compose up

down:
> docker compose down

restart:
> docker compose down
> docker compose up

build:
> docker compose build

rebuild:
> docker compose down -v
> docker compose build --no-cache
> docker compose up

clean:
> rm -rf _site .jekyll-cache .sass-cache

drafts:
> docker compose run --rm --service-ports jekyll bundle exec jekyll serve --host 0.0.0.0 --drafts --livereload --force_polling

logs:
> docker compose logs -f

shell:
> docker compose run --rm jekyll bash

check:
> ./scripts/check-blog.sh

post:
> ./scripts/new-post.sh "$(POST_TITLE)" "$(CATEGORIES)" "$(TAGS)"

new: post
