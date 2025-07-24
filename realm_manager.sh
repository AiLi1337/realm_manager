#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 2.2 (WSS Enhanced & Bug Fixed)
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

# WSS 相关全局变量
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

# 安装 acme.sh
install_acme_sh() {
    if check_acme_installation; then
        echo -e "${G_GREEN}acme.sh 已安装，无需重复操作。${NC}"
        return 0
    fi
    
    echo "开始安装 acme.sh 证书管理工具..."
    echo "------------------------------------------------------------"
    
    if ! command -v curl &> /dev/null; then
        echo -e "${G_RED}错误: curl 未安装，请先安装 curl。${NC}"
        return 1
    fi
    
    echo "正在从官方源下载并安装 acme.sh..."
    if curl -fsSL ${ACME_SH_INSTALL_URL} | sh -s email=admin@$(hostname -f) 2>/dev/null; then
        echo -e "${G_GREEN}acme.sh 安装成功！${NC}"
        mkdir -p "${SSL_CERT_DIR}"
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

# 2.3 添加 WSS 转发规则
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
    
    case $(check_certificate "$domain") in
        1)
            echo -e "${G_YELLOW}域名 ${domain} 没有有效的 SSL 证书。${NC}"
            read -p "是否现在申请证书？(y/n): " apply_cert
            if [[ "${apply_cert}" == "y" || "${apply_cert}" == "Y" ]]; then
                if ! check_acme_installation; then
                    echo "正在安装 acme.sh..."
                    if ! install_acme_sh; then
                        echo -e "${G_RED}acme.sh 安装失败，无法申请证书。${NC}"
                        return
                    fi
                fi
                
                echo "正在为域名 ${domain} 申请 SSL 证书..."
                local cert_dir="${SSL_CERT_DIR}/${domain}"
                mkdir -p "$cert_dir"
                
                if ${ACME_SH_PATH} --issue -d "$domain" --standalone --httpport 80; then
                    if ${ACME_SH_PATH} --install-cert -d "$domain" \
                        --cert-file "${cert_dir}/cert.pem" \
                        --key-file "${cert_dir}/privkey.pem" \
                        --fullchain-file "${cert_dir}/fullchain.pem" \
                        --reloadcmd "systemctl reload realm"; then
                        echo -e "${G_GREEN}SSL 证书申请成功！${NC}"
                    else
                        echo -e "${G_RED}证书安装失败，无法创建 WSS 规则。${NC}"
                        return
                    fi
                else
                    echo -e "${G_RED}证书申请失败，无法创建 WSS 规则。${NC}"
                    return
                fi
            else
                echo -e "${G_YELLOW}没有有效证书，无法创建 WSS 规则。${NC}"
                return
            fi
            ;;
        2)
            echo -e "${G_YELLOW}域名 ${domain} 的证书即将过期，建议先续订证书。${NC}"
            ;;
    esac
    
    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then 
        formatted_remote_addr="[${remote_addr}]"
    else 
        formatted_remote_addr="${remote_addr}"
    fi
    
    local final_remote_str="${formatted_remote_addr}:${remote_port}"
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"\nprotocol = \"wss\"\npath = \"${ws_path}\"\ndomain = \"${domain}\"\ntls_cert = \"${cert_dir}/fullchain.pem\"\ntls_key = \"${cert_dir}/privkey.pem\"" >> ${REALM_CONFIG_PATH}
    echo -e "${G_GREEN}WebSocket Secure 转发规则添加成功！${NC}"
    echo -e "${G_YELLOW}提示: 请确保域名 ${domain} 正确解析到本服务器。${NC}"
    restart_realm
}

