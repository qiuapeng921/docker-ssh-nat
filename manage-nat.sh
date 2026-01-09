#!/bin/bash
# NAT 小鸡管理脚本
# 用法: bash manage-nat.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

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
    
    printf "${CYAN}%-6s %-14s %-10s %-18s %-10s %-15s${NC}\n" "No." "Name" "Status" "Internal IP" "SSH Port" "NAT Ports"
    echo "--------------------------------------------------------------------------------"
    
    local index=1
    while IFS=$'\t' read -r name status; do
        # 提取 IP 序号（只处理 nat-数字 格式的容器）
        ip_index=$(echo "$name" | sed 's/nat-//')
        
        # 验证是否为1-254的纯数字
        if ! [[ "$ip_index" =~ ^[0-9]+$ ]] || [ "$ip_index" -lt 1 ] || [ "$ip_index" -gt 254 ]; then
            # 跳过非标准命名的容器
            continue
        fi
        
        container_ip="192.168.10.${ip_index}"
        ssh_port=$((10000 + ip_index))
        nat_start=$((20000 + ip_index * 10))
        nat_end=$((nat_start + 9))
        
        # 状态显示（英文）
        if [[ "$status" == *"Up"* ]]; then
            status_text="${GREEN}Running${NC}"
        else
            status_text="${RED}Stopped${NC}"
        fi
        
        printf "${MAGENTA}[%-3s]${NC} %-14s %-18b %-18s %-10s %-15s\n" \
            "$index" "$name" "$status_text" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        
        # 保存容器名称供后续选择
        eval "CONTAINER_${index}=$name"
        index=$((index + 1))
    done <<< "$CONTAINERS"
    
    TOTAL_COUNT=$((index - 1))
    
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}未发现符合规范的 NAT 容器 (nat-1 ~ nat-254)${NC}"
        return 1
    fi
    
    echo "--------------------------------------------------------------------------------"
    echo -e "共 ${CYAN}${TOTAL_COUNT}${NC} 个容器"
    echo ""
    
    return 0
}

# 启动容器
start_container() {
    local name=$1
    echo -e "${YELLOW}正在启动容器 ${name}...${NC}"
    if docker start "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 容器 ${name} 已启动${NC}"
    else
        echo -e "${RED}✗ 启动失败${NC}"
    fi
}

# 停止容器
stop_container() {
    local name=$1
    echo -e "${YELLOW}正在停止容器 ${name}...${NC}"
    if docker stop "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 容器 ${name} 已停止${NC}"
    else
        echo -e "${RED}✗ 停止失败${NC}"
    fi
}

# 重启容器
restart_container() {
    local name=$1
    echo -e "${YELLOW}正在重启容器 ${name}...${NC}"
    if docker restart "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 容器 ${name} 已重启${NC}"
    else
        echo -e "${RED}✗ 重启失败${NC}"
    fi
}

# 删除容器
delete_container() {
    local name=$1
    echo -e "${RED}警告: 即将删除容器 ${name}${NC}"
    printf "确认删除? (y/n): "
    read confirm
    if [ "$confirm" = "y" ]; then
        echo -e "${YELLOW}正在删除容器 ${name}...${NC}"
        if docker rm -f "$name" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 容器 ${name} 已删除${NC}"
        else
            echo -e "${RED}✗ 删除失败${NC}"
        fi
    else
        echo -e "${YELLOW}已取消删除${NC}"
    fi
}

# 查看容器日志
view_logs() {
    local name=$1
    echo -e "${CYAN}容器 ${name} 的日志:${NC}"
    echo "--------------------------------------------------------------------------------"
    docker logs --tail 50 "$name"
    echo "--------------------------------------------------------------------------------"
}

# 主菜单
show_menu() {
    echo ""
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}请选择操作:${NC}"
    echo -e "${BLUE}===================================${NC}"
    echo "  1. 启动容器"
    echo "  2. 停止容器"
    echo "  3. 重启容器"
    echo "  4. 删除容器"
    echo "  5. 查看日志"
    echo "  6. 刷新列表"
    echo "  0. 退出"
    echo -e "${BLUE}===================================${NC}"
    printf "请输入选项 [0-6]: "
}

# 选择容器
select_container() {
    echo ""
    echo -e "${YELLOW}>>> 请从上方列表中选择一个容器 <<<${NC}"
    printf "${CYAN}请输入容器序号 [1-${TOTAL_COUNT}]: ${NC}"
    read choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$TOTAL_COUNT" ]; then
        echo -e "${RED}无效的序号${NC}"
        return 1
    fi
    
    eval "SELECTED_CONTAINER=\$CONTAINER_${choice}"
    echo "$SELECTED_CONTAINER"
}

# 主循环
main() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  _   _    _  _____   __  __                                   "
        echo " | \ | |  / \|_   _| |  \/  | __ _ _ __   __ _  __ _  ___ _ __ "
        echo " |  \| | / _ \ | |   | |\/| |/ _\` | '_ \ / _\` |/ _\` |/ _ \ '__|"
        echo " | |\  |/ ___ \| |   | |  | | (_| | | | | (_| | (_| |  __/ |   "
        echo " |_| \_/_/   \_\_|   |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_|   "
        echo "                                               |___/            "
        echo -e "${NC}"
        
        if ! list_containers; then
            echo ""
            echo -e "${YELLOW}提示: 使用 deploy-nat.sh 创建新的 NAT 容器${NC}"
            echo ""
            read -p "按回车键退出..."
            exit 0
        fi
        
        show_menu
        read option
        
        case $option in
            1)
                container=$(select_container)
                [ -n "$container" ] && start_container "$container"
                ;;
            2)
                container=$(select_container)
                [ -n "$container" ] && stop_container "$container"
                ;;
            3)
                container=$(select_container)
                [ -n "$container" ] && restart_container "$container"
                ;;
            4)
                container=$(select_container)
                [ -n "$container" ] && delete_container "$container"
                ;;
            5)
                container=$(select_container)
                [ -n "$container" ] && view_logs "$container"
                ;;
            6)
                continue
                ;;
            0)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${NC}"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

main
