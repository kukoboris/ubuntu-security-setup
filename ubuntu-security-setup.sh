#!/bin/bash

# Скрипт первоначальной настройки безопасности и оптимизации Ubuntu сервера
# Автор: kukoboris
# Дата: 26.02.2025
# Версия: 2.0

# Проверка прав администратора
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

# Функция для цветного вывода
print_success() {
    echo -e "\e[32m$1\e[0m"
}

print_info() {
    echo -e "\e[34m$1\e[0m"
}

print_warning() {
    echo -e "\e[33m$1\e[0m"
}

print_error() {
    echo -e "\e[31m$1\e[0m"
}

# Функция для проверки успешности выполнения команды
check_status() {
    if [ $? -eq 0 ]; then
        print_success "✓ $1"
    else
        print_error "✗ $1"
        return 1
    fi
}

# Проверка версии Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
if [[ "$UBUNTU_VERSION" != "20.04" && "$UBUNTU_VERSION" != "22.04" ]]; then
    print_error "Скрипт поддерживает только Ubuntu 20.04 и 22.04"
    exit 1
fi

# Приветственное сообщение
clear
echo "================================================================================"
echo "               Скрипт настройки безопасности Ubuntu сервера                    "
echo "================================================================================"
echo ""
print_warning "Этот скрипт выполнит следующие действия:"
echo "1. Обновление системы"
echo "2. Создание пользователя с привилегиями root"
echo "3. Отключение входа по паролю для root"
echo "4. Запрет доступа для пользователя root по SSH"
echo "5. Смена дефолтного порта SSH"
echo "6. Настройка файрвола (UFW)"
echo "7. Установка fail2ban и его настройка"
echo "8. Установка unattended-upgrades для автоматических обновлений"
echo "9. Настройка rsyslog для ведения логов"
echo "10. Установка необходимых утилит"
echo "11. Дополнительные меры безопасности"
echo ""
print_warning "Обязательно сделайте резервную копию перед запуском!"
echo ""

read -p "Желаете продолжить? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# 1. Обновление системы
print_info "Шаг 1: Обновление системы..."
apt update
check_status "Обновление списка пакетов" || exit 1
apt upgrade -y
check_status "Обновление пакетов" || exit 1
apt dist-upgrade -y
check_status "Обновление дистрибутива" || exit 1
apt autoremove -y
check_status "Удаление ненужных пакетов" || exit 1
apt autoclean
check_status "Очистка кэша пакетов" || exit 1

# 2. Создание пользователя с привилегиями root
print_info "Шаг 2: Создание нового пользователя с правами администратора..."
echo ""
read -p "Введите имя нового пользователя: " NEW_USER
if id "$NEW_USER" &>/dev/null; then
    print_warning "Пользователь $NEW_USER уже существует."
    read -p "Хотите продолжить с этим пользователем? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    useradd -m -s /bin/bash "$NEW_USER"
    check_status "Создание пользователя $NEW_USER" || exit 1

    passwd "$NEW_USER"
    check_status "Установка пароля для $NEW_USER" || exit 1

    usermod -aG sudo "$NEW_USER"
    check_status "Предоставление прав sudo для $NEW_USER" || exit 1
fi

# Настройка каталога .ssh и прав доступа
if [ ! -d "/home/$NEW_USER/.ssh" ]; then
    mkdir -p "/home/$NEW_USER/.ssh"
    chmod 700 "/home/$NEW_USER/.ssh"
    touch "/home/$NEW_USER/.ssh/authorized_keys"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
    chown -R "$NEW_USER":"$NEW_USER" "/home/$NEW_USER/.ssh"
    check_status "Создание директории SSH для $NEW_USER" || exit 1
fi

# Добавление публичного ключа для SSH (опционально)
read -p "Добавить публичный SSH ключ для пользователя $NEW_USER? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Введите ваш публичный SSH ключ: " SSH_KEY
    # Валидация SSH ключа
    if [[ "$SSH_KEY" =~ ^ssh-(rsa|dss|ecdsa|ed25519)\ [A-Za-z0-9+/=]+\ ([^@]+@[^@]+)?$ ]]; then
        echo "$SSH_KEY" >> "/home/$NEW_USER/.ssh/authorized_keys"
        check_status "Добавление SSH ключа для $NEW_USER" || exit 1
else
        print_error "Некорректный SSH ключ. Пропускаем."
    fi
fi

# 3 и 4. Настройка SSH
print_info "Шаг 3-4: Настройка SSH..."

# Резервное копирование конфигурации SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
check_status "Создание резервной копии конфигурации SSH" || exit 1

# 5. Смена порта SSH
read -p "Введите новый порт для SSH (рекомендуется значение от 1024 до 65535): " SSH_PORT
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    print_error "Некорректный порт. Используем стандартный порт 22."
    SSH_PORT=22
fi

# Обновление настроек SSH
sed -i 's/^#\?Port .*/Port '"$SSH_PORT"'/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
sed -i '/^#\?PubkeyAuthentication/cPubkeyAuthentication yes' /etc/ssh/sshd_config
sed -i '/^#\?AuthorizedKeysFile/cAuthorizedKeysFile .ssh/authorized_keys' /etc/ssh/sshd_config
sed -i '/^#\?Protocol/cProtocol 2' /etc/ssh/sshd_config
# Добавление дополнительных настроек SSH
echo "" >> /etc/ssh/sshd_config
echo "# Дополнительные параметры безопасности" >> /etc/ssh/sshd_config
echo "AllowUsers $NEW_USER" >> /etc/ssh/sshd_config
echo "LoginGraceTime 30" >> /etc/ssh/sshd_config
echo "DebianBanner no" >> /etc/ssh/sshd_config
echo "StrictModes yes" >> /etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config

check_status "Обновление настроек SSH" || exit 1

# Создаем предупреждающий баннер
cat > /etc/issue.net << EOF
***************************************************************************
* ВНИМАНИЕ: Это частный сервер. Несанкционированный доступ запрещен.     *
* Все действия регистрируются и могут быть переданы правоохранительным    *
* органам. Закройте соединение, если вы подключились случайно.            *
***************************************************************************
EOF
check_status "Создание предупреждающего баннера" || exit 1

# Перезапуск SSH
print_warning "SSH будет перезапущен после завершения всех настроек."

# 6. Настройка UFW (файрвол)
print_info "Шаг 6: Настройка файрвола UFW..."

# Установка и настройка UFW
# Проверка, установлен ли UFW
if ! command -v ufw >/dev/null 2>&1; then
    print_info "UFW не найден. Устанавливаем..."
    apt update && apt install -y ufw
    check_status "Установка UFW" || exit 1
else
    print_success "UFW уже установлен."
fi

# Настройка базовых правил
ufw default deny incoming
ufw default allow outgoing
check_status "Настройка базовых правил UFW" || exit 1

# Разрешить SSH на указанном порту
ufw allow "$SSH_PORT/tcp"
check_status "Добавление правила для SSH на порту $SSH_PORT" || exit 1

# Запрос дополнительных портов
read -p "Хотите открыть дополнительные порты? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    while true; do
        read -p "Введите номер порта (или 'q' для завершения): " PORT
        if [[ "$PORT" == "q" ]]; then
            break
        fi

        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            print_error "Некорректный порт. Пропускаем."
            continue
        fi

        read -p "Укажите протокол (tcp/udp/both): " PROTO
        case "$PROTO" in
            tcp)
                ufw allow "$PORT/tcp"
                check_status "Добавление правила для порта $PORT/tcp" || exit 1
                ;;
            udp)
                ufw allow "$PORT/udp"
                check_status "Добавление правила для порта $PORT/udp" || exit 1
                ;;
            both)
                ufw allow "$PORT/tcp"
                ufw allow "$PORT/udp"
                check_status "Добавление правила для порта $PORT (tcp и udp)" || exit 1
                ;;
            *)
                print_error "Некорректный протокол. Пропускаем."
                ;;
        esac
    done
fi

# Включение UFW
print_warning "UFW будет включен в конце настройки."

# 7. Установка и настройка fail2ban
print_info "Шаг 7: Установка и настройка fail2ban..."
if ! command -v fail2ban >/dev/null 2>&1; then
    apt install -y fail2ban
    check_status "Установка fail2ban" || exit 1
else
    print_success "Fail2ban уже установлен."
fi

# Создание локальной конфигурации fail2ban с улучшенными параметрами
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Банить IP на 1 час (3600 секунд)
bantime = 3600
# Увеличивать время бана для рецидивистов
bantime.increment = true
bantime.factor = 1
bantime.formula = ban.Time * (1.0 + ban.Count) * banFactor
bantime.maxtime = 604800  # 1 неделя
# Время (в секундах) для поиска попыток
findtime = 600
# Количество попыток до бана
maxretry = 5
# Игнорировать IP адреса локальной сети
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

# Настройка защиты SSH
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

# Настройка защиты от сканирования портов
[port-scan]
enabled = true
filter = port-scan
logpath = /var/log/ufw.log
maxretry = 2
bantime = 86400
findtime = 300

# Защита веб-сервера (если установлен)
[apache]
enabled = false
port = http,https
filter = apache-auth
logpath = /var/log/apache2/*error.log
maxretry = 6
bantime = 3600

[nginx-http-auth]
enabled = false
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 6
bantime = 3600
EOF

# Создание фильтра для защиты от сканирования портов
mkdir -p /etc/fail2ban/filter.d
cat > /etc/fail2ban/filter.d/port-scan.conf << EOF
[Definition]
failregex = UFW BLOCK.* SRC=<HOST>
ignoreregex =
EOF

check_status "Настройка fail2ban" || exit 1

# Перезапуск fail2ban
systemctl restart fail2ban
systemctl enable fail2ban
check_status "Запуск fail2ban" || exit 1

# 8. Настройка автоматических обновлений
print_info "Шаг 8: Настройка автоматических обновлений..."
if ! command -v unattended-upgrades >/dev/null 2>&1; then
    apt install -y unattended-upgrades apt-listchanges
    check_status "Установка unattended-upgrades" || exit 1
else
    print_success "Unattended-upgrades уже установлен."
fi

# Настройка автоматических обновлений
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

# Настройка параметров unattended-upgrades
sed -i 's|//Unattended-Upgrade::Remove-Unused-Dependencies "false";|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
sed -i 's|//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
sed -i 's|//Unattended-Upgrade::Automatic-Reboot-Time "02:00";|Unattended-Upgrade::Automatic-Reboot-Time "03:00";|' /etc/apt/apt.conf.d/50unattended-upgrades

check_status "Настройка автоматических обновлений" || exit 1

# 9. Настройка rsyslog
print_info "Шаг 9: Настройка rsyslog..."
if ! command -v rsyslog >/dev/null 2>&1; then
    apt install -y rsyslog
    check_status "Установка rsyslog" || exit 1
else
    print_success "Rsyslog уже установлен."
fi

# Проверка конфигурации rsyslog
if [ ! -f /etc/rsyslog.d/50-default.conf ]; then
    cat > /etc/rsyslog.d/50-default.conf << EOF
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          -/var/log/syslog
kern.*                          -/var/log/kern.log
daemon.*                        -/var/log/daemon.log
syslog.*                        -/var/log/syslog
user.*                          -/var/log/user.log
mail.*                          -/var/log/mail.log
cron.*                          -/var/log/cron.log
ufw.*                           -/var/log/ufw.log
local7.*                        -/var/log/boot.log
*.emerg                         :omusrmsg:*
EOF
    check_status "Создание конфигурации rsyslog" || exit 1
fi

# Настройка ротации логов
cat > /etc/logrotate.d/custom-logs << EOF
/var/log/auth.log
/var/log/syslog
/var/log/kern.log
/var/log/daemon.log
/var/log/user.log
/var/log/mail.log
/var/log/cron.log
/var/log/ufw.log
/var/log/boot.log {
    rotate 7
    daily
    missingok
    notifempty
    delaycompress
    compress
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF
check_status "Настройка ротации логов" || exit 1

systemctl restart rsyslog
systemctl enable rsyslog
check_status "Перезапуск rsyslog" || exit 1

# 10. Установка необходимых утилит
print_info "Шаг 10: Установка необходимых утилит..."
UTILS="htop iotop iftop net-tools curl wget vim nmap tcpdump lynis rkhunter chkrootkit mtr-tiny logwatch needrestart apt-show-versions debsums"
for util in $UTILS; do
    if ! command -v "$util" >/dev/null 2>&1; then
        apt install -y "$util"
        check_status "Установка $util" || exit 1
    else
        print_success "$util уже установлен."
    fi
done

# 11. Дополнительные меры безопасности
print_info "Шаг 11: Дополнительные меры безопасности..."

# Настройка параметров ядра для усиления безопасности сети
cat > /etc/sysctl.d/99-security.conf << EOF
# Защита от спуфинга IP
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Игнорировать эхо-запросы broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Защита от атак SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Защита от TIME-WAIT атак
net.ipv4.tcp_rfc1337 = 1

# Отключение перенаправления пакетов
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Защита от source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Уменьшение количества дампов ядра
kernel.core_uses_pid = 1
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1

# Защита от SACK (Selective ACK) уязвимостей
net.ipv4.tcp_sack = 0

# Ограничение использования ptrace
kernel.yama.ptrace_scope = 1
EOF
check_status "Настройка параметров ядра" || exit 1

# Применение параметров sysctl
sysctl -p /etc/sysctl.d/99-security.conf
check_status "Применение параметров ядра" || exit 1

# Ограничение доступа к критичным файлам
chmod 750 /root
chmod 600 /boot/grub/grub.cfg
chmod 600 /etc/shadow
chmod 640 /etc/group
check_status "Настройка прав доступа к критичным файлам" || exit 1

# Настройка ограничений использования ресурсов (limits.conf)
cat > /etc/security/limits.d/99-limits.conf << EOF
* soft core 0
* hard core 0
* soft nproc 1000
* hard nproc 2000
EOF
check_status "Настройка ограничений использования ресурсов" || exit 1

# Настройка политики паролей
if ! command -v pwquality >/dev/null 2>&1; then
    apt install -y libpam-pwquality
    check_status "Установка libpam-pwquality" || exit 1
else
    print_success "libpam-pwquality уже установлен."
fi

# Настройка сложности паролей
sed -i 's/^# minlen =.*/minlen = 12/' /etc/security/pwquality.conf
sed -i 's/^# dcredit =.*/dcredit = -1/' /etc/security/pwquality.conf
sed -i 's/^# ucredit =.*/ucredit = -1/' /etc/security/pwquality.conf
sed -i 's/^# ocredit =.*/ocredit = -1/' /etc/security/pwquality.conf
sed -i 's/^# lcredit =.*/lcredit = -1/' /etc/security/pwquality.conf
check_status "Настройка политики сложности паролей" || exit 1

# Настройка сроков действия паролей
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs
check_status "Настройка сроков действия паролей" || exit 1

# Установка и настройка Auditd для аудита системы
if ! command -v auditd >/dev/null 2>&1; then
    apt install -y auditd audispd-plugins
    check_status "Установка auditd" || exit 1
else
    print_success "Auditd уже установлен."
fi

# Настройка правил аудита
cat > /etc/audit/rules.d/audit.rules << EOF
# Мониторинг модификации файлов паролей и групп
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Мониторинг модификации системных файлов
-w /etc/ssh/sshd_config -p wa -k system_config
-w /etc/security -p wa -k security_config

# Мониторинг изменений в системе
-w /usr/bin/sudo -p x -k sudo_usage
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Мониторинг действий пользователя root
-a always,exit -F euid=0 -F arch=b64 -S execve -k rootcmd
-a always,exit -F euid=0 -F arch=b32 -S execve -k rootcmd

# Мониторинг неудачных попыток доступа
-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EACCES -k access
-a always,exit -F arch=b32 -S open,openat,creat -F exit=-EACCES -k access
-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EPERM -k access
-a always,exit -F arch=b32 -S open,openat,creat -F exit=-EPERM -k access

# Сохраняем все правила
-e 2
EOF
check_status "Настройка правил аудита" || exit 1

# Настройка тревожных оповещений через aureport
cat > /etc/cron.daily/aureport-check << 'EOF'
#!/bin/bash
# Создание ежедневных отчетов аудита
REPORT_DIR="/var/log/aureports"
mkdir -p $REPORT_DIR
chmod 700 $REPORT_DIR

YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
aureport --start $YESTERDAY --summary -i > "$REPORT_DIR/aureport-summary-$YESTERDAY.txt"
aureport --start $YESTERDAY --auth -i > "$REPORT_DIR/aureport-auth-$YESTERDAY.txt"
aureport --start $YESTERDAY --login -i > "$REPORT_DIR/aureport-login-$YESTERDAY.txt"
aureport --start $YESTERDAY --failed -i > "$REPORT_DIR/aureport-failed-$YESTERDAY.txt"

# Проверка наличия подозрительных событий
SUSPICIOUS=$(aureport --start $YESTERDAY --failed | grep -c "failed")
if [ "$SUSPICIOUS" -gt 10 ]; then
    echo "ВНИМАНИЕ: Обнаружено $SUSPICIOUS подозрительных событий аудита за $YESTERDAY" \
    | mail -s "Предупреждение аудита - $HOSTNAME" root
fi
EOF
chmod +x /etc/cron.daily/aureport-check
check_status "Настройка ежедневных отчетов аудита" || exit 1

# Перезапуск службы аудита
systemctl restart auditd
systemctl enable auditd
check_status "Запуск auditd" || exit 1

# Настройка разрешения выполнения только доверенных приложений (AppArmor)
if ! command -v apparmor >/dev/null 2>&1; then
    apt install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra
    check_status "Установка AppArmor" || exit 1
else
    print_success "AppArmor уже установлен."
fi

# Включение профилей AppArmor
for profile in /etc/apparmor.d/usr.sbin.{rsyslogd,sssd,mdnsd,avahi-daemon,cupsd}; do
    if [ -f "$profile" ]; then
        aa-enforce "$profile"
        check_status "Настройка профиля AppArmor: $profile" || exit 1
    fi
done

# Запуск Lynis для аудита безопасности системы
print_info "Запуск аудита безопасности с помощью Lynis..."
lynis audit system --quick &> /tmp/lynis-audit.log
LYNIS_SCORE=$(grep "Hardening index" /tmp/lynis-audit.log | awk '{print $4}')
check_status "Аудит безопасности: Hardening index = $LYNIS_SCORE" || exit 1

# Запуск проверки на наличие руткитов
print_info "Запуск проверки на наличие руткитов..."
rkhunter --update
rkhunter --propupd
rkhunter --check --skip-keypress &> /tmp/rkhunter-check.log
check_status "Проверка rkhunter завершена" || exit 1

chkrootkit &> /tmp/chkrootkit-check.log
check_status "Проверка chkrootkit завершена" || exit 1

# Применение изменений
print_info "Применение всех настроек..."

# Включение и запуск UFW
ufw --force enable
check_status "Включение UFW" || exit 1

# Перезапуск SSH
systemctl restart sshd
check_status "Перезапуск SSH" || exit 1

# Создание файла с информацией о настройках
cat > /root/security-setup-info.txt << EOF
=======================================================================
                ИНФОРМАЦИЯ О НАСТРОЙКЕ БЕЗОПАСНОСТИ
=======================================================================
Дата настройки: $(date)
Имя нового пользователя: $NEW_USER
Новый порт SSH: $SSH_PORT

ВАЖНО: Сохраняйте эту информацию в надежном месте!

Основные настройки:
1. SSH настроен на порту $SSH_PORT
2. Вход пользователя root по SSH отключен
3. Настроена аутентификация по ключам
4. Настроен файрвол (UFW)
5. Настроен fail2ban для защиты от брутфорс-атак
6. Настроены автоматические обновления
7. Настроено ведение логов
8. Установлены дополнительные меры безопасности

Рекомендации по дальнейшему улучшению безопасности:
1. Регулярно проверяйте логи на наличие подозрительной активности
2. Делайте резервные копии важных данных
3. Регулярно запускайте Lynis для аудита безопасности: lynis audit system
4. Выполняйте проверки на руткиты: rkhunter --check, chkrootkit
5. Обновляйте этот скрипт и настройки безопасности по мере необходимости

Подозрительные события можно найти в следующих логах:
- /var/log/auth.log - попытки аутентификации
- /var/log/syslog - общесистемные события
- /var/log/ufw.log - логи файрвола
- /var/log/fail2ban.log - логи fail2ban
- /var/log/audit/audit.log - логи аудита системы
=======================================================================
EOF
check_status "Создание информационного файла" || exit 1

# Установка прав доступа к информационному файлу
chmod 600 /root/security-setup-info.txt

# Итоговое сообщение
echo ""
echo "================================================================================"
print_success "Настройка безопасности успешно завершена!"
echo "================================================================================"
echo ""
print_info "Итоговая информация сохранена в файле: /root/security-setup-info.txt"
echo ""
print_warning "ВАЖНО: Перезагрузите сервер для применения всех изменений!"
print_warning "Новый порт SSH: $SSH_PORT"
print_warning "Новый пользователь: $NEW_USER"
echo ""
print_info "После перезагрузки подключитесь к серверу по SSH:"
echo "ssh -p $SSH_PORT $NEW_USER@your-server-ip"
echo ""
read -p "Перезагрузить сервер сейчас? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    shutdown -r now
fi
