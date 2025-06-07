#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 2.1 (Robustness & Refinement Update)
#====================================================

# --- Minimal Color Definition ---
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

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本必须以 root 权限运行！"
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

# 检查并重启 realm 服务
restart_realm() {
    echo "正在应用配置并重启 Realm 服务..."
    systemctl restart realm
    sleep 1 # 等待服务状态更新
    if systemctl is-active --quiet realm; then
        echo -e "${G_GREEN}Realm 服务已成功重启。${NC}"
    else
        echo -e "${G_RED}Realm 服务重启失败！${NC}"
        echo "以下是最新的10条日志，请检查错误信息:"
        journalctl -n 10 -u realm --no-pager
    fi
}

# 1. 安装 realm
install_realm() {
    if check_installation; then echo -e "${G_GREEN}Realm 已安装，无需重复操作。${NC}"; return; fi
    echo "开始安装 Realm..."
    echo "------------------------------------------------------------"
    if ! command -v curl &> /dev/null; then echo -e "${G_RED}错误: curl 未安装，请先安装 curl。${NC}"; exit 1; fi
    echo "正在从 GitHub 下载最新版本的 Realm..."
    if ! curl -fsSL ${REALM_LATEST_URL} | tar xz; then echo -e "${G_RED}下载或解压 Realm 失败，请检查网络或依赖。${NC}"; exit 1; fi
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
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装，请先选择 '1' 进行安装。${NC}"; return; fi
    echo "请输入要添加的转发规则信息:"
    read -p "本地监听端口 (例如 54000): " listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 443): " remote_port

    # --- v2.1 优化：更严格的输入验证 ---
    if [[ -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then echo -e "${G_RED}错误: 任何一项均不能为空。${NC}"; return; fi
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$listen_port" -ge 1 && "$listen_port" -le 65535 ]]; then echo -e "${G_RED}错误: 本地监听端口 '${listen_port}' 不是一个有效的端口 (1-65535)。${NC}"; return; fi
    if ! [[ "$remote_port" =~ ^[0-9]+$ && "$remote_port" -ge 1 && "$remote_port" -le 65535 ]]; then echo -e "${G_RED}错误: 远程目标端口 '${remote_port}' 不是一个有效的端口 (1-65535)。${NC}"; return; fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在，无法重复添加。${NC}"; return; fi
    
    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then echo -e "${L_BLUE}检测到IPv6地址，将自动添加括号。${NC}"; formatted_remote_addr="[${remote_addr}]"; else formatted_remote_addr="${remote_addr}"; fi
    local final_remote_str="${formatted_remote_addr}:${remote_port}"
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"" >> ${REALM_CONFIG_PATH}
    echo -e "${G_GREEN}转发规则添加成功！${NC}"
    restart_realm
}

# 3. 删除转发规则
delete_rule() {
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装。${NC}"; return; fi
    
    # --- v2.1 优化：使用更健壮的解析方式 ---
    local rules_to_display=()
    while IFS="," read -r listen remote; do
        rules_to_display+=("$listen,$remote")
    done < <(paste -d, <(grep 'listen' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/') <(grep 'remote' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/'))

    if [[ ${#rules_to_display[@]} -eq 0 ]]; then echo -e "${G_YELLOW}当前没有任何转发规则可供删除。${NC}"; return; fi

    echo "当前存在的转发规则如下:"; show_rules true; echo
    read -p "请输入要删除的规则序号 (可输入多个, 用空格或逗号隔开): " user_input
    user_input=${user_input//,/' '}
    read -ra to_delete_indices <<< "$user_input"
    if [[ ${#to_delete_indices[@]} -eq 0 ]]; then echo -e "${G_YELLOW}未输入任何序号，操作已取消。${NC}"; return; fi

    local -a valid_indices_to_delete; local -a rules_to_delete_summary
    local max_index=${#rules_to_display[@]}
    for index_str in "${to_delete_indices[@]}"; do
        if ! [[ "$index_str" =~ ^[1-9][0-9]*$ && "$index_str" -le "$max_index" ]]; then echo -e "${G_RED}错误: 输入的序号 '${index_str}' 无效或超出范围 (1-${max_index})。${NC}"; return; fi
        local index=$((index_str))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${index} " ]]; then
            valid_indices_to_delete+=("$index")
            local rule_info="${rules_to_display[$((index - 1))]}"
            local listen_info="${rule_info%,*}"
            local remote_info="${rule_info#*,}"
            rules_to_delete_summary+=("- 规则 #${index}: ${listen_info} -> ${remote_info}")
        fi
    done

    if [[ ${#valid_indices_to_delete[@]} -eq 0 ]]; then echo -e "${G_YELLOW}未选择任何有效规则，操作已取消。${NC}"; return; fi

    echo; echo "您选择了删除以下规则:"; for summary in "${rules_to_delete_summary[@]}"; do echo "  $summary"; done
    echo -e "\n${G_YELLOW}警告：此操作不可逆！${NC}"
    read -p "确认删除吗? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then echo "操作已取消。"; return; fi
    
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
    
    if ! grep -q "\[\[endpoints\]\]" "${REALM_CONFIG_PATH}" 2>/dev/null; then echo -e "\n# 所有规则已删除。为确保服务能正常启动，已添加以下占位符。\n#[[endpoints]]\n#listen = \"0.0.0.0:10000\"\n#remote = \"127.0.0.1:10000\"" >> "${REALM_CONFIG_PATH}"; fi
    
    IFS=$'\n' sorted_indices=($(sort -n <<<"${valid_indices_to_delete[*]}")); unset IFS
    echo; echo "规则 #${sorted_indices[*]} 已被删除。"
    restart_realm
}

# 4. 显示已有转发规则
show_rules() {
    local is_delete_mode=${1:-false}
    if ! $is_delete_mode; then if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装。${NC}"; return; fi; echo "当前存在的转发规则如下:"; fi
    
    local rules_found=false
    echo "+--------+--------------------------+-----------------------------------+"
    printf "| %-6s | %-24s | %-33s |\n" "序号" "本地监听" "远程目标"
    echo "+--------+--------------------------+-----------------------------------+"
    
    local index=1
    # --- v2.1 优化：使用更健壮的解析方式 ---
    while IFS="," read -r listen remote; do
        printf "| %-6d | %-24s | %-33s |\n" "$index" "$listen" "$remote"
        rules_found=true
        ((index++))
    done < <(paste -d, <(grep 'listen' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/') <(grep 'remote' ${REALM_CONFIG_PATH} | sed 's/.*"\(.*\)".*/\1/'))

    if ! $rules_found; then
        printf "| %-68s |\n" " (当前无任何转发规则)"
    fi
    echo "+--------+--------------------------+-----------------------------------+"
}

# 5. Realm 服务管理
manage_service() {
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装。${NC}"; return; fi
    echo "请选择要执行的操作:"
    echo " 1) 启动 Realm"; echo " 2) 停止 Realm"; echo " 3) 重启 Realm"
    echo " 4) 查看状态和日志"; echo " 5) 设置开机自启"; echo " 6) 取消开机自启"
    read -p "请输入选项 [1-6]: " service_choice
    case ${service_choice} in
        1)
            echo "正在启动 Realm..."; systemctl start realm; sleep 1
            if systemctl is-active --quiet realm; then echo -e "${G_GREEN}Realm 已成功启动。${NC}"; else echo -e "${G_RED}Realm 启动失败！${NC}"; journalctl -n 10 -u realm --no-pager; fi
            ;;
        2)
            echo "正在停止 Realm..."; systemctl stop realm; echo "Realm 已停止。"
            ;;
        3) restart_realm;;
        4) systemctl status realm;;
        5) systemctl enable realm; echo "开机自启已设置。";;
        6) systemctl disable realm; echo "开机自启已取消。";;
        *) echo -e "${G_RED}无效选项.${NC}";;
    esac
}

# 6. 卸载 realm
uninstall_realm() {
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装，无需卸载。${NC}"; return; fi
    read -p "确定要完全卸载 Realm 吗？此操作不可逆！(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then echo "操作已取消。"; return; fi
    systemctl stop realm; systemctl disable realm
    rm -f ${REALM_BIN_PATH} ${REALM_SERVICE_PATH}; rm -rf ${REALM_CONFIG_DIR}
    systemctl daemon-reload
    echo -e "${G_GREEN}Realm 已成功卸载。${NC}"
}

# 主菜单
show_menu() {
    clear; local state_color; local realm_state
    if check_installation; then
        if systemctl is-active --quiet realm; then state_color=${G_GREEN}; realm_state="运行中"; else state_color=${G_RED}; realm_state="已停止"; fi
    else state_color=${G_YELLOW}; realm_state="未安装"; fi
    echo "---- Realm 中转一键管理脚本 (v2.1) ----"
    echo " 作者: AiLi1337"
    echo
    echo "1. 安装 Realm"
    echo "2. 添加转发规则"
    echo "3. 删除转发规则"
    echo "4. 显示已有转发规则"
    echo "5. Realm 服务管理 (启/停/状态/自启)"
    echo "6. 卸载 Realm"
    echo "-----------------------------------------"
    echo "0. 退出脚本"
    echo "-----------------------------------------"
    echo -e "服务状态: ${state_color}${realm_state}${NC}"
    echo "-----------------------------------------"
}

# 主循环
main() {
    check_root
    while true; do
        show_menu
        read -p "请输入选项 [0-6]: " choice
        case ${choice} in
            1) install_realm ;; 2) add_rule ;; 3) delete_rule ;; 4) show_rules ;; 5) manage_service ;; 6) uninstall_realm ;; 0) exit 0 ;;
            *) echo -e "${G_RED}无效输入，请重新输入!${NC}" ;;
        esac
        echo; read -p "按 Enter 键返回主菜单..."
    done
}

# 启动脚本
main