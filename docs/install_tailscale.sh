#!/bin/bash

# Проверка, что скрипт запущен с правами root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root (sudo)" 
   exit 1
fi

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка curl если не установлен
apt install curl -y

# Интерактивный запрос параметров
echo "Введите желаемый hostname для этого сервера (оставьте пустым для дефолтного):"
read TS_HOSTNAME

echo "Хотите включить SSH через Tailscale? (y/n)"
read TS_SSH

echo "Хотите настроить этот сервер как exit node? (y/n)"
read TS_EXIT_NODE

# Установка Tailscale
echo "Установка Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Запуск Tailscale
echo "Запуск Tailscale..."

# Формирование команды up с параметрами
TS_UP_COMMAND="tailscale up"

if [ ! -z "$TS_HOSTNAME" ]; then
    TS_UP_COMMAND="$TS_UP_COMMAND --hostname=$TS_HOSTNAME"
fi

if [ "$TS_SSH" = "y" ] || [ "$TS_SSH" = "Y" ]; then
    TS_UP_COMMAND="$TS_UP_COMMAND --ssh"
fi

if [ "$TS_EXIT_NODE" = "y" ] || [ "$TS_EXIT_NODE" = "Y" ]; then
    TS_UP_COMMAND="$TS_UP_COMMAND --advertise-exit-node"
fi

# Выполнение команды up
eval $TS_UP_COMMAND

# Вывод инструкций для авторизации
echo "Tailscale установлен и запущен!"
echo "1. Откройте ссылку, которая появится ниже, в браузере"
echo "2. Авторизуйтесь в вашем Tailscale аккаунте"
echo "3. После авторизации сервер появится в вашей сети"

# Проверка статуса
echo -e "\nТекущий статус Tailscale:"
tailscale status

# Настройка автозапуска
systemctl enable tailscaled
systemctl start tailscaled

# Дополнительная информация
echo -e "\nДля подключения по SSH используйте:"
echo "ssh <username>@<tailscale-ip> или ssh <username>@<hostname>"
echo "IP-адрес Tailscale можно узнать командой: tailscale ip -4"
