#!/bin/bash
# NAT 小鸡快速部署脚本
# 用法: ./deploy-nat.sh <密码> <端口范围> <镜像类型>
# 示例: ./deploy-nat.sh MyPass123 10000-10100 debian

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查参数
if [ $# -ne 3 ]; then
    echo -e "${RED}错误: 参数不正确${NC}"
    echo ""
    echo "用法: $0 <密码> <端口范围> <镜像类型>"
    echo ""
    echo "参数说明:"
    echo "  密码        - root 密码,例如: MyPass123, SecureP@ss"
    echo "  端口范围    - NAT端口范围,例如: 10000-10100, 20000-20050"
    echo "  镜像类型    - debian 或 alpine"
    echo ""
    echo "示例:"
    echo "  $0 MyPass123 10000-10100 debian"
    echo "  $0 SecureP@ss 20000-20050 alpine"
    echo ""
    exit 1
fi

# 获取参数
PASSWORD=$1
PORT_RANGE=$2
IMAGE_TYPE=$3

# 验证端口范围格式
if [[ ! "$PORT_RANGE" =~ ^[0-9]+-[0-9]+$ ]]; then
    echo -e "${RED}错误: 端口范围格式不正确,应为: 起始端口-结束端口${NC}"
    echo "示例: 10000-10100"
    exit 1
fi

# 解析端口范围
PORT_START=$(echo $PORT_RANGE | cut -d'-' -f1)
PORT_END=$(echo $PORT_RANGE | cut -d'-' -f2)

# 验证端口范围
if [ $PORT_START -ge $PORT_END ]; then
    echo -e "${RED}错误: 起始端口必须小于结束端口${NC}"
    exit 1
fi

PORT_COUNT=$((PORT_END - PORT_START + 1))

# 验证镜像类型
if [[ "$IMAGE_TYPE" != "debian" && "$IMAGE_TYPE" != "alpine" ]]; then
    echo -e "${RED}错误: 镜像类型必须是 debian 或 alpine${NC}"
    exit 1
fi

# 生成容器名称(基于端口范围)
CONTAINER_NAME="nat-${PORT_START}-${PORT_END}"

# 检查容器是否已存在
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}错误: 容器 ${CONTAINER_NAME} 已存在${NC}"
    echo "请先删除现有容器: docker rm -f ${CONTAINER_NAME}"
    exit 1
fi

# 查找可用的 SSH 端口
SSH_PORT=2222
while docker ps --format '{{.Ports}}' | grep -q ":${SSH_PORT}->"; do
    SSH_PORT=$((SSH_PORT + 1))
done

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}NAT 小鸡部署${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}部署信息:${NC}"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像类型: ${IMAGE_TYPE}"
echo "  SSH 端口: ${SSH_PORT}"
echo "  NAT 端口: ${PORT_START}-${PORT_END} (${PORT_COUNT} 个端口)"
echo "  Root 密码: ${PASSWORD}"
echo ""

# 确认部署
read -p "确认部署? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo -e "${RED}已取消部署${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}开始部署...${NC}"

# 检查镜像是否存在
IMAGE_NAME="${IMAGE_TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo ""
    echo -e "${YELLOW}镜像不存在,正在构建 ${IMAGE_NAME}...${NC}"
    if docker build -t ${IMAGE_NAME} ./${IMAGE_TYPE}; then
        echo -e "${GREEN}✓ 镜像构建成功${NC}"
    else
        echo -e "${RED}✗ 镜像构建失败${NC}"
        exit 1
    fi
fi

# 运行容器
echo ""
echo -e "${YELLOW}正在创建容器...${NC}"

# 计算容器内端口范围(从 10000 开始)
CONTAINER_PORT_END=$((10000 + PORT_COUNT - 1))

if docker run -d \
    -p "${SSH_PORT}:22" \
    -p "${PORT_START}-${PORT_END}:10000-${CONTAINER_PORT_END}" \
    -e ROOT_PASSWORD="${PASSWORD}" \
    -e TZ=Asia/Shanghai \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --restart unless-stopped \
    ${IMAGE_NAME} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 容器创建成功${NC}"
else
    echo -e "${RED}✗ 容器创建失败${NC}"
    echo ""
    echo "尝试查看错误信息:"
    docker run -d \
        -p "${SSH_PORT}:22" \
        -p "${PORT_START}-${PORT_END}:10000-${CONTAINER_PORT_END}" \
        -e ROOT_PASSWORD="${PASSWORD}" \
        -e TZ=Asia/Shanghai \
        --name "${CONTAINER_NAME}" \
        --hostname "${CONTAINER_NAME}" \
        --restart unless-stopped \
        ${IMAGE_NAME}
    exit 1
fi

# 等待容器启动
echo ""
echo -e "${YELLOW}等待容器启动...${NC}"
sleep 2

# 检查容器状态
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${GREEN}✓ 容器运行正常${NC}"
else
    echo -e "${RED}✗ 容器启动失败${NC}"
    echo ""
    echo "容器日志:"
    docker logs ${CONTAINER_NAME}
    echo ""
    echo "容器状态:"
    docker ps -a | grep ${CONTAINER_NAME}
    exit 1
fi

# 显示容器启动日志
echo ""
echo -e "${YELLOW}容器启动日志:${NC}"
docker logs ${CONTAINER_NAME}

echo ""
echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}部署完成! 🎉${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo -e "${YELLOW}连接信息:${NC}"
echo -e "  ${CYAN}容器名称:${NC} ${CONTAINER_NAME}"
echo -e "  ${CYAN}SSH 连接:${NC} ssh root@<服务器IP> -p ${SSH_PORT}"
echo -e "  ${CYAN}Root 密码:${NC} ${PASSWORD}"
echo -e "  ${CYAN}NAT 端口:${NC} ${PORT_START}-${PORT_END} (${PORT_COUNT} 个端口)"
echo ""
echo -e "${YELLOW}管理命令:${NC}"
echo "  查看容器状态: docker ps | grep ${CONTAINER_NAME}"
echo "  查看容器日志: docker logs ${CONTAINER_NAME}"
echo "  进入容器:     docker exec -it ${CONTAINER_NAME} bash"
echo "  停止容器:     docker stop ${CONTAINER_NAME}"
echo "  删除容器:     docker rm -f ${CONTAINER_NAME}"
echo ""
echo -e "${GREEN}部署成功!${NC}"
