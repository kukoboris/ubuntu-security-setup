#!/bin/bash

# Скрипт настройки Tailscale и сокрытия SSH за VPN
# Автор: kukoboris (Refactored by Antigravity)
# Дата: 13.01.2026
# Версия: 2.1 (ZT Bunker Standard)

set -euo pipefail
trap 'echo "Error on line $LINENO. Script halted." >&2' ERR

# Проверка прав администратора
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

# Цветной вывод
print_success() { echo -e "\e[32m$1\e[0m"; }
print_info()    { echo -e "\e[34m$1\e[0m"; }
print_warning() { echo -e "\e[33m$1\e[0m"; }
print_error()   { echo -e "\e[31m$1\e[0m"; }

# Идемпотентная настройка конфигов
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

# --- 1. Настройка ядра ---
print_info "Шаг 1: Настройка IP forwarding..."
cat > /etc/sysctl.d/99-tailscale.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf > /dev/null

# --- 2. Установка Tailscale ---
if ! command -v tailscale &> /dev/null; then
    print_info "Шаг 2: Установка Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    print_success "Tailscale уже установлен."
fi

# --- 3. Запуск VPN ---
print_info "Шаг 3: Запуск VPN..."
# Проверяем, запущен ли уже Tailscale и авторизован ли
TS_STATUS=$(tailscale status --peers=false 2>&1 || true)

if [[ "$TS_STATUS" == *"Logged out"* || "$TS_STATUS" == *"Tailscale is stopped"* ]]; then
    print_warning "Требуется авторизация в Tailscale."
    tailscale up --advertise-exit-node
else
    print_success "Tailscale уже активен."
    # Обновляем параметры (на случай если не был exit-node)
    tailscale up --advertise-exit-node
fi

# --- 4. Верификация (Safety Check) ---
print_info "Шаг 4: Проверка соединения..."
# Пытаемся получить IP несколько раз (иногда интерфейс поднимается не мгновенно)
MAX_RETRIES=5
RETRY_COUNT=0
TS_IP=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    TS_IP=$(tailscale ip -4 || true)
    if [[ -n "$TS_IP" ]]; then
        break
    fi
    print_info "Ожидание интерфейса tailscale0... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [[ -z "$TS_IP" ]]; then
    print_error "КРИТИЧЕСКАЯ ОШИБКА: Не удалось получить IP адрес Tailscale!"
    print_error "Прекращаем выполнение, чтобы не заблокировать SSH доступ."
    exit 1
fi
print_success "VPN IP адрес получен: $TS_IP"

# --- 5. Тюнинг SSH ---
print_info "Шаг 5: Оптимизация SSH для работы через VPN..."
# Используем нашу функцию для идемпотентности
set_config_value "/etc/ssh/sshd_config" "ClientAliveInterval" "60"
set_config_value "/etc/ssh/sshd_config" "ClientAliveCountMax" "3"
systemctl restart ssh

# --- 6. Настройка Фаервола (UFW) ---
print_info "Шаг 6: Настройка периметра (UFW)..."

# Разрешаем всё внутри VPN
ufw allow in on tailscale0 comment 'VPN Internal Traffic'
# UDP порт для P2P соединения Tailscale
ufw allow 41641/udp comment 'Tailscale P2P'

# Определяем текущий SSH порт
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}

print_warning "ВНИМАНИЕ: Сейчас будет закрыт публичный доступ к порту $SSH_PORT."
print_warning "Доступ к SSH будет возможен ТОЛЬКО через VPN IP: $TS_IP"
echo ""
read -p "Вы уверены, что хотите продолжить? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Настройка фаервола отменена пользователем."
    exit 0
fi

# Удаляем правила публичного доступа (tcp и без протокола)
ufw delete allow "$SSH_PORT/tcp" || true
ufw delete allow "$SSH_PORT" || true
ufw delete limit "$SSH_PORT/tcp" || true

# Перезагружаем для верности
ufw reload > /dev/null

print_success "================================================================"
print_success "СЕРВЕР ЗАЩИЩЕН: SSH теперь скрыт за VPN!"
print_info "Ваш новый адрес для подключения: ssh $USER@$TS_IP -p $SSH_PORT"
print_success "================================================================"
