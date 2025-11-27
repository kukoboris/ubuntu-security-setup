#!/bin/bash

# ==========================================
# Автоматический установщик LibreChat (Cloudflare Tunnel + Compatibility Mode)
# Версия: 2.2
# ==========================================

# Остановка при ошибках
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
echo -e "${GREEN}=== Установка LibreChat (Universal) ===${NC}"
echo ""

# 2. Определение команды Docker Compose
log "Определение версии Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    log "Обнаружен плагин CLI (используем 'docker compose')"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    log "Обнаружен бинарный файл (используем 'docker-compose')"
else
    err "Docker Compose не найден ни в одном из вариантов."
    err "Пожалуйста, установите docker-compose-plugin или docker-compose."
    exit 1
fi

# 3. Проверка AVX (для MongoDB)
log "Проверка поддержки AVX..."
if grep -q avx /proc/cpuinfo || grep -q avx2 /proc/cpuinfo; then
    echo -e "   - Процессор поддерживает AVX (OK)"
else
    warn "AVX не найден. MongoDB 5.0+ может не запуститься."
    read -p "Продолжить? (y/n): " avx_choice
    if [[ "$avx_choice" != "y" ]]; then exit 1; fi
fi

# 4. Обновление и зависимости
log "Проверка системных утилит..."
# Устанавливаем только если каких-то нет, чтобы не тормозить процесс
if ! command -v git &> /dev/null || ! command -v curl &> /dev/null || ! command -v netstat &> /dev/null; then
    log "Установка недостающих пакетов (git, curl, net-tools)..."
    apt-get update -qq
    apt-get install -y curl git openssl net-tools sed grep > /dev/null
else
    log "Все необходимые утилиты найдены."
fi

# 5. Папка установки
DEFAULT_DIR="/opt/LibreChat"
echo -e ""
read -p "Папка для установки [Enter = $DEFAULT_DIR]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}

if [ -d "$INSTALL_DIR" ]; then
    warn "Папка $INSTALL_DIR существует."
    read -p "Удалить старую версию и переустановить? (y/n): " reinstall
    if [[ "$reinstall" == "y" ]]; then
        # Пытаемся остановить старые контейнеры
        cd "$INSTALL_DIR"
        $DOCKER_COMPOSE_CMD down > /dev/null 2>&1 || true
        cd /
        rm -rf "$INSTALL_DIR"
        log "Старая папка очищена."
    else
        err "Установка отменена пользователем."
        exit 1
    fi
fi

# 6. Клонирование
log "Клонирование репозитория..."
git clone https://github.com/danny-avila/LibreChat.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 7. Настройка конфига
log "Настройка .env..."
cp .env.example .env

# Генерация ключей
CREDS=$(openssl rand -hex 32)
SIGN=$(openssl rand -hex 32)

sed -i '/^CREDS_KEY=/d' .env
sed -i '/^SIGN_KEY=/d' .env
echo "CREDS_KEY=$CREDS" >> .env
echo "SIGN_KEY=$SIGN" >> .env

# Ввод OpenAI Key
echo -e ""
echo -e "${YELLOW}Настройка API:${NC}"
read -p "Введите OpenAI API Key (или Enter для пропуска): " OPENAI_KEY

if [ ! -z "$OPENAI_KEY" ]; then
    if grep -q "OPENAI_API_KEY=" .env; then
        sed -i "s|^#\?OPENAI_API_KEY=.*|OPENAI_API_KEY=$OPENAI_KEY|" .env
    else
        echo "OPENAI_API_KEY=$OPENAI_KEY" >> .env
    fi
    log "API Key сохранен."
fi

# 8. Проверка порта
log "Проверка доступности порта 3080..."
if netstat -tuln | grep -q ":3080 "; then
    warn "Порт 3080 занят!"
    read -p "Сменить порт LibreChat на 3081? (y/n): " port_change
    if [[ "$port_change" == "y" ]]; then
        cat <<EOF > docker-compose.override.yml
services:
  api:
    ports:
      - "3081:3080"
EOF
        PORT=3081
        log "Порт изменен на 3081."
    else
        err "Пожалуйста, освободите порт 3080."
        exit 1
    fi
else
    PORT=3080
fi

# 9. Запуск
echo -e ""
log "Запуск контейнеров используя команду: $DOCKER_COMPOSE_CMD up -d"
$DOCKER_COMPOSE_CMD up -d

# 10. Финал
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   LibreChat установлен и запущен!   ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e ""
echo -e "Для Cloudflare Tunnel направьте трафик на:"
echo -e "${YELLOW}http://localhost:$PORT${NC}"
echo -e ""
echo -e "Локальная папка: $INSTALL_DIR"
echo -e "Управление:"
echo -e "  Остановить:    cd $INSTALL_DIR && $DOCKER_COMPOSE_CMD down"
echo -e "  Перезапустить: cd $INSTALL_DIR && $DOCKER_COMPOSE_CMD restart"
echo -e ""
