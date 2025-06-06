#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 1.4 (Indexed Deletion & UI Rework)
#====================================================

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
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

# 1. 安装 realm (无改动)
install_realm() {
    if check_installation; then
        echo "Realm 已安装，无需重复操作。"
        return
    fi

    echo "开始安装 Realm..."
    echo "------------------------------------------------------------"
    
    echo "正在从 GitHub 下载最新版本的 Realm..."
    if ! curl -fsSL ${REALM_LATEST_URL} | tar xz; then
        echo "下载或解压 Realm 失败，请检查网络或依赖。"
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
    echo "Realm 安装成功！"
    echo "默认开机自启已设置，但服务尚未启动，请添加转发规则后手动启动。"
}

# 2. 添加转发规则 (无改动)
add_rule() {
    if ! check_installation; then
        echo "错误: Realm 未安装，请先选择 '1' 进行安装。"
        return
    fi

    echo "请输入要添加的转发规则信息:"
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
        echo "错误: 任何一项均不能为空。"
        return
    fi
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口号必须为纯数字。"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH} 2>/dev/null; then
        echo "错误: 本地监听端口 ${listen_port} 已存在，无法重复添加。"
        return
    fi

    local formatted_remote_addr
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then
        echo "检测到IPv6地址，将自动添加括号。"
        formatted_remote_addr="[${remote_addr}]"
    else
        formatted_remote_addr="${remote_addr}"
    fi

    local final_remote_str="${formatted_remote_addr}:${remote_port}"

    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"" >> ${REALM_CONFIG_PATH}

    echo "转发规则添加成功！正在重启 Realm 服务以应用配置..."
    systemctl restart realm
    sleep 2
    
    if systemctl is-active --quiet realm; then
        echo "Realm 服务已成功重启。"
    else
        echo "Realm 服务重启失败，请使用 'systemctl status realm' 查看日志。"
    fi
}

