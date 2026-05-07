---
title: "Собираем Samba NAS в Proxmox LXC. Часть 2: Рабочая шара для файлов"
date: 2026-05-10 10:20:00 +0300
categories: [Proxmox, Samba]
tags: [samba, smb, bash, linux, proxmox, lxc, nas]
description: "Настраиваем рабочую Samba-шару Share в Proxmox LXC: SMB3 only, пользователь, права доступа, smb.conf и bash-скрипт установки."
pin: false
toc: true
comments: false
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-02-share.png
  alt: "Собираем Samba NAS в Proxmox LXC: рабочая шара Share"
---

## Задача

В первой части мы спроектировали архитектуру Samba/NAS под Proxmox.

Теперь создадим первую рабочую шару:

```text
\\nas\share
```

Это будет основная writable-шара для авторизованного пользователя.

Требования:

- установить Samba;
- включить SMB3-only;
- отключить устаревшую аутентификацию;
- создать Unix-пользователя;
- добавить пользователя в Samba;
- создать каталог `/srv/samba/share`;
- настроить права;
- создать `/etc/samba/smb.conf`;
- проверить конфиг;
- перезапустить сервис;
- проверить подключение.

> В этой статье мы делаем базовый фундамент. `[secure]`, audit и `[public]` добавим в следующих частях.
{: .prompt-info }

---

## Исходные данные

Сервер:

```text
Proxmox LXC
└── Debian / Ubuntu / TurnKey Linux
```

Шара:

```text
/srv/samba/share
```

Пользователь:

```text
samba
```

Скрипт:

```text
setup-samba-share.sh
```

---

## Почему не хранить пароль прямо в скрипте

В быстрых черновиках часто встречается так:

```bash
SAMBA_PASS="password"
```

Для статьи и реальной практики лучше так не делать.

Правильнее:

- запросить пароль интерактивно;
- не писать его в историю команд;
- не хранить его в Git;
- не коммитить секреты в репозиторий.

Поэтому скрипт ниже спросит пароль сам.

---

## Скрипт `setup-samba-share.sh`

Создай файл:

```bash
nano setup-samba-share.sh
```

Вставь:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMB на bash. Часть 2. Share
# Базовая настройка Samba SMB3-only и рабочей шары [share]
# ============================================================

SAMBA_USER="${SAMBA_USER:-samba}"
SHARE_NAME="${SHARE_NAME:-share}"
SHARE_DIR="${SHARE_DIR:-/srv/samba/share}"
SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запусти скрипт от root"
    exit 1
  fi
}

ask_password() {
  if [[ -n "${SAMBA_PASS:-}" ]]; then
    return
  fi

  read -rsp "Введите пароль для пользователя Samba '${SAMBA_USER}': " SAMBA_PASS
  echo
  read -rsp "Повторите пароль: " SAMBA_PASS_CONFIRM
  echo

  if [[ "${SAMBA_PASS}" != "${SAMBA_PASS_CONFIRM}" ]]; then
    echo "Ошибка: пароли не совпадают"
    exit 1
  fi

  if [[ -z "${SAMBA_PASS}" ]]; then
    echo "Ошибка: пароль не может быть пустым"
    exit 1
  fi
}

install_packages() {
  echo "==> Устанавливаем Samba и ACL"
  apt update
  apt install -y samba smbclient acl
}

create_user() {
  if ! id "${SAMBA_USER}" &>/dev/null; then
    echo "==> Создаём Unix-пользователя ${SAMBA_USER}"
    useradd -m -s /usr/sbin/nologin "${SAMBA_USER}"
  else
    echo "==> Unix-пользователь ${SAMBA_USER} уже существует"
  fi

  echo "==> Обновляем пароль Unix-пользователя"
  echo "${SAMBA_USER}:${SAMBA_PASS}" | chpasswd
}

prepare_share_dir() {
  echo "==> Создаём каталог ${SHARE_DIR}"
  mkdir -p "${SHARE_DIR}"

  echo "==> Настраиваем владельца и права"
  chown "${SAMBA_USER}:${SAMBA_USER}" "${SHARE_DIR}"
  chmod 0770 "${SHARE_DIR}"

  # Сбрасываем лишние ACL, если они были.
  setfacl -b "${SHARE_DIR}" 2>/dev/null || true
}

create_samba_user() {
  echo "==> Добавляем пользователя в базу Samba"
  printf "%s\n%s\n" "${SAMBA_PASS}" "${SAMBA_PASS}" | smbpasswd -a "${SAMBA_USER}"
  smbpasswd -e "${SAMBA_USER}"
}

backup_config() {
  if [[ -f "${SMB_CONF}" ]]; then
    local backup="${SMB_CONF}.bak.$(date +%F_%H-%M-%S)"
    echo "==> Делаем backup ${backup}"
    cp "${SMB_CONF}" "${backup}"
  fi
}

