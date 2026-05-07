---
title: "Собираем Samba NAS в Proxmox LXC. Часть 6: Immutable backup через ZFS snapshots"
date: 2026-05-10 11:40:00 +0300
categories: [Proxmox, Samba]
tags: [proxmox, zfs, backup, immutable-backup, snapshots, samba, lxc]
description: "Настраиваем immutable backup для Samba NAS на Proxmox: ZFS snapshots, zfs hold, защита от удаления и health-check скрипт."
pin: false
toc: true
comments: false
image:
  path: /assets/img/posts/samba-nas-proxmox-lxc/part-06-immutable-backup-zfs.png
  alt: "Собираем Samba NAS в Proxmox LXC: immutable backup на ZFS"
---

## Задача

В предыдущих частях мы собрали Samba/NAS:

```text
/srv/samba
├── public
├── share
└── secure
```

Теперь нужно решить главный вопрос:

```text
как защитить данные от удаления, ошибки администратора и ransomware?
```

Обычный backup — это хорошо. Но если backup можно удалить так же легко, как обычный файл, то это не стратегия, а надежда.

В этой части сделаем immutable backup на уровне Proxmox/ZFS.

> Backup без проверки и защиты от удаления — это не backup, а предположение, что всё будет хорошо.
{: .prompt-danger }

---

## Что такое immutable backup

Immutable backup — это резервная копия, которую нельзя изменить или удалить до снятия защиты.

Цель:

- пережить ошибочный `rm -rf`;
- пережить ransomware;
- защититься от случайного удаления;
- иметь точку восстановления;
- сделать backup независимым от LXC-контейнера.

---

## Почему не внутри LXC

Если Samba работает в LXC, может возникнуть желание делать защиту внутри контейнера:

```bash
chattr +i backup.tar.zst
```

Это лучше, чем ничего, но это слабый уровень защиты.

Проблемы:

- root внутри контейнера может быть скомпрометирован;
- `chattr +i` можно снять;
- ransomware внутри контейнера видит файловую систему контейнера;
- контейнер не должен управлять своей единственной защитой.

Правильнее выносить immutable-слой на уровень Proxmox host.

---

## Архитектура

Пример:

```text
Proxmox host
└── ZFS pool: NAS
    └── subvol-102-disk-0
        └── LXC container: samba
            └── /srv/samba
                ├── public
                ├── share
                └── secure
```

Ключевая мысль:

```text
LXC отдаёт файлы по SMB.
Proxmox/ZFS защищает snapshots.
```

Если snapshot создан на хосте и на него поставлен `zfs hold`, контейнер не сможет его удалить.

---

## Варианты immutable-подхода

| Вариант | Где работает | Плюсы | Минусы |
|---|---|---|---|
| `chattr +i` | ext4/xfs | просто | root может снять флаг |
| Btrfs read-only snapshots | btrfs | быстро, удобно | root может удалить snapshot |
| ZFS snapshots + hold | ZFS | лучший вариант для Proxmox | требует ZFS и дисциплины |

Для Proxmox с ZFS самый интересный вариант:

```bash
zfs snapshot pool/dataset@backup-YYYY-MM-DD
zfs hold immutable pool/dataset@backup-YYYY-MM-DD
```

---

## Шаг 1. Найти dataset контейнера

На Proxmox host:

```bash
pct config 102
```

Пример:

```text
rootfs: NAS:subvol-102-disk-0,size=30G
```

Значит dataset:

```text
NAS/subvol-102-disk-0
```

Проверим:

```bash
zfs list | grep subvol-102-disk-0
```

---

## Шаг 2. Создать snapshot

```bash
zfs snapshot NAS/subvol-102-disk-0@backup-$(date +%F)
```

Проверить:

```bash
zfs list -t snapshot | grep subvol-102-disk-0
```

---

## Шаг 3. Поставить hold

```bash
zfs hold immutable NAS/subvol-102-disk-0@backup-$(date +%F)
```

