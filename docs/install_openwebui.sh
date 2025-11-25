#!/bin/bash

# Остановка скрипта при любой ошибке
set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт с правами root"
    exit 1
fi

# Создание директории проекта
PROJECT_DIR="/opt/open-webui"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Проверка и установка зависимостей
echo "Установка зависимостей..."
apt install -y curl

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не установлен. Установка Docker..."
    apt install -y docker.io
    systemctl enable --now docker
fi

# Проверка наличия docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose не установлен. Установка Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Запрос параметров у пользователя
read -p "Введите ваш OpenAI API ключ: " OPENAI_API_KEY

read -p "Введите порт для Open WebUI (по умолчанию 8555): " APP_PORT
APP_PORT=${APP_PORT:-8555}

read -p "Введите URL для Ollama API (оставьте пустым, если не используете): " OLLAMA_API_ENDPOINT

# Создание .env файла для хранения переменных окружения
cat <<EOF > .env
OPENAI_API_KEY=$OPENAI_API_KEY
OLLAMA_API_ENDPOINT=$OLLAMA_API_ENDPOINT
EOF

# Создание docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "$APP_PORT:8080"
    env_file:
      - .env
    restart: unless-stopped
    volumes:
      - ./data:/app/backend/data

  watchtower:
    image: nickfedor/watchtower:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 3600 --cleanup
    restart: unless-stopped
EOF

# Запуск контейнеров
echo "Запуск контейнеров..."
docker-compose up -d

# Получение внешнего IP
EXTERNAL_IP=$(curl -s ifconfig.me)

# Вывод информации
echo "------------------------------------------------------"
echo " Установка успешно завершена!"
echo " Доступ к Open WebUI: http://$EXTERNAL_IP:$APP_PORT"
echo "------------------------------------------------------"
echo " Директория проекта: $PROJECT_DIR"
echo " Конфигурационные файлы:"
echo " - $PROJECT_DIR/docker-compose.yml"
echo " - $PROJECT_DIR/.env (содержит API ключи)"
echo "------------------------------------------------------"
echo " Watchtower настроен на автоматическое обновление"
echo " контейнеров каждый час. Для отключения:"
echo " cd $PROJECT_DIR && docker-compose stop watchtower"
echo "------------------------------------------------------"
echo " Для резервного копирования данных:"
echo " cp -r $PROJECT_DIR/data /path/to/backup"
echo "------------------------------------------------------"