# 3. 删除转发规则
delete_rule() {
    if ! check_installation; then 
        echo -e "${G_RED}错误: Realm 未安装。${NC}"
        return
    fi
    
    local rules_to_display=()
    while IFS="," read -r listen remote; do
        rules_to_display+=("$listen,$remote")
    done < <(paste -d, <(grep 'listen' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/') <(grep 'remote' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/'))

    if [[ ${#rules_to_display[@]} -eq 0 ]]; then 
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
    local max_index=${#rules_to_display[@]}
    
    for index_str in "${to_delete_indices[@]}"; do
        if ! [[ "$index_str" =~ ^[1-9][0-9]*$ && "$index_str" -le "$max_index" ]]; then 
            echo -e "${G_RED}错误: 输入的序号 '${index_str}' 无效或超出范围 (1-${max_index})。${NC}"
            return
        fi
        
        local index=$((index_str))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${index} " ]]; then
            valid_indices_to_delete+=("$index")
            local rule_info="${rules_to_display[$((index - 1))]}"
            local listen_info="${rule_info%,*}"
            local remote_info="${rule_info#*,}"
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
    
    local temp_config_file=$(mktemp)
    awk '/\[log\]/{p=1} p && !/\[\[endpoints\]\]/{print} /\[\[endpoints\]\]/{p=0}' "${REALM_CONFIG_PATH}" > "${temp_config_file}"
    
    for i in "${!rules_to_display[@]}"; do
        local current_index=$((i + 1))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${current_index} " ]]; then
             local rule_info="${rules_to_display[$i]}"
             local listen_info="${rule_info%,*}"
             local remote_info="${rule_info#*,}"
             echo -e "\n[[endpoints]]\nlisten = \"${listen_info}\"\nremote = \"${remote_info}\"" >> "${temp_config_file}"
        fi
    done
    
    mv "${temp_config_file}" "${REALM_CONFIG_PATH}"
    
    if ! grep -q "\[\[endpoints\]\]" "${REALM_CONFIG_PATH}" 2>/dev/null; then 
        echo -e "\n# 所有规则已删除。为确保服务能正常启动，已添加以下占位符。\n#[[endpoints]]\n#listen = \"0.0.0.0:10000\"\n#remote = \"127.0.0.1:10000\"" >> "${REALM_CONFIG_PATH}"
    fi
    
    IFS=$'\n' sorted_indices=($(sort -n <<<"${valid_indices_to_delete[*]}"))
    unset IFS
    echo
    echo "规则 #${sorted_indices[*]} 已被删除。"
    restart_realm
}

# 4. 显示已有转发规则
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
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        if [[ "$line" == "[[endpoints]]" ]]; then
            if [[ -n "$listen_addr" && -n "$remote_addr" ]]; then
                local display_protocol="$protocol"
                if [[ -n "$domain" && "$protocol" == "wss" ]]; then
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
        elif [[ "$line" =~ ^listen[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            listen_addr="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^remote[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            remote_addr="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^protocol[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            protocol="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^domain[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            domain="${BASH_REMATCH[1]}"
        fi
    done < "${REALM_CONFIG_PATH}"
    
    if [[ -n "$listen_addr" && -n "$remote_addr" ]]; then
        local display_protocol="$protocol"
        if [[ -n "$domain" && "$protocol" == "wss" ]]; then
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

# 5. Realm 服务管理
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

# 6. 卸载 realm
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

# 7. SSL 证书申请
request_ssl_certificate() {
    if ! check_installation; then
        echo -e "${G_RED}错误: Realm 未安装，请先安装 Realm。${NC}"
        return
    fi
    
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
    
    echo "请选择验证方式:"
    echo " 1) HTTP-01 验证 (需要域名指向本服务器的80端口)"
    echo " 2) DNS-01 验证 (需要手动添加 DNS TXT 记录)"
    read -p "请选择验证方式 [1-2]: " verify_method
    
    local cert_dir="${SSL_CERT_DIR}/${domain}"
    mkdir -p "$cert_dir"
    
    echo "正在申请 SSL 证书..."
    echo "------------------------------------------------------------"
    
    case $verify_method in
        1)
            if ${ACME_SH_PATH} --issue -d "$domain" --standalone --httpport 80; then
                echo "证书申请成功，正在安装证书..."
                if ${ACME_SH_PATH} --install-cert -d "$domain" \
                    --cert-file "${cert_dir}/cert.pem" \
                    --key-file "${cert_dir}/privkey.pem" \
                    --fullchain-file "${cert_dir}/fullchain.pem" \
                    --reloadcmd "systemctl reload realm"; then
                    echo -e "${G_GREEN}SSL 证书申请并安装成功！${NC}"
                    echo "证书路径: ${cert_dir}"
                else
                    echo -e "${G_RED}证书安装失败。${NC}"
                fi
            else
                echo -e "${G_RED}证书申请失败，请检查域名解析和网络连接。${NC}"
            fi
            ;;
        2)
            echo "开始 DNS 验证流程..."
            if ${ACME_SH_PATH} --issue -d "$domain" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
                echo -e "${G_YELLOW}请按照上述提示添加 DNS TXT 记录，然后按任意键继续...${NC}"
                read -n 1
                if ${ACME_SH_PATH} --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
                    echo "证书申请成功，正在安装证书..."
                    if ${ACME_SH_PATH} --install-cert -d "$domain" \
                        --cert-file "${cert_dir}/cert.pem" \
                        --key-file "${cert_dir}/privkey.pem" \
                        --fullchain-file "${cert_dir}/fullchain.pem" \
                        --reloadcmd "systemctl reload realm"; then
                        echo -e "${G_GREEN}SSL 证书申请并安装成功！${NC}"
                        echo "证书路径: ${cert_dir}"
                    else
                        echo -e "${G_RED}证书安装失败。${NC}"
                    fi
                else
                    echo -e "${G_RED}DNS 验证失败，请检查 DNS 记录是否正确添加。${NC}"
                fi
            else
                echo -e "${G_RED}DNS 验证初始化失败。${NC}"
            fi
            ;;
        *)
            echo -e "${G_RED}无效的验证方式选择。${NC}"
            ;;
    esac
    
    echo "------------------------------------------------------------"
}

# 8. 查看 SSL 证书状态
show_ssl_certificates() {
    if ! check_acme_installation; then
        echo -e "${G_YELLOW}acme.sh 未安装，无法查看证书状态。${NC}"
        return
    fi
    
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

# 9. 续订 SSL 证书
renew_ssl_certificate() {
    if ! check_acme_installation; then
        echo -e "${G_RED}错误: acme.sh 未安装。${NC}"
        return
    fi
    
    echo "请选择要续订的证书:"
    echo " 1) 续订所有证书"
    echo " 2) 续订指定域名证书"
    echo " 3) 设置自动续订"
    read -p "请选择操作 [1-3]: " renew_choice
    
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
        3)
            setup_auto_renew
            ;;
        *)
            echo -e "${G_RED}无效选项。${NC}"
            ;;
    esac
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

# SSL 证书管理菜单
ssl_certificate_menu() {
    while true; do
        clear
        echo "---- SSL 证书管理 ----"
        echo
        echo "1. 申请 SSL 证书"
        echo "2. 查看证书状态"
        echo "3. 续订 SSL 证书"
        echo "4. 删除 SSL 证书"
        echo "5. 安装 acme.sh"
        echo "6. 查看续订日志"
        echo "-----------------------------------------"
        echo "0. 返回主菜单"
        echo "-----------------------------------------"
        
        read -p "请输入选项 [0-6]: " ssl_choice
        case ${ssl_choice} in
            1) request_ssl_certificate ;;
            2) show_ssl_certificates ;;
            3) renew_ssl_certificate ;;
            4) delete_ssl_certificate ;;
            5) install_acme_sh ;;
            6) view_renew_logs ;;
            0) break ;;
            *) echo -e "${G_RED}无效输入，请重新输入!${NC}" ;;
        esac
        echo
        read -p "按 Enter 键继续..."
    done
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
    
    echo "---- Realm WSS 中转一键管理脚本 (v2.2) ----"
    echo " 作者: AiLi1337 | WSS增强版"
    echo
    echo "1. 安装 Realm"
    echo "2. 添加转发规则 (TCP/WS/WSS)"
    echo "3. 删除转发规则"
    echo "4. 显示已有转发规则"
    echo "5. Realm 服务管理 (启/停/状态/自启)"
    echo "6. 卸载 Realm"
    echo "7. SSL 证书管理"
    echo "-----------------------------------------"
    echo "0. 退出脚本"
    echo "-----------------------------------------"
    echo -e "服务状态: ${state_color}${realm_state}${NC}${ssl_status}"
    echo "-----------------------------------------"
    echo
    echo -e "${G_YELLOW}WSS 功能说明:${NC}"
    echo "• 支持 WebSocket Secure (WSS) 加密转发"
    echo "• 自动化 Let's Encrypt SSL 证书管理"
    echo "• 兼容原有 TCP 和 WebSocket 转发功能"
}

# 主循环
main() {
    check_root
    while true; do
        show_menu
        read -p "请输入选项 [0-7]: " choice
        case ${choice} in
            1) install_realm ;; 
            2) add_rule ;; 
            3) delete_rule ;; 
            4) show_rules ;; 
            5) manage_service ;; 
            6) uninstall_realm ;; 
            7) ssl_certificate_menu ;;
            0) exit 0 ;;
            *) echo -e "${G_RED}无效输入，请重新输入!${NC}" ;;
        esac
        echo
        read -p "按 Enter 键返回主菜单..."
    done
}

# 启动脚本
main
