---
title: "Собираем Samba NAS в Proxmox LXC. Часть 1: Архитектура и безопасность"
date: 2026-05-10 10:00:00 +0300
categories: [Proxmox, Samba]
tags: [proxmox, lxc, samba, nas, smb3, linux, architecture]
description: "Проектируем Samba NAS в Proxmox LXC: архитектура, классы доступа, SMB3, безопасность шар и роль ZFS на Proxmox host."
pin: false
toc: true
comments: false
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-01-architecture-security.png
  alt: "Собираем Samba NAS в Proxmox LXC: архитектура и безопасность"
---

## Задача

В этой серии я хочу собрать **практический Samba/NAS на bash**: без панели управления, без магии и без ручного редактирования десятков файлов.

Цель — получить файловый сервер под Proxmox, который можно развивать по шагам:

1. спроектировать архитектуру;
2. создать рабочую шару `[share]`;
3. добавить защищённую шару `[secure]`;
4. включить аудит действий пользователей;
5. добавить публичную read-only шару `[public]`;
6. настроить immutable backup на уровне Proxmox/ZFS.

Это не “идеальный enterprise NAS”, а понятная и воспроизводимая DevOps-схема: **скрипты, конфиги, проверки, логи и rollback**.

> Главная идея серии: Samba должна быть не набором случайных шар, а управляемой системой с понятными классами данных и разными уровнями доступа.
{: .prompt-info }

---

## Исходные данные

Ориентируюсь на такую схему:

```text
Proxmox host
└── LXC container: samba-nas
    ├── Debian / Ubuntu / TurnKey Linux
    ├── Samba
    ├── /srv/samba/share
    ├── /srv/samba/secure
    ├── /srv/samba/public
    └── /srv/samba/backup
```

Роль Proxmox:

- хранит контейнер;
- управляет ZFS dataset;
- делает snapshots;
- защищает backups на уровне хоста.

Роль LXC-контейнера:

- отдаёт SMB-шары;
- управляет пользователями Samba;
- пишет audit-логи;
- предоставляет доступ клиентам Windows/macOS/Linux/iOS.

---

## Почему не одна общая шара

Самая частая ошибка домашнего NAS или маленького офисного файлового сервера — сделать одну шару:

```text
\\nas\files
```

и складывать туда всё:

- публичные файлы;
- рабочие документы;
- личные документы;
- резервные копии;
- временный мусор;
- конфиденциальные файлы.

Проблема в том, что у этих данных разный уровень безопасности. Если всё лежит в одной шаре, сложно настроить права, аудит, шифрование и backup-стратегию.

Поэтому я делю данные на классы.

---

## Классы безопасности

Базовая архитектура:

| Шара | Назначение | Доступ | Особенности |
|---|---|---|---|
| `[public]` | общие файлы | guest read-only | без пароля, только чтение |
| `[share]` | рабочие файлы | авторизованный пользователь | основная рабочая шара |
| `[secure]` | чувствительные данные | авторизованный пользователь | SMB encryption + audit |
| `[backup]` | резервные копии | read-only | не место для ежедневной работы |

В файловой системе:

```text
/srv/samba
├── public
├── share
├── secure
└── backup
```

Логика простая:

```text
public  → можно читать всем
share   → можно работать авторизованным пользователям
secure  → защищённые файлы, аудит и шифрование
backup  → только чтение, резервные копии
```

---

## Базовые принципы безопасности

### 1. SMB3-only

В глобальной секции Samba задаём современный минимум:

```ini
[global]
   server min protocol = SMB3
   server max protocol = SMB3
```

Это отключает старые варианты протокола и оставляет только SMB3.

> Если в сети есть старые клиенты, они могут не подключиться. Это нормальная плата за безопасную baseline-конфигурацию.
{: .prompt-warning }

### 2. NTLMv2-only

```ini
[global]
   ntlm auth = ntlmv2-only
   lanman auth = no
   client lanman auth = no
```

Цель — не разрешать старую и слабую аутентификацию.

### 3. Минимальные права на каталогах

Для рабочей шары:

```bash
mkdir -p /srv/samba/share
chown samba:samba /srv/samba/share
chmod 770 /srv/samba/share
```

Для публичной read-only шары:

```bash
mkdir -p /srv/samba/public
chown nobody:nogroup /srv/samba/public
chmod 755 /srv/samba/public
```

Для защищённой шары:

```bash
mkdir -p /srv/samba/secure
chown samba:samba /srv/samba/secure
chmod 770 /srv/samba/secure
```

---

## Почему bash

Для такой задачи bash удобен по нескольким причинам:

