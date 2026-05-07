#!/usr/bin/env bash
set -euo pipefail

TITLE="${1:-}"
CATEGORIES="${2:-DevOps,Notes}"
TAGS="${3:-devops,notes}"

if [ -z "$TITLE" ]; then
  echo "Ошибка: не указан заголовок статьи."
  echo
  echo "Пример:"
  echo '  make post POST_TITLE="Docker Compose для Jekyll" CATEGORIES="Docker,DevOps" TAGS="docker,jekyll"'
  echo
  echo "Или напрямую:"
  echo '  ./scripts/new-post.sh "Docker Compose для Jekyll" "Docker,DevOps" "docker,jekyll"'
  exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POSTS_DIR="$ROOT_DIR/_posts"

mkdir -p "$POSTS_DIR"

DATE_YMD="$(date +%F)"
DATE_FULL="$(date '+%Y-%m-%d %H:%M:%S %z')"

slug="$(python3 - "$TITLE" <<'PY'
import re
import sys
import unicodedata

title = sys.argv[1].strip().lower()

mapping = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d",
    "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i",
    "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
    "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
    "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch",
    "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "",
    "э": "e", "ю": "yu", "я": "ya",
}

for src, dst in mapping.items():
    title = title.replace(src, dst)

title = unicodedata.normalize("NFKD", title)
title = title.encode("ascii", "ignore").decode("ascii")
title = re.sub(r"[^a-z0-9]+", "-", title)
title = title.strip("-")

print(title or "new-post")
PY
)"

file="$POSTS_DIR/${DATE_YMD}-${slug}.md"

if [ -f "$file" ]; then
  i=2
  while [ -f "$POSTS_DIR/${DATE_YMD}-${slug}-${i}.md" ]; do
    i=$((i + 1))
  done
  file="$POSTS_DIR/${DATE_YMD}-${slug}-${i}.md"
fi

normalize_list() {
  local input="$1"
  local output=""
  local item=""

  IFS=',' read -ra parts <<< "$input"

  for item in "${parts[@]}"; do
    item="$(echo "$item" | xargs)"
    if [ -n "$item" ]; then
      if [ -z "$output" ]; then
        output="$item"
      else
        output="$output, $item"
      fi
    fi
  done

  echo "$output"
}

CATEGORIES_NORMALIZED="$(normalize_list "$CATEGORIES")"
TAGS_NORMALIZED="$(normalize_list "$TAGS")"

cat > "$file" <<POST
---
title: "$TITLE"
date: $DATE_FULL
categories: [$CATEGORIES_NORMALIZED]
tags: [$TAGS_NORMALIZED]
description: ""
pin: false
toc: true
comments: false
---

## Задача

Что нужно сделать и зачем.

## Исходные данные

Опиши окружение:

- ОС:
- версии:
- структура проекта:
- важные вводные:

## Решение

Пошаговое решение.

\`\`\`bash
# пример команды
\`\`\`

## Проверка

Как проверить, что всё работает.

\`\`\`bash
# команды проверки
\`\`\`

## Возможные ошибки

### Ошибка 1

Симптом:

\`\`\`text
текст ошибки
\`\`\`

Решение:

\`\`\`bash
команда исправления
\`\`\`

## Итог

Что получили в результате.
POST

echo "Создан новый пост:"
echo "$file"
