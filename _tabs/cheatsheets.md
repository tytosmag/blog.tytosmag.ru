---
title: Шпаргалки
icon: fas fa-terminal
order: 7
permalink: /cheatsheets/
---

Короткие команды и заметки, которые удобно держать под рукой.

Эта страница — быстрый справочник по Linux, Docker, Docker Compose, Git, Jekyll, systemd, сети и диагностике.


# Linux: базовая диагностика

### Информация о системе

```bash
uname -a
hostnamectl
cat /etc/os-release
uptime
whoami
id
```

### Диски и место

```bash
df -h
lsblk
blkid
du -sh *
du -sh /var/log/*
```

### Память и процессы

```bash
free -h
top
htop
ps aux
ps aux | grep nginx
```

### Порты и сеть

```bash
ss -ltnp
ss -tulpn
ip a
ip route
ping 8.8.8.8
curl -I https://example.com
```

# systemd

### Статус сервиса

```bash
systemctl status nginx
systemctl status docker
systemctl status ssh
```

### Запуск, остановка, перезапуск

```bash
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
sudo systemctl reload nginx
```

### Автозапуск

```bash
sudo systemctl enable nginx
sudo systemctl disable nginx
```

### Логи сервиса

```bash
journalctl -u nginx
journalctl -u nginx -f
journalctl -u nginx --since "1 hour ago"
journalctl -xe
```

# Docker

### Контейнеры

```bash
docker ps
docker ps -a
docker logs -f container_name
docker exec -it container_name bash
docker stop container_name
docker rm container_name
```

### Образы

```bash
docker images
docker pull nginx:latest
docker rmi image_name
docker image prune
```

### Очистка

```bash
docker system df
docker system prune
docker system prune -a
docker volume prune
docker network prune
```

> Осторожно: `docker system prune -a` удаляет все неиспользуемые образы.
{: .prompt-warning }


# Docker Compose

### Запуск

```bash
docker compose up
docker compose up -d
docker compose up --build
```

### Остановка

```bash
docker compose down
docker compose down -v
```

### Логи

```bash
docker compose logs
docker compose logs -f
docker compose logs -f app
```

### Пересборка

```bash
docker compose build
docker compose build --no-cache
docker compose up --build
```

### Выполнить команду внутри сервиса

```bash
docker compose exec app bash
docker compose run --rm app bash
```

# Git

### Состояние проекта

```bash
git status
git branch
git log --oneline --graph --decorate --all
```

### Ветки

```bash
git switch -c feature/name
git switch main
git pull
```

### Коммит

```bash
git add .
git commit -m "Message"
```

### Push новой ветки

```bash
git push -u origin feature/name
```

### Откат изменений в файле

```bash
git checkout -- filename
```

### Посмотреть изменения

```bash
git diff
git diff --staged
```

# Jekyll / Chirpy

### Локальный запуск через Docker Compose

```bash
docker compose up
```

### Полная пересборка

```bash
docker compose down -v
docker compose build --no-cache
docker compose up
```

### Очистка Jekyll-кэша

```bash
rm -rf _site .jekyll-cache .sass-cache
```

### Запуск с черновиками

```bash
docker compose run --rm --service-ports jekyll bundle exec jekyll serve \
  --host 0.0.0.0 \
  --drafts \
  --livereload \
  --force_polling
```

### Создать новый пост

```bash
cp _templates/post.md _posts/2026-05-09-new-post.md
```

Формат имени поста:

```text
_posts/YYYY-MM-DD-title.md
```

# Markdown для статей

### Заголовки

```markdown
# H1
## H2
### H3
```

### Список

```markdown
- пункт 1
- пункт 2
- пункт 3
```

### Нумерованный список

```markdown
1. первый шаг
2. второй шаг
3. третий шаг
```

### Блок кода

````markdown
```bash
docker compose up
```
````

### Подсказки Chirpy

```markdown
> Информационный блок.
{: .prompt-info }

> Полезный совет.
{: .prompt-tip }

> Предупреждение.
{: .prompt-warning }

> Опасное действие.
{: .prompt-danger }
```

## SSH

### Подключение

```bash
ssh user@server_ip
```

### Подключение с ключом

```bash
ssh -i ~/.ssh/id_ed25519 user@server_ip
```

### Генерация ключа

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

### Копирование ключа на сервер

```bash
ssh-copy-id user@server_ip
```

### Проверка конфига SSH

```bash
ssh -v user@server_ip
```

## Nginx

### Проверка конфига

```bash
sudo nginx -t
```

### Перезапуск

```bash
sudo systemctl reload nginx
sudo systemctl restart nginx
```

### Логи

```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Проверка ответа сайта

```bash
curl -I https://example.com
```

# DNS

### Проверить A-запись

```bash
dig example.com A +short
```

### Проверить CNAME

```bash
dig www.example.com CNAME +short
```

### Проверить NS

```bash
dig example.com NS +short
```

### Проверить через конкретный DNS-сервер

```bash
dig @1.1.1.1 example.com A +short
dig @8.8.8.8 example.com A +short
```

# curl

### Только заголовки

```bash
curl -I https://example.com
```

### Подробный вывод

```bash
curl -v https://example.com
```

### Проверить редиректы

```bash
curl -IL https://example.com
```

### Скачать файл

```bash
curl -LO https://example.com/file.tar.gz
```

# Права доступа

### Посмотреть права

```bash
ls -la
stat filename
```

### Изменить владельца

```bash
sudo chown user:user filename
sudo chown -R user:user directory/
```

### Изменить права

```bash
chmod 644 file
chmod 755 script.sh
chmod -R 755 directory/
```

### Сделать скрипт исполняемым

```bash
chmod +x script.sh
```

# Архивы

### tar.gz

```bash
tar -czf archive.tar.gz directory/
tar -xzf archive.tar.gz
```

### zip

```bash
zip -r archive.zip directory/
unzip archive.zip
```

# Быстрая диагностика сервера

```bash
hostnamectl
uptime
df -h
free -h
ss -ltnp
systemctl --failed
journalctl -xe
```

# Быстрая диагностика Docker-проекта

```bash
docker compose ps
docker compose logs -f
docker compose config
docker system df
```

# Быстрая диагностика Jekyll-блога

```bash
docker compose ps
docker compose logs -f
rm -rf _site .jekyll-cache .sass-cache
docker compose build --no-cache
docker compose up
```
