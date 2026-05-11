---
title: "Собираем Samba NAS в Proxmox LXC. Часть 3: Защищённая шара с SMB encryption"
date: 2026-05-10 10:40:00 +0300
categories: [Proxmox, Samba]
tags: [samba, smb3, encryption, secure, bash, linux, proxmox]
description: "Добавляем защищённую Samba-шару Secure в Proxmox LXC: SMB encryption, права 770, SMB3, проверка подключения и bash-скрипт."
pin: false
toc: true
comments: true
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-03-secure.png
  alt: "Собираем Samba NAS в Proxmox LXC: защищённая шара Secure"
---

## Задача

В прошлой части мы создали основную рабочую шару:

```text
\\nas\share
```

Теперь добавим отдельную защищённую шару:

```text
\\nas\secure
```

Эта шара нужна для файлов, к которым нужно относиться внимательнее:

- личные документы;
- бухгалтерия;
- сканы;
- служебные файлы;
- данные, где важны аудит и контроль доступа.

Для `[secure]` включим SMB encryption.

> `[share]` остаётся обычной рабочей шарой. `[secure]` будет отдельной зоной с повышенными требованиями.
{: .prompt-info }

---

## Что такое SMB encryption

SMB encryption — это шифрование на уровне протокола SMB3.

Это не TLS поверх HTTP и не VPN. Шифрование встроено в SMB3 и защищает SMB-трафик между клиентом и сервером.

Практически это означает:

```text
клиент ↔ Samba server
        SMB3 encrypted traffic
```

В Samba за это отвечает параметр:

```ini
smb encrypt = required
```

или более мягкий вариант:

```ini
smb encrypt = desired
```

В этой статье я сделаю режим по умолчанию:

```ini
smb encrypt = desired
```

Почему не сразу `required`?

Потому что в реальной сети могут быть клиенты, которые не смогут подключиться к mandatory encryption. Лучше сначала проверить совместимость, а затем поднять уровень до `required`.

---

## Secure vs Share

| Шара | Назначение | Encryption | Audit |
|---|---|---|---|
| `[share]` | рабочие файлы | нет / обычный SMB3 | нет |
| `[secure]` | чувствительные файлы | desired или required | будет в части 4 |

Так мы не ломаем обычную работу и включаем усиленную защиту там, где она действительно нужна.

---

## Скрипт `add-secure-smb-share.sh`

Скрипт:

- не перезатирает весь `/etc/samba/smb.conf`;
- создаёт каталог `/srv/samba/secure`;
- добавляет блок `[secure]`;
- делает backup конфига;
- проверяет `testparm`;
- перезапускает Samba.

Создай файл:

```bash
nano add-secure-smb-share.sh
```

Вставь:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMB на bash. Часть 3. Secure
# Добавление защищённой шары [secure] с SMB encryption
# ============================================================

SAMBA_USER="${SAMBA_USER:-samba}"
SHARE_NAME="${SHARE_NAME:-secure}"
SECURE_DIR="${SECURE_DIR:-/srv/samba/secure}"
SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"

# desired — шифровать, если клиент поддерживает.
# required — требовать шифрование всегда.
SMB_ENCRYPT="${SMB_ENCRYPT:-desired}"

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

  if ! id "${SAMBA_USER}" &>/dev/null; then
    echo "Ошибка: Unix-пользователь ${SAMBA_USER} не найден"
    exit 1
  fi
}

prepare_dir() {
  echo "==> Создаём каталог ${SECURE_DIR}"
  mkdir -p "${SECURE_DIR}"
  chown "${SAMBA_USER}:${SAMBA_USER}" "${SECURE_DIR}"
  chmod 0770 "${SECURE_DIR}"
}

backup_config() {
  local backup="${SMB_CONF}.bak.secure.$(date +%F_%H-%M-%S)"
  echo "==> Делаем backup ${backup}"
  cp "${SMB_CONF}" "${backup}"
}

