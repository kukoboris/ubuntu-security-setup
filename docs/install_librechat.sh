#!/bin/bash

# ==========================================
# Автоматический установщик LibreChat (Fix: Project Name & UID)
# Версия: 2.6
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

clear
echo -e "${GREEN}=== Установка LibreChat (v2.6) ===${NC}"
echo ""

# 2. Определение команды Docker Compose
log "Определение версии Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    log "Используем: docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    log "Используем: docker-compose"
else
    err "Docker Compose не найден. Установите docker-compose-plugin."
    exit 1
fi

# 3. Проверка AVX
log "Проверка процессора..."
if grep -q avx /proc/cpuinfo || grep -q avx2 /proc/cpuinfo; then
    echo -e "   - AVX поддерживается (OK)"
else
    warn "AVX не найден. MongoDB 5.0+ может не запуститься."
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
    read -p "Переустановить с удалением старых данных? (y/n): " reinstall
    if [[ "$reinstall" == "y" ]]; then
        cd "$INSTALL_DIR"
        $DOCKER_COMPOSE_CMD down > /dev/null 2>&1 || true
        cd /
        rm -rf "$INSTALL_DIR"
        log "Старая папка удалена."
    else
        err "Установка отменена."
        exit 1
    fi
fi

# 6. Клонирование
log "Клонирование репозитория..."
git clone https://github.com/danny-avila/LibreChat.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 7. Настройка окружения (.env)
log "Настройка .env..."
cp .env.example .env

# --- ИСПРАВЛЕНИЕ ОШИБОК DOCKER (v2.6) ---
# Добавляем явное имя проекта, чтобы избежать ошибки "project name can't be empty"
echo "COMPOSE_PROJECT_NAME=librechat" >> .env

# Добавляем UID/GID, чтобы избежать WARN и проблем с правами
# Получаем ID пользователя, который запустил sudo (SUDO_UID), или root (0)
REAL_USER_ID=${SUDO_UID:-0}
REAL_GROUP_ID=${SUDO_GID:-0}
echo "UID=$REAL_USER_ID" >> .env
echo "GID=$REAL_GROUP_ID" >> .env
# ----------------------------------------

# Ключи безопасности
CREDS=$(openssl rand -hex 32)
SIGN=$(openssl rand -hex 32)
sed -i '/^CREDS_KEY=/d' .env
sed -i '/^SIGN_KEY=/d' .env
echo "CREDS_KEY=$CREDS" >> .env
echo "SIGN_KEY=$SIGN" >> .env

# --- НАСТРОЙКА API ПРОВАЙДЕРОВ ---
echo -e ""
echo -e "${YELLOW}--- Настройка ключей API ---${NC}"
echo "Нажмите Enter, чтобы пропустить ввод ключа."

update_key() {
    local key_name=$1
    local key_value=$2
    if [ ! -z "$key_value" ]; then
        if grep -q "$key_name=" .env; then
            sed -i "s|^#\?$key_name=.*|$key_name=$key_value|" .env
        else
            echo "$key_name=$key_value" >> .env
        fi
    fi
}

read -p "OpenAI API Key: " KEY_OPENAI
update_key "OPENAI_API_KEY" "$KEY_OPENAI"

read -p "Anthropic API Key: " KEY_ANTHRO
update_key "ANTHROPIC_API_KEY" "$KEY_ANTHRO"

read -p "OpenRouter Key: " KEY_ROUTER
update_key "OPENROUTER_KEY" "$KEY_ROUTER"

log "Ключи API сохранены."

# 8. Настройка конфигов (YAML)
log "Настройка конфигурационных файлов..."

if [ ! -f "librechat.yaml" ]; then
    if [ -f "librechat.example.yaml" ]; then
        cp librechat.example.yaml librechat.yaml
        log "Файл librechat.yaml создан из примера."
    else
        warn "librechat.example.yaml не найден!"
    fi
fi

if [ -f "docker-compose.override.yml.example" ]; then
    cp docker-compose.override.yml.example docker-compose.override.yml
    log "Файл Override скопирован из официального примера."
else
    # Backup создание, если примера нет
    echo "version: '3.4'" > docker-compose.override.yml
    echo "services: { api: { volumes: ['./librechat.yaml:/app/librechat.yaml'] } }" >> docker-compose.override.yml
fi

# 9. Проверка и настройка порта
DEFAULT_PORT=3080
TARGET_PORT=$DEFAULT_PORT

log "Проверка порта $DEFAULT_PORT..."
if netstat -tuln | grep -q ":$DEFAULT_PORT "; then
    warn "Порт $DEFAULT_PORT занят!"
    read -p "Сменить порт LibreChat на 3081? (y/n): " port_change
    if [[ "$port_change" == "y" ]]; then
        TARGET_PORT=3081
        echo "    ports:" >> docker-compose.override.yml
        echo "      - \"3081:3080\"" >> docker-compose.override.yml
        log "Порт изменен на 3081."
    else
        err "Освободите порт $DEFAULT_PORT."
        exit 1
    fi
else
    TARGET_PORT=3080
fi

# 10. Запуск
echo -e ""
log "Запуск контейнеров..."
# Добавляем явное указание имени проекта и файла .env для перестраховки
$DOCKER_COMPOSE_CMD --env-file .env up -d

# 11. Финал
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   LibreChat успешно установлен! (v2.6)   ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e ""
echo -e "Адрес сервиса:     ${YELLOW}http://localhost:$TARGET_PORT${NC}"
echo -e "Папка установки:   $INSTALL_DIR"
echo -e ""
echo -e "Если ошибка Project Name возникнет снова, выполните:"
echo -e "cd $INSTALL_DIR && $DOCKER_COMPOSE_CMD up -d"
echo -e ""