write_config() {
  echo "==> Пишем новый ${SMB_CONF}"

  cat > "${SMB_CONF}" <<EOF
[global]
   server string = Tytosmag Samba NAS
   workgroup = WORKGROUP
   security = user
   server role = standalone server
   map to guest = Bad User

   # SMB3 only
   server min protocol = SMB3
   server max protocol = SMB3

   # Authentication hardening
   ntlm auth = ntlmv2-only
   lanman auth = no
   client lanman auth = no

   # Signing
   server signing = auto
   client signing = auto

   # Charset and logs
   unix charset = UTF-8
   log file = /var/log/samba/log.%m
   max log size = 1000

[${SHARE_NAME}]
   path = ${SHARE_DIR}
   valid users = ${SAMBA_USER}
   read only = no
   writable = yes
   browseable = yes

   force user = ${SAMBA_USER}
   force group = ${SAMBA_USER}

   create mask = 0660
   directory mask = 0770
EOF
}

validate_config() {
  echo "==> Проверяем Samba config через testparm"
  testparm -s "${SMB_CONF}" >/dev/null
}

restart_samba() {
  echo "==> Перезапускаем Samba"
  systemctl restart smbd

  if systemctl list-unit-files | grep -q '^nmbd'; then
    systemctl restart nmbd || true
  fi
}

print_summary() {
  local host
  host="$(hostname -f 2>/dev/null || hostname)"

  echo
  echo "Готово."
  echo "Шара: //${host}/${SHARE_NAME}"
  echo "Каталог: ${SHARE_DIR}"
  echo "Пользователь: ${SAMBA_USER}"
  echo
  echo "Проверка на сервере:"
  echo "  testparm -s"
  echo "  systemctl status smbd --no-pager"
  echo "  smbstatus"
  echo
  echo "Проверка с клиента Linux:"
  echo "  smbclient //SERVER_IP/${SHARE_NAME} -U ${SAMBA_USER} -m SMB3"
}

main() {
  require_root
  ask_password
  install_packages
  create_user
  prepare_share_dir
  create_samba_user
  backup_config
  write_config
  validate_config
  restart_samba
  print_summary
}

main "$@"
```

---

## Запуск

```bash
chmod +x setup-samba-share.sh
sudo ./setup-samba-share.sh
```

Если хочешь запускать без интерактивного ввода, можно передать переменные окружения:

```bash
sudo SAMBA_USER="samba" SAMBA_PASS="StrongPasswordHere" ./setup-samba-share.sh
```

> Не используй пароль из примера в реальной сети. Лучше сгенерировать уникальный пароль и сохранить его в менеджере паролей.
{: .prompt-warning }

---

## Проверка конфигурации

На сервере:

```bash
testparm -s
```

Проверяем сервис:

```bash
systemctl status smbd --no-pager
```

Проверяем открытый порт:

```bash
ss -ltnp | grep ':445'
```

Проверяем статус Samba:

```bash
smbstatus
```

---

## Проверка подключения с Linux

```bash
smbclient -L //SERVER_IP -U samba -m SMB3
```

Подключение к шаре:

```bash
smbclient //SERVER_IP/share -U samba -m SMB3
```

Внутри `smbclient`:

```text
smb: \> ls
smb: \> put test.txt
smb: \> ls
smb: \> quit
```

---

## Проверка подключения с Windows

В проводнике:

```text
\\SERVER_IP\share
```

Или через CMD:

```cmd
net use S: \\SERVER_IP\share /user:samba
```

Отключить:

```cmd
net use S: /delete
```

---

## Что получилось

После запуска у нас есть:

```text
/srv/samba/share
```

и рабочая SMB-шара:

```text
\\nas\share
```

Свойства:

- доступ только по логину и паролю;
- writable;
- SMB3-only;
- NTLMv2-only;
- корректные права `0770`;
- создаваемые файлы получают маску `0660`;
- директории получают маску `0770`.

---

## Возможные ошибки

### `NT_STATUS_LOGON_FAILURE`

Причина:

- неверный пароль;
- пользователь не добавлен в Samba;
- пользователь отключён.

Проверка:

```bash
sudo pdbedit -L
sudo smbpasswd -e samba
```

Сброс пароля:

```bash
sudo smbpasswd samba
```

### `tree connect failed: NT_STATUS_BAD_NETWORK_NAME`

Причина:

- неверное имя шары;
- блок `[share]` не попал в `smb.conf`;
- Samba не перезапущена.

Проверка:

```bash
testparm -s | grep -A20 '\[share\]'
```

### Порт 445 не слушается

Проверка:

```bash
systemctl status smbd --no-pager
journalctl -u smbd -n 100 --no-pager
ss -ltnp | grep ':445'
```

---

## Итог

Мы получили базовую рабочую Samba-шару `[share]`.

Это фундамент всей серии. В следующей части добавим отдельную защищённую шару `[secure]`, где включим SMB encryption и подготовим её под аудит.
