#!/bin/bash
# NAT 小鸡全能管理脚本
# 用法: 
#   1. ./nat.sh                  (交互式管理/新建)
#   2. ./nat.sh -t debian ...    (命令行自动部署)

set -e

# ==================== 配置区域 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

GHCR_PREFIX="ghcr.io/qiuapeng921/docker-ssh-nat"
NETWORK_NAME="nat-network"
NETWORK_SUBNET="192.168.10.0/24"
IP_PREFIX="192.168.10"

# 表格格式: 序号(6) 名称(14) 状态(10) IP(16) SSH(10) NAT(15)
TABLE_FORMAT="%-6s %-14s %-10s %-16s %-10s %-15s\n"

# ==================== 部署逻辑 ====================

# 确保网络存在
ensure_network() {
    if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        echo -e "${YELLOW}创建自定义网络: $NETWORK_NAME ($NETWORK_SUBNET)${NC}"
        docker network create --subnet="$NETWORK_SUBNET" "$NETWORK_NAME" >/dev/null
    fi
}

# 获取下一个可用 IP
get_next_ip_index() {
    # 容器名占用
    RESERVED_BY_NAME=$(docker ps -a --filter "name=^nat-" --format "{{.Names}}" | \
        awk -F'-' '{print $NF}' | grep -E '^[0-9]+$')
    
    # 网络实际占用
    RESERVED_BY_NET=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.IPv4Address}} {{end}}' | \
        tr ' ' '\n' | grep "^$IP_PREFIX\." | cut -d'.' -f4 | cut -d'/' -f1)
    
    USED_INDICES=$(echo -e "${RESERVED_BY_NAME}\n${RESERVED_BY_NET}" | sort -n | uniq)
    
    # 从 2 开始 ( .1 是网关)
    for i in $(seq 2 254); do
        if ! echo "$USED_INDICES" | grep -qx "$i"; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# 核心部署函数
deploy_container() {
    local TYPE=$1
    local PASS=$2
    local CPU=${3:-1}
    local MEM=$4

    # 默认内存逻辑
    if [ -z "$MEM" ]; then
        if [ "$TYPE" = "debian" ]; then MEM=512; else MEM=128; fi
    fi

    # 随机密码
    if [ -z "$PASS" ]; then
        PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $((8 + RANDOM % 3)))
    fi

    echo -e "${BLUE}=== 开始部署 [${TYPE}] ===${NC}"
    
    ensure_network
    
    local IP_INDEX=$(get_next_ip_index)
    if [ -z "$IP_INDEX" ]; then
        echo -e "${RED}错误: IP 地址耗尽!${NC}"
        return 1
    fi

    local CONTAINER_IP="${IP_PREFIX}.${IP_INDEX}"
    local SSH_PORT=$((10000 + IP_INDEX))
    local NAT_START=$((20000 + IP_INDEX * 10))
    local NAT_END=$((NAT_START + 19))
    local CONTAINER_NAME="nat-${TYPE}-${IP_INDEX}"

    # 检查重名 (理论上 get_next_ip_index 已经避开了，但双重保险)
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        echo -e "${RED}错误: 容器 $CONTAINER_NAME 已存在(异常状态)!${NC}"
        return 1
    fi

    # 显示配置
    echo "容器名称: ${CONTAINER_NAME}"
    echo "内网 IP : ${CONTAINER_IP}"
    echo "SSH 端口: ${SSH_PORT}"
    echo "NAT 端口: ${NAT_START}-${NAT_END}"
    echo "Root密码: ${PASS}"
    
    # 镜像拉取/构建
    local IMAGE_NAME="${TYPE}-ssh:latest"
    local REMOTE_IMAGE="${GHCR_PREFIX}-${TYPE}:latest"

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
        echo -e "${YELLOW}拉取镜像...${NC}"
        if ! docker pull "${REMOTE_IMAGE}"; then
             echo -e "${YELLOW}拉取失败，尝试本地构建...${NC}"
             docker build -t "${IMAGE_NAME}" "./${TYPE}"
        else
             docker tag "${REMOTE_IMAGE}" "${IMAGE_NAME}"
        fi
    fi

    # 运行
    local RUN_ERR
    RUN_ERR=$(docker run -d \
        --cpus="${CPU}" \
        --memory="${MEM}M" \
        --memory-swap="${MEM}M" \
        -p "${SSH_PORT}:22" \
        -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}" \
        -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}/udp" \
        --cap-add=MKNOD \
        -e ROOT_PASSWORD="${PASS}" \
        -e TZ=Asia/Shanghai \
        --name "${CONTAINER_NAME}" \
        --hostname "${CONTAINER_NAME}" \
        --network "${NETWORK_NAME}" \
        --ip "${CONTAINER_IP}" \
        --restart unless-stopped \
        "${IMAGE_NAME}" 2>&1) 
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}启动失败: ${RUN_ERR}${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ 部署成功!${NC}"
    return 0
}

# ==================== 管理逻辑 ====================

