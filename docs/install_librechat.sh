#!/bin/bash

# ==========================================
# Автоматический установщик LibreChat (Config & Tunnel Ready)
# Версия: 2.3
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
echo -e "${GREEN}=== Установка LibreChat (v2.3) ===${NC}"
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

# 3. Проверка AVX (для MongoDB)
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

# Ключи безопасности
CREDS=$(openssl rand -hex 32)
SIGN=$(openssl rand -hex 32)

sed -i '/^CREDS_KEY=/d' .env
sed -i '/^SIGN_KEY=/d' .env
echo "CREDS_KEY=$CREDS" >> .env
echo "SIGN_KEY=$SIGN" >> .env

# OpenAI API Key
echo -e ""
read -p "Введите OpenAI API Key (или Enter для пропуска): " OPENAI_KEY
if [ ! -z "$OPENAI_KEY" ]; then
    if grep -q "OPENAI_API_KEY=" .env; then
        sed -i "s|^#\?OPENAI_API_KEY=.*|OPENAI_API_KEY=$OPENAI_KEY|" .env
    else
        echo "OPENAI_API_KEY=$OPENAI_KEY" >> .env
    fi
fi

# 8. Настройка librechat.yaml и docker-compose.override.yml
log "Настройка конфигурации (librechat.yaml)..."

# Удаляем docker-compose.override.yml если он вдруг есть (от прошлых тестов)
rm -f docker-compose.override.yml

# Создаем librechat.yaml из примера, если его нет
if [ ! -f "librechat.yaml" ]; then
    if [ -f "librechat.example.yaml" ]; then
        cp librechat.example.yaml librechat.yaml
        log "Файл настройки librechat.yaml создан из примера."
    else
        warn "librechat.example.yaml не найден, создание конфига пропущено."
    fi
fi

# Начинаем формировать Override файл
# Обязательно добавляем volume mapping для конфига
echo "services:" > docker-compose.override.yml
echo "  api:" >> docker-compose.override.yml
echo "    volumes:" >> docker-compose.override.yml
echo "      - ./librechat.yaml:/app/librechat.yaml" >> docker-compose.override.yml

# 9. Проверка порта
DEFAULT_PORT=3080
TARGET_PORT=$DEFAULT_PORT

log "Проверка порта $DEFAULT_PORT..."
if netstat -tuln | grep -q ":$DEFAULT_PORT "; then
    warn "Порт $DEFAULT_PORT занят!"
    read -p "Сменить порт LibreChat на 3081? (y/n): " port_change
    if [[ "$port_change" == "y" ]]; then
        TARGET_PORT=3081
        # Дописываем изменение порта в Override файл
        echo "    ports:" >> docker-compose.override.yml
        echo "      - \"3081:3080\"" >> docker-compose.override.yml
        log "Порт изменен на 3081 в docker-compose.override.yml"
    else
        err "Освободите порт $DEFAULT_PORT."
        exit 1
    fi
else
    # Порт свободен, используем стандартный
    TARGET_PORT=3080
fi

# 10. Запуск
echo -e ""
log "Запуск контейнеров..."
$DOCKER_COMPOSE_CMD up -d

# 11. Финал
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   LibreChat успешно установлен! (v2.3)   ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e ""
echo -e "Файл детальных настроек создан:"
echo -e "${BLUE}$INSTALL_DIR/librechat.yaml${NC}"
echo -e "(Редактируйте его для настройки моделей, иконок и пресетов)"
echo -e ""
echo -e "Адрес сервиса (для Cloudflare Tunnel):"
echo -e "${YELLOW}http://localhost:$TARGET_PORT${NC}"
echo -e ""
echo -e "Команда перезагрузки (после правки конфигов):"
echo -e "cd $INSTALL_DIR && $DOCKER_COMPOSE_CMD restart"
echo -e ""
