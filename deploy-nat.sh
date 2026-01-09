#!/bin/bash
# NAT 小鸡全自动部署脚本 (Linux 纯净版)
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

show_help() {
    echo -e "${BLUE}NAT 小鸡部署工具 (Linux专用)${NC}"
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

echo -e "${YELLOW}正在扫描端口资源...${NC}"

# --- 核心优化: 预加载占用端口 ---

# 1. 提取 Docker 占用的所有端口(含端口段)
RAW_DOCKER_PORTS=$(docker ps --format '{{.Ports}}' | grep -oP '(?<=:)[0-9-]+(?=->)' | sort -u || echo "")

# 2. 提取 Linux 系统监听的端口
RAW_SYSTEM_PORTS=$(netstat -tuln 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' || echo "")

# 3. 展开所有端口段
EXPANDED_PORTS=""
for item in $RAW_DOCKER_PORTS $RAW_SYSTEM_PORTS; do
    if [[ "$item" == *"-"* ]]; then
        start=${item%-*}
        end=${item#*-}
        [ $((end - start)) -lt 2000 ] && EXPANDED_PORTS="$EXPANDED_PORTS $(seq $start $end)"
    else
        EXPANDED_PORTS="$EXPANDED_PORTS $item"
    fi
done

# 转换为极速检索字符串
ALL_OCCUPIED=" $EXPANDED_PORTS "

is_port_free() {
    [[ "$ALL_OCCUPIED" == *" $1 "* ]] && return 1
    return 0
}

# 寻找资源
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
echo "配置信息:"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像系统: ${TYPE}"
echo "  资源配额: ${CPU}核 / ${MEM}MB"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC}"
echo "  Root 密码: ${PASS}"
echo -e "${BLUE}===================================${NC}"

read -p "确认部署? (y/n): " confirm
[ "$confirm" != "y" ] && exit 0

IMAGE_NAME="${TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在构建镜像...${NC}"
    docker build -t "${IMAGE_NAME}" "./${TYPE}"
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
    echo -e "${RED}✗ 启动失败${NC}"
    exit 1
fi

echo -e "\n${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@服务器IP -p ${SSH_PORT}"
echo " Root 密码: ${PASS}"
