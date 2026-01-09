#!/bin/bash
# NAT 小鸡自动部署脚本 (带资源限制)
# 用法: ./deploy-nat.sh <密码> <镜像类型> [CPU核心] [内存MB]
# 示例: ./deploy-nat.sh MyPass123 debian 1 512

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

# 检查基础参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 参数不足${NC}"
    echo ""
    echo "用法: $0 <密码> <镜像类型> [CPU核心] [内存MB]"
    echo "示例: $0 MyPass123 debian 0.5 512"
    echo ""
    echo "默认最小资源:"
    echo "  Debian: 512MB"
    echo "  Alpine: 128MB"
    exit 1
fi

PASSWORD=$1
IMAGE_TYPE=$2
CPU_LIMIT=${3:-"0.5"}  # 默认 0.5 核

# 设置各镜像默认最小内存
if [[ "$IMAGE_TYPE" == "debian" ]]; then
    MIN_MEM=512
elif [[ "$IMAGE_TYPE" == "alpine" ]]; then
    MIN_MEM=128
else
    echo -e "${RED}错误: 不支持的镜像类型 $IMAGE_TYPE${NC}"
    exit 1
fi

MEM_LIMIT=${4:-$MIN_MEM}

# 校验内存是否低于最小值
if [ "$MEM_LIMIT" -lt "$MIN_MEM" ]; then
    echo -e "${YELLOW}警告: $IMAGE_TYPE 建议内存不低于 ${MIN_MEM}MB，已自动调整为最小值。${NC}"
    MEM_LIMIT=$MIN_MEM
fi

# 函数: 检查端口是否被占用
is_port_occupied() {
    local port=$1
    if docker ps --format '{{.Ports}}' | grep -q ":${port}->"; then return 0; fi
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then return 0; fi
    fi
    return 1
}

# 寻找可用端口
find_free_ssh_port() {
    local port=$SSH_SEARCH_START
    while [ $port -lt 20000 ]; do
        if ! is_port_occupied $port; then echo $port; return 0; fi
        port=$((port + 1))
    done
    echo "FAILED"
    return 1
}

find_free_nat_block() {
    local current=$NAT_SEARCH_START
    while [ $current -lt 60000 ]; do
        local block_ok=true
        for ((p=current; p<(current + NAT_PORT_COUNT); p++)); do
            if is_port_occupied $p; then block_ok=false; break; fi
        done
        if [ "$block_ok" = true ]; then echo $current; return 0; fi
        current=$((current + NAT_PORT_COUNT))
    done
    echo "FAILED"
    return 1
}

echo -e "${YELLOW}正在搜寻可用端口资源...${NC}"
SSH_PORT=$(find_free_ssh_port)
NAT_START=$(find_free_nat_block)

if [ "$SSH_PORT" = "FAILED" ] || [ "$NAT_START" = "FAILED" ]; then
    echo -e "${RED}错误: 无法找到合适的可用端口!${NC}"
    exit 1
fi

NAT_END=$((NAT_START + NAT_PORT_COUNT - 1))
CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}NAT 小鸡部署 (资源限额版)${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}配置详情:${NC}"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像类型: ${IMAGE_TYPE}"
echo -e "  CPU 限制: ${CYAN}${CPU_LIMIT} 核${NC}"
echo -e "  内存限制: ${CYAN}${MEM_LIMIT} MB${NC}"
echo -e "  SSH 端口: ${SSH_PORT}"
echo -e "  NAT 端口: ${NAT_START}-${NAT_END}"
echo "  Root 密码: ${PASSWORD}"
echo ""

# 确认部署
read -p "确认部署? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then exit 0; fi

# 检查镜像
IMAGE_NAME="${IMAGE_TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在构建镜像...${NC}"
    docker build -t ${IMAGE_NAME} ./${IMAGE_TYPE}
fi

echo -e "${YELLOW}正在启动容器并应用资源限制...${NC}"
if docker run -d \
    --cpus="${CPU_LIMIT}" \
    --memory="${MEM_LIMIT}m" \
    -p "${SSH_PORT}:22" \
    -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}" \
    -e ROOT_PASSWORD="${PASSWORD}" \
    -e TZ=Asia/Shanghai \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --restart unless-stopped \
    ${IMAGE_NAME} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 容器创建成功${NC}"
else
    echo -e "${RED}✗ 容器创建失败，请检查 Docker 资源限制设置${NC}"
    exit 1
fi

sleep 2
echo ""
echo -e "${BLUE}连接信息:${NC}"
echo -e "  SSH: ${CYAN}ssh root@<IP> -p ${SSH_PORT}${NC}"
echo "  密码: ${PASSWORD}"
echo "  NAT 端口: ${NAT_START}-${NAT_END}"
