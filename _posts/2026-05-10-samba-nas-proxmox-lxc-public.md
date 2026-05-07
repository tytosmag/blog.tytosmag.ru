---
title: "Собираем Samba NAS в Proxmox LXC. Часть 5: Публичная read-only шара"
date: 2026-05-10 11:20:00 +0300
categories: [Proxmox, Samba]
tags: [samba, public-share, smb3, guest, read-only, bash, linux]
description: "Создаём публичную read-only Samba-шару Public в Proxmox LXC: гостевой доступ, SMB3, безопасные права и bash-скрипт."
pin: false
toc: true
comments: false
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-05-public-readonly.png
  alt: "Собираем Samba NAS в Proxmox LXC: публичная read-only шара"
---

## Задача

В предыдущих частях мы сделали:

- `[share]` — основную рабочую шару;
- `[secure]` — защищённую шару;
- audit для `[secure]`.

Теперь добавим публичную read-only шару:

```text
\\nas\public
```

Она нужна для файлов, которые можно читать всем:

- инструкции;
- ISO-образы;
- драйверы;
- публичные документы;
- общие материалы;
- файлы для быстрой передачи внутри LAN.

Требования:

- доступ без пароля;
- только чтение;
- отдельный каталог `/srv/samba/public`;
- безопасные права;
- не перезатирать текущий `smb.conf`;
- проверить конфиг перед перезапуском.

> `[public]` — это не место для рабочих документов. Всё, что требует контроля доступа, должно лежать в `[share]` или `[secure]`.
{: .prompt-warning }

---

## Архитектура

После этой части структура будет такой:

```text
/srv/samba
├── public   # guest read-only
├── share    # user writable
└── secure   # user writable + encryption + audit
```

---

## Важный момент про guest-доступ

Для guest-шары в Samba обычно нужен глобальный параметр:

```ini
map to guest = Bad User
```

Он говорит Samba: если пришёл неизвестный пользователь, можно сопоставить его с guest-учёткой.

Но сам guest-доступ должен быть разрешён только в конкретной шаре:

```ini
[public]
   guest ok = yes
   read only = yes
```

Так мы не делаем весь сервер анонимным, а разрешаем guest только в `[public]`.

---

## Скрипт `add-public-smb-share.sh`

Скрипт:

- создаёт каталог `/srv/samba/public`;
- выставляет `755`;
- добавляет `[public]`;
- проверяет наличие `map to guest = Bad User`;
- делает backup;
- проверяет `testparm`;
- перезапускает Samba.

Создай файл:

```bash
nano add-public-smb-share.sh
```

Вставь:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMB на bash. Часть 5. Public
# Добавление read-only guest-шары [public]
# ============================================================

SHARE_NAME="${SHARE_NAME:-public}"
PUBLIC_DIR="${PUBLIC_DIR:-/srv/samba/public}"
SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"
GUEST_USER="${GUEST_USER:-nobody}"
GUEST_GROUP="${GUEST_GROUP:-nogroup}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запусти скрипт от root"
    exit 1
  fi
}

check_requirements() {
  if [[ ! -f "${SMB_CONF}" ]]; then
    echo "Ошибка: не найден ${SMB_CONF}"
    echo "Сначала выполни часть 2 и создай базовую Samba-конфигурацию."
    exit 1
  fi

  if ! id "${GUEST_USER}" &>/dev/null; then
    echo "Ошибка: пользователь ${GUEST_USER} не найден"
    exit 1
  fi

  if ! getent group "${GUEST_GROUP}" >/dev/null; then
    echo "Группа ${GUEST_GROUP} не найдена, пробуем использовать nobody"
    GUEST_GROUP="nobody"
  fi
}

prepare_dir() {
  echo "==> Создаём каталог ${PUBLIC_DIR}"
  mkdir -p "${PUBLIC_DIR}"
  chown "${GUEST_USER}:${GUEST_GROUP}" "${PUBLIC_DIR}"
  chmod 0755 "${PUBLIC_DIR}"
}

backup_config() {
  local backup="${SMB_CONF}.bak.public.$(date +%F_%H-%M-%S)"
  echo "==> Делаем backup ${backup}"
  cp "${SMB_CONF}" "${backup}"
}

