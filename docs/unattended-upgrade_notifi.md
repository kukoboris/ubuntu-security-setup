# Настройка уведомлений Unattended Upgrades через MSMTP (Gmail)

В этой инструкции описан процесс настройки автоматических обновлений безопасности в Ubuntu/Debian с отправкой отчетов на email. Для отправки почты используется легкий клиент `msmtp` и учетная запись Google (Gmail).

## Оглавление
1. [Подготовка аккаунта Google](#1-подготовка-аккаунта-google)
2. [Установка пакетов](#2-установка-пакетов)
3. [Настройка MSMTP](#3-настройка-msmtp)
4. [Тестирование отправки почты](#4-тестирование-отправки-почты)
5. [Настройка Unattended Upgrades](#5-настройка-unattended-upgrades)
6. [Проверка работы](#6-проверка-работы)

---

## 1. Подготовка аккаунта Google

Google больше не позволяет использовать обычный пароль от аккаунта для сторонних приложений. Необходимо создать **Пароль приложения**.

1. Перейдите в настройки безопасности Google Аккаунта: [https://myaccount.google.com/security](https://myaccount.google.com/security).
2. Включите **Двухэтапную аутентификацию** (если она еще не включена).
3. В строке поиска настроек введите "Пароли приложений" (App passwords) и перейдите в этот раздел.
4. Создайте новый пароль:
   - **Приложение:** Другое (введите, например, "Ubuntu Server").
   - Нажмите **Создать**.
5. Скопируйте полученный 16-значный пароль (он будет использоваться в конфигурации msmtp).

---

## 2. Установка пакетов

Обновите списки пакетов и установите `msmtp`, `msmtp-mta` (для эмуляции sendmail), `ca-certificates` и `unattended-upgrades`.

```bash
sudo apt update
sudo apt install msmtp msmtp-mta ca-certificates bsd-mailx unattended-upgrades
```

> **Примечание:** Пакет `msmtp-mta` создает символическую ссылку, благодаря которой система считает, что у вас установлен классический `sendmail`. Это необходимо для работы системных утилит.

---

## 3. Настройка MSMTP

Создайте глобальный файл конфигурации `/etc/msmtprc`.

1. Откройте файл для редактирования:

```bash
sudo nano /etc/msmtprc
```

2. Вставьте следующее содержимое, заменив данные на свои:

```ini
# Общие настройки
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

# Настройки Gmail
account        gmail
host           smtp.gmail.com
port           587
from           ВАШ_GMAIL@gmail.com
user           ВАШ_GMAIL@gmail.com
password       ВАШ_ПАРОЛЬ_ПРИЛОЖЕНИЯ

# Установка аккаунта по умолчанию
account default : gmail
```

3. **Важно:** Настройте права доступа. Файл содержит пароль, поэтому он должен быть доступен только root (или пользователю, от которого запускается процесс, но unattended-upgrades работает от root).

```bash
sudo chmod 600 /etc/msmtprc
```

4. (Опционально) Настройте алиасы, чтобы почта для `root` уходила на ваш email.
   Откройте `/etc/aliases`:
   ```bash
   sudo nano /etc/aliases
   ```
   Добавьте или измените строку:
   ```text
   root: ВАШ_GMAIL@gmail.com
   default: ВАШ_GMAIL@gmail.com
   ```

---

## 4. Тестирование отправки почты

Перед настройкой обновлений убедитесь, что почта отправляется корректно.

Выполните команду:

```bash
echo "Это тестовое письмо от сервера." | msmtp -v ВАШ_GMAIL@gmail.com
```

*Флаг `-v` покажет подробный лог общения с сервером Google. Если в конце вы увидите `OK` и письмо придет на почту — настройка `msmtp` выполнена верно.*

---

## 5. Настройка Unattended Upgrades

Теперь настроим саму службу обновлений, чтобы она использовала почту.

1. Откройте файл конфигурации:

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

2. Найдите и раскомментируйте (уберите `//`) строку `Unattended-Upgrade::Mail`. Впишите туда ваш email:

```conf
Unattended-Upgrade::Mail "ВАШ_GMAIL@gmail.com";
```

3. (Опционально) Настройте, когда присылать уведомления.
   
   - **Только при ошибках** (чтобы не спамить):
     ```conf
     Unattended-Upgrade::MailOnlyOnError "true";
     ```
   - **Всегда** (при каждом обновлении):
     ```conf
     Unattended-Upgrade::MailOnlyOnError "false";
     ```

4. Убедитесь, что автоматические обновления включены в файле `/etc/apt/apt.conf.d/20auto-upgrades`. Он должен выглядеть так:

```conf
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```
*(Если файла нет, создайте его или выполните `sudo dpkg-reconfigure -plow unattended-upgrades` и выберите "Yes").*

---

## 6. Проверка работы

Чтобы не ждать реального обновления, можно запустить `unattended-upgrades` в режиме отладки (dry-run). Это симулирует процесс и попытается отправить письмо (если есть обновления).

```bash
sudo unattended-upgrade --dry-run --debug
```

Если обновлений нет, письмо может не отправиться. Чтобы принудительно проверить отправку именно от имени `unattended-upgrades`, можно временно отредактировать файл `/usr/bin/unattended-upgrade` (не рекомендуется для новичков) или просто довериться тесту из пункта 4, так как `unattended-upgrade` использует стандартный системный вызов `/usr/sbin/sendmail`, который мы заменили на `msmtp`.

### Полезные команды для диагностики

Посмотреть логи msmtp:
```bash
cat /var/log/msmtp.log
```

Посмотреть логи unattended-upgrades:
```bash
cat /var/log/unattended-upgrades/unattended-upgrades.log
```
