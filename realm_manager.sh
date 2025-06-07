#!/bin/bash

#=================================================
#	System Required: Centos 7+/Debian 8+/Ubuntu 16+
#	Description: realm All-in-one script (GitHub International Version)
#	Version: 2.7-github (Live Status Display)
#	Author: AiLi1337
#=================================================

sh_ver="2.7-github"
config_file="/etc/realm/config.json"
service_file="/etc/systemd/system/realm.service"

#--- Helper Functions ---#
check_root(){
	[[ $EUID -ne 0 ]] && echo -e "错误: 必须使用root用户运行此脚本！\n" && exit 1
}

check_arch() {
    case $(uname -m) in
        "x86_64") arch="x86_64" ;;
        "aarch64") arch="aarch64" ;;
        *) echo "错误: 不支持的架构 $(uname -m)"; exit 1 ;;
    esac
}

check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "依赖工具 jq 未安装，正在尝试自动安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        fi
        if ! command -v jq &> /dev/null; then
            echo "错误：jq 自动安装失败，请手动安装后重试。"
            return 1
        fi
    fi
    return 0
}

prompt_for_restart() {
    read -p "配置已修改，是否立即重启 realm 服务以应用新规则? (y/n): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        echo "正在重启 realm..."
        systemctl restart realm
        echo "realm 重启完成。"
    else
        echo "操作已取消。请记得稍后手动重启 realm。"
    fi
}

get_realm_status_string() {
    local green="\033[0;32m"
    local red="\033[0;31m"
    local yellow="\033[0;33m"
    local reset="\033[0m"

    if [ ! -f "$service_file" ]; then
        echo -e "${red}未安装${reset}"
        return
    fi

    local status
    status=$(systemctl is-active realm.service)
    case "$status" in
        "active")
            echo -e "${green}运行中${reset}"
            ;;
        "inactive")
            echo -e "${yellow}已停止${reset}"
            ;;
        "failed")
            echo -e "${red}运行失败${reset}"
            ;;
        *)
            echo -e "${yellow}状态未知 (${status})${reset}"
            ;;
    esac
}

#--- Core Functions ---#
install_realm() {
    check_arch
    local download_url="https://github.com/zhboner/realm/releases/latest/download/realm-$arch-unknown-linux-gnu.tar.gz"
    
    echo "正在从 GitHub 官方源下载 realm..."
    wget --no-check-certificate -O realm.tar.gz "$download_url" || { echo "下载失败!"; exit 1; }
    
    tar -xzf realm.tar.gz
    mv realm /usr/local/bin/realm
    chmod +x /usr/local/bin/realm
    
    mkdir -p /etc/realm
    
    if [ ! -f "$config_file" ]; then
        echo '{"log":{"level":"warn","output":"/var/log/realm.log"},"network":{"no_tcp":false,"use_udp":true},"endpoints":[]}' > "$config_file"
    fi
    
    if [ ! -f "$service_file" ]; then
        echo "[Unit]
Description=realm
After=network-online.target
[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/realm -c $config_file
[Install]
WantedBy=multi-user.target" > "$service_file"
    fi
    
    systemctl daemon-reload
    systemctl enable realm
    systemctl start realm
    
    echo "realm 安装并启动成功！"
    rm -f realm.tar.gz
}

add_forwarding_rule() {
    check_and_install_jq || return 1
    
    read -p "请输入本地监听端口: " local_port
    read -p "请输入远程目标IP或域名: " remote_ip
    read -p "请输入远程目标端口: " remote_port
    
    if [[ -z "$local_port" || -z "$remote_ip" || -z "$remote_port" ]]; then
        echo "错误：输入不能为空！"; return
    fi
    
    local remote_address="${remote_ip}:${remote_port}"
    
    local new_endpoint
    new_endpoint=$(jq -n --arg lp "$local_port" --arg ra "$remote_address" '{listen: "[::]:\($lp)", remote: $ra}')
    
    local tmp_json=$(mktemp)
    jq ".endpoints += [$new_endpoint]" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"
    
    echo "转发规则添加成功！"
    prompt_for_restart
}

delete_forwarding_rule() {
    check_and_install_jq || return 1
    
    echo "--- 当前转发规则 ---"
    jq -r '.endpoints[] | .listen + " -> " + .remote' "$config_file"
    echo "--------------------"
    
    read -p "请输入要删除的规则的【监听端口】(不带冒号): " port_to_delete
    
    if [[ -z "$port_to_delete" ]]; then
        echo "错误：输入不能为空！"; return
    fi
    
    local tmp_json=$(mktemp)
    jq "del(.endpoints[] | select(.listen == \"[::]:$port_to_delete\"))" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"
    
    echo "规则删除成功！"
    prompt_for_restart
}

display_forwarding_rules() {
    if [ ! -f "$config_file" ]; then
        echo "配置文件不存在，请先安装realm或添加一条规则！"
        return
    fi
    check_and_install_jq || return 1
    echo "=================================="
    jq -r '.endpoints[] | "监听: \(.listen)\n转发至: \(.remote)\n选项: \(.options | (if . == null then "无" else tostring end))\n----------------------------------"' "$config_file"
    echo "=================================="
}

manage_realm_service() {
    PS3="请选择操作 (输入数字): "
    select opt in "启动服务" "停止服务" "重启服务" "返回上级"; do
        case $opt in
            "启动服务") systemctl start realm; echo "服务已尝试启动。"; break ;;
            "停止服务") systemctl stop realm; echo "服务已尝试停止。"; break ;;
            "重启服务") systemctl restart realm; echo "服务已尝试重启。"; break ;;
            "返回上级") break ;;
            *) echo "无效选项 $REPLY";;
        esac
    done
}

