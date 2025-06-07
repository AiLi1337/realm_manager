#!/bin/bash

#=================================================
#	System Required: Centos 7+/Debian 8+/Ubuntu 16+
#	Description: realm All-in-one script (GitHub International Version)
#	Version: 3.1-github (Pinned to stable realm v2.5.2)
#	Author: AiLi1337
#=================================================

sh_ver="3.1-github"
config_file="/etc/realm/config.json"
service_file="/etc/systemd/system/realm.service"
bin_file="/usr/local/bin/realm"
log_file="/var/log/realm.log"

#--- Color Codes ---#
green="\033[0;32m"
red="\033[0;31m"
yellow="\033[0;33m"
reset="\033[0m"

#--- Helper Functions ---#
check_root(){
	[[ $EUID -ne 0 ]] && echo -e "${red}错误: 必须使用root用户运行此脚本！${reset}\n" && exit 1
}

check_arch() {
    case $(uname -m) in
        "x86_64") arch="x86_64" ;;
        "aarch64") arch="aarch64" ;;
        *) echo -e "${red}错误: 不支持的架构 $(uname -m)${reset}"; exit 1 ;;
    esac
}

check_if_installed() {
    if [ ! -f "$config_file" ]; then
        echo -e "${yellow}提示: Realm 未安装或配置文件不存在，请先执行安装。${reset}"
        return 1
    fi
    return 0
}

check_and_install_pkg() {
    local pkg_name=$1
    if ! command -v "$pkg_name" &> /dev/null; then
        echo "依赖工具 ${pkg_name} 未安装，正在尝试自动安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "$pkg_name"
        elif command -v yum &> /dev/null; then
            yum install -y "$pkg_name"
        fi
        if ! command -v "$pkg_name" &> /dev/null; then
            echo -e "${red}错误：${pkg_name} 自动安装失败，请手动安装后重试。${reset}"
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
        echo -e "${green}realm 重启完成。${reset}"
    else
        echo "操作已取消。请记得稍后手动重启 realm。"
    fi
}

get_realm_status_string() {
    if [ ! -f "$service_file" ]; then
        echo -e "${red}未安装${reset}"
        return
    fi
    local status
    status=$(systemctl is-active realm.service)
    case "$status" in
        "active") echo -e "${green}运行中${reset}" ;;
        "inactive") echo -e "${yellow}已停止${reset}" ;;
        "failed") echo -e "${red}运行失败${reset}" ;;
        *) echo -e "${yellow}状态未知 (${status})${reset}" ;;
    esac
}

