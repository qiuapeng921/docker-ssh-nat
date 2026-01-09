#!/bin/bash
# NAT 小鸡自动部署脚本 (SSH与NAT端口分离)
# 用法: ./deploy-nat.sh <密码> <镜像类型>
# 示例: ./deploy-nat.sh MyPass123 debian

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
SSH_SEARCH_START=10000    # SSH 端口从 10000 开始查找
NAT_SEARCH_START=20000    # NAT 端口从 20000 开始查找
NAT_PORT_COUNT=100        # 每个小鸡分配 100 个 NAT 端口

# 检查参数
if [ $# -ne 2 ]; then
    echo -e "${RED}错误: 参数不正确${NC}"
    echo ""
    echo "用法: $0 <密码> <镜像类型>"
    echo "示例: $0 MyPass123 debian"
    exit 1
fi

PASSWORD=$1
IMAGE_TYPE=$2

# 验证镜像类型
if [[ "$IMAGE_TYPE" != "debian" && "$IMAGE_TYPE" != "alpine" ]]; then
    echo -e "${RED}错误: 镜像类型必须是 debian 或 alpine${NC}"
    exit 1
fi

# 函数: 检查端口是否被占用
is_port_occupied() {
    local port=$1
    if docker ps --format '{{.Ports}}' | grep -q ":${port}->"; then
        return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 0
        fi
    fi
    return 1
}

# 函数: 寻找可用的 SSH 端口
find_free_ssh_port() {
    local port=$SSH_SEARCH_START
    while [ $port -lt 20000 ]; do
        if ! is_port_occupied $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
    echo "FAILED"
    return 1
}

# 函数: 寻找可用的 NAT 端口段 (连续 100 个)
find_free_nat_block() {
    local current=$NAT_SEARCH_START
    while [ $current -lt 60000 ]; do
        local block_ok=true
        for ((p=current; p<(current + NAT_PORT_COUNT); p++)); do
            if is_port_occupied $p; then
                block_ok=false
                break
            fi
        done
        
        if [ "$block_ok" = true ]; then
            echo $current
            return 0
        fi
        current=$((current + NAT_PORT_COUNT)) # 以 100 为步长查找，更整齐
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
echo -e "${BLUE}NAT 小鸡部署 (SSH与NAT分离)${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}分配资源:${NC}"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像类型: ${IMAGE_TYPE}"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC} (10000段)"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC} (20000段)"
echo "  Root 密码: ${PASSWORD}"
echo ""

# 确认部署
read -p "确认部署? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo -e "${RED}已取消部署${NC}"
    exit 0
fi

# 构建镜像
IMAGE_NAME="${IMAGE_TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在构建镜像...${NC}"
    docker build -t ${IMAGE_NAME} ./${IMAGE_TYPE}
fi

echo -e "${YELLOW}正在启动容器...${NC}"
if docker run -d \
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
    echo -e "${RED}✗ 容器创建失败${NC}"
    exit 1
fi

sleep 2
echo ""
echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}部署完成! 🎉${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}连接信息:${NC}"
echo -e "  SSH 连接: ${CYAN}ssh root@<服务器IP> -p ${SSH_PORT}${NC}"
echo -e "  Root 密码: ${PASSWORD}"
echo -e "  NAT 端口范围: ${NAT_START}-${NAT_END}"
echo ""
echo -e "${YELLOW}管理命令:${NC}"
echo "  查看日志: docker logs ${CONTAINER_NAME}"
echo "  停止小鸡: docker stop ${CONTAINER_NAME}"
echo "  删除小鸡: docker rm -f ${CONTAINER_NAME}"
