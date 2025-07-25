#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 2.3 (证书管理增强版)
#====================================================

# --- 颜色定义 ---
G_RED="\033[31m"
G_GREEN="\033[32m"
G_YELLOW="\033[33m"
NC="\033[0m" # No Color

# 全局变量
REALM_BIN_PATH="/usr/local/bin/realm"
REALM_CONFIG_DIR="/etc/realm"
REALM_CONFIG_PATH="${REALM_CONFIG_DIR}/config.toml"
REALM_SERVICE_PATH="/etc/systemd/system/realm.service"
REALM_LATEST_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"

# SSL 相关全局变量
ACME_SH_PATH="/root/.acme.sh/acme.sh"
ACME_SH_INSTALL_URL="https://get.acme.sh"
SSL_CERT_DIR="/etc/realm/ssl"

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${G_RED}错误: 此脚本必须以 root 权限运行！${NC}"
        exit 1
    fi
}

# 检查 realm 是否已安装
check_installation() {
    if [[ -f "${REALM_BIN_PATH}" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查 acme.sh 是否已安装
check_acme_installation() {
    if [[ -f "${ACME_SH_PATH}" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查域名格式是否有效
validate_domain() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        return 1
    fi
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 检查证书是否存在且有效
check_certificate() {
    local domain="$1"
    local cert_path="${SSL_CERT_DIR}/${domain}/fullchain.pem"
    local key_path="${SSL_CERT_DIR}/${domain}/privkey.pem"
    
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        return 1
    fi
    
    if openssl x509 -checkend 2592000 -noout -in "$cert_path" >/dev/null 2>&1; then
        return 0
    else
        return 2
    fi
}

# 检查并重启 realm 服务
restart_realm() {
    echo "正在应用配置并重启 Realm 服务..."
    systemctl restart realm
    sleep 1
    if systemctl is-active --quiet realm; then
        echo -e "${G_GREEN}Realm 服务已成功重启。${NC}"
    else
        echo -e "${G_RED}Realm 服务重启失败！${NC}"
        echo "以下是最新的10条日志，请检查错误信息:"
        journalctl -n 10 -u realm --no-pager
    fi
}

# 安装必要的依赖包
install_dependencies() {
    echo "正在检查并安装必要的依赖包..."
    
    # 检测系统类型
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu 系统
        echo "检测到 Debian/Ubuntu 系统，正在安装依赖..."
        apt-get update -qq
        apt-get install -y socat curl openssl cron lsof net-tools
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL 系统
        echo "检测到 CentOS/RHEL 系统，正在安装依赖..."
        yum install -y socat curl openssl cronie lsof net-tools
        systemctl enable crond
        systemctl start crond
    elif command -v dnf &> /dev/null; then
        # Fedora 系统
        echo "检测到 Fedora 系统，正在安装依赖..."
        dnf install -y socat curl openssl cronie lsof net-tools
        systemctl enable crond
        systemctl start crond
    else
        echo -e "${G_YELLOW}警告: 无法自动检测系统类型，请手动安装以下依赖包：${NC}"
        echo "- socat"
        echo "- curl"
        echo "- openssl"
        echo "- cron/cronie"
        echo "- lsof"
        echo "- net-tools"
        return 1
    fi
    
    echo -e "${G_GREEN}依赖包安装完成。${NC}"
    return 0
}

# 安装 acme.sh
install_acme_sh() {
    if check_acme_installation; then
        echo -e "${G_GREEN}acme.sh 已安装，无需重复操作。${NC}"
        return 0
    fi
    
    echo "开始安装 acme.sh 证书管理工具..."
    echo "------------------------------------------------------------"
    
    # 安装必要的依赖包
    if ! install_dependencies; then
        echo -e "${G_RED}依赖包安装失败，请手动安装后重试。${NC}"
        return 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo -e "${G_RED}错误: curl 未安装，请先安装 curl。${NC}"
        return 1
    fi
    
    if ! command -v socat &> /dev/null; then
        echo -e "${G_RED}错误: socat 未安装，请先安装 socat。${NC}"
        return 1
    fi
    
    echo "正在从官方源下载并安装 acme.sh..."
    
    # 使用有效的邮箱地址格式
    local install_email="admin@example.com"
    read -p "请输入您的邮箱地址 (用于证书通知，默认: ${install_email}): " user_email
    if [[ -n "$user_email" && "$user_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        install_email="$user_email"
    fi
    
    if curl -fsSL ${ACME_SH_INSTALL_URL} | sh -s email="$install_email"; then
        echo -e "${G_GREEN}acme.sh 安装成功！${NC}"
        mkdir -p "${SSL_CERT_DIR}"
        
        # 重新加载环境变量
        source ~/.bashrc 2>/dev/null || true
        export PATH="$HOME/.acme.sh:$PATH"
        
        return 0
    else
        echo -e "${G_RED}acme.sh 安装失败，请检查网络连接。${NC}"
        return 1
    fi
}

# 1. 安装 realm
install_realm() {
    if check_installation; then 
        echo -e "${G_GREEN}Realm 已安装，无需重复操作。${NC}"
        return
    fi
    
    echo "开始安装 Realm..."
    echo "------------------------------------------------------------"
    
    if ! command -v curl &> /dev/null; then 
        echo -e "${G_RED}错误: curl 未安装，请先安装 curl。${NC}"
        exit 1
    fi
    
    echo "正在从 GitHub 下载最新版本的 Realm..."
    if ! curl -fsSL ${REALM_LATEST_URL} | tar xz; then 
        echo -e "${G_RED}下载或解压 Realm 失败，请检查网络或依赖。${NC}"
        exit 1
    fi
    
    echo "移动二进制文件到 /usr/local/bin/ ..."
    mv realm ${REALM_BIN_PATH}
    chmod +x ${REALM_BIN_PATH}
    
    echo "创建配置文件..."
    mkdir -p ${REALM_CONFIG_DIR}
    cat > ${REALM_CONFIG_PATH} <<EOF
[log]
level = "info"
output = "/var/log/realm.log"
EOF
    
    echo "创建 Systemd 服务..."
    cat > ${REALM_SERVICE_PATH} <<EOF
[Unit]
Description=Realm Binary Custom Service
After=network.target

[Service]
Type=simple
User=root
Restart=always
ExecStart=${REALM_BIN_PATH} -c ${REALM_CONFIG_PATH}

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable realm > /dev/null 2>&1
    
    echo "------------------------------------------------------------"
    echo -e "${G_GREEN}Realm 安装成功！${NC}"
    echo "默认开机自启已设置，但服务尚未启动，请添加转发规则后手动启动。"
}

# 2. 添加转发规则
add_rule() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装，请先选择 '1' 进行安装。${NC}"
        return
    fi
    
    echo "请选择转发规则类型:"
    echo " 1) 普通 TCP 转发"
    echo " 2) WebSocket (WS) 转发"
    echo " 3) WebSocket Secure (WSS) 转发"
    read -p "请选择类型 [1-3]: " rule_type
    
    case $rule_type in
        1) add_tcp_rule ;;
        2) add_ws_rule ;;
        3) add_wss_rule ;;
        *) echo -e "${G_RED}无效选项。${NC}" ;;
    esac
}

# 3. WSS 隧道配置
add_wss_tunnel_rule() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装，请先选择 '1' 进行安装。${NC}"
        return
    fi
    
    echo "请选择 WSS 隧道配置类型:"
    echo " 1) 配置中转端 (B端服务器 - 需要域名和证书)"
    echo " 2) 配置落地端 (A端服务器 - 客户端连接)"
    echo " 3) 查看配置示例"
    read -p "请选择类型 [1-3]: " tunnel_type
    
    case $tunnel_type in
        1) add_wss_tunnel_relay_side ;;
        2) add_wss_tunnel_landing_side ;;
        3) show_wss_tunnel_examples ;;
        *) echo -e "${G_RED}无效选项。${NC}" ;;
    esac
}