ensure_global_guest_mapping() {
  if grep -qE '^[[:space:]]*map to guest[[:space:]]*=' "${SMB_CONF}"; then
    echo "==> map to guest уже настроен"
    return
  fi

  echo "==> Добавляем map to guest = Bad User в [global]"

  awk '
    BEGIN { in_global = 0; added = 0 }
    /^\[global\]/ {
      in_global = 1
      print
      next
    }
    in_global && /^\[/ && added == 0 {
      print "   map to guest = Bad User"
      added = 1
      in_global = 0
    }
    { print }
    END {
      if (in_global && added == 0) {
        print "   map to guest = Bad User"
      }
    }
  ' "${SMB_CONF}" > /tmp/smb.conf.public

  mv /tmp/smb.conf.public "${SMB_CONF}"
}

ensure_share_not_exists() {
  if grep -qE "^\[${SHARE_NAME}\]" "${SMB_CONF}"; then
    echo "Шара [${SHARE_NAME}] уже существует — пропускаем"
    exit 0
  fi
}

append_share() {
  echo "==> Добавляем шару [${SHARE_NAME}]"

  cat >> "${SMB_CONF}" <<EOF

[${SHARE_NAME}]
   path = ${PUBLIC_DIR}
   guest ok = yes
   public = yes
   read only = yes
   writable = no
   browseable = yes

   force user = ${GUEST_USER}
   force group = ${GUEST_GROUP}
EOF
}

validate_config() {
  echo "==> Проверяем Samba config"
  testparm -s "${SMB_CONF}" >/dev/null
}

restart_samba() {
  echo "==> Перезапускаем Samba"
  systemctl restart smbd
}

print_summary() {
  local host
  host="$(hostname -f 2>/dev/null || hostname)"

  echo
  echo "Готово."
  echo "Публичная read-only шара создана:"
  echo "  //${host}/${SHARE_NAME}"
  echo
  echo "Каталог:"
  echo "  ${PUBLIC_DIR}"
  echo
  echo "Проверка:"
  echo "  smbclient //SERVER_IP/${SHARE_NAME} -N -m SMB3"
}

main() {
  require_root
  check_requirements
  prepare_dir
  backup_config
  ensure_global_guest_mapping
  ensure_share_not_exists
  append_share
  validate_config
  restart_samba
  print_summary
}

main "$@"
```

---

## Запуск

```bash
chmod +x add-public-smb-share.sh
sudo ./add-public-smb-share.sh
```

---

## Добавим тестовый файл

```bash
echo "Hello from public Samba share" | sudo tee /srv/samba/public/readme.txt
sudo chmod 0644 /srv/samba/public/readme.txt
```

---

## Проверка с Linux

Список шар:

```bash
smbclient -L //SERVER_IP -N -m SMB3
```

Подключение к public без пароля:

```bash
smbclient //SERVER_IP/public -N -m SMB3
```

Внутри:

```text
smb: \> ls
smb: \> get readme.txt
smb: \> put test.txt
```

Команда `put test.txt` должна завершиться ошибкой, потому что шара read-only.

---

## Проверка с Windows

Открыть в проводнике:

```text
\\SERVER_IP\public
```

Или подключить как диск:

```cmd
net use P: \\SERVER_IP\public /user:guest ""
```

---

## Почему public должна быть read-only

Публичная writable-шара — это почти всегда проблема.

Если разрешить запись без пароля, любой клиент в сети сможет:

- загрузить мусор;
- удалить файлы;
- положить вредоносный файл;
- заполнить диск;
- устроить хаос в каталоге.

Поэтому для публичного доступа лучше использовать принцип:

```text
read-only по сети
write только локально администратором
```

Если нужно место для обмена файлами, лучше сделать отдельную authenticated-шару, например `[upload]`, а не превращать `[public]` в общую корзину.

---

## Возможные ошибки

### `NT_STATUS_ACCESS_DENIED` при подключении без пароля

Проверь:

```bash
testparm -s | grep -E 'map to guest|guest ok|public'
```

В конфиге должны быть:

```ini
map to guest = Bad User
guest ok = yes
```

### Видно шару, но нельзя читать файлы

Проверь права:

```bash
ls -ld /srv/samba/public
ls -la /srv/samba/public
```

Исправить:

```bash
sudo chown -R nobody:nogroup /srv/samba/public
sudo chmod 0755 /srv/samba/public
sudo find /srv/samba/public -type f -exec chmod 0644 {} \;
```

Если в системе нет `nogroup`, используй:

```bash
sudo chown -R nobody:nobody /srv/samba/public
```

---

## Итог

Мы добавили публичную read-only шару:

```text
\\nas\public
```

Она:

- доступна без пароля;
- работает только на чтение;
- отделена от рабочих и защищённых данных;
- не ломает текущие `[share]` и `[secure]`;
- подходит для общих файлов внутри локальной сети.

В следующей части займёмся самым важным для NAS — immutable backups на уровне Proxmox/ZFS.
