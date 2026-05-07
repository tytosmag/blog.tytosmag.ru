---
title: "Собираем Samba NAS в Proxmox LXC. Часть 4: Логирование действий пользователей"
date: 2026-05-10 11:00:00 +0300
categories: [Proxmox, Samba]
tags: [samba, audit, logging, syslog, full-audit, bash, linux]
description: "Включаем аудит действий пользователей в Samba Secure: vfs_full_audit, syslog-ng, отдельный лог, logrotate и проверка событий."
pin: false
toc: true
comments: false
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-04-logging.png
  alt: "Собираем Samba NAS в Proxmox LXC: аудит действий пользователей"
---

## Задача

В третьей части мы добавили защищённую шару:

```text
\\nas\secure
```

Теперь включим аудит действий пользователей именно для неё.

Нужно видеть:

- кто подключался;
- с какого IP;
- к какой шаре;
- какие операции выполнял;
- какие файлы открывал, создавал, изменял или удалял.

Для этого используем Samba VFS-модуль:

```ini
vfs objects = full_audit
```

> Audit включаем только для `[secure]`, а не для всех шар. Иначе можно получить много шума, лишнюю нагрузку и огромные логи.
{: .prompt-warning }

---

## Что будем логировать

Базовый набор операций:

```text
connect
disconnect
mkdir
rmdir
open
close
rename
unlink
write
pwrite
chmod
fchmod
chown
fchown
```

Можно сделать логирование шире, но для начала лучше не превращать audit в поток мусора.

---

## Где будут логи

Сделаем отдельный файл:

```text
/var/log/samba/audit-secure.log
```

Формат будет примерно такой:

```text
samba_audit: samba|192.168.1.42|secure|unlink|ok|secret.docx
```

То есть:

```text
user | ip | share | operation | result | file
```

---

## Скрипт `add-secure-audit-logging.sh`

Скрипт:

- проверяет наличие шары `[secure]`;
- устанавливает `syslog-ng`, если его нет;
- делает backup `smb.conf`;
- добавляет audit-блок в `[secure]`;
- настраивает отдельный syslog-ng destination;
- создаёт лог-файл;
- проверяет конфиг Samba;
- перезапускает сервисы.

Создай файл:

```bash
nano add-secure-audit-logging.sh
```

Вставь:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMB на bash. Часть 4. Logging
# Audit-логирование действий в шаре [secure]
# ============================================================

SHARE_NAME="${SHARE_NAME:-secure}"
SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/samba/audit-secure.log}"
SYSLOG_NG_CONF="${SYSLOG_NG_CONF:-/etc/syslog-ng/conf.d/samba-audit-secure.conf}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запусти скрипт от root"
    exit 1
  fi
}

check_share_exists() {
  if ! grep -qE "^\[${SHARE_NAME}\]" "${SMB_CONF}"; then
    echo "Ошибка: шара [${SHARE_NAME}] не найдена в ${SMB_CONF}"
    echo "Сначала выполни часть 3."
    exit 1
  fi
}

install_syslog_ng() {
  if ! command -v syslog-ng >/dev/null 2>&1; then
    echo "==> Устанавливаем syslog-ng"
    apt update
    apt install -y syslog-ng
  else
    echo "==> syslog-ng уже установлен"
  fi
}

backup_config() {
  local backup="${SMB_CONF}.bak.audit.$(date +%F_%H-%M-%S)"
  echo "==> Делаем backup ${backup}"
  cp "${SMB_CONF}" "${backup}"
}

ensure_not_already_enabled() {
  if grep -A40 -E "^\[${SHARE_NAME}\]" "${SMB_CONF}" | grep -q "vfs objects = full_audit"; then
    echo "Audit для [${SHARE_NAME}] уже включён — пропускаем изменение smb.conf"
    return 0
  fi

  return 1
}

