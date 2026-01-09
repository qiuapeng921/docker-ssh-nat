#!/bin/bash
# NAT 小鸡全自动部署脚本 (云端版)
# 用法: ./deploy-nat.sh -t <debian|alpine> [选项]

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
    echo -e "${BLUE}NAT 小鸡部署工具 (支持 GHCR 云端镜像)${NC}"
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

# 参数解析
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

echo -e "${YELLOW}正在快速扫描端口资源...${NC}"

# --- 端口扫描逻辑 ---
RAW_DOCKER_PORTS=$(docker ps --format '{{.Ports}}' | grep -oP '(?<=:)[0-9-]+(?=->)' | sort -u || echo "")
RAW_SYSTEM_PORTS=$(netstat -tuln 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' || echo "")
EXPANDED_PORTS=""
for item in $RAW_DOCKER_PORTS $RAW_SYSTEM_PORTS; do
    if [[ "$item" == *"-"* ]]; then
        start=${item%-*}; end=${item#*-}
        [ $((end - start)) -lt 2000 ] && EXPANDED_PORTS="$EXPANDED_PORTS $(seq $start $end)"
    else
        EXPANDED_PORTS="$EXPANDED_PORTS $item"
    fi
done
ALL_OCCUPIED=" $EXPANDED_PORTS "

is_port_free() { [[ "$ALL_OCCUPIED" == *" $1 "* ]] && return 1; return 0; }

SSH_PORT=""
for ((p=SSH_SEARCH_START; p<20000; p++)); do
    if is_port_free $p; then SSH_PORT=$p; break; fi
done

NAT_START=""
for ((current=NAT_SEARCH_START; current<60000; current+=NAT_PORT_COUNT)); do
    block_ok=true
    for ((p=current; p<current+NAT_PORT_COUNT; p++)); do
        if ! is_port_free $p; then block_ok=false; break; fi
    done
    if [ "$block_ok" = true ]; then NAT_START=$current; break; fi
done

[ -z "$SSH_PORT" ] || [ -z "$NAT_START" ] || NAT_END=$((NAT_START + NAT_PORT_COUNT - 1))
[ -z "$NAT_END" ] && { echo -e "${RED}错误: 端口资源不足!${NC}"; exit 1; }

CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo "配置详情:"
echo "  镜像系统: ${TYPE}"
echo "  资源限制: ${CPU}核 / ${MEM}MB"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC}"
echo "  Root 密码: ${PASS}"
echo -e "${BLUE}===================================${NC}"

read -p "确认部署? (y/n): " confirm
[ "$confirm" != "y" ] && exit 0

# --- 镜像处理逻辑: 优先拉取，失败则本地构建 ---
IMAGE_NAME="${TYPE}-ssh:latest"
REMOTE_IMAGE="${GHCR_PREFIX}-${TYPE}:latest"

if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}本地无镜像，正在尝试从云端拉取 (GHCR)...${NC}"
    if docker pull "${REMOTE_IMAGE}"; then
        echo -e "${GREEN}✓ 云端镜像拉取成功${NC}"
        docker tag "${REMOTE_IMAGE}" "${IMAGE_NAME}"
    else
        echo -e "${YELLOW}⚠ 无法连接云端或镜像未发布，正在进行本地构建...${NC}"
        docker build -t "${IMAGE_NAME}" "./${TYPE}"
    fi
fi

echo -e "${YELLOW}正在启动容器...${NC}"
if docker run -d \
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
    "${IMAGE_NAME}" > /dev/null 2>&1; then
    
    echo -e "${GREEN}✓ 容器创建成功${NC}"
else
    echo -e "${RED}✗ 启动失败，请检查 Docker 日志${NC}"
    exit 1
fi

echo -e "\n${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@服务器IP -p ${SSH_PORT}"
echo "Root 密码: ${PASS}"
