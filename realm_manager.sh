#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 1.5 (Final Alignment & Color Fix)
#====================================================

# --- 颜色定义 ---
G_RED="\033[31m"
G_GREEN="\033[32m"
G_YELLOW="\033[33m"
G_CYAN="\033[36m"
G_WHITE="\033[37m"
L_BLUE="\033[94m"
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
        echo -e "${G_RED}错误: 此脚本必须以 root 权限运行！${NC}"
        exit 1
    fi
}

# 检查 realm 是否已安装
check_installation() {
    if [[ -f "${REALM_BIN_PATH}" ]]; then
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

# 1. 安装 realm
install_realm() {
    if check_installation; then
        echo -e "${G_GREEN}Realm 已安装，无需重复操作。${NC}"
        return
    fi

    echo -e "${G_YELLOW}开始安装 Realm...${NC}"
    echo "------------------------------------------------------------"
    
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
    systemctl enable realm > /dev/null 2&>1
    
    echo "------------------------------------------------------------"
    echo -e "${G_GREEN}Realm 安装成功！${NC}"
    echo -e "${G_YELLOW}默认开机自启已设置，但服务尚未启动，请添加转发规则后手动启动。${NC}"
}

# 2. 添加转发规则
add_rule() {
    if ! check_installation; then
        echo -e "${G_RED}错误: Realm 未安装，请先选择 '1' 进行安装。${NC}"
        return
    fi

    echo -e "${G_YELLOW}请输入要添加的转发规则信息:${NC}"
    local last_port
    last_port=$(grep 'listen =' "${REALM_CONFIG_PATH}" 2>/dev/null | awk -F'[:"]' '{print $5}' | sort -nr | head -n 1)
    
    local default_port
    if [[ -z "$last_port" ]]; then
        default_port=54000
    else
        default_port=$((last_port + 1))
    fi

    read -e -p "本地监听端口 (默认为 ${default_port}): " -i "${default_port}" listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 443): " remote_port

    if [[ -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then
        echo -e "${G_RED}错误: 任何一项均不能为空。${NC}"
        return
    fi
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
        echo -e "${G_RED}错误: 端口号必须为纯数字。${NC}"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then
        echo -e "${G_RED}错误: 本地监听端口 ${listen_port} 已存在，无法重复添加。${NC}"
        return
    fi

    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then
        echo -e "${L_BLUE}检测到IPv6地址，将自动添加括号。${NC}"
        formatted_remote_addr="[${remote_addr}]"
    else
        formatted_remote_addr="${remote_addr}"
    fi

    local final_remote_str="${formatted_remote_addr}:${remote_port}"

    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"" >> ${REALM_CONFIG_PATH}

    echo -e "${G_GREEN}转发规则添加成功！正在重启 Realm 服务以应用配置...${NC}"
    systemctl restart realm
    sleep 2
    
    if systemctl is-active --quiet realm; then
        echo -e "${G_GREEN}Realm 服务已成功重启。${NC}"
    else
        echo -e "${G_RED}Realm 服务重启失败，请使用 'systemctl status realm' 查看日志。${NC}"
    fi
}

# 3. 删除转发规则
delete_rule() {
    if ! check_installation; then
        echo -e "${G_RED}错误: Realm 未安装。${NC}"
        return
    fi
    
    mapfile -t rule_blocks < <(awk 'BEGIN{RS="[[endpoints]]"} NR>1' "${REALM_CONFIG_PATH}")

    if [[ ${#rule_blocks[@]} -eq 0 ]]; then
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

    local -a valid_indices_to_delete; local -a rules_to_delete_summary
    local max_index=${#rule_blocks[@]}

    for index in "${to_delete_indices[@]}"; do
        if ! [[ "$index" =~ ^[1-9][0-9]*$ && "$index" -le "$max_index" ]]; then
            echo -e "${G_RED}错误: 输入的序号 '${index}' 无效或超出范围 (1-${max_index})。${NC}"
            return
        fi
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${index} " ]]; then
            valid_indices_to_delete+=("$index")
            local block_content="${rule_blocks[$((index - 1))]}"
            local summary=$(echo "$block_content" | awk -F'"' '/listen|remote/{printf "%s -> %s", $2, $4}')
            rules_to_delete_summary+=("- 规则 #${index}: ${summary}")
        fi
    done

    if [[ ${#valid_indices_to_delete[@]} -eq 0 ]]; then echo -e "${G_YELLOW}未选择任何有效规则，操作已取消。${NC}"; return; fi

    echo; echo "您选择了删除以下规则:"; for summary in "${rules_to_delete_summary[@]}"; do echo "  $summary"; done; echo
    read -p "确认删除吗? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then echo -e "${G_YELLOW}操作已取消。${NC}"; return; fi
    
    local temp_config_file=$(mktemp)
    awk '/\[log\]/{p=1} p && !/\[\[endpoints\]\]/{print} /\[\[endpoints\]\]/{p=0}' "${REALM_CONFIG_PATH}" > "${temp_config_file}"

    for i in "${!rule_blocks[@]}"; do
        local current_index=$((i + 1))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${current_index} " ]]; then
            echo -e "\n[[endpoints]]\n${rule_blocks[$i]}" >> "${temp_config_file}"
        fi
    done

    mv "${temp_config_file}" "${REALM_CONFIG_PATH}"
    
    IFS=$'\n' sorted_indices=($(sort -n <<<"${valid_indices_to_delete[*]}")); unset IFS

    echo; echo -e "${G_GREEN}规则 #${sorted_indices[*]} 已被删除。正在重启 Realm 服务...${NC}"
    systemctl restart realm; sleep 1

    if systemctl is-active --quiet realm; then echo -e "${G_GREEN}Realm 服务已成功重启。${NC}"; else echo -e "${G_RED}Realm 服务重启失败，请检查配置或日志。${NC}"; fi
}

# 4. 显示已有转发规则
show_rules() {
    local is_delete_mode=${1:-false}

    if ! $is_delete_mode; then
        if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装。${NC}"; return; fi
        echo "当前存在的转发规则如下:"; fi

    mapfile -t listen_lines < <(grep 'listen =' "${REALM_CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')
    mapfile -t remote_lines < <(grep 'remote =' "${REALM_CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')

    if [[ ${#listen_lines[@]} -eq 0 ]]; then echo -e "  ${G_YELLOW}(当前无任何转发规则)${NC}"; return; fi

    echo -e "${G_CYAN}╔══════╤════════════════════════╤══════════════════════════════════╗${NC}"
    printf "${G_CYAN}║${G_WHITE} %-4s ${G_CYAN}│${G_WHITE} %-22s ${G_CYAN}│${G_WHITE} %-32s ${G_CYAN}║\n" "序号" "本地监听" "远程目标"
    echo -e "${G_CYAN}╠══════╧════════════════════════╧══════════════════════════════════╣${NC}"

    for i in "${!listen_lines[@]}"; do
        printf "${G_CYAN}║${NC} %-4d ${G_CYAN}│${NC} %-22s ${G_CYAN}│${NC} %-32s ${G_CYAN}║\n" "$((i + 1))" "${listen_lines[$i]}" "${remote_lines[$i]}"
    done

    echo -e "${G_CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

# 5. Realm 服务管理
manage_service() {
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装。${NC}"; return; fi
    echo "请选择要执行的操作:"
    echo " 1) 启动 Realm"; echo " 2) 停止 Realm"; echo " 3) 重启 Realm"
    echo " 4) 查看状态和日志"; echo " 5) 设置开机自启"; echo " 6) 取消开机自启"
    read -p "请输入选项 [1-6]: " service_choice
    case ${service_choice} in
        1) systemctl start realm; echo -e "${G_GREEN}Realm 已启动.${NC}";;
        2) systemctl stop realm; echo -e "${G_GREEN}Realm 已停止.${NC}";;
        3) systemctl restart realm; echo -e "${G_GREEN}Realm 已重启.${NC}";;
        4) systemctl status realm;;
        5) systemctl enable realm; echo -e "${G_GREEN}开机自启已设置.${NC}";;
        6) systemctl disable realm; echo -e "${G_GREEN}开机自启已取消.${NC}";;
        *) echo -e "${G_RED}无效选项.${NC}";;
    esac
}

# 6. 卸载 realm
uninstall_realm() {
    if ! check_installation; then echo -e "${G_RED}错误: Realm 未安装，无需卸载。${NC}"; return; fi
    read -p "确定要完全卸载 Realm 吗？(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then echo -e "${G_YELLOW}操作已取消。${NC}"; return; fi
    systemctl stop realm; systemctl disable realm
    rm -f ${REALM_BIN_PATH} ${REALM_SERVICE_PATH}; rm -rf ${REALM_CONFIG_DIR}
    systemctl daemon-reload
    echo -e "${G_GREEN}Realm 已成功卸载。${NC}"
}

# 主菜单 (v1.5)
show_menu() {
    clear; local state_color; local realm_state
    if check_installation; then
        if systemctl is-active --quiet realm; then state_color=${G_GREEN}; realm_state="运行中"; else state_color=${G_RED}; realm_state="已停止"; fi
    else state_color=${G_YELLOW}; realm_state="未安装"; fi

    echo -e "${G_CYAN}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G_CYAN}║${NC}              ${G_YELLOW} Realm 中转一键管理脚本 (v1.5)              ${G_CYAN} ║${NC}"
    echo -e "${G_CYAN}║${NC}                 ${G_WHITE} 作者: AiLi1337                           ${G_CYAN} ║${NC}"
    echo -e "${G_CYAN}╠═════════════════════════════════════════════════════════╣${NC}"
    printf "${G_CYAN}║${NC}  ${L_BLUE}1.${NC} %-52s ${G_CYAN}║\n" "安装 Realm"
    printf "${G_CYAN}║${NC}  ${L_BLUE}2.${NC} %-52s ${G_CYAN}║\n" "添加转发规则"
    printf "${G_CYAN}║${NC}  ${L_BLUE}3.${NC} %-50s ${G_CYAN}║\n" "删除转发规则"
    printf "${G_CYAN}║${NC}  ${L_BLUE}4.${NC} %-48s ${G_CYAN}║\n" "显示已有转发规则"
    printf "${G_CYAN}║${NC}  ${L_BLUE}5.${NC} %-41s ${G_CYAN}║\n" "Realm 服务管理 (启/停/状态/自启)"
    printf "${G_CYAN}║${NC}  ${L_BLUE}6.${NC} %-50s ${G_CYAN}║\n" "卸载 Realm"
    echo -e "${G_CYAN}╟─────────────────────────────────────────────────────────╢${NC}"
    printf "${G_CYAN}║${NC}  ${G_RED}0.${NC} %-52s ${G_CYAN}║\n" "退出脚本"
    echo -e "${G_CYAN}╠═════════════════════════════════════════════════════════╣${NC}"
    printf "${G_CYAN}║${NC}  服务状态: %-49s ${G_CYAN}║\n" "${state_color}${realm_state}${NC}"
    echo -e "${G_CYAN}╚═════════════════════════════════════════════════════════╝${NC}"
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