# 3.1 配置 WSS 隧道中转端 (B端服务器)
add_wss_tunnel_relay_side() {
    echo "配置 WSS 隧道中转端 (B端服务器):"
    echo "------------------------------------------------------------"
    echo -e "${G_YELLOW}注意: 中转端需要域名和SSL证书！${NC}"
    echo
    
    read -p "监听端口 (例如 54321): " listen_port
    read -p "转发目标地址 (例如 127.0.0.1): " target_addr
    read -p "转发目标端口 (例如 12345): " target_port
    read -p "域名 (必须已申请证书): " domain
    read -p "WebSocket 路径 (例如 /somepath): " ws_path
    
    # 参数验证
    if [[ -z "$listen_port" || -z "$target_addr" || -z "$target_port" || -z "$domain" || -z "$ws_path" ]]; then 
        echo -e "${G_RED}错误: 所有参数都不能为空。${NC}"
        return
    fi
    
    # 验证端口格式
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 监听端口无效。${NC}"
        return
    fi
    
    if ! [[ "$target_port" =~ ^[0-9]+$ && "$target_port" -ge 1 && "$target_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 目标端口无效。${NC}"
        return
    fi
    
    # 验证域名格式
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    # 检查证书是否存在
    local cert_path="${SSL_CERT_DIR}/${domain}/fullchain.pem"
    local key_path="${SSL_CERT_DIR}/${domain}/privkey.pem"
    
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        echo -e "${G_RED}错误: 域名 ${domain} 的SSL证书不存在！${NC}"
        echo -e "${G_YELLOW}请先使用 '7. SSL证书管理' 申请证书。${NC}"
        echo -e "${G_YELLOW}证书路径应为: ${cert_path}${NC}"
        echo -e "${G_YELLOW}私钥路径应为: ${key_path}${NC}"
        return
    fi
    
    # 检查端口是否已存在
    if grep -q "listen = \".*:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then 
        echo -e "${G_RED}错误: 监听端口 ${listen_port} 已存在。${NC}"
        return
    fi
    
    # 构建配置
    local listen_transport="wss;host=${domain};path=${ws_path};cert=${cert_path};key=${key_path}"
    
    # 添加配置
    echo -e "\n[[endpoints]]\nlisten = \"[::]:${listen_port}\"\nremote = \"${target_addr}:${target_port}\"\nlisten_transport = \"${listen_transport}\"" >> ${REALM_CONFIG_PATH}
    
    echo -e "${G_GREEN}WSS 隧道中转端配置添加成功！${NC}"
    echo
    echo "=== 中转端配置摘要 ==="
    echo "监听端口: [::]:${listen_port}"
    echo "转发目标: ${target_addr}:${target_port}"
    echo "域名: ${domain}"
    echo "WebSocket路径: ${ws_path}"
    echo "SSL证书: ${cert_path}"
    echo "========================"
    echo
    echo -e "${G_YELLOW}请记录以下信息，配置落地端时需要：${NC}"
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo '请手动获取')
    echo "- 中转端公网IP: ${server_ip}"
    echo "- 监听端口: ${listen_port}"
    echo "- 域名: ${domain}"
    echo "- WebSocket路径: ${ws_path}"
    
    restart_realm
}

# 3.2 配置 WSS 隧道落地端 (A端服务器)
add_wss_tunnel_landing_side() {
    echo "配置 WSS 隧道落地端 (A端服务器):"
    echo "------------------------------------------------------------"
    echo -e "${G_YELLOW}注意: 需要中转端的连接信息！${NC}"
    echo
    
    read -p "本地监听端口 (例如 12345): " listen_port
    read -p "中转端公网IP地址: " remote_ip
    read -p "中转端监听端口 (例如 54321): " remote_port
    read -p "域名 (与中转端相同): " domain
    read -p "WebSocket路径 (与中转端相同，例如 /somepath): " ws_path
    
    # 参数验证
    if [[ -z "$listen_port" || -z "$remote_ip" || -z "$remote_port" || -z "$domain" || -z "$ws_path" ]]; then 
        echo -e "${G_RED}错误: 所有参数都不能为空。${NC}"
        return
    fi
    
    # 验证端口格式
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 本地监听端口无效。${NC}"
        return
    fi
    
    if ! [[ "$remote_port" =~ ^[0-9]+$ && "$remote_port" -ge 1 && "$remote_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 远程端口无效。${NC}"
        return
    fi
    
    # 验证IP地址格式（简单验证）
    if ! [[ "$remote_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${G_YELLOW}警告: IP地址格式可能无效，请确认输入正确。${NC}"
    fi
    
    # 验证域名格式
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    # 检查端口是否已存在
    if grep -q "listen = \".*:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then 
        echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在。${NC}"
        return
    fi
    
    # 构建配置
    local remote_transport="wss;host=${domain};path=${ws_path};sni=${domain}"
    
    # 添加配置
    echo -e "\n[[endpoints]]\nlisten = \"[::]:${listen_port}\"\nremote = \"${remote_ip}:${remote_port}\"\nremote_transport = \"${remote_transport}\"" >> ${REALM_CONFIG_PATH}
    
    echo -e "${G_GREEN}WSS 隧道落地端配置添加成功！${NC}"
    echo
    echo "=== 落地端配置摘要 ==="
    echo "本地监听: [::]:${listen_port}"
    echo "中转端地址: ${remote_ip}:${remote_port}"
    echo "域名: ${domain}"
    echo "WebSocket路径: ${ws_path}"
    echo "========================"
    
    restart_realm
}

# 3.3 显示 WSS 隧道配置示例
show_wss_tunnel_examples() {
    echo "WSS 隧道配置示例:"
    echo "============================================================"
    echo
    echo -e "${G_GREEN}中转端 (B端服务器) 配置示例:${NC}"
    echo "[[endpoints]]"
    echo "listen = \"[::]:54321\""
    echo "remote = \"127.0.0.1:12345\""
    echo "listen_transport = \"wss;host=yourdomain.com;path=/somepath;cert=/etc/realm/ssl/yourdomain.com/fullchain.pem;key=/etc/realm/ssl/yourdomain.com/privkey.pem\""
    echo
    echo -e "${G_GREEN}落地端 (A端服务器) 配置示例:${NC}"
    echo "[[endpoints]]"
    echo "listen = \"[::]:12345\""
    echo "remote = \"B端公网IP:54321\""
    echo "remote_transport = \"wss;host=yourdomain.com;path=/somepath;sni=yourdomain.com\""
    echo
    echo "============================================================"
    echo -e "${G_YELLOW}配置要点:${NC}"
    echo "1. 中转端需要域名和SSL证书"
    echo "2. host、path、sni 参数必须在两端保持一致"
    echo "3. 不要使用 insecure 参数，确保安全性"
    echo "4. 域名必须解析到中转端服务器IP"
    echo "5. 中转端先配置并启动，再配置落地端"
    echo
    echo -e "${G_YELLOW}部署流程:${NC}"
    echo "第一步: 在中转端服务器申请SSL证书"
    echo "第二步: 配置中转端WSS隧道"
    echo "第三步: 配置落地端WSS隧道"
    echo "第四步: 分别启动两端服务"
}

# 2.1 添加 TCP 转发规则
add_tcp_rule() {
    echo "请输入要添加的 TCP 转发规则信息:"
    read -p "本地监听端口 (例如 54000): " listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 443): " remote_port

    if [[ -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then 
        echo -e "${G_RED}错误: 任何一项均不能为空。${NC}"
        return
    fi
    
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 本地监听端口无效。${NC}"
        return
    fi
    
    if ! [[ "$remote_port" =~ ^[0-9]+$ && "$remote_port" -ge 1 && "$remote_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 远程目标端口无效。${NC}"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then 
        echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在。${NC}"
        return
    fi
    
    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then 
        echo -e "${G_YELLOW}检测到IPv6地址，将自动添加括号。${NC}"
        formatted_remote_addr="[${remote_addr}]"
    else 
        formatted_remote_addr="${remote_addr}"
    fi
    
    local final_remote_str="${formatted_remote_addr}:${remote_port}"
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"" >> ${REALM_CONFIG_PATH}
    echo -e "${G_GREEN}TCP 转发规则添加成功！${NC}"
    restart_realm
}

# 2.2 添加 WS 转发规则
add_ws_rule() {
    echo "请输入要添加的 WebSocket 转发规则信息:"
    read -p "本地监听端口 (例如 8080): " listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 80): " remote_port
    read -p "WebSocket 路径 (例如 /ws, 默认为 /): " ws_path
    
    ws_path=${ws_path:-"/"}
    
    if [[ -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then 
        echo -e "${G_RED}错误: 端口和地址不能为空。${NC}"
        return
    fi
    
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 本地监听端口无效。${NC}"
        return
    fi
    
    if ! [[ "$remote_port" =~ ^[0-9]+$ && "$remote_port" -ge 1 && "$remote_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 远程目标端口无效。${NC}"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then 
        echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在。${NC}"
        return
    fi
    
    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then 
        formatted_remote_addr="[${remote_addr}]"
    else 
        formatted_remote_addr="${remote_addr}"
    fi
    
    local final_remote_str="${formatted_remote_addr}:${remote_port}"
    
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"\nprotocol = \"ws\"\npath = \"${ws_path}\"" >> ${REALM_CONFIG_PATH}
    echo -e "${G_GREEN}WebSocket 转发规则添加成功！${NC}"
    restart_realm
}

# 2.3 添加 WSS 转发规则 (需要手动提供证书)
add_wss_rule() {
    echo "请输入要添加的 WebSocket Secure 转发规则信息:"
    read -p "域名 (例如 example.com): " domain
    read -p "本地监听端口 (例如 443): " listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 80): " remote_port
    read -p "WebSocket 路径 (例如 /ws, 默认为 /): " ws_path
    
    ws_path=${ws_path:-"/"}
    
    if [[ -z "$domain" || -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then 
        echo -e "${G_RED}错误: 域名、端口和地址不能为空。${NC}"
        return
    fi
    
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 本地监听端口无效。${NC}"
        return
    fi
    
    if ! [[ "$remote_port" =~ ^[0-9]+$ && "$remote_port" -ge 1 && "$remote_port" -le 65535 ]]; then 
        echo -e "${G_RED}错误: 远程目标端口无效。${NC}"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then 
        echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在。${NC}"
        return
    fi
    
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    local cert_path="${cert_dir}/fullchain.pem"
    local key_path="${cert_dir}/privkey.pem"
    
    # 检查证书是否存在
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        echo -e "${G_YELLOW}警告: 域名 ${domain} 的 SSL 证书不存在。${NC}"
        echo -e "${G_YELLOW}请先使用证书管理功能申请或上传证书。${NC}"
        echo -e "${G_YELLOW}证书文件应位于: ${cert_path}${NC}"
        echo -e "${G_YELLOW}私钥文件应位于: ${key_path}${NC}"
        echo
        read -p "是否继续创建 WSS 规则？(证书不存在时服务可能无法启动) (y/n): " confirm_continue
        if [[ "${confirm_continue}" != "y" && "${confirm_continue}" != "Y" ]]; then
            echo "操作已取消。请先配置 SSL 证书。"
            return
        fi
        # 创建证书目录
        mkdir -p "${cert_dir}"
    else
        echo -e "${G_GREEN}检测到域名 ${domain} 的 SSL 证书存在，继续创建 WSS 规则...${NC}"
    fi
    
    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then 
        formatted_remote_addr="[${remote_addr}]"
    else 
        formatted_remote_addr="${remote_addr}"
    fi
    
    local final_remote_str="${formatted_remote_addr}:${remote_port}"
    
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"\nprotocol = \"wss\"\npath = \"${ws_path}\"\ndomain = \"${domain}\"\ntls_cert = \"${cert_path}\"\ntls_key = \"${key_path}\"" >> ${REALM_CONFIG_PATH}
    echo -e "${G_GREEN}WebSocket Secure 转发规则添加成功！${NC}"
    echo -e "${G_YELLOW}提示: 请确保域名 ${domain} 正确解析到本服务器。${NC}"
    
    # 显示配置摘要
    echo
    echo "=== WSS 转发规则配置摘要 ==="
    echo "域名: ${domain}"
    echo "监听端口: ${listen_port}"
    echo "转发目标: ${final_remote_str}"
    echo "WebSocket 路径: ${ws_path}"
    echo "SSL 证书: ${cert_path}"
    echo "SSL 私钥: ${key_path}"
    echo "=========================="
    
    restart_realm
}

# 4. 删除转发规则
delete_rule() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装。${NC}"
        return
    fi
    
    # 获取完整的规则信息，包括所有配置项
    local -a all_rules=()
    local current_rule=""
    local rule_index=0
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        if [[ "$line" == "[[endpoints]]" ]]; then
            if [[ -n "$current_rule" ]]; then
                all_rules+=("$current_rule")
                ((rule_index++))
            fi
            current_rule="[[endpoints]]"$'\n'
        elif [[ -n "$current_rule" && "$line" =~ ^[a-zA-Z_]+ ]]; then
            current_rule+="$line"$'\n'
        fi
    done < "${REALM_CONFIG_PATH}"
    
    # 添加最后一个规则
    if [[ -n "$current_rule" ]]; then
        all_rules+=("$current_rule")
    fi

    if [[ ${#all_rules[@]} -eq 0 ]]; then 
        echo -e "${G_YELLOW}当前没有任何转发规则可供删除。${NC}"
        return
    fi

    echo "当前存在的转发规则如下:"
    show_rules true
    echo
    
    read -p "请输入要删除的规则序号 (可输入多个, 用空格或逗号隔开): " user_input
    user_input=${user_input//,/' '}
    read -ra to_delete_indices <<< "$user_input"
    
    if [[ ${#to_delete_indices[@]} -eq 0 ]]; then 
        echo -e "${G_YELLOW}未输入任何序号，操作已取消。${NC}"
        return
    fi

    local -a valid_indices_to_delete
    local -a rules_to_delete_summary
    local max_index=${#all_rules[@]}
    
    for index_str in "${to_delete_indices[@]}"; do
        if ! [[ "$index_str" =~ ^[1-9][0-9]*$ && "$index_str" -le "$max_index" ]]; then 
            echo -e "${G_RED}错误: 输入的序号 '${index_str}' 无效或超出范围 (1-${max_index})。${NC}"
            return
        fi
        
        local index=$((index_str))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${index} " ]]; then
            valid_indices_to_delete+=("$index")
            
            # 从规则中提取监听和远程信息用于显示
            local rule_content="${all_rules[$((index - 1))]}"
            local listen_info=$(echo "$rule_content" | grep -o 'listen = "[^"]*"' | sed 's/listen = "\(.*\)"/\1/')
            local remote_info=$(echo "$rule_content" | grep -o 'remote = "[^"]*"' | sed 's/remote = "\(.*\)"/\1/')
            rules_to_delete_summary+=("- 规则 #${index}: ${listen_info} -> ${remote_info}")
        fi
    done

    if [[ ${#valid_indices_to_delete[@]} -eq 0 ]]; then 
        echo -e "${G_YELLOW}未选择任何有效规则，操作已取消。${NC}"
        return
    fi

    echo
    echo "您选择了删除以下规则:"
    for summary in "${rules_to_delete_summary[@]}"; do 
        echo "  $summary"
    done
    
    echo -e "\n${G_YELLOW}警告：此操作不可逆！${NC}"
    read -p "确认删除吗? (y/n): " confirm
    
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then 
        echo "操作已取消。"
        return
    fi
    
    # 停止 Realm 服务以释放端口
    echo "正在停止 Realm 服务以释放端口..."
    systemctl stop realm 2>/dev/null || true
    sleep 2
    
    # 创建新的配置文件
    local temp_config_file=$(mktemp)
    
    # 保留日志配置部分
    awk '/\[log\]/{p=1} p && !/\[\[endpoints\]\]/{print} /\[\[endpoints\]\]/{p=0}' "${REALM_CONFIG_PATH}" > "${temp_config_file}"
    
    # 添加未被删除的规则
    for i in "${!all_rules[@]}"; do
        local current_index=$((i + 1))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${current_index} " ]]; then
            echo "" >> "${temp_config_file}"
            echo "${all_rules[$i]}" >> "${temp_config_file}"
        fi
    done
    
    # 替换原配置文件
    mv "${temp_config_file}" "${REALM_CONFIG_PATH}"
    
    # 如果没有任何规则，添加注释说明
    if ! grep -q "\[\[endpoints\]\]" "${REALM_CONFIG_PATH}" 2>/dev/null; then 
        echo -e "\n# 所有规则已删除。为确保服务能正常启动，已添加以下占位符。\n#[[endpoints]]\n#listen = \"0.0.0.0:10000\"\n#remote = \"127.0.0.1:10000\"" >> "${REALM_CONFIG_PATH}"
    fi
    
    # 检查并清理可能占用端口的进程
    for index in "${valid_indices_to_delete[@]}"; do
        local rule_content="${all_rules[$((index - 1))]}"
        local listen_port=$(echo "$rule_content" | grep -o 'listen = "[^"]*"' | sed 's/.*:\([0-9]*\)".*/\1/')
        if [[ -n "$listen_port" ]]; then
            echo "正在检查端口 ${listen_port} 的占用情况..."
            local pid=$(lsof -ti:${listen_port} 2>/dev/null || netstat -tlnp 2>/dev/null | grep ":${listen_port} " | awk '{print $7}' | cut -d'/' -f1)
            if [[ -n "$pid" && "$pid" != "-" ]]; then
                echo "发现端口 ${listen_port} 被进程 ${pid} 占用，正在终止..."
                kill -9 $pid 2>/dev/null || true
                sleep 1
            fi
        fi
    done
    
    IFS=$'\n' sorted_indices=($(sort -n <<<"${valid_indices_to_delete[*]}"))
    unset IFS
    echo
    echo "规则 #${sorted_indices[*]} 已被删除，相关端口已释放。"
    
    # 重新启动服务
    restart_realm
}

# 5. 显示已有转发规则
show_rules() {
    local is_delete_mode=${1:-false}
    if ! $is_delete_mode; then 
        if ! check_installation; then 
            echo -e "${G_RED}错误: Realm 未安装。${NC}"
            return
        fi
        echo "当前存在的转发规则如下:"
    fi
    
    local rules_found=false
    echo "+--------+--------------------------+-----------------------------------+----------+"
    printf "| %-6s | %-24s | %-33s | %-8s |\n" "序号" "本地监听" "远程目标" "协议"
    echo "+--------+--------------------------+-----------------------------------+----------+"
    
    local index=1
    local listen_addr=""
    local remote_addr=""
    local protocol="TCP"
    local domain=""
    local listen_transport=""
    local remote_transport=""
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        if [[ "$line" == "[[endpoints]]" ]]; then
            if [[ -n "$listen_addr" && -n "$remote_addr" ]]; then
                local display_protocol="$protocol"
                
                # 检查是否为 WSS 隧道配置
                if [[ -n "$listen_transport" && "$listen_transport" =~ wss ]]; then
                    if [[ "$listen_transport" =~ host=([^;]+) ]]; then
                        local host="${BASH_REMATCH[1]}"
                        display_protocol="WSS隧道-中转(${host})"
                    else
                        display_protocol="WSS隧道-中转"
                    fi
                elif [[ -n "$remote_transport" && "$remote_transport" =~ wss ]]; then
                    if [[ "$remote_transport" =~ host=([^;]+) ]]; then
                        local host="${BASH_REMATCH[1]}"
                        display_protocol="WSS隧道-落地(${host})"
                    else
                        display_protocol="WSS隧道-落地"
                    fi
                elif [[ -n "$domain" && "$protocol" == "wss" ]]; then
                    display_protocol="WSS($domain)"
                elif [[ "$protocol" == "ws" ]]; then
                    display_protocol="WS"
                fi
                
                printf "| %-6d | %-24s | %-33s | %-8s |\n" "$index" "$listen_addr" "$remote_addr" "$display_protocol"
                rules_found=true
                ((index++))
            fi
            listen_addr=""
            remote_addr=""
            protocol="TCP"
            domain=""
            listen_transport=""
            remote_transport=""
        elif [[ "$line" =~ ^listen[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            listen_addr="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^remote[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            remote_addr="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^protocol[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            protocol="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^domain[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            domain="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^listen_transport[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            listen_transport="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^remote_transport[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            remote_transport="${BASH_REMATCH[1]}"
        fi
    done < "${REALM_CONFIG_PATH}"
    
    if [[ -n "$listen_addr" && -n "$remote_addr" ]]; then
        local display_protocol="$protocol"
        
        # 检查是否为 WSS 隧道配置
        if [[ -n "$listen_transport" && "$listen_transport" =~ wss ]]; then
            if [[ "$listen_transport" =~ host=([^;]+) ]]; then
                local host="${BASH_REMATCH[1]}"
                display_protocol="WSS隧道-中转(${host})"
            else
                display_protocol="WSS隧道-中转"
            fi
        elif [[ -n "$remote_transport" && "$remote_transport" =~ wss ]]; then
            if [[ "$remote_transport" =~ host=([^;]+) ]]; then
                local host="${BASH_REMATCH[1]}"
                display_protocol="WSS隧道-落地(${host})"
            else
                display_protocol="WSS隧道-落地"
            fi
        elif [[ -n "$domain" && "$protocol" == "wss" ]]; then
            display_protocol="WSS($domain)"
        elif [[ "$protocol" == "ws" ]]; then
            display_protocol="WS"
        fi
        
        printf "| %-6d | %-24s | %-33s | %-8s |\n" "$index" "$listen_addr" "$remote_addr" "$display_protocol"
        rules_found=true
    fi

    if ! $rules_found; then
        printf "| %-78s |\n" " (当前无任何转发规则)"
    fi
    echo "+--------+--------------------------+-----------------------------------+----------+"
}

# 6. Realm 服务管理
manage_service() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装。${NC}"
        return
    fi
    
    echo "请选择要执行的操作:"
    echo " 1) 启动 Realm"
    echo " 2) 停止 Realm"
    echo " 3) 重启 Realm"
    echo " 4) 查看状态和日志"
    echo " 5) 设置开机自启"
    echo " 6) 取消开机自启"
    read -p "请输入选项 [1-6]: " service_choice
    
    case ${service_choice} in
        1)
            echo "正在启动 Realm..."
            systemctl start realm
            sleep 1
            if systemctl is-active --quiet realm; then 
                echo -e "${G_GREEN}Realm 已成功启动。${NC}"
            else 
                echo -e "${G_RED}Realm 启动失败！${NC}"
                journalctl -n 10 -u realm --no-pager
            fi
            ;;
        2)
            echo "正在停止 Realm..."
            systemctl stop realm
            echo "Realm 已停止。"
            ;;
        3) restart_realm ;;
        4) systemctl status realm ;;
        5) 
            systemctl enable realm
            echo "开机自启已设置。"
            ;;
        6) 
            systemctl disable realm
            echo "开机自启已取消。"
            ;;
        *) echo -e "${G_RED}无效选项。${NC}" ;;
    esac
}

# 7. 卸载 realm
uninstall_realm() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装，无需卸载。${NC}"
        return
    fi
    
    read -p "确定要完全卸载 Realm 吗？此操作不可逆！(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then 
        echo "操作已取消。"
        return
    fi
    
    systemctl stop realm
    systemctl disable realm
    rm -f ${REALM_BIN_PATH} ${REALM_SERVICE_PATH}
    rm -rf ${REALM_CONFIG_DIR}
    systemctl daemon-reload
    echo -e "${G_GREEN}Realm 已成功卸载。${NC}"
}

# 重置 acme.sh 账户
reset_acme_account() {
    if ! check_acme_installation; then
        echo -e "${G_RED}错误: acme.sh 未安装。${NC}"
        return
    fi
    
    echo "重置 acme.sh 账户信息"
    echo "------------------------------------------------------------"
    echo -e "${G_YELLOW}警告: 此操作将删除所有现有的 ACME 账户信息！${NC}"
    read -p "确认继续吗？(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "操作已取消。"
        return
    fi
    
    # 删除账户信息
    rm -rf ~/.acme.sh/ca/
    rm -f ~/.acme.sh/account.conf
    
    echo -e "${G_GREEN}ACME 账户信息已重置。${NC}"
    echo "下次申请证书时将重新注册账户。"
}

# 8. SSL 证书管理菜单
ssl_certificate_menu() {
    while true; do
        clear
        echo "---- SSL 证书管理 ----"
        echo
        echo "1. 安装 acme.sh 工具"
        echo "2. 申请 SSL 证书 (Let's Encrypt)"
        echo "3. 查看证书状态"
        echo "4. 续订 SSL 证书"
        echo "5. 删除 SSL 证书"
        echo "6. 上传自定义证书"
        echo "7. 设置自动续订"
        echo "8. 查看续订日志"
        echo "9. 重置 ACME 账户"
        echo "-----------------------------------------"
        echo "0. 返回主菜单"
        echo "-----------------------------------------"
        
        read -p "请输入选项 [0-9]: " ssl_choice
        case ${ssl_choice} in
            1) install_acme_sh ;;
            2) request_ssl_certificate ;;
            3) show_ssl_certificates ;;
            4) renew_ssl_certificate ;;
            5) delete_ssl_certificate ;;
            6) upload_custom_certificate ;;
            7) setup_auto_renew ;;
            8) view_renew_logs ;;
            9) reset_acme_account ;;
            0) break ;;
            *) echo -e "${G_RED}无效输入，请重新输入!${NC}" ;;
        esac
        echo
        read -p "按 Enter 键继续..."
    done
}

# 申请 SSL 证书
request_ssl_certificate() {
    if ! check_acme_installation; then
        echo "检测到 acme.sh 未安装，正在自动安装..."
        if ! install_acme_sh; then
            echo -e "${G_RED}acme.sh 安装失败，无法申请证书。${NC}"
            return
        fi
    fi
    
    echo "请输入要申请 SSL 证书的域名信息:"
    read -p "域名 (例如 example.com): " domain
    
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    case $(check_certificate "$domain") in
        0)
            echo -e "${G_GREEN}域名 ${domain} 已有有效证书。${NC}"
            read -p "是否要重新申请证书？(y/n): " renew_confirm
            if [[ "${renew_confirm}" != "y" && "${renew_confirm}" != "Y" ]]; then
                return
            fi
            ;;
        2)
            echo -e "${G_YELLOW}域名 ${domain} 的证书即将过期，建议重新申请。${NC}"
            ;;
    esac
    
    echo "请选择 CA 提供商:"
    echo " 1) Let's Encrypt (推荐，免费)"
    echo " 2) Buypass (免费)"
    echo " 3) Google Trust Services (免费)"
    read -p "请选择 CA [1-3]: " ca_choice
    
    local ca_server=""
    case $ca_choice in
        1) ca_server="letsencrypt" ;;
        2) ca_server="buypass" ;;
        3) ca_server="google" ;;
        *) 
            echo -e "${G_YELLOW}使用默认 CA: Let's Encrypt${NC}"
            ca_server="letsencrypt"
            ;;
    esac
    
    echo "请选择验证方式:"
    echo " 1) HTTP-01 验证 (需要域名指向本服务器的80端口)"
    echo " 2) DNS-01 验证 (需要手动添加 DNS TXT 记录)"
    read -p "请选择验证方式 [1-2]: " verify_method
    
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    mkdir -p "$cert_dir"
    
    echo "正在申请 SSL 证书..."
    echo "------------------------------------------------------------"
    
    # 设置 CA 服务器
    echo "正在设置 CA 服务器为: ${ca_server}"
    if ! ${ACME_SH_PATH} --set-default-ca --server ${ca_server}; then
        echo -e "${G_YELLOW}警告: CA 服务器设置可能失败，继续使用默认设置...${NC}"
    fi
    
    case $verify_method in
        1)
            echo "使用 HTTP-01 验证方式申请证书..."
            echo "请确保："
            echo "1. 域名 ${domain} 已正确解析到本服务器"
            echo "2. 服务器的80端口未被占用"
            echo "3. 防火墙允许80端口访问"
            echo
            
            # 检查80端口是否被占用
            if netstat -tlnp 2>/dev/null | grep -q ":80 " || ss -tlnp 2>/dev/null | grep -q ":80 "; then
                echo -e "${G_YELLOW}警告: 检测到80端口被占用，尝试停止可能冲突的服务...${NC}"
                # 尝试停止常见的Web服务
                for service in nginx apache2 httpd; do
                    if systemctl is-active --quiet $service 2>/dev/null; then
                        echo "正在临时停止 $service 服务..."
                        systemctl stop $service
                        sleep 2
                    fi
                done
            fi
            
            # 检查账户是否已注册，如果没有则先注册
            echo "正在检查 ACME 账户状态..."
            if ! ${ACME_SH_PATH} --list 2>/dev/null | grep -q "Main_Domain"; then
                echo "正在注册 ACME 账户..."
                local reg_email="admin@example.com"
                read -p "请输入用于注册的邮箱地址 (默认: ${reg_email}): " user_reg_email
                if [[ -n "$user_reg_email" && "$user_reg_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    reg_email="$user_reg_email"
                fi
                
                if ! ${ACME_SH_PATH} --register-account -m "$reg_email"; then
                    echo -e "${G_YELLOW}账户注册可能失败，但继续尝试申请证书...${NC}"
                fi
            fi
            
            echo "正在申请证书..."
            if ${ACME_SH_PATH} --issue -d "$domain" --standalone --httpport 80 --force; then
                echo "证书申请成功，正在安装证书..."
                if ${ACME_SH_PATH} --install-cert -d "$domain" \
                    --cert-file "${cert_dir}/cert.pem" \
                    --key-file "${cert_dir}/privkey.pem" \
                    --fullchain-file "${cert_dir}/fullchain.pem" \
                    --reloadcmd "systemctl reload realm 2>/dev/null || true"; then
                    echo -e "${G_GREEN}SSL 证书申请并安装成功！${NC}"
                    echo "证书路径: ${cert_dir}"
                    
                    # 重启之前停止的服务
                    for service in nginx apache2 httpd; do
                        if systemctl is-enabled --quiet $service 2>/dev/null; then
                            echo "正在重启 $service 服务..."
                            systemctl start $service 2>/dev/null || true
                        fi
                    done
                else
                    echo -e "${G_RED}证书安装失败。${NC}"
                fi
            else
                echo -e "${G_RED}证书申请失败！${NC}"
                echo "可能的原因："
                echo "1. 域名解析不正确 - 请确保域名指向本服务器IP"
                echo "2. 80端口被占用或无法访问 - 请检查防火墙设置"
                echo "3. 邮箱地址格式问题 - 请使用有效的邮箱地址"
                echo "4. 网络连接问题 - 请检查服务器网络连接"
                echo "5. CA 服务器问题 - 可以尝试更换其他 CA 提供商"
                
                # 显示详细错误信息
                echo
                echo "详细错误信息请查看："
                echo "journalctl -u acme.sh --no-pager -n 20"
                
                # 重启之前停止的服务
                for service in nginx apache2 httpd; do
                    if systemctl is-enabled --quiet $service 2>/dev/null; then
                        systemctl start $service 2>/dev/null || true
                    fi
                done
            fi
            ;;
        2)
            echo "使用 DNS-01 验证方式申请证书..."
            echo "开始 DNS 验证流程..."
            
            # 检查账户是否已注册
            echo "正在检查 ACME 账户状态..."
            if ! ${ACME_SH_PATH} --list 2>/dev/null | grep -q "Main_Domain"; then
                echo "正在注册 ACME 账户..."
                local reg_email="admin@example.com"
                read -p "请输入用于注册的邮箱地址 (默认: ${reg_email}): " user_reg_email
                if [[ -n "$user_reg_email" && "$user_reg_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    reg_email="$user_reg_email"
                fi
                
                if ! ${ACME_SH_PATH} --register-account -m "$reg_email"; then
                    echo -e "${G_YELLOW}账户注册可能失败，但继续尝试申请证书...${NC}"
                fi
            fi
            
            echo "开始 DNS 手动验证模式..."
            if ${ACME_SH_PATH} --issue -d "$domain" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please --force; then
                echo
                echo -e "${G_YELLOW}请按照上述提示添加 DNS TXT 记录到您的域名解析中。${NC}"
                echo -e "${G_YELLOW}记录格式示例：${NC}"
                echo -e "${G_YELLOW}类型: TXT${NC}"
                echo -e "${G_YELLOW}名称: _acme-challenge.${domain}${NC}"
                echo -e "${G_YELLOW}值: (上面显示的长字符串)${NC}"
                echo
                echo -e "${G_YELLOW}添加完成后，请等待几分钟让DNS记录生效，然后按任意键继续...${NC}"
                read -n 1
                echo
                
                echo "正在验证 DNS 记录..."
                if ${ACME_SH_PATH} --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
                    echo "证书申请成功，正在安装证书..."
                    if ${ACME_SH_PATH} --install-cert -d "$domain" \
                        --cert-file "${cert_dir}/cert.pem" \
                        --key-file "${cert_dir}/privkey.pem" \
                        --fullchain-file "${cert_dir}/fullchain.pem" \
                        --reloadcmd "systemctl reload realm 2>/dev/null || true"; then
                        echo -e "${G_GREEN}SSL 证书申请并安装成功！${NC}"
                        echo "证书路径: ${cert_dir}"
                    else
                        echo -e "${G_RED}证书安装失败。${NC}"
                    fi
                else
                    echo -e "${G_RED}DNS 验证失败！${NC}"
                    echo "请检查："
                    echo "1. DNS TXT 记录是否正确添加到域名解析中"
                    echo "2. 记录名称是否为: _acme-challenge.${domain}"
                    echo "3. DNS 记录是否已生效（可使用以下命令检查）："
                    echo "   nslookup -type=TXT _acme-challenge.${domain}"
                    echo "   dig TXT _acme-challenge.${domain}"
                    echo "4. 等待时间是否足够（建议等待5-10分钟）"
                    echo "5. 邮箱地址是否有效"
                fi
            else
                echo -e "${G_RED}DNS 验证初始化失败。${NC}"
                echo "可能的原因："
                echo "1. 邮箱地址格式无效"
                echo "2. 网络连接问题"
                echo "3. CA 服务器问题"
            fi
            ;;
        *)
            echo -e "${G_RED}无效的验证方式选择。${NC}"
            ;;
    esac
    
    echo "------------------------------------------------------------"
}

# 查看 SSL 证书状态
show_ssl_certificates() {
    echo "当前 SSL 证书状态:"
    echo "+---------------------------+------------------+---------------------------+"
    printf "| %-25s | %-16s | %-25s |\n" "域名" "状态" "过期时间"
    echo "+---------------------------+------------------+---------------------------+"
    
    local found_certs=false
    if [[ -d "${SSL_CERT_DIR}" ]]; then
        for cert_dir in "${SSL_CERT_DIR}"/*; do
            if [[ -d "$cert_dir" ]]; then
                local domain=$(basename "$cert_dir")
                local cert_file="${cert_dir}/fullchain.pem"
                
                if [[ -f "$cert_file" ]]; then
                    found_certs=true
                    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                    local status
                    
                    case $(check_certificate "$domain") in
                        0) status="${G_GREEN}有效${NC}" ;;
                        1) status="${G_RED}无效${NC}" ;;
                        2) status="${G_YELLOW}即将过期${NC}" ;;
                    esac
                    
                    printf "| %-25s | %-16s | %-25s |\n" "$domain" "$status" "${expiry_date:-未知}"
                fi
            fi
        done
    fi
    
    if ! $found_certs; then
        printf "| %-69s |\n" " (当前无任何 SSL 证书)"
    fi
    echo "+---------------------------+------------------+---------------------------+"
}

# 续订 SSL 证书
renew_ssl_certificate() {
    if ! check_acme_installation; then
        echo -e "${G_RED}错误: acme.sh 未安装。${NC}"
        return
    fi
    
    echo "请选择要续订的证书:"
    echo " 1) 续订所有证书"
    echo " 2) 续订指定域名证书"
    read -p "请选择操作 [1-2]: " renew_choice
    
    case $renew_choice in
        1)
            echo "正在续订所有证书..."
            if ${ACME_SH_PATH} --cron --home ~/.acme.sh; then
                echo -e "${G_GREEN}所有证书续订完成。${NC}"
                restart_realm
            else
                echo -e "${G_RED}证书续订失败。${NC}"
            fi
            ;;
        2)
            read -p "请输入要续订的域名: " domain
            if ! validate_domain "$domain"; then
                echo -e "${G_RED}错误: 域名格式无效。${NC}"
                return
            fi
            
            echo "正在续订域名 ${domain} 的证书..."
            if ${ACME_SH_PATH} --renew -d "$domain" --force; then
                echo -e "${G_GREEN}域名 ${domain} 证书续订成功。${NC}"
                restart_realm
            else
                echo -e "${G_RED}域名 ${domain} 证书续订失败。${NC}"
            fi
            ;;
        *)
            echo -e "${G_RED}无效选项。${NC}"
            ;;
    esac
}

# 删除 SSL 证书
delete_ssl_certificate() {
    if ! check_acme_installation; then
        echo -e "${G_RED}错误: acme.sh 未安装。${NC}"
        return
    fi
    
    echo "当前已安装的证书:"
    show_ssl_certificates
    echo
    
    read -p "请输入要删除的域名: " domain
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    if [[ ! -d "$cert_dir" ]]; then
        echo -e "${G_RED}错误: 域名 ${domain} 的证书不存在。${NC}"
        return
    fi
    
    echo -e "${G_YELLOW}警告: 此操作将删除域名 ${domain} 的所有证书文件！${NC}"
    read -p "确认删除吗? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "操作已取消。"
        return
    fi
    
    ${ACME_SH_PATH} --remove -d "$domain" 2>/dev/null
    rm -rf "$cert_dir"
    
    echo -e "${G_GREEN}域名 ${domain} 的证书已成功删除。${NC}"
}

# 上传自定义证书
upload_custom_certificate() {
    echo "上传自定义 SSL 证书"
    echo "------------------------------------------------------------"
    
    read -p "请输入域名: " domain
    if ! validate_domain "$domain"; then
        echo -e "${G_RED}错误: 域名格式无效。${NC}"
        return
    fi
    
    read -p "请输入证书文件路径 (fullchain.pem): " cert_file
    read -p "请输入私钥文件路径 (privkey.pem): " key_file
    
    if [[ ! -f "$cert_file" ]]; then
        echo -e "${G_RED}错误: 证书文件不存在: $cert_file${NC}"
        return
    fi
    
    if [[ ! -f "$key_file" ]]; then
        echo -e "${G_RED}错误: 私钥文件不存在: $key_file${NC}"
        return
    fi
    
    # 验证证书文件
    if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        echo -e "${G_RED}错误: 证书文件格式无效。${NC}"
        return
    fi
    
    # 验证私钥文件
    if ! openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
        echo -e "${G_RED}错误: 私钥文件格式无效。${NC}"
        return
    fi
    
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    mkdir -p "$cert_dir"
    
    # 复制证书文件
    cp "$cert_file" "${cert_dir}/fullchain.pem"
    cp "$key_file" "${cert_dir}/privkey.pem"
    cp "$cert_file" "${cert_dir}/cert.pem"
    
    # 设置权限
    chmod 644 "${cert_dir}/fullchain.pem" "${cert_dir}/cert.pem"
    chmod 600 "${cert_dir}/privkey.pem"
    
    echo -e "${G_GREEN}自定义证书上传成功！${NC}"
    echo "证书路径: ${cert_dir}"
    
    # 显示证书信息
    echo
    echo "证书信息:"
    openssl x509 -in "${cert_dir}/fullchain.pem" -noout -subject -dates
}

# 设置自动续订
setup_auto_renew() {
    echo "设置 SSL 证书自动续订..."
    
    local auto_renew_script="/usr/local/bin/realm-ssl-renew.sh"
    cat > "$auto_renew_script" <<'EOF'
#!/bin/bash

ACME_SH_PATH="/root/.acme.sh/acme.sh"
LOG_FILE="/var/log/realm-ssl-renew.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if [[ -f "$ACME_SH_PATH" ]]; then
    log_message "开始检查证书续订..."
    
    if "$ACME_SH_PATH" --cron --home ~/.acme.sh >> "$LOG_FILE" 2>&1; then
        log_message "证书续订检查完成"
        
        if systemctl is-active --quiet realm; then
            systemctl reload realm
            log_message "Realm 服务已重新加载"
        fi
    else
        log_message "证书续订检查失败"
    fi
else
    log_message "错误: acme.sh 未找到"
fi
EOF
    
    chmod +x "$auto_renew_script"
    
    if crontab -l 2>/dev/null | grep -q "realm-ssl-renew.sh"; then
        echo -e "${G_YELLOW}自动续订任务已存在。${NC}"
        read -p "是否要更新现有任务？(y/n): " update_cron
        if [[ "${update_cron}" != "y" && "${update_cron}" != "Y" ]]; then
            return
        fi
        crontab -l 2>/dev/null | grep -v "realm-ssl-renew.sh" | crontab -
    fi
    
    (crontab -l 2>/dev/null; echo "0 2 * * * $auto_renew_script") | crontab -
    
    echo -e "${G_GREEN}自动续订设置完成！${NC}"
    echo "• 续订脚本: $auto_renew_script"
    echo "• 执行时间: 每天凌晨 2:00"
    echo "• 日志文件: /var/log/realm-ssl-renew.log"
}

# 查看续订日志
view_renew_logs() {
    local log_file="/var/log/realm-ssl-renew.log"
    
    if [[ ! -f "$log_file" ]]; then
        echo -e "${G_YELLOW}续订日志文件不存在。${NC}"
        echo "这可能是因为："
        echo "1. 尚未设置自动续订"
        echo "2. 自动续订尚未执行过"
        return
    fi
    
    echo "最近的 SSL 证书续订日志 (最后20行):"
    echo "------------------------------------------------------------"
    tail -20 "$log_file"
    echo "------------------------------------------------------------"
    echo
    echo "完整日志文件位置: $log_file"
}

# 主菜单
show_menu() {
    clear
    local state_color
    local realm_state
    
    if check_installation; then
        if systemctl is-active --quiet realm; then 
            state_color=${G_GREEN}
            realm_state="运行中"
        else 
            state_color=${G_RED}
            realm_state="已停止"
        fi
    else 
        state_color=${G_YELLOW}
        realm_state="未安装"
    fi
    
    local ssl_status=""
    if check_acme_installation && [[ -d "${SSL_CERT_DIR}" ]]; then
        local cert_count=$(find "${SSL_CERT_DIR}" -name "fullchain.pem" 2>/dev/null | wc -l)
        if [[ $cert_count -gt 0 ]]; then
            ssl_status=" | SSL证书: ${G_GREEN}${cert_count}个${NC}"
        fi
    fi
    
    echo "---- Realm WSS 中转一键管理脚本 (v2.3 证书管理增强版) ----"
    echo " 作者: AiLi1337 | 删除自动申请，增强证书管理"
    echo
    echo "1. 安装 Realm"
    echo "2. 添加转发规则 (TCP/WS/WSS)"
    echo "3. 添加 WSS 隧道配置 (中转/落地)"
    echo "4. 删除转发规则"
    echo "5. 显示已有转发规则"
    echo "6. Realm 服务管理 (启/停/状态/自启)"
    echo "7. 卸载 Realm"
    echo "8. SSL 证书管理"
    echo "-----------------------------------------"
    echo "0. 退出脚本"
    echo "-----------------------------------------"
    echo -e "服务状态: ${state_color}${realm_state}${NC}${ssl_status}"
    echo "-----------------------------------------"
    echo
    echo -e "${G_YELLOW}更新内容:${NC}"
    echo "• 删除 WSS 自动申请证书功能"
    echo "• 增强 SSL 证书管理功能"
    echo "• 支持多种 CA 提供商选择"
    echo "• 支持自定义证书上传"
    echo "• 修复端口占用问题"
}

# 主循环
main() {
    check_root
    while true; do
        show_menu
        read -p "请输入选项 [0-8]: " choice
        case ${choice} in
            1) install_realm ;; 
            2) add_rule ;; 
            3) add_wss_tunnel_rule ;;
            4) delete_rule ;; 
            5) show_rules ;; 
            6) manage_service ;; 
            7) uninstall_realm ;; 
            8) ssl_certificate_menu ;;
            0) exit 0 ;;
            *) echo -e "${G_RED}无效输入，请重新输入!${NC}" ;;
        esac
        echo
        read -p "按 Enter 键返回主菜单..."
    done
}

# 启动脚本
main