- скрипт можно запустить прямо в LXC;
- легко читать и проверять;
- не нужен Python/Ansible/Terraform для первого этапа;
- удобно показывать в статье;
- подходит для пошагового DevOps-подхода.

Но есть правило: **скрипт должен быть безопаснее ручных команд**, а не наоборот.

Поэтому в скриптах этой серии будут:

- `set -Eeuo pipefail`;
- проверка root;
- backup `/etc/samba/smb.conf`;
- проверка существующих шар;
- `testparm` перед перезапуском;
- понятный вывод;
- команды проверки после запуска.

---

## Общая структура будущих скриптов

Каждый скрипт будет устроен примерно так:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запусти скрипт от root"
    exit 1
  fi
}

backup_smb_conf() {
  cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%F_%H-%M-%S)"
}

validate_samba_config() {
  testparm -s /etc/samba/smb.conf >/dev/null
}

restart_samba() {
  systemctl restart smbd
}
```

Такой подход делает скрипты более предсказуемыми.

---

## Архитектура серии

### Часть 1. Архитектура

Что проектируем:

- классы данных;
- базовую безопасность;
- разделение public/share/secure/backup;
- роль Proxmox и LXC;
- логику будущих скриптов.

### Часть 2. Share

Создаём основную рабочую шару:

```text
\\nas\share
```

Она будет:

- SMB3-only;
- доступна только авторизованному пользователю;
- writable;
- с корректными правами файловой системы;
- с проверками после установки.

### Часть 3. Secure

Добавляем защищённую шару:

```text
\\nas\secure
```

Она будет:

- отдельной от обычной рабочей шары;
- с правами `770`;
- с SMB encryption;
- готовой для аудита.

### Часть 4. Logging

Включаем аудит для `[secure]`.

Будем логировать важные операции:

- создание;
- запись;
- удаление;
- переименование;
- изменение прав;
- открытие файлов, если нужно.

### Часть 5. Public

Добавляем публичную read-only шару:

```text
\\nas\public
```

Она будет:

- доступна без пароля;
- только для чтения;
- удобна для ISO, драйверов, общих файлов и инструкций;
- отделена от рабочих данных.

### Часть 6. Immutable Backups

Выносим защиту backup на уровень Proxmox/ZFS.

Ключевая мысль:

```text
Immutable backup в LXC — слабая защита.
Immutable backup на Proxmox host/ZFS — правильный уровень.
```

---

## Базовый `/etc/samba/smb.conf`

Финальный конфиг будет собираться постепенно, но базовая идея такая:

```ini
[global]
   server string = Tytosmag Samba NAS
   workgroup = WORKGROUP
   security = user
   server role = standalone server
   map to guest = Bad User

   server min protocol = SMB3
   server max protocol = SMB3

   ntlm auth = ntlmv2-only
   lanman auth = no
   client lanman auth = no

   server signing = auto
   client signing = auto

   unix charset = UTF-8
   log file = /var/log/samba/log.%m
   max log size = 1000
```

Почему `map to guest = Bad User`?

Потому что в пятой части мы сделаем публичную шару `[public]` с guest-доступом, но не хотим превращать весь сервер в “анонимную помойку”. Гость будет использоваться только там, где мы явно разрешим.

---

## Проверки после каждого шага

После любого изменения Samba-конфига нужно проверять:

```bash
testparm -s
systemctl status smbd --no-pager
smbstatus
journalctl -u smbd -n 100 --no-pager
```

Проверка доступных шар с Linux-клиента:

```bash
smbclient -L //SERVER_IP -U samba -m SMB3
```

Подключение к рабочей шаре:

```bash
smbclient //SERVER_IP/share -U samba -m SMB3
```

---

## Что важно помнить про Proxmox

Если Samba работает внутри LXC, то контейнер не должен быть единственным уровнем защиты.

Контейнер может:

- отдавать файлы по SMB;
- управлять пользователями;
- писать логи;
- ограничивать права.

Но backup-стратегию лучше держать выше:

```text
Proxmox host
└── ZFS snapshots
    └── holds
        └── immutable backup
```

Так ransomware или ошибка внутри контейнера не сможет напрямую удалить ZFS snapshots на хосте.

---

## Итог

В этой части мы не ставили Samba и не писали финальный скрипт. Мы спроектировали архитектуру.

Получилась модель:

```text
public  → guest read-only
share   → рабочая writable шара
secure  → защищённая шара с encryption и audit
backup  → read-only backup-доступ
```

В следующих частях начнём реализовывать эту схему на bash: сначала создадим основную рабочую шару `[share]`.