add_tls_ws_rule() {
    check_and_install_jq || return 1
    echo "--- 添加一个新的 TLS + WebSocket 转发规则 (手动证书) ---"
    
    read -p "请输入 realm 的监听端口 (例如 443): " local_port
    read -p "请输入要转发到的目标IP或域名: " remote_ip
    read -p "请输入要转发到的目标端口: " remote_port
    read -p "请输入您的域名 (用于TLS证书): " domain_name
    read -p "请输入 WebSocket 路径 (以'/'开头, 例如 /ws): " ws_path
    read -p "请输入证书公钥(cert)文件的绝对路径: " cert_path
    read -p "请输入证书私钥(key)文件的绝对路径: " key_path

    if [[ -z "$local_port" || -z "$remote_ip" || -z "$remote_port" || -z "$domain_name" || -z "$ws_path" || -z "$cert_path" || -z "$key_path" ]]; then
        echo "错误：所有选项都不能为空！"; return 1
    fi

    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        echo "错误：找不到证书或私钥文件，请检查路径。"; return 1
    fi

    local remote_address="${remote_ip}:${remote_port}"
    local new_endpoint
    new_endpoint=$(jq -n --arg lp "$local_port" --arg ra "$remote_address" --arg dn "$domain_name" --arg wp "$ws_path" --arg cp "$cert_path" --arg kp "$key_path" \
        '{"listen":"[::]:\($lp)","remote":$ra,"options":{"protocol":"ws","path":$wp,"tls":{"server_name":$dn,"certificates":{"cert_file":$cp,"key_file":$kp}}}}')

    local tmp_json=$(mktemp)
    jq ".endpoints += [$new_endpoint]" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"

    echo "TLS+WS 转发规则已成功添加！"
    prompt_for_restart
}

add_tls_ws_rule_auto() {
    check_and_install_jq || return 1
    echo "--- (全自动证书) 添加一个新的 TLS + WebSocket 转发规则 ---"
    echo "前提: 1. 域名已解析到本服务器IP。 2. 80端口未被占用。"
    
    read -p "请输入 realm 的监听端口 (例如 443): " local_port
    read -p "请输入要转发到的目标IP或域名: " remote_ip
    read -p "请输入要转发到的目标端口: " remote_port
    read -p "请输入您已解析好的域名: " domain_name
    read -p "请输入 WebSocket 路径 (以'/'开头, 例如 /ws): " ws_path

    if [[ -z "$local_port" || -z "$remote_ip" || -z "$remote_port" || -z "$domain_name" || -z "$ws_path" ]]; then
        echo "错误：所有选项都不能为空！"; return 1
    fi

    if [ ! -f "/root/.acme.sh/acme.sh" ]; then
        echo "正在从 GitHub 安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=my@example.com
        if [ $? -ne 0 ]; then echo "acme.sh 安装失败。"; return 1; fi
        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    fi

    echo "正在为域名 ${domain_name} 申请证书..."
    /root/.acme.sh/acme.sh --issue -d "$domain_name" --standalone --force
    if [ $? -ne 0 ]; then echo "证书申请失败，请检查域名解析和80端口。"; return 1; fi

    local cert_path="/root/.acme.sh/${domain_name}_ecc/fullchain.cer"
    local key_path="/root/.acme.sh/${domain_name}_ecc/${domain_name}.key"
    if [ ! -f "$cert_path" ]; then
        cert_path="/root/.acme.sh/${domain_name}/fullchain.cer"
        key_path="/root/.acme.sh/${domain_name}/${domain_name}.key"
    fi
    if [ ! -f "$cert_path" ]; then
        echo "错误：找不到申请好的证书文件，acme.sh 可能出现未知问题。"; return 1;
    fi
    echo "证书申请成功，路径: $cert_path"

    local remote_address="${remote_ip}:${remote_port}"
    echo "正在生成 realm 配置文件..."
    local new_endpoint
    new_endpoint=$(jq -n --arg lp "$local_port" --arg ra "$remote_address" --arg dn "$domain_name" --arg wp "$ws_path" --arg cp "$cert_path" --arg kp "$key_path" \
        '{"listen":"[::]:\($lp)","remote":$ra,"options":{"protocol":"ws","path":$wp,"tls":{"server_name":$dn,"certificates":{"cert_file":$cp,"key_file":$kp}}}}')

    local tmp_json=$(mktemp)
    jq ".endpoints += [$new_endpoint]" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"

    if [ $? -eq 0 ]; then
        echo "新规则已成功添加，配置已自动完成！"
        prompt_for_restart
    else
        echo "写入 realm 配置文件失败！请检查权限。"
    fi
}

show_menu() {
    clear
    local realm_status
    realm_status=$(get_realm_status_string)

    echo -e "
    ---- Realm 中转一键管理脚本 (v${sh_ver}) ----
    作者: AiLi1337

    1. 安装/更新 Realm
    2. 添加转发规则
    3. 删除转发规则
    4. 显示已有转发规则
    5. Realm 服务管理 (启/停/重启)
    6. 添加TLS+WS规则 (手动证书)
    7. 添加TLS+WS规则 (自动证书)
    
    0. 退出脚本
    ---------------------------------------------------
    服务状态: ${realm_status}
    ---------------------------------------------------
    "
    read -p "请输入选项 [0-7]: " choice
}

main() {
    check_root
    while true; do
        show_menu
        case $choice in
            1) install_realm ;;
            2) add_forwarding_rule ;;
            3) delete_forwarding_rule ;;
            4) display_forwarding_rules ;;
            5) manage_realm_service ;;
            6) add_tls_ws_rule ;;
            7) add_tls_ws_rule_auto ;;
            0) exit 0 ;;
            *) echo -e "\n无效输入，请重新输入" ;;
        esac
        echo -e "\n按任意键返回主菜单..."
        read -n 1
    done
}

main