Проверить:

```bash
zfs holds NAS/subvol-102-disk-0@backup-$(date +%F)
```

Ожидаемый смысл:

```text
пока есть hold с тегом immutable, snapshot нельзя удалить
```

---

## Шаг 4. Проверить защиту

Пробуем удалить snapshot:

```bash
zfs destroy NAS/subvol-102-disk-0@backup-$(date +%F)
```

Если всё правильно, ZFS не даст удалить snapshot и сообщит, что он удерживается hold.

> Проверка удаления нужна не для того, чтобы сломать backup, а чтобы убедиться, что защита реально работает.
{: .prompt-tip }

---

## Скрипт создания immutable snapshot

Создадим скрипт на Proxmox host:

```bash
nano create-immutable-zfs-snapshot.sh
```

Содержимое:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMB на bash. Часть 6. Immutable Backups
# Создание ZFS snapshot + hold для LXC dataset
# Запускать на Proxmox host, не внутри контейнера.
# ============================================================

DATASET="${DATASET:-NAS/subvol-102-disk-0}"
TAG="${TAG:-immutable}"
PREFIX="${PREFIX:-backup}"
DATE="$(date +%F)"
SNAP="${DATASET}@${PREFIX}-${DATE}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запусти скрипт от root на Proxmox host"
    exit 1
  fi
}

check_dataset() {
  if ! zfs list -H -o name "${DATASET}" >/dev/null 2>&1; then
    echo "Ошибка: dataset не найден: ${DATASET}"
    echo "Проверь: zfs list"
    exit 1
  fi
}

create_snapshot() {
  if zfs list -H -t snapshot -o name | grep -qx "${SNAP}"; then
    echo "Snapshot уже существует: ${SNAP}"
  else
    echo "==> Создаём snapshot ${SNAP}"
    zfs snapshot "${SNAP}"
  fi
}

apply_hold() {
  if zfs holds "${SNAP}" | grep -q "${TAG}"; then
    echo "Hold уже установлен: ${TAG}"
  else
    echo "==> Ставим hold ${TAG}"
    zfs hold "${TAG}" "${SNAP}"
  fi
}

verify() {
  echo "==> Проверяем snapshot"
  zfs list "${SNAP}" >/dev/null

  echo "==> Проверяем hold"
  zfs holds "${SNAP}" | grep -q "${TAG}"

  echo
  echo "Immutable snapshot готов:"
  echo "  ${SNAP}"
}

main() {
  require_root
  check_dataset
  create_snapshot
  apply_hold
  verify
}

