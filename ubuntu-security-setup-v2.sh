#!/bin/bash

# Скрипт первоначальной настройки безопасности и оптимизации Ubuntu сервера
# Автор: kukoboris (Refactored by Antigravity)
# Дата: 13.01.2026
# Версия: 2.1 (ZT Bunker Standard)

# 0. Safety & Standards check
set -euo pipefail
trap 'echo "Error on line $LINENO. Local changes might be partial." >&2' ERR

# Проверка прав администратора
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

# Функция для цветного вывода
print_success() { echo -e "\e[32m$1\e[0m"; }
print_info()    { echo -e "\e[34m$1\e[0m"; }
print_warning() { echo -e "\e[33m$1\e[0m"; }
print_error()   { echo -e "\e[31m$1\e[0m"; }

# Функция для проверки успешности выполнения команды
check_status() {
    if [ $? -eq 0 ]; then
        print_success "✓ $1"
    else
        print_error "✗ $1"
        return 1
    fi
}

# Функция для идемпотентного изменения конфигов (key-value)
# Usage: set_config_value "/etc/ssh/sshd_config" "Port" "2222" " "
set_config_value() {
    local file=$1
    local key=$2
    local value=$3
    local delim=${4:-" "}
    
    if grep -q "^#\?${key}${delim}" "$file"; then
        sed -i "s|^#\?${key}${delim}.*|${key}${delim}${value}|" "$file"
    else
        echo "${key}${delim}${value}" >> "$file"
    fi
}

# Проверка версии Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
if [[ "$UBUNTU_VERSION" != "20.04" && "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ]]; then
    print_error "Скрипт поддерживает Ubuntu 20.04, 22.04 и 24.04. Ваша версия: $UBUNTU_VERSION"
    exit 1
fi

# Приветственное сообщение
clear
echo "================================================================================"
echo "               Скрипт настройки безопасности Ubuntu (v2.1)                    "
echo "               Стандарт: ZT Bunker (Idempotent Edition)                        "
echo "================================================================================"
echo ""
print_warning "Этот скрипт выполнит комплексную настройку безопасности сервера."
echo ""

read -p "Желаете продолжить? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# 1. Обновление системы
print_info "Шаг 1: Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
check_status "Обновление списка пакетов"
apt-get upgrade -y
check_status "Обновление пакетов"
apt-get dist-upgrade -y
check_status "Обновление дистрибутива"
apt-get autoremove -y
apt-get autoclean

# 2. Создание пользователя
print_info "Шаг 2: Создание пользователя администратора..."
read -rp "Введите имя нового пользователя [kerstin]: " NEW_USER
NEW_USER=${NEW_USER:-kerstin}

if id "$NEW_USER" &>/dev/null; then
    print_success "Пользователь $NEW_USER уже существует."
else
    useradd -m -s /bin/bash "$NEW_USER"
    check_status "Создание пользователя $NEW_USER"
    passwd "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    check_status "Предоставление прав sudo"
fi

# Настройка каталога .ssh
SSH_DIR="/home/$NEW_USER/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    chown -R "$NEW_USER":"$NEW_USER" "$SSH_DIR"
fi

# Добавление публичного ключа (Идемпотентно)
read -p "Желаете добавить публичный SSH ключ? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    while true; do
        read -r -p "Введите ключ (или оставьте пустым для пропуска): " SSH_KEY
        if [[ -z "$SSH_KEY" ]]; then break; fi
        
        # Проверяем валидность и наличие ключа в файле
        if echo "$SSH_KEY" | ssh-keygen -l -f - >/dev/null 2>&1; then
            if ! grep -qF "$SSH_KEY" "$AUTH_KEYS"; then
                echo "$SSH_KEY" >> "$AUTH_KEYS"
                print_success "Ключ добавлен."
            else
                print_info "Ключ уже был добавлен ранее."
            fi
            break
        else
            print_error "Некорректный SSH ключ. Попробуйте еще раз."
        fi
    done
fi

# 3. Настройка SSH (Идемпотентно)
print_info "Шаг 3: Настройка SSH..."
[ ! -f /etc/ssh/sshd_config.bak ] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

read -rp "Введите порт SSH [22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Применяем настройки через функцию set_config_value
set_config_value "/etc/ssh/sshd_config" "Port" "$SSH_PORT"
set_config_value "/etc/ssh/sshd_config" "PermitRootLogin" "no"
set_config_value "/etc/ssh/sshd_config" "PasswordAuthentication" "no"
set_config_value "/etc/ssh/sshd_config" "X11Forwarding" "no"
set_config_value "/etc/ssh/sshd_config" "MaxAuthTries" "3"
set_config_value "/etc/ssh/sshd_config" "ClientAliveInterval" "300"
set_config_value "/etc/ssh/sshd_config" "ClientAliveCountMax" "2"
set_config_value "/etc/ssh/sshd_config" "PubkeyAuthentication" "yes"

# Добавляем AllowUsers только если его еще нет
if ! grep -q "^AllowUsers.*$NEW_USER" /etc/ssh/sshd_config; then
    # Если строка AllowUsers вообще есть, добавляем к ней, иначе создаем
    if grep -q "^AllowUsers" /etc/ssh/sshd_config; then
        sed -i "/^AllowUsers/ s/$/ $NEW_USER/" /etc/ssh/sshd_config
    else
        echo "AllowUsers $NEW_USER" >> /etc/ssh/sshd_config
    fi
fi

# 4. Файрвол UFW (Идемпотентно)
print_info "Шаг 4: Настройка файрвола..."
apt-get install -y ufw >/dev/null
ufw --force reset # Сброс старых правил для чистоты (опционально, но лучше для setup)
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
print_success "Разрешен SSH на порту $SSH_PORT"

# 5. Fail2ban
print_info "Шаг 5: Настройка Fail2ban..."
apt-get install -y fail2ban >/dev/null
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
bantime.increment = true
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8

[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
EOF
systemctl restart fail2ban

# 6. Unattended-upgrades
print_info "Шаг 6: Автоматические обновления..."
apt-get install -y unattended-upgrades apt-listchanges >/dev/null
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# 7. Утилиты (Идемпотентно через apt)
print_info "Шаг 7: Установка базовых утилит..."
UTILS=(htop iotop iftop net-tools curl wget vim nmap tcpdump lynis rkhunter chkrootkit mtr-tiny needrestart)
apt-get install -y "${UTILS[@]}" >/dev/null

# 8. Параметры Ядра (Sysctl)
print_info "Шаг 8: Оптимизация ядра (sysctl)..."
cat > /etc/sysctl.d/99-zt-bunker.conf << EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
EOF
sysctl -p /etc/sysctl.d/99-zt-bunker.conf >/dev/null

# 9. Финальные проверки
print_info "Шаг 9: Применение изменений..."
ufw --force enable
systemctl restart ssh

# Создание инфо-файла
cat > /root/setup-info.txt << EOF
SETUP DONE: $(date)
USER: $NEW_USER
SSH PORT: $SSH_PORT
EOF
chmod 600 /root/setup-info.txt

print_success "Настройка завершена успешно!"
print_info "Порт SSH: $SSH_PORT, Пользователь: $NEW_USER"
print_warning "Для полной безопасности рекомендуется перезагрузка (reboot)."

read -p "Перезагрузить сейчас? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi
