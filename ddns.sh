#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[0;33m"
NC="\033[0m"
GREEN_ground="\033[42;37m"
RED_ground="\033[41;37m"
Info="${GREEN}[信息]${NC}"
Error="${RED}[错误]${NC}"
Tip="${YELLOW}[提示]${NC}"

cop_info(){
clear
echo -e "${GREEN}##################################
#      DDNS 一键脚本 v2.0
#   $(date '+%Y-%m-%d %H:%M:%S')
##################################${NC}"
echo
}

quote_array() {
    local result=""
    local item
    for item in "$@"; do
        result+="\"$item\" "
    done
    echo "${result% }"
}

if ! grep -qiE "debian|ubuntu|alpine" /etc/os-release; then
    echo -e "${RED}本脚本仅支持 Debian、Ubuntu 或 Alpine 系统，请在这些系统上运行。${NC}"
    exit 1
fi

if [[ $(whoami) != "root" ]]; then
    echo -e "${Error}请以root身份执行该脚本！"
    exit 1
fi

check_curl() {
    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}未检测到 curl，正在安装 curl...${NC}"
        if grep -qiE "debian|ubuntu" /etc/os-release; then
            apt update
            apt install -y curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Debian/Ubuntu 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        elif grep -qiE "alpine" /etc/os-release; then
            apk update
            apk add curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}未检测到 jq，正在安装 jq...${NC}"
        if grep -qiE "debian|ubuntu" /etc/os-release; then
            apt update
            apt install -y jq
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Debian/Ubuntu 上安装 jq 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        elif grep -qiE "alpine" /etc/os-release; then
            apk update
            apk add jq
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 jq 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi

    if grep -qiE "alpine" /etc/os-release; then
        if ! grep --version 2>/dev/null | grep -q "GNU"; then
            echo -e "${YELLOW}当前 grep 不是 GNU 版本，正在安装 GNU grep...${NC}"
            apk update
            apk add grep
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 GNU grep 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi
}

install_ddns(){
    if [ ! -f "/usr/bin/ddns" ]; then
        curl -fsSL -o /usr/bin/ddns https://raw.githubusercontent.com/wyusgw/ddns/refs/heads/main/ddns.sh && chmod +x /usr/bin/ddns
    fi

    mkdir -p /etc/DDNS

    cat <<'EOF_DDNS_SCRIPT' > /etc/DDNS/DDNS
#!/bin/bash

source /etc/DDNS/.config

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[0;33m"
NC="\033[0m"

LAST_RUN_FILE="/etc/DDNS/.last_run"
LOG_FILE="/etc/DDNS/ddns.log"

cf_api() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local -a headers=( -H "Content-Type: application/json" )

    if [[ "${Cloudflare_Auth_Method:-key}" == "token" ]]; then
        if [[ -z "${Api_token:-}" ]]; then
            echo -e "${RED}[错误]${NC} Cloudflare Token 为空！"
            return 1
        fi
        headers+=( -H "Authorization: Bearer ${Api_token}" )
    else
        if [[ -z "${Email:-}" || -z "${Api_key:-}" ]]; then
            echo -e "${RED}[错误]${NC} Cloudflare Email 或 Global API Key 为空！"
            return 1
        fi
        headers+=( -H "X-Auth-Email: ${Email}" -H "X-Auth-Key: ${Api_key}" )
    fi

    if [[ -n "$data" ]]; then
        curl -s -X "$method" "$url" "${headers[@]}" --data "$data"
    else
        curl -s -X "$method" "$url" "${headers[@]}"
    fi
}

# 使用 jq 构建 Telegram 通知 JSON，正确处理特殊字符
send_telegram_notification() {
    local nl=$'\n'
    local message="DDNS 更新通知${nl}"
    message+="────────────────────${nl}"

    if [[ -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ]]; then
        local old_ipv4_display="${Old_Public_IPv4:-未记录}"
        message+="[IPv4] 地址变更${nl}"
        for ((i=0; i<${#Domains[@]}; i++)); do
            domain="${Domains[$i]}"
            if [[ ${#Domains_Names[@]} -gt $i && -n "${Domains_Names[$i]}" ]]; then
                domain_name="${Domains_Names[$i]}"
            else
                domain_name="$domain"
            fi
            message+="名称: $domain_name${nl}"
            message+="域名: $domain${nl}"
            message+="变更: $old_ipv4_display -> $Public_IPv4${nl}"
        done
    fi

    if [[ "${ipv6_set:-false}" == "true" && -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" ]]; then
        local old_ipv6_display="${Old_Public_IPv6:-未记录}"
        message+="[IPv6] 地址变更${nl}"
        for ((i=0; i<${#Domainsv6[@]}; i++)); do
            domainv6="${Domainsv6[$i]}"
            if [[ ${#Domainsv6_Names[@]} -gt $i && -n "${Domainsv6_Names[$i]}" ]]; then
                domainv6_name="${Domainsv6_Names[$i]}"
            else
                domainv6_name="$domainv6"
            fi
            message+="名称: $domainv6_name${nl}"
            message+="域名: $domainv6${nl}"
            message+="变更: $old_ipv6_display -> $Public_IPv6${nl}"
        done
    fi

    message+="────────────────────${nl}"
    message+="更新时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 使用 jq 安全构建 JSON，parse_mode 不传（纯文本），避免特殊字符被误解析
    local json_payload
    json_payload=$(jq -n \
        --arg chat_id "$Telegram_Chat_ID" \
        --arg text "$message" \
        '{chat_id: $chat_id, text: $text}')

    curl -s -X POST "https://api.telegram.org/bot${Telegram_Bot_Token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$json_payload" >/dev/null 2>&1
}

record_last_run() {
    mkdir -p /etc/DDNS
    local now
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    {
        echo "LAST_RUN_TIME=\"$now\""
        echo "LAST_RUN_IPV4=\"${Public_IPv4:-}\""
        echo "LAST_RUN_IPV6=\"${Public_IPv6:-}\""
    } > "$LAST_RUN_FILE"
    echo "$now IPv4=${Public_IPv4:-none} IPv6=${Public_IPv6:-none}" >> "$LOG_FILE"
}

Old_Public_IPv4="${Old_Public_IPv4:-}"
Old_Public_IPv6="${Old_Public_IPv6:-}"

regex_pattern='^(eth|ens|eno|esp|enp)[0-9]+'
InterFace=($(ip link show | awk -F': ' '{print $2}' | grep -E "$regex_pattern" | sed "s/@.*//g"))

Public_IPv4=""
Public_IPv6=""
ipv4Regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
ipv6Regex="^([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"

if grep -qiE "debian|ubuntu" /etc/os-release; then
    for i in "${InterFace[@]}"; do
        ipv4=$(curl -s4 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
        if [[ -z "$ipv4" ]]; then
            ipv4=$(curl -s4 --max-time 3 --interface "$i" https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi
        if [[ -n "$ipv4" && "$ipv4" =~ $ipv4Regex ]]; then
            Public_IPv4="$ipv4"
        fi

        if [[ "${ipv6_set:-false}" == "true" ]]; then
            ipv6=$(curl -s6 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
            if [[ -z "$ipv6" ]]; then
                ipv6=$(curl -s6 --max-time 3 --interface "$i" https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
            fi
            if [[ -n "$ipv6" && "$ipv6" =~ $ipv6Regex ]]; then
                Public_IPv6="$ipv6"
            fi
        fi
    done
else
    ipv4=$(curl -s4 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
    if [[ -z "$ipv4" ]]; then
        ipv4=$(curl -s4 --max-time 3 https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
    fi
    if [[ -n "$ipv4" && "$ipv4" =~ $ipv4Regex ]]; then
        Public_IPv4="$ipv4"
    fi

    if [[ "${ipv6_set:-false}" == "true" ]]; then
        ipv6=$(curl -s6 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
        if [[ -z "$ipv6" ]]; then
            ipv6=$(curl -s6 --max-time 3 https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi
        if [[ -n "$ipv6" && "$ipv6" =~ $ipv6Regex ]]; then
            Public_IPv6="$ipv6"
        fi
    fi
fi

# FIX 3: 仅在 IP 发生变更时才调用 Cloudflare API，避免不必要的请求
if [[ -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ]]; then
    for Domain in "${Domains[@]}"; do
        [ -z "$Domain" ] && continue
        Root_domain=$(echo "$Domain" | awk -F '.' '{print $(NF-1)"."$NF}')
        Zone_id=$(cf_api GET "https://api.cloudflare.com/client/v4/zones?name=$Root_domain" | jq -r '.result[0].id // empty')
        DNS_IDv4=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/$Zone_id/dns_records?type=A&name=$Domain" | jq -r '.result[0].id // empty')

        if [[ -n "$Zone_id" && -n "$DNS_IDv4" ]]; then
            cf_api PUT "https://api.cloudflare.com/client/v4/zones/$Zone_id/dns_records/$DNS_IDv4" \
                "{\"type\":\"A\",\"name\":\"$Domain\",\"content\":\"$Public_IPv4\"}" >/dev/null 2>&1
        fi
    done
fi

if [[ "${ipv6_set:-false}" == "true" && -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" ]]; then
    for Domainv6 in "${Domainsv6[@]}"; do
        [ -z "$Domainv6" ] && continue
        Root_domainv6=$(echo "$Domainv6" | awk -F '.' '{print $(NF-1)"."$NF}')
        Zone_idv6=$(cf_api GET "https://api.cloudflare.com/client/v4/zones?name=$Root_domainv6" | jq -r '.result[0].id // empty')
        DNS_IDv6=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/$Zone_idv6/dns_records?type=AAAA&name=$Domainv6" | jq -r '.result[0].id // empty')

        if [[ -n "$Zone_idv6" && -n "$DNS_IDv6" ]]; then
            cf_api PUT "https://api.cloudflare.com/client/v4/zones/$Zone_idv6/dns_records/$DNS_IDv6" \
                "{\"type\":\"AAAA\",\"name\":\"$Domainv6\",\"content\":\"$Public_IPv6\"}" >/dev/null 2>&1
        fi
    done
fi

if [[ -n "$Telegram_Bot_Token" && -n "$Telegram_Chat_ID" && (
    ( -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ) ||
    ( -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" )
) ]]; then
    send_telegram_notification
fi

sleep 3

if [[ -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ]]; then
    sed -i "s/^Old_Public_IPv4=.*/Old_Public_IPv4=\"$Public_IPv4\"/" /etc/DDNS/.config
fi

if [[ -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" ]]; then
    sed -i "s/^Old_Public_IPv6=.*/Old_Public_IPv6=\"$Public_IPv6\"/" /etc/DDNS/.config
fi

record_last_run
EOF_DDNS_SCRIPT

    cat <<'EOF_DDNS_CONFIG' > /etc/DDNS/.config
Cloudflare_Auth_Method="key"
Email="your_email@gmail.com"
Api_key="your_api_key"
Api_token=""
Domains=("your_domain1.com" "your_domain2.com")
Domains_Names=("服务器1" "服务器2")
ipv6_set="false"
Domainsv6=("your_domainv6_1.com" "your_domainv6_2.com")
Domainsv6_Names=("服务器1-IPv6" "服务器2-IPv6")
Telegram_Bot_Token=""
Telegram_Chat_ID=""
Old_Public_IPv4=""
Old_Public_IPv6=""
EOF_DDNS_CONFIG

    chmod +x /etc/DDNS/DDNS
    # FIX 6: 配置文件含密钥，权限应为 600 而非 +x
    chmod 600 /etc/DDNS/.config
    touch /etc/DDNS/ddns.log
    echo -e "${Info}DDNS 安装完成！"
    echo
}

check_ddns_status() {
    if grep -qiE "alpine" /etc/os-release; then
        if crontab -l 2>/dev/null | grep -q "/bin/bash /etc/DDNS/DDNS"; then
            ddns_status=running
        else
            ddns_status=dead
        fi
    else
        if [[ -f "/etc/systemd/system/ddns.timer" ]] && systemctl is-active --quiet ddns.timer 2>/dev/null; then
            ddns_status=running
        else
            ddns_status=dead
        fi
    fi
}

start_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        if ! crontab -l 2>/dev/null | grep -q "/bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"; then
            (crontab -l 2>/dev/null; echo "*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1") | crontab -
        fi
        echo -e "${Info}DDNS 已启动！"
    else
        systemctl enable --now ddns.timer >/dev/null 2>&1
        systemctl start ddns.service >/dev/null 2>&1
        echo -e "${Info}DDNS 已启动！"
    fi
}

# FIX 1: 修复 restart_ddns，Alpine 下直接删除旧任务再重新添加，避免重复追加 >/dev/null 2>&1
restart_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}重新启动 ddns 脚本..."
        # 先移除旧任务
        crontab -l 2>/dev/null | grep -v "/etc/DDNS/DDNS" | crontab -
        # 重新添加标准格式任务
        (crontab -l 2>/dev/null; echo "*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1") | crontab -
        echo -e "${Info}DDNS 已重启！"
    else
        echo -e "${Info}重启 DDNS 服务..."
        systemctl restart ddns.service >/dev/null 2>&1
        systemctl restart ddns.timer >/dev/null 2>&1
        echo -e "${Info}DDNS 已重启！"
    fi
}

stop_ddns(){
    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}停止 ddns 脚本..."
        crontab -l 2>/dev/null | grep -v "/bin/bash /etc/DDNS/DDNS" | crontab -
        echo -e "${Info}DDNS 已停止！"
    else
        echo -e "${Info}停止 DDNS 服务..."
        systemctl stop ddns.service >/dev/null 2>&1
        systemctl stop ddns.timer >/dev/null 2>&1
        echo -e "${Info}DDNS 已停止！"
    fi
}

run_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}设置 ddns 脚本每两分钟运行一次..."
        if ! crontab -l 2>/dev/null | grep -q "/bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"; then
            (crontab -l 2>/dev/null; echo "*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1") | crontab -
            echo -e "${Info}ddns 脚本已设置为每两分钟运行一次！"
        else
            echo -e "${Tip}ddns 脚本的 cron 任务已存在，无需再次创建！"
        fi
    else
        service='[Unit]
Description=ddns
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/DDNS
ExecStart=bash DDNS

[Install]
WantedBy=multi-user.target'

        timer='[Unit]
Description=ddns timer

[Timer]
OnUnitActiveSec=60s
Unit=ddns.service

[Install]
WantedBy=multi-user.target'

        if [ ! -f "/etc/systemd/system/ddns.service" ] || [ ! -f "/etc/systemd/system/ddns.timer" ]; then
            echo -e "${Info}创建 ddns 定时任务..."
            echo "$service" >/etc/systemd/system/ddns.service
            echo "$timer" >/etc/systemd/system/ddns.timer
            echo -e "${Info}ddns 定时任务已创建，每1分钟执行一次！"
            systemctl daemon-reload
            systemctl enable --now ddns.timer >/dev/null 2>&1
        else
            echo -e "${Tip}服务和定时器单元文件已存在，无需再次创建！"
        fi
    fi
}

set_ddns_run_interval() {
    read -rp "请输入新的 DDNS 运行间隔（分钟）： " interval

    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo -e "${Error}无效输入！请输入一个正整数。"
        return 1
    fi

    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}正在更新 DDNS 脚本的 cron 任务..."
        local cron_time="*/$interval * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"
        if crontab -l 2>/dev/null | grep -q "/etc/DDNS/DDNS"; then
            (crontab -l | grep -v "/etc/DDNS/DDNS") | crontab -
        fi
        (crontab -l 2>/dev/null; echo "$cron_time") | crontab -
        echo -e "${Info}DDNS 脚本已设置为每 ${interval} 分钟运行一次！"
    else
        echo -e "${Info}正在更新 DDNS 定时器..."
        systemctl stop ddns.timer >/dev/null 2>&1
        systemctl disable ddns.timer >/dev/null 2>&1
        sed -i "s/OnUnitActiveSec=.*/OnUnitActiveSec=${interval}m/" /etc/systemd/system/ddns.timer
        systemctl daemon-reload
        systemctl enable --now ddns.timer >/dev/null 2>&1
        echo -e "${Info}DDNS 定时器已设置为每 ${interval} 分钟运行一次！"
    fi
}

enable_autostart() {
    if grep -qiE "alpine" /etc/os-release; then
        if command -v rc-update >/dev/null 2>&1; then
            rc-update add crond default >/dev/null 2>&1
            rc-service crond restart >/dev/null 2>&1
            echo -e "${Info}已开启 Alpine 开机自启（crond）。"
        else
            echo -e "${Error}未检测到 rc-update，无法设置 Alpine 开机自启。"
        fi
    else
        systemctl enable ddns.service >/dev/null 2>&1
        systemctl enable ddns.timer >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
        echo -e "${Info}已开启 Debian/Ubuntu 开机自启（systemd timer）。"
    fi
}

disable_autostart() {
    if grep -qiE "alpine" /etc/os-release; then
        if command -v rc-update >/dev/null 2>&1; then
            rc-update del crond default >/dev/null 2>&1
            echo -e "${Info}已关闭 Alpine 开机自启（crond）。"
        else
            echo -e "${Error}未检测到 rc-update，无法关闭 Alpine 开机自启。"
        fi
    else
        systemctl disable ddns.timer >/dev/null 2>&1
        systemctl disable ddns.service >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
        echo -e "${Info}已关闭 Debian/Ubuntu 开机自启。"
    fi
}

# FIX 5: 用更精确的方式检测 crond 是否在 Alpine 开机自启中
check_autostart_status() {
    if grep -qiE "alpine" /etc/os-release; then
        local crond_autostart="未开启"
        local cron_task="未设置"

        if command -v rc-update >/dev/null 2>&1; then
            # 用 rc-update show 精确匹配 crond，避免误匹配
            if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx "crond"; then
                crond_autostart="已开启"
            fi
        fi

        if crontab -l 2>/dev/null | grep -q "/bin/bash /etc/DDNS/DDNS"; then
            cron_task="已存在"
        fi

        echo -e "${Tip}开机自启状态：${GREEN}${crond_autostart}${NC}（crond） / ${GREEN}${cron_task}${NC}（任务）"
    else
        local timer_status="未开启"
        local service_status="未开启"

        if systemctl is-enabled ddns.timer >/dev/null 2>&1; then
            timer_status="已开启"
        fi

        if systemctl is-enabled ddns.service >/dev/null 2>&1; then
            service_status="已开启"
        fi

        echo -e "${Tip}开机自启状态：${GREEN}${timer_status}${NC}（ddns.timer） / ${GREEN}${service_status}${NC}（ddns.service）"
    fi
}

check_config_status() {
    if [ -f "/etc/DDNS/.config" ]; then
        echo -e "${Info}配置文件：${GREEN}存在${NC}"
    else
        echo -e "${Info}配置文件：${RED}不存在${NC}"
    fi
}

check_service_status() {
    if grep -qiE "alpine" /etc/os-release; then
        if crontab -l 2>/dev/null | grep -q "/bin/bash /etc/DDNS/DDNS"; then
            echo -e "${Info}定时任务状态：${GREEN}已设置${NC}"
        else
            echo -e "${Info}定时任务状态：${RED}未设置${NC}"
        fi
    else
        if systemctl is-active --quiet ddns.timer 2>/dev/null; then
            echo -e "${Info}ddns.timer：${GREEN}运行中${NC}"
        else
            echo -e "${Info}ddns.timer：${RED}未运行${NC}"
        fi

        if systemctl is-enabled --quiet ddns.timer 2>/dev/null; then
            echo -e "${Info}ddns.timer 开机自启：${GREEN}已开启${NC}"
        else
            echo -e "${Info}ddns.timer 开机自启：${RED}未开启${NC}"
        fi

        if systemctl is-enabled --quiet ddns.service 2>/dev/null; then
            echo -e "${Info}ddns.service 开机自启：${GREEN}已开启${NC}"
        else
            echo -e "${Info}ddns.service 开机自启：${RED}未开启${NC}"
        fi
    fi
}

check_last_run() {
    if [ -f "/etc/DDNS/.last_run" ]; then
        source /etc/DDNS/.last_run
        echo -e "${Info}最近执行时间：${GREEN}${LAST_RUN_TIME:-未知}${NC}"
        if [ -n "${LAST_RUN_IPV4:-}" ] || [ -n "${LAST_RUN_IPV6:-}" ]; then
            echo -e "${Info}最近执行结果：${GREEN}IPv4=${LAST_RUN_IPV4:-无}，IPv6=${LAST_RUN_IPV6:-无}${NC}"
        fi
    else
        echo -e "${Info}最近执行时间：${YELLOW}暂无记录${NC}"
    fi
}

check_ddns_last_run() {
    check_last_run
}

check_schedule_config() {
    echo -e "${Tip}========== 当前定时任务配置 =========="

    if grep -qiE "alpine" /etc/os-release; then
        local cron_line
        cron_line=$(crontab -l 2>/dev/null | grep "/bin/bash /etc/DDNS/DDNS" | head -n 1)

        if [ -n "$cron_line" ]; then
            echo -e "${Info}Cron任务：${GREEN}已存在${NC}"
            echo -e "${Info}任务内容：${YELLOW}${cron_line}${NC}"

            local cron_min
            cron_min=$(echo "$cron_line" | awk '{print $1}')
            if [[ "$cron_min" =~ ^\*/([0-9]+)$ ]]; then
                echo -e "${Info}运行间隔：${GREEN}每 ${BASH_REMATCH[1]} 分钟${NC}"
            else
                echo -e "${Info}运行间隔：${YELLOW}无法自动解析${NC}"
            fi
        else
            echo -e "${Info}Cron任务：${RED}未设置${NC}"
        fi
    else
        if [ -f "/etc/systemd/system/ddns.service" ]; then
            echo -e "${Info}ddns.service：${GREEN}存在${NC}"
            echo -e "${Info}ddns.service 内容："
            grep -E '^(Description|Type|WorkingDirectory|ExecStart|WantedBy)' /etc/systemd/system/ddns.service 2>/dev/null | sed 's/^/  /'
        else
            echo -e "${Info}ddns.service：${RED}不存在${NC}"
        fi

        if [ -f "/etc/systemd/system/ddns.timer" ]; then
            echo -e "${Info}ddns.timer：${GREEN}存在${NC}"
            echo -e "${Info}ddns.timer 内容："
            grep -E '^(Description|OnUnitActiveSec|Unit|WantedBy)' /etc/systemd/system/ddns.timer 2>/dev/null | sed 's/^/  /'

            local interval
            interval=$(grep -E '^OnUnitActiveSec=' /etc/systemd/system/ddns.timer 2>/dev/null | cut -d'=' -f2)
            if [ -n "$interval" ]; then
                echo -e "${Info}运行间隔：${GREEN}${interval}${NC}"
            else
                echo -e "${Info}运行间隔：${YELLOW}未识别${NC}"
            fi
        else
            echo -e "${Info}ddns.timer：${RED}不存在${NC}"
        fi

        echo -e "${Info}systemd启用状态："
        if systemctl is-enabled --quiet ddns.timer 2>/dev/null; then
            echo -e "  ddns.timer：${GREEN}enabled${NC}"
        else
            echo -e "  ddns.timer：${RED}disabled${NC}"
        fi

        if systemctl is-enabled --quiet ddns.service 2>/dev/null; then
            echo -e "  ddns.service：${GREEN}enabled${NC}"
        else
            echo -e "  ddns.service：${RED}disabled${NC}"
        fi
    fi

    echo -e "${Tip}======================================"
}

show_status_summary() {
    echo -e "${Tip}========== 状态查询 =========="
    check_config_status
    check_ddns_status
    if [[ "$ddns_status" == "running" ]]; then
        echo -e "${Info}DDNS 运行状态：${GREEN}运行中${NC}"
    else
        echo -e "${Info}DDNS 运行状态：${RED}未运行${NC}"
    fi
    check_autostart_status
    check_service_status
    check_last_run
    echo -e "${Tip}=============================="
}

show_recent_run() {
    echo -e "${Tip}========== 最近一次执行记录 =========="
    check_last_run
    if [ -f "/etc/DDNS/ddns.log" ]; then
        echo -e "${Info}最近日志："
        tail -n 5 /etc/DDNS/ddns.log | sed 's/^/  /'
    else
        echo -e "${Info}最近日志：${YELLOW}暂无日志${NC}"
    fi
    echo -e "${Tip}======================================"
}

set_cloudflare_api(){
    echo -e "${Tip}开始配置Cloudflare API..."
    echo
    echo -e "${Tip}请选择认证方式："
    echo -e "  ${GREEN}1${NC}：Global API Key"
    echo -e "  ${GREEN}2${NC}：API Token"
    read -rp "选择 [1-2]: " auth_mode

    case "$auth_mode" in
        1)
            echo -e "${Tip}请输入您的Cloudflare邮箱"
            read -rp "邮箱: " EMail
            if [ -z "$EMail" ]; then
                echo -e "${Error}未输入邮箱，无法执行操作！"
                exit 1
            fi
            EMAIL="$EMail"

            echo -e "${Tip}请输入您的Cloudflare Global API Key"
            read -rp "密钥: " Api_Key
            if [ -z "$Api_Key" ]; then
                echo -e "${Error}未输入密钥，无法执行操作！"
                exit 1
            fi
            API_KEY="$Api_Key"

            sed -i 's/^#\?Cloudflare_Auth_Method=".*"/Cloudflare_Auth_Method="key"/g' /etc/DDNS/.config
            sed -i 's/^#\?Email=".*"/Email="'"${EMAIL}"'"/g' /etc/DDNS/.config
            sed -i 's/^#\?Api_key=".*"/Api_key="'"${API_KEY}"'"/g' /etc/DDNS/.config
            sed -i 's/^#\?Api_token=".*"/Api_token=""/g' /etc/DDNS/.config

            echo -e "${Info}已保存 Global API Key 认证方式。"
            echo
        ;;
        2)
            echo -e "${Tip}请输入您的Cloudflare API Token"
            read -rp "Token: " Api_Token
            if [ -z "$Api_Token" ]; then
                echo -e "${Error}未输入 Token，无法执行操作！"
                exit 1
            fi
            API_TOKEN="$Api_Token"

            sed -i 's/^#\?Cloudflare_Auth_Method=".*"/Cloudflare_Auth_Method="token"/g' /etc/DDNS/.config
            sed -i 's/^#\?Api_token=".*"/Api_token="'"${API_TOKEN}"'"/g' /etc/DDNS/.config
            sed -i 's/^#\?Email=".*"/Email=""/g' /etc/DDNS/.config
            sed -i 's/^#\?Api_key=".*"/Api_key=""/g' /etc/DDNS/.config

            echo -e "${Info}已保存 API Token 认证方式。"
            echo
        ;;
        *)
            echo -e "${Error}无效选择！"
            exit 1
        ;;
    esac
}

set_domain() {
    ipv4_check=$(curl -s ip.sb -4)
    if [ -n "$ipv4_check" ]; then
        echo -e "${Info}检测到IPv4地址: ${ipv4_check}"
        echo -e "${Tip}请输入您要解析的IPv4域名（可解析多个域名，使用逗号分隔） (或按回车跳过)"
        read -rp "IPv4域名: " Domain_input
        if [ -z "$Domain_input" ]; then
            echo -e "${Info}跳过IPv4域名设置。"
        else
            Domain_input="${Domain_input//，/,}"
            IFS=',' read -ra Domains <<< "$Domain_input"
            echo -e "${Info}你输入的IPv4域名为: ${RED_ground}${Domains[*]}${NC}"
            echo
            sed -i "/^Domains=/c\Domains=($(quote_array "${Domains[@]}"))" /etc/DDNS/.config

            # FIX 2: 每次调用前明确清空数组，避免多次调用时累积旧数据
            Domains_Names=()
            echo -e "${Tip}现在为IPv4域名设置名称标识（用于Telegram通知中显示）"
            for ((i=0; i<${#Domains[@]}; i++)); do
                echo -e "${Tip}请为域名 '${GREEN}${Domains[$i]}${NC}' 设置一个名称标识，或按回车使用域名作为标识"
                read -rp "名称标识: " domain_name
                if [ -z "$domain_name" ]; then
                    Domains_Names+=("${Domains[$i]}")
                else
                    Domains_Names+=("$domain_name")
                fi
            done
            echo -e "${Info}IPv4域名名称标识为: ${RED_ground}${Domains_Names[*]}${NC}"
            echo
            sed -i "/^Domains_Names=/c\Domains_Names=($(quote_array "${Domains_Names[@]}"))" /etc/DDNS/.config
        fi
    else
        echo -e "${Info}未检测到IPv4地址，跳过IPv4域名设置。"
        echo
    fi

    ipv6_check=$(curl -s ip.sb -6)
    if [ -n "$ipv6_check" ]; then
        echo -e "${Info}检测到IPv6地址: ${ipv6_check}"

        while true; do
            echo -e "${Tip}是否开启 IPv6 解析？(y/n)"
            read -rp "选择: " enable_ipv6

            if [[ "$enable_ipv6" =~ ^[Yy]$ ]]; then
                ipv6_set="true"
                sed -i 's/^#\?ipv6_set=".*"/ipv6_set="true"/g' /etc/DDNS/.config

                echo -e "${Tip}请输入您要解析的IPv6域名（可解析多个域名，使用逗号分隔） (或按回车跳过)"
                read -rp "IPv6域名: " Domainv6_input

                if [ -z "$Domainv6_input" ]; then
                    echo -e "${Info}跳过IPv6域名设置。"
                    echo
                else
                    Domainv6_input="${Domainv6_input//，/,}"
                    IFS=',' read -ra Domainsv6 <<< "$Domainv6_input"
                    echo -e "${Info}你输入的IPv6域名为: ${RED_ground}${Domainsv6[*]}${NC}"
                    echo
                    sed -i "/^Domainsv6=/c\Domainsv6=($(quote_array "${Domainsv6[@]}"))" /etc/DDNS/.config

                    # FIX 2: 同样清空 IPv6 名称数组
                    Domainsv6_Names=()
                    echo -e "${Tip}现在为IPv6域名设置名称标识（用于Telegram通知中显示）"
                    for ((i=0; i<${#Domainsv6[@]}; i++)); do
                        echo -e "${Tip}请为域名 '${GREEN}${Domainsv6[$i]}${NC}' 设置一个名称标识，或按回车使用域名作为标识"
                        read -rp "名称标识: " domainv6_name
                        if [ -z "$domainv6_name" ]; then
                            Domainsv6_Names+=("${Domainsv6[$i]}")
                        else
                            Domainsv6_Names+=("$domainv6_name")
                        fi
                    done
                    echo -e "${Info}IPv6域名名称标识为: ${RED_ground}${Domainsv6_Names[*]}${NC}"
                    echo
                    sed -i "/^Domainsv6_Names=/c\Domainsv6_Names=($(quote_array "${Domainsv6_Names[@]}"))" /etc/DDNS/.config
                fi
                break
            elif [[ "$enable_ipv6" =~ ^[Nn]$ ]]; then
                ipv6_set="false"
                sed -i 's/^#\?ipv6_set=".*"/ipv6_set="false"/g' /etc/DDNS/.config
                echo -e "${Info}IPv6 解析未开启，跳过 IPv6 域名设置。"
                echo
                break
            else
                echo -e "${Error}无效输入，请输入 'y' 或 'n'。"
            fi
        done
    else
        echo -e "${Info}未检测到IPv6地址，跳过IPv6域名设置。"
        echo
        ipv6_set="false"
        sed -i 's/^#\?ipv6_set=".*"/ipv6_set="false"/g' /etc/DDNS/.config
    fi
}

set_domain_names() {
    echo -e "${Info}开始修改域名名称标识..."
    echo

    if [ ! -f "/etc/DDNS/.config" ]; then
        echo -e "${Error}配置文件不存在，请先安装 DDNS！"
        return 1
    fi

    source /etc/DDNS/.config

    echo -e "${Info}当前 IPv4 域名配置："
    for ((i=0; i<${#Domains[@]}; i++)); do
        domain="${Domains[$i]}"
        if [[ ${#Domains_Names[@]} -gt $i && -n "${Domains_Names[$i]}" ]]; then
            domain_name="${Domains_Names[$i]}"
        else
            domain_name="$domain"
        fi
        echo -e "  ${GREEN}$((i+1))${NC}. $domain_name ($domain)"
    done
    echo

    if [ ${#Domains[@]} -gt 0 ]; then
        echo -e "${Tip}现在修改 IPv4 域名名称标识："
        # FIX 2: 明确初始化为空数组
        new_domains_names=()
        for ((i=0; i<${#Domains[@]}; i++)); do
            domain="${Domains[$i]}"
            current_name="${Domains_Names[$i]:-$domain}"
            echo -e "${Tip}域名: ${GREEN}$domain${NC}"
            echo -e "${Tip}当前名称: ${YELLOW}$current_name${NC}"
            read -rp "新名称标识 (留空保持不变): " new_name
            if [ -n "$new_name" ]; then
                new_domains_names+=("$new_name")
            else
                new_domains_names+=("$current_name")
            fi
            echo
        done
        sed -i "/^Domains_Names=/c\Domains_Names=($(quote_array "${new_domains_names[@]}"))" /etc/DDNS/.config
        echo -e "${Info}IPv4 域名名称标识已更新！"
        echo
    fi

    if [ "${ipv6_set:-false}" == "true" ] && [ ${#Domainsv6[@]} -gt 0 ]; then
        echo -e "${Info}当前 IPv6 域名配置："
        for ((i=0; i<${#Domainsv6[@]}; i++)); do
            domainv6="${Domainsv6[$i]}"
            if [[ ${#Domainsv6_Names[@]} -gt $i && -n "${Domainsv6_Names[$i]}" ]]; then
                domainv6_name="${Domainsv6_Names[$i]}"
            else
                domainv6_name="$domainv6"
            fi
            echo -e "  ${GREEN}$((i+1))${NC}. $domainv6_name ($domainv6)"
        done
        echo

        echo -e "${Tip}现在修改 IPv6 域名名称标识："
        # FIX 2: 明确初始化为空数组
        new_domainsv6_names=()
        for ((i=0; i<${#Domainsv6[@]}; i++)); do
            domainv6="${Domainsv6[$i]}"
            current_name="${Domainsv6_Names[$i]:-$domainv6}"
            echo -e "${Tip}域名: ${GREEN}$domainv6${NC}"
            echo -e "${Tip}当前名称: ${YELLOW}$current_name${NC}"
            read -rp "新名称标识 (留空保持不变): " new_name
            if [ -n "$new_name" ]; then
                new_domainsv6_names+=("$new_name")
            else
                new_domainsv6_names+=("$current_name")
            fi
            echo
        done
        sed -i "/^Domainsv6_Names=/c\Domainsv6_Names=($(quote_array "${new_domainsv6_names[@]}"))" /etc/DDNS/.config
        echo -e "${Info}IPv6 域名名称标识已更新！"
        echo
    fi

    echo -e "${Info}域名名称标识修改完成！"
}

set_telegram_settings(){
    echo -e "${Info}开始配置Telegram通知设置..."
    echo

    echo -e "${Tip}请输入您的Telegram Bot Token，如果不使用Telegram通知请直接按 Enter 跳过"
    read -rp "Token: " Token
    if [ -n "$Token" ]; then
        TELEGRAM_BOT_TOKEN="$Token"
        echo -e "${Info}你的TOKEN：${RED_ground}$TELEGRAM_BOT_TOKEN${NC}"
        echo

        echo -e "${Tip}请输入您的Telegram Chat ID，如果不使用Telegram通知请直接按 Enter 跳过"
        read -rp "Chat ID: " Chat_ID
        if [ -n "$Chat_ID" ]; then
            TELEGRAM_CHAT_ID="$Chat_ID"
            echo -e "${Info}你的Chat ID：${RED_ground}$TELEGRAM_CHAT_ID${NC}"
            echo

            sed -i 's/^#\?Telegram_Bot_Token=".*"/Telegram_Bot_Token="'"${TELEGRAM_BOT_TOKEN}"'"/g' /etc/DDNS/.config
            sed -i 's/^#\?Telegram_Chat_ID=".*"/Telegram_Chat_ID="'"${TELEGRAM_CHAT_ID}"'"/g' /etc/DDNS/.config
        else
            echo -e "${Info}已跳过设置Telegram Chat ID"
        fi
    else
        echo -e "${Info}已跳过设置Telegram Bot Token和Chat ID"
        echo
        return
    fi
}

update_ddns() {
    echo -e "${Info}正在检查更新..."
    local remote_url="https://raw.githubusercontent.com/wyusgw/ddns/refs/heads/main/ddns.sh"
    local tmp_file="/tmp/ddns_new.sh"

    if ! curl -fsSL --max-time 15 -o "$tmp_file" "$remote_url"; then
        echo -e "${Error}下载失败，请检查网络连接后重试。"
        return 1
    fi

    local local_md5 remote_md5
    local_md5=$(md5sum /usr/bin/ddns 2>/dev/null | awk '{print $1}')
    remote_md5=$(md5sum "$tmp_file" 2>/dev/null | awk '{print $1}')

    if [[ "$local_md5" == "$remote_md5" ]]; then
        echo -e "${Info}当前已是最新版本，无需更新。"
        rm -f "$tmp_file"
        return 0
    fi

    echo -e "${Tip}检测到新版本，正在更新..."
    cp "$tmp_file" /usr/bin/ddns
    chmod +x /usr/bin/ddns
    rm -f "$tmp_file"
    echo -e "${Info}更新完成！请重新执行 ${GREEN}ddns${NC} 以使用新版本。"
    exit 0
}

uninstall_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        stop_ddns
        rm -rf /etc/DDNS /usr/bin/ddns
    else
        systemctl stop ddns.service >/dev/null 2>&1
        systemctl stop ddns.timer >/dev/null 2>&1
        rm -rf /etc/systemd/system/ddns.service /etc/systemd/system/ddns.timer /etc/DDNS /usr/bin/ddns
    fi
    echo -e "${Info}DDNS 已卸载！"
    echo
}

show_menu(){
    while true; do
        cop_info
        check_ddns_status
        if [[ "$ddns_status" == "running" ]]; then
            echo -e "${Info}DDNS：${GREEN}已安装${NC} 并 ${GREEN}已启动${NC}"
        else
            echo -e "${Tip}DDNS：${GREEN}已安装${NC} 但 ${RED}未启动${NC}"
        fi
        check_autostart_status
        echo
        echo -e "${Tip}启动菜单"
        echo -e "  ${GREEN}1${NC}：启动 DDNS"
        echo -e "  ${GREEN}2${NC}：停止 DDNS"
        echo -e "  ${GREEN}3${NC}：重启 DDNS"
        echo -e "  ${GREEN}4${NC}：重新配置 Cloudflare"
        echo -e "  ${GREEN}5${NC}：配置 Telegram"
        echo -e "  ${GREEN}6${NC}：修改域名"
        echo -e "  ${GREEN}7${NC}：修改运行间隔"
        echo -e "  ${GREEN}8${NC}：修改域名名称标识"
        echo -e "  ${GREEN}9${NC}：卸载 DDNS"
        echo -e "  ${GREEN}10${NC}：开启开机自启"
        echo -e "  ${GREEN}11${NC}：关闭开机自启"
        echo -e "  ${GREEN}12${NC}：查看最近一次执行记录"
        echo -e "  ${GREEN}13${NC}：查看全部状态"
        echo -e "  ${GREEN}14${NC}：查看定时任务配置"
        echo -e "  ${GREEN}15${NC}：更新脚本"
        echo -e "  ${GREEN}0${NC}：退出"
        echo

        read -rp "选项 [0-15]： " option

        if [[ -z "$option" ]]; then
            echo -e "${RED}请输入正确的数字 [0-15]${NC}"
            sleep 1
            exit 0
        fi

        if ! [[ "$option" =~ ^([0-9]|1[0-5])$ ]]; then
            echo -e "${RED}请输入正确的数字 [0-15]${NC}"
            sleep 1
            continue
        fi

        case "$option" in
            1)
                start_ddns
                sleep 1
            ;;
            2)
                stop_ddns
                sleep 1
            ;;
            3)
                restart_ddns
                sleep 1
            ;;
            4)
                set_cloudflare_api
                restart_ddns
                sleep 1
            ;;
            5)
                set_telegram_settings
                sleep 1
            ;;
            6)
                set_domain
                restart_ddns
                sleep 1
            ;;
            7)
                set_ddns_run_interval
                sleep 1
            ;;
            8)
                set_domain_names
                sleep 1
            ;;
            9)
                uninstall_ddns
                sleep 1
                exit 0
            ;;
            10)
                enable_autostart
                sleep 1
            ;;
            11)
                disable_autostart
                sleep 1
            ;;
            12)
                show_recent_run
                read -rp "按回车返回菜单..." dummy
                sleep 1
            ;;
            13)
                show_status_summary
                read -rp "按回车返回菜单..." dummy
                sleep 1
            ;;
            14)
                check_schedule_config
                read -rp "按回车返回菜单..." dummy
                sleep 1
            ;;
            15)
                update_ddns
                sleep 1
            ;;
            0)
                exit 0
            ;;
        esac
    done
}

check_ddns_install(){
    if [ ! -f "/etc/DDNS/.config" ]; then
        cop_info
        echo -e "${Tip}DDNS 未安装，现在开始安装..."
        echo
        install_ddns
        set_cloudflare_api
        set_domain
        set_telegram_settings
        run_ddns
        enable_autostart
        echo -e "${Info}执行 ${GREEN}ddns${NC} 可呼出菜单！"
        echo
        return 0
    fi
}

check_curl
check_ddns_install
show_menu