main "$@"
```

---

## Запуск

```bash
chmod +x create-immutable-zfs-snapshot.sh
sudo DATASET="NAS/subvol-102-disk-0" ./create-immutable-zfs-snapshot.sh
```

---

## Health-check immutable backup

Backup должен не только создаваться. Его нужно проверять.

Проверим:

1. snapshot существует;
2. snapshot имеет hold;
3. ZFS pool без ошибок;
4. snapshot не старше 24 часов.

Создай скрипт:

```bash
nano healthcheck-immutable-zfs-snapshot.sh
```

Содержимое:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Health-check immutable ZFS snapshot
# Запускать на Proxmox host.
# ============================================================

DATASET="${DATASET:-NAS/subvol-102-disk-0}"
TAG="${TAG:-immutable}"
PREFIX="${PREFIX:-backup}"
DATE="$(date +%F)"
SNAP="${DATASET}@${PREFIX}-${DATE}"

EXIT_OK=0
EXIT_WARN=1
EXIT_CRIT=2

echo "=== ZFS Immutable Backup Health Check ==="
echo "Dataset : ${DATASET}"
echo "Snapshot: ${SNAP}"
echo

if ! zfs list -H -t snapshot -o name | grep -qx "${SNAP}"; then
  echo "CRITICAL: snapshot not found"
  exit "${EXIT_CRIT}"
fi

echo "OK: snapshot exists"

if ! zfs holds "${SNAP}" | grep -q "${TAG}"; then
  echo "CRITICAL: snapshot exists but hold '${TAG}' not found"
  exit "${EXIT_CRIT}"
fi

echo "OK: snapshot is immutable"

POOL="$(echo "${DATASET}" | cut -d/ -f1)"

if ! zpool status "${POOL}" >/tmp/zpool-status.$$; then
  echo "CRITICAL: cannot read zpool status for ${POOL}"
  rm -f /tmp/zpool-status.$$
  exit "${EXIT_CRIT}"
fi

if grep -q "errors: No known data errors" /tmp/zpool-status.$$; then
  echo "OK: ZFS pool has no known data errors"
else
  echo "WARNING: ZFS pool reports issues"
  cat /tmp/zpool-status.$$
  rm -f /tmp/zpool-status.$$
  exit "${EXIT_WARN}"
fi

rm -f /tmp/zpool-status.$$

CREATION="$(zfs get -H -o value creation "${SNAP}")"
CREATION_TS="$(date -d "${CREATION}" +%s)"
NOW_TS="$(date +%s)"
AGE_HOURS="$(( (NOW_TS - CREATION_TS) / 3600 ))"

if [[ "${AGE_HOURS}" -gt 24 ]]; then
  echo "WARNING: snapshot is older than 24 hours: ${AGE_HOURS}h"
  exit "${EXIT_WARN}"
fi

echo "OK: snapshot age ${AGE_HOURS}h"
echo
echo "BACKUP HEALTH: OK"
exit "${EXIT_OK}"
```

---

## Запуск health-check

```bash
chmod +x healthcheck-immutable-zfs-snapshot.sh
sudo DATASET="NAS/subvol-102-disk-0" ./healthcheck-immutable-zfs-snapshot.sh
```

Ожидаемый результат:

```text
OK: snapshot exists
OK: snapshot is immutable
OK: ZFS pool has no known data errors
OK: snapshot age 0h

BACKUP HEALTH: OK
```

---

## Как удалить immutable snapshot

Удалять такой snapshot нужно осознанно.

Сначала снять hold:

```bash
zfs release immutable NAS/subvol-102-disk-0@backup-2026-05-10
```

Потом удалить:

```bash
zfs destroy NAS/subvol-102-disk-0@backup-2026-05-10
```

Проверить:

```bash
zfs list -t snapshot | grep subvol-102-disk-0
```

> Снятие hold — административное действие. Его стоит логировать и не делать автоматически без политики retention.
{: .prompt-warning }

---

## Retention-политика

На старте можно использовать простую схему:

```text
daily snapshots    → 7 дней
weekly snapshots   → 4 недели
monthly snapshots  → 6 месяцев
```

Но важно: если на snapshot стоит hold, его нельзя удалить обычной ротацией. Значит ротация должна:

1. выбирать snapshot;
2. проверять возраст;
3. снимать hold только по политике;
4. удалять snapshot;
5. писать лог.

Это лучше вынести в отдельную статью, чтобы не смешивать создание backup и retention.

---

## Что получилось в серии

Мы собрали Samba/NAS по частям:

| Часть | Результат |
|---|---|
| 1 | Архитектура public/share/secure/backup |
| 2 | Рабочая шара `[share]` |
| 3 | Защищённая шара `[secure]` |
| 4 | Audit-логирование для `[secure]` |
| 5 | Public read-only шара `[public]` |
| 6 | Immutable backup на Proxmox/ZFS |

---

## Итог

Immutable backup лучше делать не внутри Samba-контейнера, а на уровне Proxmox/ZFS.

Итоговая схема:

```text
Samba LXC
└── отдаёт файлы по SMB

Proxmox host
└── создаёт ZFS snapshots
    └── ставит zfs hold
        └── защищает backup от удаления
```

Такой подход заметно повышает устойчивость к ошибкам, ransomware и случайному удалению данных.
