#!/bin/bash
# NAT 小鸡管理脚本
# 用法: bash manage-nat.sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 定义表格格式：列宽固定，确保绝对对齐
# 序号(6) 名称(12) 状态(10) IP(16) SSH(10) NAT(15)
TABLE_FORMAT="%-6s %-12s %-10s %-16s %-10s %-15s\n"

# 全局变量，用于存储用户选择的容器名
SELECTED_NAME=""

# 显示所有 NAT 容器
list_containers() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}NAT 小鸡列表${NC}"
    echo -e "${BLUE}===================================${NC}"
    
    # 获取所有 nat- 开头的容器
    CONTAINERS=$(docker ps -a --filter "name=^nat-" --format "{{.Names}}\t{{.Status}}" | sort -V)
    
    if [ -z "$CONTAINERS" ]; then
        echo -e "${YELLOW}未发现任何 NAT 容器${NC}"
        return 1
    fi
    
    # 打印表头 (颜色代码单独处理，不影响宽度计算)
    printf "${CYAN}${TABLE_FORMAT}${NC}" "No." "Name" "Status" "Internal IP" "SSH Port" "NAT Ports"
    echo "---------------------------------------------------------------------------"
    
    local index=1
    while IFS=$'\t' read -r name status; do
        # 提取并验证 IP 序号
        ip_index=$(echo "$name" | sed 's/nat-//')
        if ! [[ "$ip_index" =~ ^[0-9]+$ ]] || [ "$ip_index" -lt 1 ] || [ "$ip_index" -gt 254 ]; then
            continue
        fi
        
        container_ip="192.168.10.${ip_index}"
        ssh_port=$((10000 + ip_index))
        nat_start=$((20000 + ip_index * 10))
        nat_end=$((nat_start + 9))
        
        # 状态处理
        if [[ "$status" == *"Up"* ]]; then
            status_show="Running" # 纯文本用于对齐
            line_color="${GREEN}" # 绿色
        else
            status_show="Stopped" # 纯文本用于对齐
            line_color="${RED}"   # 红色（停止状态整行变红，更醒目）
        fi
        
        # 打印数据行 (使用相同的格式变量)
        # 注意：这里我们让整行根据状态变色，既美观又不会破坏 System 对齐
        if [[ "$status" == *"Up"* ]]; then
             printf "${TABLE_FORMAT}" "[$index]" "$name" "$status_show" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        else
             # 停止的容器用红色显示
             printf "${RED}${TABLE_FORMAT}${NC}" "[$index]" "$name" "$status_show" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        fi
        
        # 保存映射关系
        eval "CONTAINER_${index}=$name"
        index=$((index + 1))
    done <<< "$CONTAINERS"
    
    TOTAL_COUNT=$((index - 1))
    
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}未发现符合规范的 NAT 容器 (nat-1 ~ nat-254)${NC}"
        return 1
    fi
    
    echo "---------------------------------------------------------------------------"
    echo -e "共 ${CYAN}${TOTAL_COUNT}${NC} 个容器"
    echo ""
    return 0
}

# 统一的选择函数
# 直接修改全局变量 SELECTED_NAME，不再使用 echo 返回值，避免污染
ask_for_selection() {
    SELECTED_NAME=""
    echo -e "${YELLOW}>>> 请从上方列表中选择一个容器 <<<${NC}"
    printf "请输入容器序号 [1-${TOTAL_COUNT}]: "
    read choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$TOTAL_COUNT" ]; then
        echo -e "${RED}错误：无效的序号！${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    # 获取对应容器名
    eval "SELECTED_NAME=\$CONTAINER_${choice}"
    return 0
}

# 操作函数
do_start() {
    ask_for_selection || return
    echo -e "${YELLOW}正在启动 ${SELECTED_NAME} ...${NC}"
    docker start "$SELECTED_NAME" >/dev/null && echo -e "${GREEN}成功${NC}" || echo -e "${RED}失败${NC}"
    read -p "按回车键继续..."
}

do_stop() {
    ask_for_selection || return
    echo -e "${YELLOW}正在停止 ${SELECTED_NAME} ...${NC}"
    docker stop "$SELECTED_NAME" >/dev/null && echo -e "${GREEN}成功${NC}" || echo -e "${RED}失败${NC}"
    read -p "按回车键继续..."
}

do_restart() {
    ask_for_selection || return
    echo -e "${YELLOW}正在重启 ${SELECTED_NAME} ...${NC}"
    docker restart "$SELECTED_NAME" >/dev/null && echo -e "${GREEN}成功${NC}" || echo -e "${RED}失败${NC}"
    read -p "按回车键继续..."
}

do_delete() {
    ask_for_selection || return
    echo -e "${RED}警告：即将删除容器 ${SELECTED_NAME} ${NC}"
    printf "确认删除? (y/n): "
    read confirm
    if [ "$confirm" == "y" ]; then
        docker rm -f "$SELECTED_NAME" >/dev/null && echo -e "${GREEN}删除成功${NC}" || echo -e "${RED}删除失败${NC}"
    else
        echo "已取消"
    fi
    read -p "按回车键继续..."
}

do_logs() {
    ask_for_selection || return
    clear
    echo -e "${CYAN}容器 ${SELECTED_NAME} 日志:${NC}"
    echo "------------------------------------------------"
    docker logs --tail 20 "$SELECTED_NAME"
    echo "------------------------------------------------"
    read -p "按回车键返回菜单..."
}

# 主循环
while true; do
    clear
    
    # 1. 先列出容器
    if ! list_containers; then
        echo "暂无容器，请先使用 deploy-nat.sh 创建。"
        exit 0
    fi

    # 2. 显示菜单
    echo -e "${CYAN}请选择操作:${NC}"
    echo "  1. 启动容器"
    echo "  2. 停止容器"
    echo "  3. 重启容器"
    echo "  4. 删除容器"
    echo "  5. 查看日志"
    echo "  6. 刷新列表"
    echo "  0. 退出"
    echo "==================================="
    printf "请输入选项 [0-6]: "
    read option

    case $option in
        1) do_start ;;
        2) do_stop ;;
        3) do_restart ;;
        4) do_delete ;;
        5) do_logs ;;
        6) continue ;; # 刷新
        0) echo "Bye!"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
done
