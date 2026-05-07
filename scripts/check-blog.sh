#!/usr/bin/env bash
set -euo pipefail

echo "==> Cleaning old Jekyll build"
rm -rf _site .jekyll-cache .sass-cache

echo "==> Validating required files"

required_files=(
  "_config.yml"
  "Gemfile"
  "docker-compose.yml"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Ошибка: не найден файл $file"
    exit 1
  fi
done

echo "==> Checking robots.txt configuration"

if [ -f "robots.txt" ] && [ -f "assets/robots.txt" ]; then
  echo "Ошибка: найден конфликт robots.txt"
  echo
  echo "Нельзя держать одновременно:"
  echo "  ./robots.txt"
  echo "  ./assets/robots.txt"
  echo
  echo "Для Chirpy оставь только:"
  echo "  ./assets/robots.txt"
  exit 1
fi

if [ -f "robots.txt" ]; then
  echo "Предупреждение: найден ./robots.txt"
  echo "Для Chirpy лучше использовать ./assets/robots.txt"
fi

echo "==> Building Jekyll site"
docker compose run --rm jekyll bundle exec jekyll build

echo "==> Checking generated files"

generated_files=(
  "_site/index.html"
  "_site/sitemap.xml"
  "_site/feed.xml"
  "_site/robots.txt"
)

for file in "${generated_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Ошибка: после сборки не найден файл $file"
    exit 1
  fi
done

echo "==> Checking ownership of _site"

site_owner="$(stat -c '%U' _site)"

if [ "$site_owner" = "root" ]; then
  echo "Ошибка: _site создан от root."
  echo "Выполни: sudo chown -R \"\$USER:\$USER\" ."
  exit 1
fi

echo "==> Build check completed successfully"