add_audit_block() {
  echo "==> Добавляем audit-блок в [${SHARE_NAME}]"

  awk -v share="[${SHARE_NAME}]" '
    BEGIN {
      in_share = 0
      added = 0
    }

    {
      if ($0 == share) {
        in_share = 1
        print
        next
      }

      if (in_share && $0 ~ /^\[/ && added == 0) {
        print ""
        print "   # Audit logging"
        print "   vfs objects = full_audit"
        print "   full_audit:prefix = %u|%I|%S"
        print "   full_audit:success = connect disconnect mkdir rmdir open close rename unlink write pwrite chmod fchmod chown fchown"
        print "   full_audit:failure = none"
        print "   full_audit:facility = local5"
        print "   full_audit:priority = notice"
        added = 1
        in_share = 0
      }

      print
    }

    END {
      if (in_share && added == 0) {
        print ""
        print "   # Audit logging"
        print "   vfs objects = full_audit"
        print "   full_audit:prefix = %u|%I|%S"
        print "   full_audit:success = connect disconnect mkdir rmdir open close rename unlink write pwrite chmod fchmod chown fchown"
        print "   full_audit:failure = none"
        print "   full_audit:facility = local5"
        print "   full_audit:priority = notice"
      }
    }
  ' "${SMB_CONF}" > /tmp/smb.conf.audit

  mv /tmp/smb.conf.audit "${SMB_CONF}"
}

configure_syslog_ng() {
  echo "==> Настраиваем syslog-ng"

  mkdir -p "$(dirname "${SYSLOG_NG_CONF}")"
  mkdir -p "$(dirname "${AUDIT_LOG}")"

  cat > "${SYSLOG_NG_CONF}" <<EOF
destination d_samba_audit_secure {
    file("${AUDIT_LOG}" owner("root") group("adm") perm(0640));
};

filter f_samba_audit_secure {
    facility(local5) and level(notice);
};

log {
    source(s_src);
    filter(f_samba_audit_secure);
    destination(d_samba_audit_secure);
};
EOF

  touch "${AUDIT_LOG}"
  chown root:adm "${AUDIT_LOG}" 2>/dev/null || chown root:root "${AUDIT_LOG}"
  chmod 0640 "${AUDIT_LOG}"
}

validate_config() {
  echo "==> Проверяем Samba config"
  testparm -s "${SMB_CONF}" >/dev/null

  echo "==> Проверяем syslog-ng config"
  syslog-ng --syntax-only
}

restart_services() {
  echo "==> Перезапускаем syslog-ng и Samba"
  systemctl restart syslog-ng
  systemctl restart smbd
}

print_summary() {
  echo
  echo "Audit-логирование включено."
  echo "Шара: [${SHARE_NAME}]"
  echo "Лог: ${AUDIT_LOG}"
  echo
  echo "Просмотр:"
  echo "  tail -f ${AUDIT_LOG}"
  echo
  echo "Проверка Samba:"
  echo "  testparm -s | grep -A40 '\\[${SHARE_NAME}\\]'"
}

main() {
  require_root
  check_share_exists
  install_syslog_ng
  backup_config

  if ! ensure_not_already_enabled; then
    add_audit_block
  fi

  configure_syslog_ng
  validate_config
  restart_services
  print_summary
}

main "$@"
```

---

## Запуск

```bash
chmod +x add-secure-audit-logging.sh
sudo ./add-secure-audit-logging.sh
```

---

## Проверка audit-блока

```bash
testparm -s | grep -A40 '\[secure\]'
```

Должны появиться параметры:

```ini
vfs objects = full_audit
full_audit:prefix = %u|%I|%S
full_audit:facility = local5
full_audit:priority = notice
```

---

## Проверка логов

Открой лог на сервере:

```bash
tail -f /var/log/samba/audit-secure.log
```

С клиента подключись к шаре:

```bash
smbclient //SERVER_IP/secure -U samba -m SMB3
```

Создай файл:

```text
smb: \> put test.txt
smb: \> rename test.txt renamed.txt
smb: \> del renamed.txt
smb: \> quit
```

В логе должны появиться записи с пользователем, IP, шарой и операцией.

---

## Logrotate

Audit-лог может быстро расти. Добавим ротацию.

Создай файл:

```bash
sudo nano /etc/logrotate.d/samba-audit-secure
```

Содержимое:

```text
/var/log/samba/audit-secure.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
```

Проверка:

```bash
sudo logrotate -d /etc/logrotate.d/samba-audit-secure
```

---

## Что логировать, а что нет

Если логов слишком много, можно уменьшить набор операций.

Например оставить только изменения:

```ini
full_audit:success = mkdir rmdir rename unlink write pwrite chmod fchmod chown fchown
```

Если нужна полная картина, можно добавить `open` и `close`, но они создают много записей.

---

## Возможные ошибки

### `syslog-ng --syntax-only` падает

Проверь конфиг:

```bash
cat /etc/syslog-ng/conf.d/samba-audit-secure.conf
journalctl -u syslog-ng -n 100 --no-pager
```

### Лог-файл пустой

Проверь:

```bash
testparm -s | grep -A40 '\[secure\]'
systemctl status syslog-ng --no-pager
systemctl status smbd --no-pager
```

Затем сделай реальную операцию в шаре: создать, удалить или переименовать файл.

### Логи слишком шумные

Убери `open` и `close`:

```ini
full_audit:success = mkdir rmdir rename unlink write pwrite chmod fchmod chown fchown
```

---

## Почему audit важен

Backup отвечает на вопрос:

```text
можем ли мы восстановиться?
```

Audit отвечает на другой вопрос:

```text
что именно произошло?
```

Если файл пропал или был изменён, audit помогает понять:

- кто это сделал;
- с какого IP;
- когда;
- в какой шаре;
- какая операция была выполнена.

---

## Итог

Мы включили audit для `[secure]`.

Теперь защищённая шара не просто хранит файлы, но и оставляет следы важных операций. В следующей части добавим публичную read-only шару `[public]`.