list_containers() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}NAT 小鸡列表${NC}"
    echo -e "${BLUE}===================================${NC}"
    
    # 获取 NAT 容器
    CONTAINERS=$(docker ps -a --filter "name=^nat-" --format "{{.Names}}\t{{.Status}}" | sort -V)
    
    if [ -z "$CONTAINERS" ]; then
        echo -e "${YELLOW}  暂无 NAT 容器${NC}"
        TOTAL_COUNT=0
        return 0
    fi
    
    # 表头
    printf "${CYAN}${TABLE_FORMAT}${NC}" "No." "Name" "Status" "Internal IP" "SSH Port" "NAT Ports"
    echo "---------------------------------------------------------------------------"
    
    local index=1
    while IFS=$'\t' read -r name status; do
        # 提取序号 (兼容 nat-debian-2 格式)
        ip_index=$(echo "$name" | awk -F'-' '{print $NF}')
        if ! [[ "$ip_index" =~ ^[0-9]+$ ]] || [ "$ip_index" -lt 1 ] || [ "$ip_index" -gt 254 ]; then
            continue
        fi
        
        container_ip="192.168.10.${ip_index}"
        ssh_port=$((10000 + ip_index))
        nat_start=$((20000 + ip_index * 10))
        nat_end=$((nat_start + 9))
        
        # 状态显示
        if [[ "$status" == *"Up"* ]]; then
            status_show="Running"
            printf "${TABLE_FORMAT}" "[$index]" "$name" "$status_show" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        else
            status_show="Stopped"
            printf "${RED}${TABLE_FORMAT}${NC}" "[$index]" "$name" "$status_show" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        fi
        
        eval "CONTAINER_${index}=$name"
        index=$((index + 1))
    done <<< "$CONTAINERS"
    
    TOTAL_COUNT=$((index - 1))
    echo "---------------------------------------------------------------------------"
    echo -e "共 ${CYAN}${TOTAL_COUNT}${NC} 个容器"
    echo ""
}

ask_for_selection() {
    [ "$TOTAL_COUNT" -eq 0 ] && return 1
    
    echo -e "${YELLOW}>>> 请选择容器 <<<${NC}"
    printf "输入序号 [1-${TOTAL_COUNT}]: "
    read choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$TOTAL_COUNT" ]; then
        echo -e "${RED}无效序号${NC}"
        return 1
    fi
    
    eval "SELECTED_NAME=\$CONTAINER_${choice}"
    return 0
}

# 交互式新建向导
interactive_create() {
    echo -e "${BLUE}--- 新建容器向导 ---${NC}"
    echo "1. Debian"
    echo "2. Alpine"
    read -p "选择系统 [1-2]: " sys_choice
    
    case $sys_choice in
        1) TYPE="debian" ;;
        2) TYPE="alpine" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    read -p "设置密码 (留空随机): " input_pass
    read -p "CPU核心 (默认1): " input_cpu
    
    deploy_container "$TYPE" "$input_pass" "$input_cpu" ""
    
    read -p "按回车键返回菜单..."
}

# ==================== 如果有参数，进入 CLI 模式 ====================
if [ $# -gt 0 ]; then
    TYPE=""
    PASS=""
    CPU=1
    MEM=""
    
    while getopts "t:p:c:m:h" opt; do
        case $opt in
            t) TYPE=$OPTARG ;;
            p) PASS=$OPTARG ;;
            c) CPU=$OPTARG ;;
            m) MEM=$OPTARG ;;
            h) echo "用法: $0 -t <debian|alpine> ..."; exit 0 ;;
            *) exit 1 ;;
        esac
    done

    if [ -z "$TYPE" ]; then
        echo "错误: 必须指定 -t <debian|alpine>"
        exit 1
    fi
    
    deploy_container "$TYPE" "$PASS" "$CPU" "$MEM"
    exit $?
fi

# ==================== 否则进入 交互模式 ====================
while true; do
    clear
    list_containers
    
    echo -e "${CYAN}操作菜单:${NC}"
    echo "  [1] 新建容器 (+)"
    echo "  [2] 启动"
    echo "  [3] 停止"
    echo "  [4] 重启"
    echo "  [5] 删除"
    echo "  [6] 日志"
    echo "  [0] 退出"
    echo "==================================="
    printf "选项: "
    read option
    
    case $option in
        1|+) 
            interactive_create 
            ;;
        2) 
            ask_for_selection && docker start "$SELECTED_NAME" >/dev/null && echo "成功" 
            ;;
        3) 
            ask_for_selection && docker stop "$SELECTED_NAME" >/dev/null && echo "成功" 
            ;;
        4) 
            ask_for_selection && docker restart "$SELECTED_NAME" >/dev/null && echo "成功" 
            ;;
        5) 
            ask_for_selection 
            if [ -n "$SELECTED_NAME" ]; then
                printf "${RED}确认删除 ${SELECTED_NAME}? (y/n): ${NC}"
                read confirm
                [ "$confirm" = "y" ] && docker rm -f "$SELECTED_NAME" >/dev/null && echo "已删除"
            fi
            ;;
        6) 
            ask_for_selection 
            if [ -n "$SELECTED_NAME" ]; then
                clear
                docker logs "$SELECTED_NAME"
                echo "---"
                read -p "按回车返回..." 
            fi
            ;;
        0) echo "Bye!"; exit 0 ;;
        *) ;;
    esac
done
