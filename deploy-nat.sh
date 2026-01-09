#!/bin/bash
# NAT 小鸡全自动部署脚本 (极速性能版)
# 用法: bash deploy-nat.sh -t <debian|alpine> [选项]

# 自动提升至 Bash 运行
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Windows 环境适配: 禁用 Git Bash 的路径转换
export MSYS_NO_PATHCONV=1
export COMPOSE_CONVERT_WINDOWS_PATHS=1

# 配置
SSH_SEARCH_START=10000
NAT_SEARCH_START=20000
NAT_PORT_COUNT=100
DEFAULT_CPU=1

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

# 解析参数
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

if [ -z "$TYPE" ]; then
    echo -e "${RED}错误: 必须使用 -t 指定镜像类型${NC}"
    exit 1
fi

# 处理默认内存逻辑
if [ "$TYPE" = "debian" ]; then MIN_MEM=512; else MIN_MEM=128; fi
MEM=${MEM:-$MIN_MEM}
[ "$MEM" -lt "$MIN_MEM" ] && MEM=$MIN_MEM

# 随机密码逻辑
if [ -z "$PASS" ]; then
    PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $((8 + RANDOM % 3)))
fi

echo -e "${YELLOW}正在快速扫描端口资源...${NC}"

# --- 核心优化: 预加载占用端口 ---
# 1. 获取 Docker 所有已映射端口
OCCUPIED_DOCKER=$(docker ps --format '{{.Ports}}' | grep -oP '(?<=:)\d+(?=->)' || echo "")

# 2. 获取系统监听端口
OCCUPIED_SYSTEM=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OCCUPIED_SYSTEM=$(netstat -tuln | awk '{print $4}' | awk -F: '{print $NF}' || echo "")
elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
    OCCUPIED_SYSTEM=$(netstat -ano | grep LISTENING | awk '{print $3}' | awk -F: '{print $NF}' || echo "")
fi

# 合并所有占用端口
ALL_OCCUPIED=" $OCCUPIED_DOCKER $OCCUPIED_SYSTEM "

# 高速检测函数
is_port_free() {
    if [[ "$ALL_OCCUPIED" == *" $1 "* ]]; then return 1; fi
    return 0
}

# 寻找 SSH 端口
SSH_PORT=""
for ((p=SSH_SEARCH_START; p<20000; p++)); do
    if is_port_free $p; then SSH_PORT=$p; break; fi
done

# 寻找 NAT 块
NAT_START=""
for ((current=NAT_SEARCH_START; current<60000; current+=NAT_PORT_COUNT)); do
    found_block=true
    for ((p=current; p<current+NAT_PORT_COUNT; p++)); do
        if ! is_port_free $p; then found_block=false; break; fi
    done
    if [ "$found_block" = true ]; then NAT_START=$current; break; fi
done

if [ -z "$SSH_PORT" ] || [ -z "$NAT_START" ]; then
    echo -e "${RED}错误: 未能找到可用端口块!${NC}"
    exit 1
fi

NAT_END=$((NAT_START + NAT_PORT_COUNT - 1))
CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo "配置信息:"
echo "  镜像系统: ${TYPE}"
echo "  资源配额: ${CPU}核 / ${MEM}MB"
echo -e "  SSH 端口: ${CYAN}${SSH_PORT}${NC}"
echo -e "  NAT 端口: ${CYAN}${NAT_START}-${NAT_END}${NC}"
echo "  Root 密码: ${PASS}"
echo -e "${BLUE}===================================${NC}"

printf "确认部署? (y/n): "
read confirm
[ "$confirm" != "y" ] && exit 0

# 构建/运行...
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
    "${IMAGE_NAME}"; then
    
    echo -e "${GREEN}✓ 容器创建成功${NC}"
    ACTUAL_MEM=$(docker inspect "${CONTAINER_NAME}" --format '{{.HostConfig.Memory}}')
    [ "$ACTUAL_MEM" != "0" ] && echo -e "${GREEN}✓ 资源限制已生效${NC}"
else
    echo -e "${RED}✗ 启动失败${NC}"
    exit 1
fi

echo -e "\n${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@服务器IP -p ${SSH_PORT}"
echo "Root 密码: ${PASS}"