# 3. 删除转发规则 (已重做)
delete_rule() {
    if ! check_installation; then
        echo "错误: Realm 未安装。"
        return
    fi
    
    # 将所有 endpoints 块读入数组
    mapfile -t rule_blocks < <(awk 'BEGIN{RS="[[endpoints]]"} NR>1' "${REALM_CONFIG_PATH}")

    if [[ ${#rule_blocks[@]} -eq 0 ]]; then
        echo "当前没有任何转发规则可供删除。"
        return
    fi

    echo "当前存在的转发规则如下:"
    show_rules true # true 表示在删除模式下调用，不显示外框

    echo
    read -p "请输入要删除的规则序号 (可输入多个, 用空格或逗号隔开): " user_input

    # 将逗号替换为空格，以便解析
    user_input=${user_input//,/' '}
    read -ra to_delete_indices <<< "$user_input"

    if [[ ${#to_delete_indices[@]} -eq 0 ]]; then
        echo "未输入任何序号，操作已取消。"
        return
    fi

    local -a valid_indices_to_delete
    local -a rules_to_delete_summary
    local max_index=${#rule_blocks[@]}

    # 验证输入并收集待删除规则的摘要
    for index in "${to_delete_indices[@]}"; do
        if ! [[ "$index" =~ ^[1-9][0-9]*$ && "$index" -le "$max_index" ]]; then
            echo "错误: 输入的序号 '${index}' 无效或超出范围 (1-${max_index})。"
            return
        fi
        # 防止重复添加
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${index} " ]]; then
            valid_indices_to_delete+=("$index")
            local block_content="${rule_blocks[$((index - 1))]}"
            local listen_line=$(echo "$block_content" | grep 'listen =')
            local remote_line=$(echo "$block_content" | grep 'remote =')
            local summary=$(echo "$listen_line -> $remote_line" | sed 's/listen = "//' | sed 's/"//' | sed 's/remote = "//' | sed 's/"//')
            rules_to_delete_summary+=("- 规则 #${index}: ${summary}")
        fi
    done

    if [[ ${#valid_indices_to_delete[@]} -eq 0 ]]; then
        echo "未选择任何有效规则，操作已取消。"
        return
    fi

    echo
    echo "您选择了删除以下规则:"
    for summary in "${rules_to_delete_summary[@]}"; do
        echo "  $summary"
    done
    
    echo
    read -p "确认删除吗? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "操作已取消。"
        return
    fi
    
    # 重建配置文件
    local temp_config_file=$(mktemp)
    # 先写入日志部分
    awk '/\[log\]/{p=1} p && !/\[\[endpoints\]\]/{print} /\[\[endpoints\]\]/{p=0}' "${REALM_CONFIG_PATH}" > "${temp_config_file}"

    # 仅写入需要保留的规则
    for i in "${!rule_blocks[@]}"; do
        local current_index=$((i + 1))
        if [[ ! " ${valid_indices_to_delete[*]} " =~ " ${current_index} " ]]; then
            echo -e "\n[[endpoints]]\n${rule_blocks[$i]}" >> "${temp_config_file}"
        fi
    done

    mv "${temp_config_file}" "${REALM_CONFIG_PATH}"
    
    # 对序号进行排序，以便显示
    IFS=$'\n' sorted_indices=($(sort -n <<<"${valid_indices_to_delete[*]}"))
    unset IFS

    echo
    echo "规则 #${sorted_indices[*]} 已被删除。正在重启 Realm 服务..."
    systemctl restart realm
    sleep 1

    if systemctl is-active --quiet realm; then
        echo "Realm 服务已成功重启。"
    else
        echo "Realm 服务重启失败，请检查配置或日志。"
    fi
}

# 4. 显示已有转发规则 (已重做)
show_rules() {
    local is_delete_mode=${1:-false} # 检查是否在删除模式下被调用

    if ! $is_delete_mode; then
        if ! check_installation; then
            echo "错误: Realm 未安装。"
            return
        fi
        echo "当前存在的转发规则如下:"
    fi

    mapfile -t listen_lines < <(grep 'listen =' "${REALM_CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')
    mapfile -t remote_lines < <(grep 'remote =' "${REALM_CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')

    if [[ ${#listen_lines[@]} -eq 0 ]]; then
        echo "  (当前无任何转发规则)"
        return
    fi

    echo "╔══════╤════════════════════════╤══════════════════════════════════╗"
    printf "║ %-4s │ %-22s │ %-32s ║\n" "序号" "本地监听" "远程目标"
    echo "╠══════╧════════════════════════╧══════════════════════════════════╣"

    for i in "${!listen_lines[@]}"; do
        printf "║ %-4d │ %-22s │ %-32s ║\n" "$((i + 1))" "${listen_lines[$i]}" "${remote_lines[$i]}"
    done

    echo "╚══════════════════════════════════════════════════════════════════╝"
}

# 5. Realm 服务管理 (无改动)
manage_service() {
    # ... 省略未改动代码 ...
    if ! check_installation; then echo "错误: Realm 未安装。"; return; fi
    echo "请选择要执行的操作:"
    echo " 1) 启动 Realm"; echo " 2) 停止 Realm"; echo " 3) 重启 Realm"
    echo " 4) 查看状态和日志"; echo " 5) 设置开机自启"; echo " 6) 取消开机自启"
    read -p "请输入选项 [1-6]: " service_choice
    case ${service_choice} in
        1) systemctl start realm; echo "Realm 已启动.";;
        2) systemctl stop realm; echo "Realm 已停止.";;
        3) systemctl restart realm; echo "Realm 已重启.";;
        4) systemctl status realm;;
        5) systemctl enable realm; echo "开机自启已设置.";;
        6) systemctl disable realm; echo "开机自启已取消.";;
        *) echo "无效选项.";;
    esac
}

# 6. 卸载 realm (无改动)
uninstall_realm() {
    # ... 省略未改动代码 ...
    if ! check_installation; then echo "错误: Realm 未安装，无需卸载。"; return; fi
    read -p "确定要完全卸载 Realm 吗？(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then echo "操作已取消。"; return; fi
    systemctl stop realm; systemctl disable realm
    rm -f ${REALM_BIN_PATH} ${REALM_SERVICE_PATH}
    rm -rf ${REALM_CONFIG_DIR}
    systemctl daemon-reload
    echo "Realm 已成功卸载。"
}

# 主菜单 (无改动)
show_menu() {
    clear
    local realm_state
    if check_installation; then
        if systemctl is-active --quiet realm; then realm_state="运行中"; else realm_state="已停止"; fi
    else realm_state="未安装"; fi
    echo "╔═════════════════════════════════════════════════════════╗"
    echo "║               Realm 中转一键管理脚本 (v1.4)               ║"
    echo "║                  作者: AiLi1337                         ║"
    echo "╠═════════════════════════════════════════════════════════╣"
    printf "║  %-52s ║\n" "1. 安装 Realm"
    printf "║  %-52s ║\n" "2. 添加转发规则"
    printf "║  %-52s ║\n" "3. 删除转发规则"
    printf "║  %-52s ║\n" "4. 显示已有转发规则"
    printf "║  %-52s ║\n" "5. Realm 服务管理 (启/停/状态/自启)"
    printf "║  %-52s ║\n" "6. 卸载 Realm"
    echo "╟─────────────────────────────────────────────────────────╢"
    printf "║  %-52s ║\n" "0. 退出脚本"
    echo "╠═════════════════════════════════════════════════════════╣"
    printf "║  服务状态: %-42s ║\n" "${realm_state}"
    echo "╚═════════════════════════════════════════════════════════╝"
}

# 主循环 (无改动)
main() {
    check_root
    while true; do
        show_menu
        read -p "请输入选项 [0-6]: " choice
        case ${choice} in
            1) install_realm ;;
            2) add_rule ;;
            3) delete_rule ;;
            4) show_rules ;;
            5) manage_service ;;
            6) uninstall_realm ;;
            0) exit 0 ;;
            *) echo "无效输入，请重新输入!" ;;
        esac
        echo
        read -p "按 Enter 键返回主菜单..."
    done
}

# 启动脚本
main