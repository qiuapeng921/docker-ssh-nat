#!/bin/bash
# NAT 小鸡全自动部署脚本 (高兼容 & 健壮版)
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
SSH_SEARCH_START=10000
NAT_SEARCH_START=20000
NAT_PORT_COUNT=100
DEFAULT_CPU=1
GHCR_PREFIX="ghcr.io/qiuapeng921/docker-ssh-nat"

show_help() {
    echo -e "${BLUE}NAT 小鸡部署工具${NC}"
    echo ""
    echo "用法: $0 -t <debian|alpine> [选项]"
    echo ""
    echo "选项:"
    echo "  -t  镜像类型 (debian/alpine)"
    echo "  -p  Root 密码 (可选, 默认随机)"
    echo "  -c  CPU 核心限制 (默认: 1)"
    echo "  -m  内存限制 MB (Debian:512, Alpine:128)"
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

echo -e "${YELLOW}正在快速扫描端口与容器名称...${NC}"

# --- 核心优化: 更健壮的资源提取 ---

# 1. 提取所有已占用的端口 (兼容所有版本的终端输出)
OCCUPIED_PORTS=$(docker ps --format '{{.Ports}}' | tr ',' '\n' | sed -n 's/.*:\([0-9-]*\)->.*/\1/p' | sort -u || echo "")
SYSTEM_PORTS=$(netstat -tuln 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' || echo "")

# 展开端口段
EXPANDED=""
for item in $OCCUPIED_PORTS $SYSTEM_PORTS; do
    if [[ "$item" == *"-"* ]]; then
        s=${item%-*}; e=${item#*-}
        [ $((e - s)) -lt 2000 ] && EXPANDED="$EXPANDED $(seq $s $e)"
    else
        EXPANDED="$EXPANDED $item"
    fi
done

# 2. 提取所有已存在的容器名称（包括已停止的）
OCCUPIED_NAMES=$(docker ps -a --format '{{.Names}}')

ALL_OCCUPIED_PORTS=" $EXPANDED "
ALL_OCCUPIED_NAMES=" $OCCUPIED_NAMES "

is_free() {
    local port=$1
    local name="nat-$1"
    
    # 检查端口是否被占用
    if [[ "$ALL_OCCUPIED_PORTS" == *" $port "* ]]; then
        return 1
    fi
    
    # 检查容器名称是否已存在（使用 grep 精确匹配）
    if echo "$OCCUPIED_NAMES" | grep -qx "$name"; then
        return 1
    fi
    
    return 0
}

# 寻找 SSH 端口
SSH_PORT=""
for ((p=SSH_SEARCH_START; p<20000; p++)); do
    if is_free $p; then SSH_PORT=$p; break; fi
done

# 寻找 NAT 块
NAT_START=""
for ((current=NAT_SEARCH_START; current<60000; current+=NAT_PORT_COUNT)); do
    block_ok=true
    for ((p=current; p<current+NAT_PORT_COUNT; p++)); do
        if [[ "$ALL_OCCUPIED_PORTS" == *" $p "* ]]; then block_ok=false; break; fi
    done
    if [ "$block_ok" = true ]; then NAT_START=$current; break; fi
done

if [ -z "$SSH_PORT" ] || [ -z "$NAT_START" ]; then
    echo -e "${RED}错误: 端口资源不足或名称冲突!${NC}"
    exit 1
fi

NAT_END=$((NAT_START + NAT_PORT_COUNT - 1))
CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo "分配配置:"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像系统: ${TYPE}"
echo "  资源限制: ${CPU}核 / ${MEM}MB"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC}"
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
# 捕获错误输出到变量
RUN_ERR=$(docker run -d \
    --cpus="${CPU}" \
    --memory="${MEM}M" \
    --memory-swap="${MEM}M" \
    -p "${SSH_PORT}:22" \
    -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}" \
    -e ROOT_PASSWORD="${PASS}" \
    -e TZ=Asia/Shanghai \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --restart unless-stopped \
    "${IMAGE_NAME}" 2>&1) || {
    echo -e "${RED}✗ 启动失败!${NC}"
    echo -e "${YELLOW}错误原因:${NC}"
    echo "$RUN_ERR"
    exit 1
}

echo -e "${GREEN}✓ 容器创建成功${NC}"
echo -e "\n${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@服务器IP -p ${SSH_PORT}"
echo "Root 密码: ${PASS}"
