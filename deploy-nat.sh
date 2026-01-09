#!/bin/bash
# NAT 小鸡全自动部署脚本
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
START_BASE_PORT=10000  # 从 10000 端口开始搜寻
NAT_PORT_COUNT=100     # 每个小鸡分配 100 个 NAT 端口

# 检查参数
if [ $# -ne 2 ]; then
    echo -e "${RED}错误: 参数不正确${NC}"
    echo ""
    echo "用法: $0 <密码> <镜像类型>"
    echo ""
    echo "说明: 脚本将自动寻找 1 个 SSH 端口 + 100 个连续的 NAT 端口"
    echo "示例: $0 MyPass123 debian"
    echo ""
    exit 1
fi

PASSWORD=$1
IMAGE_TYPE=$2

# 验证镜像类型
if [[ "$IMAGE_TYPE" != "debian" && "$IMAGE_TYPE" != "alpine" ]]; then
    echo -e "${RED}错误: 镜像类型必须是 debian 或 alpine${NC}"
    exit 1
fi

# 函数: 检查端口是否被占用 (Docker 或系统)
is_port_occupied() {
    local port=$1
    # 检查 Docker 端口映射
    if docker ps --format '{{.Ports}}' | grep -q ":${port}->"; then
        return 0
    fi
    # 检查系统端口占用 (需要 netstat)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 0
        fi
    fi
    return 1
}

# 函数: 寻找可用的连续端口块 (1 SSH + 100 NAT)
find_available_block() {
    local current=$START_BASE_PORT
    local found=false
    
    while [ "$found" = false ]; do
        local block_ok=true
        # 检查从 current 到 current + NAT_PORT_COUNT 的所有端口
        for ((p=current; p<=(current + NAT_PORT_COUNT); p++)); do
            if is_port_occupied $p; then
                block_ok=false
                break
            fi
        done
        
        if [ "$block_ok" = true ]; then
            echo $current
            return 0
        fi
        current=$((current + 1))
        # 简单限制，防止死循环
        if [ $current -gt 60000 ]; then
            echo "FAILED"
            return 1
        fi
    done
}

echo -e "${YELLOW}正在搜寻可用端口资源...${NC}"
SSH_PORT=$(find_available_block)

if [ "$SSH_PORT" = "FAILED" ]; then
    echo -e "${RED}错误: 无法找到足够的连续可用端口!${NC}"
    exit 1
fi

# 计算 NAT 范围
NAT_START=$((SSH_PORT + 1))
NAT_END=$((SSH_PORT + NAT_PORT_COUNT))
CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}NAT 小鸡全自动部署${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}自动分配资源:${NC}"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像类型: ${IMAGE_TYPE}"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC} (${NAT_PORT_COUNT} 个)"
echo "  Root 密码: ${PASSWORD}"
echo ""

# 确认部署
read -p "确认部署? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo -e "${RED}已取消部署${NC}"
    exit 0
fi

# 检查镜像
IMAGE_NAME="${IMAGE_TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在构建镜像...${NC}"
    docker build -t ${IMAGE_NAME} ./${IMAGE_TYPE}
fi

echo -e "${YELLOW}正在创建容器...${NC}"
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
    echo -e "${RED}✗ 容器创建失败，尝试查看错误:${NC}"
    docker run -d \
        -p "${SSH_PORT}:22" \
        -p "${NAT_START}-${NAT_END}:${NAT_START}-${NAT_END}" \
        -e ROOT_PASSWORD="${PASSWORD}" \
        --name "${CONTAINER_NAME}" \
        ${IMAGE_NAME}
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
echo -e "  NAT 端口: ${NAT_START}-${NAT_END}"
echo ""
echo -e "${YELLOW}管理命令:${NC}"
echo "  查看日志: docker logs ${CONTAINER_NAME}"
echo "  删除小鸡: docker rm -f ${CONTAINER_NAME}"