ensure_share_not_exists() {
  if grep -qE "^\[${SHARE_NAME}\]" "${SMB_CONF}"; then
    echo "Шара [${SHARE_NAME}] уже существует в ${SMB_CONF}"
    exit 0
  fi
}

append_share() {
  echo "==> Добавляем шару [${SHARE_NAME}]"

  cat >> "${SMB_CONF}" <<EOF

[${SHARE_NAME}]
   path = ${SECURE_DIR}
   valid users = ${SAMBA_USER}
   read only = no
   writable = yes
   browseable = yes

   force user = ${SAMBA_USER}
   force group = ${SAMBA_USER}

   create mask = 0660
   directory mask = 0770

   smb encrypt = ${SMB_ENCRYPT}
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
  echo "Шара: //${host}/${SHARE_NAME}"
  echo "Каталог: ${SECURE_DIR}"
  echo "SMB encryption: ${SMB_ENCRYPT}"
  echo
  echo "Проверка:"
  echo "  testparm -s | grep -A20 '\\[${SHARE_NAME}\\]'"
  echo "  smbclient //SERVER_IP/${SHARE_NAME} -U ${SAMBA_USER} -m SMB3"
  echo "  smbstatus"
}

main() {
  require_root
  check_requirements
  prepare_dir
  backup_config
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

Мягкий вариант, совместимый с большим количеством клиентов:

```bash
chmod +x add-secure-smb-share.sh
sudo ./add-secure-smb-share.sh
```

Строгий вариант:

```bash
sudo SMB_ENCRYPT="required" ./add-secure-smb-share.sh
```

> Сначала проверь клиентов с `desired`, а уже потом переходи на `required`.
{: .prompt-tip }

---

## Проверка конфигурации

```bash
testparm -s | grep -A25 '\[secure\]'
```

Ожидаем увидеть:

```ini
[secure]
   path = /srv/samba/secure
   valid users = samba
   read only = No
   smb encrypt = desired
```

---

## Проверка подключения

С Linux-клиента:

```bash
smbclient //SERVER_IP/secure -U samba -m SMB3
```

На сервере после подключения:

```bash
smbstatus
```

Нас интересует колонка с протоколом и шифрованием. Если шифрование активно, в статусе будет видно, что соединение использует SMB3 и encryption.

---

## Как переключить `desired` на `required`

Открой конфиг:

```bash
sudo nano /etc/samba/smb.conf
```

Найди блок:

```ini
[secure]
```

Замени:

```ini
smb encrypt = desired
```

на:

```ini
smb encrypt = required
```

Проверь и перезапусти:

```bash
testparm -s
systemctl restart smbd
```

---

## Возможные ошибки

### Клиент не подключается после `required`

Причина:

- клиент не поддерживает SMB encryption;
- старый SMB-клиент;
- старый мобильный SMB-клиент.

Решение:

```ini
smb encrypt = desired
```

Или обновить клиент.

### `Encryption = -` в `smbstatus`

Причина:

- клиент подключился без encryption;
- используется `desired`, но клиент не запросил шифрование;
- нужно включить `required`.

Решение:

```ini
smb encrypt = required
```

### `NT_STATUS_ACCESS_DENIED`

Проверить права:

```bash
ls -ld /srv/samba/secure
id samba
```

Исправить:

```bash
sudo chown samba:samba /srv/samba/secure
sudo chmod 0770 /srv/samba/secure
```

---

## Почему audit не включаем сразу

Audit полезен, но он создаёт нагрузку и много логов.

Поэтому я не включаю его на все шары и не включаю его в момент создания `[secure]`.

Логика такая:

```text
часть 3 → создаём secure и проверяем доступ
часть 4 → добавляем audit только для secure
```

---

## Итог

Мы добавили отдельную шару:

```text
\\nas\secure
```

Она:

- живёт в отдельном каталоге `/srv/samba/secure`;
- доступна только пользователю `samba`;
- имеет права `0770`;
- использует SMB encryption в режиме `desired` или `required`;
- готова к подключению audit-логирования.

В следующей части включим логирование действий пользователей только для `[secure]`.
