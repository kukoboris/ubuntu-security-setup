# Скрипт установки Open WebUI

Этот скрипт автоматизирует процесс установки Open WebUI с использованием Docker и Docker Compose. Open WebUI предоставляет удобный веб-интерфейс для работы с API OpenAI и другими языковыми моделями.

## Содержание

- [Описание](#описание)
- [Требования](#требования)
- [Инструкция по запуску](#инструкция-по-запуску)
- [Управление сервисом](#управление-сервисом)
- [Безопасность](#безопасность)
- [Примечания](#примечания)
- [Лицензия](#лицензия)

## Описание

Скрипт выполняет следующие действия:
1. Проверяет наличие прав root
2. Обновляет систему
3. Устанавливает необходимые зависимости (Docker, Docker Compose)
4. Запрашивает API ключ OpenAI и порт для веб-интерфейса
5. Создает файл конфигурации docker-compose.yml
6. Запускает контейнеры
7. Отображает информацию о доступе к установленному сервису

Дополнительно скрипт настраивает Watchtower для автоматического обновления контейнеров каждый час.

## Требования

- Операционная система на базе Debian/Ubuntu
- Права администратора (root)
- Доступ к интернету
- API ключ OpenAI (опционально)

## Инструкция по запуску

### Шаг 1: Скачайте скрипт

```bash
wget https://raw.githubusercontent.com/kukoboris/ubuntu-security-setup/refs/heads/main/docs/install_openwebui.sh
```

### Шаг 2: Сделайте скрипт исполняемым

```bash
chmod +x install-open-webui.sh
```

### Шаг 3: Запустите скрипт с правами администратора

```bash
sudo ./install-open-webui.sh
```

### Шаг 4: Следуйте инструкциям в консоли

Скрипт запросит:
- Ваш API ключ OpenAI
- Порт для веб-интерфейса (по умолчанию 8080)

После завершения установки вы увидите URL для доступа к Open WebUI.

## Пример вывода после установки

```
------------------------------------------------------
 Установка успешно завершена!
 Доступ к Open WebUI: http://ваш_ip:8080
------------------------------------------------------
 Watchtower настроен на автоматическое обновление
 контейнеров каждый час. Для отключения:
 docker-compose stop watchtower
------------------------------------------------------
```

## Управление сервисом

### Остановка сервиса

```bash
cd /путь/к/директории/с/docker-compose.yml
docker-compose down
```

### Перезапуск сервиса

```bash
cd /путь/к/директории/с/docker-compose.yml
docker-compose restart
```

### Просмотр логов

```bash
cd /путь/к/директории/с/docker-compose.yml
docker-compose logs
```

### Отключение автоматического обновления

```bash
cd /путь/к/директории/с/docker-compose.yml
docker-compose stop watchtower
```

## Безопасность

- Скрипт требует API ключ OpenAI, который будет храниться в файле docker-compose.yml
- Рекомендуется ограничить доступ к серверу с помощью брандмауэра
- Для продакшн-окружения рекомендуется настроить HTTPS с помощью обратного прокси

## Примечания

- Если вы хотите изменить порт после установки, отредактируйте файл docker-compose.yml и перезапустите контейнеры
- Для использования с Ollama API необходимо указать URL в переменной OLLAMA_API_ENDPOINT в docker-compose.yml



## Лицензия

MIT License

Copyright (c) 2023

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