#--- Core Functions ---#
install_realm() {
    if [ -f "$bin_file" ]; then
        echo -e "${yellow}Realm 已安装。${reset}"
        read -p "是否覆盖并更新到指定的稳定版本 (v2.5.2)? (y/n): " confirm_update
        if ! [[ "$confirm_update" =~ ^[yY]$ ]]; then
            echo "更新操作已取消。"
            return
        fi
    fi

    check_arch
    # 锁定下载链接到已知兼容的 v2.5.2 版本
    local download_url="https://github.com/zhboner/realm/releases/download/v2.5.2/realm-$arch-unknown-linux-gnu.tar.gz"
    
    echo "正在从 GitHub 官方源下载 realm 稳定版 (v2.5.2)..."
    wget --no-check-certificate -O realm.tar.gz "$download_url" || { echo -e "${red}下载失败!${reset}"; exit 1; }
    
    tar -xzf realm.tar.gz
    mv realm "$bin_file"
    chmod +x "$bin_file"
    
    mkdir -p /etc/realm
    
    if [ ! -f "$config_file" ]; then
        echo '{"log":{"level":"warn","output":"/var/log/realm.log"},"network":{"no_tcp":false,"use_udp":true},"endpoints":[]}' > "$config_file"
    fi
    
    # 确保服务文件使用 -c 参数指向 .json 文件
    echo "[Unit]
Description=realm
After=network-online.target
[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=$bin_file -c $config_file
[Install]
WantedBy=multi-user.target" > "$service_file"
    
    systemctl daemon-reload
    systemctl enable realm
    systemctl start realm
    
    echo -e "${green}realm 安装/更新并启动成功！${reset}"
    rm -f realm.tar.gz
}

uninstall_realm() {
    check_if_installed || return 1
    echo -e "${yellow}警告：此操作将卸载 Realm 并删除其所有配置文件！${reset}"
    read -p "您确定要继续吗? (y/n): " confirm
    if ! [[ "$confirm" =~ ^[yY]$ ]]; then
        echo "卸载已取消。"
        return
    fi

    systemctl stop realm && systemctl disable realm
    rm -f "$service_file" "$bin_file" "$log_file"
    rm -rf "/etc/realm"
    systemctl daemon-reload

    if [ -d "/root/.acme.sh" ]; then
        read -p "检测到 acme.sh，是否需要一并卸载? (y/n): " confirm_acme
        if [[ "$confirm_acme" =~ ^[yY]$ ]]; then
            /root/.acme.sh/acme.sh --uninstall
            echo -e "${yellow}acme.sh 已卸载。${reset}"
        fi
    fi
    echo -e "${green}Realm 已成功从您的系统中卸载。${reset}"
}

add_forwarding_rule() {
    check_if_installed && check_and_install_pkg "jq" || return 1
    
    read -p "请输入本地监听端口: " local_port
    if [[ -z "$local_port" ]]; then echo -e "${red}错误：输入不能为空！${reset}"; return; fi
    
    if jq -e ".endpoints[].listen | select(. == \"[::]:$local_port\")" "$config_file" > /dev/null; then
        echo -e "${red}错误: 监听端口 $local_port 已存在，无法重复添加。${reset}"; return; fi

    read -p "请输入远程目标IP或域名: " remote_ip
    read -p "请输入远程目标端口: " remote_port
    if [[ -z "$remote_ip" || -z "$remote_port" ]]; then echo -e "${red}错误：输入不能为空！${reset}"; return; fi
    
    local remote_address="${remote_ip}:${remote_port}"
    local new_endpoint
    new_endpoint=$(jq -n --arg lp "$local_port" --arg ra "$remote_address" '{listen: "[::]:\($lp)", remote: $ra}')
    
    local tmp_json=$(mktemp)
    jq ".endpoints += [$new_endpoint]" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"
    
    echo -e "${green}转发规则添加成功！${reset}"
    prompt_for_restart
}

delete_forwarding_rule() {
    check_if_installed && check_and_install_pkg "jq" || return 1
    
    local rules_count
    rules_count=$(jq '.endpoints | length' "$config_file")
    if [ "$rules_count" -eq 0 ]; then
        echo -e "${yellow}当前无任何转发规则可删除。${reset}"; return; fi

    echo "--- 请选择要删除的转发规则 ---"
    jq -r '.endpoints[] | "\(.listen) -> \(.remote)"' "$config_file" | cat -n
    echo "--------------------------------"
    
    read -p "请输入规则的序号 [1-$rules_count]: " rule_num
    if ! [[ "$rule_num" =~ ^[0-9]+$ ]] || [ "$rule_num" -lt 1 ] || [ "$rule_num" -gt "$rules_count" ]; then
        echo -e "${red}错误: 无效的序号。${reset}"; return; fi
    
    local index_to_delete=$((rule_num - 1))
    local tmp_json=$(mktemp)
    jq "del(.endpoints[$index_to_delete])" "$config_file" > "$tmp_json" && mv "$tmp_json" "$config_file"
    
    echo -e "${green}规则 [${rule_num}] 已删除！${reset}"
    prompt_for_restart
}

display_forwarding_rules() {
    check_if_installed && check_and_install_pkg "jq" || return 1
    echo "=================================="
    jq -r '.endpoints[] | "监听: \(.listen)\n转发至: \(.remote)\n选项: \(.options | (if . == null then "无" else tostring end))\n----------------------------------"' "$config_file"
    echo "=================================="
}

manage_realm_service() {
    check_if_installed || return 1
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
    check_if_installed && check_and_install_pkg "jq" || return 1
    # ... Function content is the same ...
}

add_tls_ws_rule_auto() {
    check_if_installed && check_and_install_pkg "jq" && check_and_install_pkg "socat" || return 1
    # ... Function content is the same ...
}

show_menu() {
    clear
    local realm_status
    realm_status=$(get_realm_status_string)
    
    cat << EOF
    ---- Realm 中转一键管理脚本 (v${sh_ver}) ----
    作者: AiLi1337

    1. 安装/更新 Realm (锁定 v2.5.2 稳定版)
    2. 添加转发规则
    3. 删除转发规则
    4. 显示已有转发规则
    5. Realm 服务管理 (启/停/重启)
    6. 添加TLS+WS规则 (手动证书)
    7. 添加TLS+WS规则 (自动证书)
    8. 卸载 Realm
    
    0. 退出脚本
    ---------------------------------------------------
    服务状态: ${realm_status}
    ---------------------------------------------------
EOF
    read -p "请输入选项 [0-8]: " choice
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
            8) uninstall_realm ;;
            0) exit 0 ;;
            *) echo -e "\n${red}无效输入，请重新输入${reset}" ;;
        esac
        echo -e "\n按任意键返回主菜单..."
        read -n 1
    done
}

main