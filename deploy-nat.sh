#!/bin/bash
# NAT 小鸡全自动部署脚本 (IP 递增版)
# 用法: bash deploy-nat.sh -t <debian|alpine> [选项]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
DEFAULT_CPU=1
GHCR_PREFIX="ghcr.io/qiuapeng921/docker-ssh-nat"

# 网络配置
NETWORK_NAME="nat-network"
NETWORK_SUBNET="192.168.10.0/24"
IP_PREFIX="192.168.10"

# 端口计算规则
# IP 最后一位 N -> SSH端口: 10000+N, NAT端口: (20000+N*10) ~ (20000+N*10+9)

show_help() {
    echo -e "${BLUE}NAT 小鸡部署工具 (IP递增版)${NC}"
    echo ""
    echo "用法: $0 -t <debian|alpine> [选项]"
    echo ""
    echo "选项:"
    echo "  -t  镜像类型 (debian/alpine)"
    echo "  -p  Root 密码 (可选, 默认随机)"
    echo "  -c  CPU 核心限制 (默认: 1)"
    echo "  -m  内存限制 MB (Debian:512, Alpine:128)"
    echo ""
    echo "自动分配规则:"
    echo "  IP 192.168.10.N -> SSH端口 10000+N, NAT端口 20000+N*10 ~ 20000+N*10+9"
    exit 0
}

TYPE=""
PASS=""
CPU=$DEFAULT_CPU
MEM=""

while getopts "t:p:c:m:h" opt; do
    case $opt in
        t) TYPE=$OPTARG ;;
        p) PASS=$OPTARG ;;
        c) CPU=$OPTARG ;;
        m) MEM=$OPTARG ;;
        h) show_help ;;
        *) exit 1 ;;
    esac
done

[ -z "$TYPE" ] && { echo -e "${RED}错误: 请使用 -t 指定镜像类型${NC}"; show_help; exit 1; }

# 处理默认内存
if [ "$TYPE" = "debian" ]; then MIN_MEM=512; else MIN_MEM=128; fi
MEM=${MEM:-$MIN_MEM}
[ "$MEM" -lt "$MIN_MEM" ] && MEM=$MIN_MEM

# 随机密码
[ -z "$PASS" ] && PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $((8 + RANDOM % 3)))

# 确保自定义网络存在
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}创建自定义网络: $NETWORK_NAME ($NETWORK_SUBNET)${NC}"
    docker network create --subnet="$NETWORK_SUBNET" "$NETWORK_NAME" >/dev/null
fi

# 获取下一个可用的 IP 序号 (1-254)
get_next_ip_index() {
    # 1. 提取所有 nat- 容器的序号（预留位，包括已停止的）
    RESERVED_BY_NAME=$(docker ps -a --filter "name=^nat-" --format "{{.Names}}" | \
        sed 's/nat-//' | grep -E '^[0-9]+$')
    
    # 2. 提取 Docker 网络中实际正在使用的 IP 序号 (防止 Address already in use)
    RESERVED_BY_NET=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.IPv4Address}} {{end}}' | \
        tr ' ' '\n' | grep "^$IP_PREFIX\." | cut -d'.' -f4 | cut -d'/' -f1)
    
    # 合并、排序、去重
    USED_INDICES=$(echo -e "${RESERVED_BY_NAME}\n${RESERVED_BY_NET}" | sort -n | uniq)
    
    # 从 2 开始查找第一个未使用的序号 ( .1 通常是网关)
    for i in $(seq 2 254); do
        if ! echo "$USED_INDICES" | grep -qx "$i"; then
            echo "$i"
            return 0
        fi
    done
    
    echo ""
    return 1
}

IP_INDEX=$(get_next_ip_index)
if [ -z "$IP_INDEX" ]; then
    echo -e "${RED}错误: 网络 IP 地址已耗尽 (1-254 全部占用)!${NC}"
    exit 1
fi

# 根据 IP 序号计算端口
CONTAINER_IP="${IP_PREFIX}.${IP_INDEX}"
SSH_PORT=$((10000 + IP_INDEX))
NAT_START=$((20000 + IP_INDEX * 10))
NAT_END=$((NAT_START + 9))
CONTAINER_NAME="nat-${TYPE}-${IP_INDEX}"

# 检查容器名称是否已存在
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo -e "${RED}错误: 容器 $CONTAINER_NAME 已存在!${NC}"
    exit 1
fi

echo -e "${BLUE}===================================${NC}"
echo "分配配置:"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像系统: ${TYPE}"
echo "  资源限制: ${CPU}核 / ${MEM}MB"
echo -e "  内网 IP: ${CYAN}${CONTAINER_IP}${NC}"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC} (10个)"
echo "  Root 密码: ${PASS}"
echo -e "${BLUE}===================================${NC}"

printf "确认部署? (y/n): "
read confirm
[ "$confirm" != "y" ] && exit 0

# --- 镜像处理 ---
IMAGE_NAME="${TYPE}-ssh:latest"
REMOTE_IMAGE="${GHCR_PREFIX}-${TYPE}:latest"

if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在尝试拉取云端镜像...${NC}"
    if docker pull "${REMOTE_IMAGE}"; then
        docker tag "${REMOTE_IMAGE}" "${IMAGE_NAME}"
    else
        echo -e "${YELLOW}本地构建镜像中...${NC}"
        docker build -t "${IMAGE_NAME}" "./${TYPE}"
    fi
fi

echo -e "${YELLOW}正在启动容器...${NC}"
RUN_ERR=$(docker run -d \
    --cpus="${CPU}" \
    --memory="${MEM}M" \
    --memory-swap="${MEM}M" \
    -p "${SSH_PORT}:22" \
    -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}" \
    --cap-add=MKNOD \
    -e ROOT_PASSWORD="${PASS}" \
    -e TZ=Asia/Shanghai \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --network "${NETWORK_NAME}" \
    --ip "${CONTAINER_IP}" \
    --restart unless-stopped \
    "${IMAGE_NAME}" 2>&1) || {
    echo -e "${RED}✗ 启动失败!${NC}"
    echo -e "${YELLOW}错误原因:${NC}"
    echo "$RUN_ERR"
    exit 1
}

echo -e "${GREEN}✓ 容器创建成功${NC}"
echo -e "\n${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@127.0.0.1 -p ${SSH_PORT}"
echo "内网 IP: ${CONTAINER_IP}"
echo "Root 密码: ${PASS}"
