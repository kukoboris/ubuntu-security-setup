#!/bin/bash

# ==========================================
# Автоматический установщик LibreChat (Fix: Permissions & Logs)
# Версия: 2.7
# ==========================================

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Проверка root
if [ "$EUID" -ne 0 ]; then
  err "Запустите скрипт с правами root (sudo)."
  exit 1
fi

# Определение реального пользователя для прав доступа
REAL_USER_ID=${SUDO_UID:-1000}
REAL_GROUP_ID=${SUDO_GID:-1000}

clear
echo -e "${GREEN}=== Установка LibreChat (v2.7) ===${NC}"
echo ""

# 2. Определение команды Docker Compose
log "Определение версии Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 3. Проверка AVX
log "Проверка процессора..."
if grep -q avx /proc/cpuinfo || grep -q avx2 /proc/cpuinfo; then
    echo -e "   - AVX поддерживается (OK)"
else
    warn "AVX не найден. MongoDB может сбоить."
    read -p "Продолжить? (y/n): " avx_choice
    if [[ "$avx_choice" != "y" ]]; then exit 1; fi
fi

# 4. Проверка утилит
if ! command -v git &> /dev/null || ! command -v curl &> /dev/null || ! command -v netstat &> /dev/null; then
    log "Установка системных утилит..."
    apt-get update -qq
    apt-get install -y curl git openssl net-tools sed grep > /dev/null
fi

# 5. Папка установки
DEFAULT_DIR="/opt/LibreChat"
echo -e ""
read -p "Папка для установки [Enter = $DEFAULT_DIR]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}

if [ -d "$INSTALL_DIR" ]; then
    warn "Папка $INSTALL_DIR существует."
    read -p "Переустановить начисто? (y/n): " reinstall
    if [[ "$reinstall" == "y" ]]; then
        cd "$INSTALL_DIR"
        $DOCKER_COMPOSE_CMD down > /dev/null 2>&1 || true
        cd /
        rm -rf "$INSTALL_DIR"
        log "Папка очищена."
    else
        log "Продолжаем установку поверх существующей папки..."
    fi
fi

# 6. Клонирование (если папки нет)
if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Клонирование репозитория..."
    git clone https://github.com/danny-avila/LibreChat.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 7. Настройка окружения (.env)
log "Настройка .env..."
if [ ! -f ".env" ]; then cp .env.example .env; fi

# Фикс имени проекта и UID в .env
# Удаляем старые записи чтобы не дублировать
sed -i '/^COMPOSE_PROJECT_NAME=/d' .env
sed -i '/^UID=/d' .env
sed -i '/^GID=/d' .env

echo "COMPOSE_PROJECT_NAME=librechat" >> .env
echo "UID=$REAL_USER_ID" >> .env
echo "GID=$REAL_GROUP_ID" >> .env

# Ключи безопасности (генерируем только если их нет или они пустые)
if ! grep -q "CREDS_KEY=................" .env; then
    log "Генерация ключей безопасности..."
    sed -i '/^CREDS_KEY=/d' .env
    sed -i '/^SIGN_KEY=/d' .env
    echo "CREDS_KEY=$(openssl rand -hex 32)" >> .env
    echo "SIGN_KEY=$(openssl rand -hex 32)" >> .env
fi

# --- АПДЕЙТ КЛЮЧЕЙ ---
update_key() {
    local k=$1; local v=$2
    if [ ! -z "$v" ]; then
        if grep -q "$k=" .env; then sed -i "s|^#\?$k=.*|$k=$v|" .env; else echo "$k=$v" >> .env; fi
    fi
}

echo -e "\n${YELLOW}--- Настройка API (Enter для пропуска) ---${NC}"
read -p "OpenAI API Key: " KEY_OPENAI; update_key "OPENAI_API_KEY" "$KEY_OPENAI"
read -p "Anthropic API Key: " KEY_ANTHRO; update_key "ANTHROPIC_API_KEY" "$KEY_ANTHRO"
read -p "OpenRouter Key: " KEY_ROUTER; update_key "OPENROUTER_KEY" "$KEY_ROUTER"

# 8. Конфиги и ПРАВА ДОСТУПА
log "Подготовка конфигов и прав..."

if [ ! -f "librechat.yaml" ] && [ -f "librechat.example.yaml" ]; then
    cp librechat.example.yaml librechat.yaml
fi

if [ -f "docker-compose.override.yml.example" ]; then
    # Всегда обновляем override из примера, чтобы сбросить ошибки
    cp docker-compose.override.yml.example docker-compose.override.yml
else
    # Fallback
    echo "version: '3.4'" > docker-compose.override.yml
    echo "services: { api: { volumes: ['./librechat.yaml:/app/librechat.yaml'] } }" >> docker-compose.override.yml
fi

# --- КРИТИЧЕСКИЙ ФИКС: ПРАВА НА ПАПКИ ---
log "Создание папки логов и исправление прав владельца..."
# Создаем папки заранее, чтобы докер не создал их рутом
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/images"
mkdir -p "$INSTALL_DIR/uploads"

# Меняем владельца папки с root на реального пользователя (обычно 1000)
chown -R $REAL_USER_ID:$REAL_GROUP_ID "$INSTALL_DIR"
# Даем права на запись (на всякий случай)
chmod -R 755 "$INSTALL_DIR"
# ----------------------------------------

# 9. Порт
TARGET_PORT=3080
if netstat -tuln | grep -q ":3080 "; then
    warn "Порт 3080 занят!"
    read -p "Сменить на 3081? (y/n): " pch
    if [[ "$pch" == "y" ]]; then
        TARGET_PORT=3081
        echo "    ports:" >> docker-compose.override.yml
        echo "      - \"3081:3080\"" >> docker-compose.override.yml
    else
        err "Освободите порт 3080."; exit 1
    fi
fi

# 10. Запуск
echo -e ""
log "Запуск контейнеров..."
# Используем --env-file явно
$DOCKER_COMPOSE_CMD --env-file .env up -d

# 11. Финал
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   LibreChat Установлен! (Права исправлены)   ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Адрес: ${YELLOW}http://localhost:$TARGET_PORT${NC}"
echo -e ""
