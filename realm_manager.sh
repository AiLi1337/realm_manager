#!/bin/bash

#====================================================
#	System Request: Centos 7+ / Debian 8+ / Ubuntu 16+
#	Author: AiLi1337
#	Description: Realm All-in-One Management Script
#	Version: 1.1 (User-friendly input update)
#====================================================

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
ENDCOLOR="\033[0m"

# 全局变量
REALM_BIN_PATH="/usr/local/bin/realm"
REALM_CONFIG_DIR="/etc/realm"
REALM_CONFIG_PATH="${REALM_CONFIG_DIR}/config.toml"
REALM_SERVICE_PATH="/etc/systemd/system/realm.service"
REALM_LATEST_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行！${ENDCOLOR}"
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

# 打印分隔线
print_divider() {
    echo "------------------------------------------------------------"
}

# 1. 安装 realm
install_realm() {
    if check_installation; then
        echo -e "${GREEN}Realm 已安装，无需重复操作。${ENDCOLOR}"
        return
    fi

    echo -e "${YELLOW}开始安装 Realm...${ENDCOLOR}"
    print_divider
    
    echo "正在从 GitHub 下载最新版本的 Realm..."
    if ! curl -fsSL ${REALM_LATEST_URL} | tar xz; then
        echo -e "${RED}下载或解压 Realm 失败，请检查网络或依赖。${ENDCOLOR}"
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
    
    print_divider
    echo -e "${GREEN}Realm 安装成功！${ENDCOLOR}"
    echo -e "${YELLOW}默认开机自启已设置，但服务尚未启动，请添加转发规则后手动启动。${ENDCOLOR}"
}

# 2. 添加转发规则 (已更新)
add_rule() {
    if ! check_installation; then
        echo -e "${RED}错误: Realm 未安装，请先选择 '1' 进行安装。${ENDCOLOR}"
        return
    fi

    echo -e "${YELLOW}请输入要添加的转发规则信息:${ENDCOLOR}"
    read -p "本地监听端口 (例如 54000): " listen_port
    read -p "远程目标地址 (IP或域名): " remote_addr
    read -p "远程目标端口 (例如 443): " remote_port

    # 验证输入
    if [[ -z "$listen_port" || -z "$remote_addr" || -z "$remote_port" ]]; then
        echo -e "${RED}错误: 任何一项均不能为空。${ENDCOLOR}"
        return
    fi
    if ! [[ "$listen_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口号必须为纯数字。${ENDCOLOR}"
        return
    fi
    
    if grep -q "listen = \"0.0.0.0:${listen_port}\"" ${REALM_CONFIG_PATH}; then
        echo -e "${RED}错误: 本地监听端口 ${listen_port} 已存在，无法重复添加。${ENDCOLOR}"
        return
    fi

    local formatted_remote_addr

    # 自动检测IPv6并添加括号
    # 如果地址包含冒号“:”，且本身不以“[”开头，则判断为需要加括号的IPv6
    if [[ "$remote_addr" == *":"* && "$remote_addr" != \[* ]]; then
        echo -e "${BLUE}检测到IPv6地址，将自动添加括号。${ENDCOLOR}"
        formatted_remote_addr="[${remote_addr}]"
    else
        # IPv4、域名或已加括号的IPv6地址，直接使用
        formatted_remote_addr="${remote_addr}"
    fi

    local final_remote_str="${formatted_remote_addr}:${remote_port}"

    # 追加新规则到配置文件
    echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${listen_port}\"\nremote = \"${final_remote_str}\"" >> ${REALM_CONFIG_PATH}

    echo -e "${GREEN}转发规则添加成功！正在重启 Realm 服务以应用配置...${ENDCOLOR}"
    systemctl restart realm
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet realm; then
        echo -e "${GREEN}Realm 服务已成功重启。${ENDCOLOR}"
    else
        echo -e "${RED}Realm 服务重启失败，请使用 'systemctl status realm' 或 'journalctl -u realm -n 50' 查看日志。${ENDCOLOR}"
    fi
}

# 3. 删除转发规则
delete_rule() {
    if ! check_installation; then
        echo -e "${RED}错误: Realm 未安装。${ENDCOLOR}"
        return
    fi
    
    if ! grep -q "\[\[endpoints\]\]" ${REALM_CONFIG_PATH}; then
        echo -e "${YELLOW}当前没有任何转发规则可供删除。${ENDCOLOR}"
        return
    fi

    echo -e "${BLUE}当前存在的转发规则如下:${ENDCOLOR}"
    show_rules
    
    read -p "请输入要删除规则的本地监听端口: " port_to_delete

    if [[ -z "$port_to_delete" ]]; then
        echo -e "${RED}错误: 未输入任何端口。${ENDCOLOR}"
        return
    fi

    if ! grep -q "listen = \"0.0.0.0:${port_to_delete}\"" ${REALM_CONFIG_PATH}; then
        echo -e "${RED}错误: 监听端口为 ${port_to_delete} 的规则不存在。${ENDCOLOR}"
        return
    fi

    awk -v port="${port_to_delete}" 'BEGIN{RS="\n\n"; ORS="\n\n"} !/listen = "0.0.0.0:'${port_to_delete}'"/' ${REALM_CONFIG_PATH} > ${REALM_CONFIG_PATH}.tmp
    mv ${REALM_CONFIG_PATH}.tmp ${REALM_CONFIG_PATH}

    echo -e "${GREEN}规则 (监听端口: ${port_to_delete}) 已被删除。正在重启 Realm 服务...${ENDCOLOR}"
    systemctl restart realm
    sleep 2

    if systemctl is-active --quiet realm; then
        echo -e "${GREEN}Realm 服务已成功重启。${ENDCOLOR}"
    else
        echo -e "${RED}Realm 服务重启失败，请检查配置或日志。${ENDCOLOR}"
    fi
}

# 4. 显示已有转发规则
show_rules() {
    if ! check_installation; then
        echo -e "${RED}错误: Realm 未安装。${ENDCOLOR}"
        return
    fi
    
    echo -e "${BLUE}当前 Realm 配置文件内容如下:${ENDCOLOR}"
    print_divider
    if ! grep -q "\[\[endpoints\]\]" ${REALM_CONFIG_PATH}; then
        echo -e "${YELLOW}  (当前无任何转发规则)${ENDCOLOR}"
    else
        # 使用 grep 和 sed 美化输出
        grep -E 'listen|remote' ${REALM_CONFIG_PATH} | sed 's/listen/本地监听/g' | sed 's/remote/远程目标/g' | sed 's/[="]/ /g' | awk '{printf "  %-25s -> %-25s\n", $2, $4}'
    fi
    print_divider
}

# 5. Realm 服务管理
manage_service() {
    if ! check_installation; then
        echo -e "${RED}错误: Realm 未安装。${ENDCOLOR}"
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
        1) systemctl start realm; echo -e "${GREEN}Realm 已启动。${ENDCOLOR}";;
        2) systemctl stop realm; echo -e "${GREEN}Realm 已停止。${ENDCOLOR}";;
        3) systemctl restart realm; echo -e "${GREEN}Realm 已重启。${ENDCOLOR}";;
        4) systemctl status realm;;
        5) systemctl enable realm; echo -e "${GREEN}开机自启已设置。${ENDCOLOR}";;
        6) systemctl disable realm; echo -e "${GREEN}开机自启已取消。${ENDCOLOR}";;
        *) echo -e "${RED}无效选项。${ENDCOLOR}";;
    esac
}


