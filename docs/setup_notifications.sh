#!/bin/bash

# ==========================================
# Настройка Unattended Upgrades + MSMTP (Gmail)
# ==========================================

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите скрипт с правами root (sudo).${NC}"
  exit 1
fi

echo -e "${YELLOW}=== Мастер настройки уведомлений Unattended Upgrades (Gmail) ===${NC}"
echo "Вам понадобится 'Пароль приложения' Google (16 символов)."
echo ""

# 1. Сбор данных
read -p "Введите ваш Gmail адрес (например, user@gmail.com): " GMAIL_USER
read -s -p "Введите Пароль приложения Google: " GMAIL_PASS
echo ""
read -p "Отправлять отчеты только при ошибках? (y/n) [n]: " ONLY_ERROR
ONLY_ERROR=${ONLY_ERROR:-n} # по умолчанию n

if [[ -z "$GMAIL_USER" || -z "$GMAIL_PASS" ]]; then
    echo -e "${RED}Ошибка: Email и пароль не могут быть пустыми.${NC}"
    exit 1
fi

# 2. Установка пакетов
echo -e "\n${YELLOW}[1/5] Установка необходимых пакетов...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq msmtp msmtp-mta ca-certificates bsd-mailx unattended-upgrades

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Пакеты установлены.${NC}"
else
    echo -e "${RED}Ошибка при установке пакетов.${NC}"
    exit 1
fi

# 3. Настройка MSMTP
echo -e "${YELLOW}[2/5] Настройка конфигурации MSMTP...${NC}"
MSMTP_CONFIG="/etc/msmtprc"

cat <<EOF > "$MSMTP_CONFIG"
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
from           $GMAIL_USER
user           $GMAIL_USER
password       $GMAIL_PASS

# Установка аккаунта по умолчанию
account default : gmail
EOF

chmod 600 "$MSMTP_CONFIG"
chown root:root "$MSMTP_CONFIG"

# Настройка алиасов
if ! grep -q "root:" /etc/aliases; then
    echo "root: $GMAIL_USER" >> /etc/aliases
    echo "default: $GMAIL_USER" >> /etc/aliases
else
    # Простая замена, если алиас уже есть (опционально можно усложнить логику)
    sed -i "s/^root:.*/root: $GMAIL_USER/" /etc/aliases
fi

echo -e "${GREEN}Конфигурация MSMTP создана.${NC}"

# 4. Настройка Unattended Upgrades
echo -e "${YELLOW}[3/5] Настройка Unattended Upgrades...${NC}"
UU_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
AUTO_CONF="/etc/apt/apt.conf.d/20auto-upgrades"

# Бэкап конфига
cp "$UU_CONF" "${UU_CONF}.bak"

# Раскомментирование и установка Email
# Используем sed для замены строки, начинающейся с //Unattended-Upgrade::Mail или просто Unattended-Upgrade::Mail
sed -i "s|^//\?\s*Unattended-Upgrade::Mail\s.*|Unattended-Upgrade::Mail \"$GMAIL_USER\";|" "$UU_CONF"

# Настройка Unattended-Upgrade::MailOnlyOnError
if [[ "$ONLY_ERROR" =~ ^[Yy]$ ]]; then
    sed -i "s|^//\?\s*Unattended-Upgrade::MailOnlyOnError\s.*|Unattended-Upgrade::MailOnlyOnError \"true\";|" "$UU_CONF"
    echo "Режим: Уведомления только об ошибках."
else
    sed -i "s|^//\?\s*Unattended-Upgrade::MailOnlyOnError\s.*|Unattended-Upgrade::MailOnlyOnError \"false\";|" "$UU_CONF"
    echo "Режим: Уведомления при каждом обновлении."
fi

# Включение автообновлений
cat <<EOF > "$AUTO_CONF"
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo -e "${GREEN}Настройки обновлений применены.${NC}"

# 5. Тестирование
echo -e "${YELLOW}[4/5] Отправка тестового письма...${NC}"
echo "Это тестовое сообщение от сервера $(hostname). Настройка msmtp завершена успешно." | msmtp -a default "$GMAIL_USER"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Тестовое письмо отправлено на $GMAIL_USER!${NC}"
else
    echo -e "${RED}Ошибка при отправке письма. Проверьте лог: /var/log/msmtp.log${NC}"
    echo -e "${RED}Возможные причины: неверный пароль приложения или блокировка со стороны Google.${NC}"
fi

# 6. Финиш
echo -e "${YELLOW}[5/5] Завершение...${NC}"
echo -e "${GREEN}Настройка полностью завершена!${NC}"
echo "Логи обновлений можно найти здесь: /var/log/unattended-upgrades/"