# 6. 卸载 realm
uninstall_realm() {
    if ! check_installation; then
        echo -e "${RED}错误: Realm 未安装，无需卸载。${ENDCOLOR}"
        return
    fi
    
    read -p "确定要完全卸载 Realm 吗？这将删除所有相关文件和配置！(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${YELLOW}操作已取消。${ENDCOLOR}"
        return
    fi

    echo -e "${YELLOW}正在停止并禁用 Realm 服务...${ENDCOLOR}"
    systemctl stop realm
    systemctl disable realm
    
    echo "正在删除相关文件..."
    rm -f ${REALM_BIN_PATH}
    rm -f ${REALM_SERVICE_PATH}
    rm -rf ${REALM_CONFIG_DIR}
    
    systemctl daemon-reload
    
    echo -e "${GREEN}Realm 已成功卸载。${ENDCOLOR}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}Realm 中转一键管理脚本 (v1.1)${ENDCOLOR}"
    echo -e "${GREEN}作者: AiLi1337${ENDCOLOR}"
    print_divider
    echo "  1. 安装 Realm"
    echo "  2. 添加转发规则"
    echo "  3. 删除转发规则"
    echo "  4. 显示已有转发规则"
    echo "  5. Realm 服务管理 (启/停/状态/自启)"
    echo "  6. 卸载 Realm"
    echo -e "  0. ${RED}退出脚本${ENDCOLOR}"
    print_divider
    
    if check_installation; then
        if systemctl is-active --quiet realm; then
            echo -e "服务状态: ${GREEN}运行中${ENDCOLOR}"
        else
            echo -e "服务状态: ${RED}已停止${ENDCOLOR}"
        fi
    else
        echo -e "服务状态: ${YELLOW}未安装${ENDCOLOR}"
    fi
    print_divider
}

# 主循环
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
            *) echo -e "${RED}无效输入，请重新输入!${ENDCOLOR}" ;;
        esac
        echo -e "\n${YELLOW}按 Enter 键返回主菜单...${ENDCOLOR}"
        read -n 1
    done
}

# 启动脚本
main