#!/bin/bash
# NAT 小鸡自动部署脚本 (参数重构版)
# 用法: bash deploy-nat.sh -t <镜像类型> [-p <密码>] [-c <CPU核心>] [-m <内存MB>]

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

# Windows 环境适配: 禁用 Git Bash 的路径转换(防止端口冒号被误转)
export MSYS_NO_PATHCONV=1
export COMPOSE_CONVERT_WINDOWS_PATHS=1

# 默认配置
SSH_SEARCH_START=10000
NAT_SEARCH_START=20000
NAT_PORT_COUNT=100
DEFAULT_CPU=1

# 帮助信息
show_help() {
    echo -e "${BLUE}NAT 小鸡部署工具${NC}"
    echo ""
    echo "用法: $0 -t <debian|alpine> [选项]"
    echo ""
    echo "选项:"
    echo "  -t  镜像类型 (必填: debian 或 alpine)"
    echo "  -p  Root 密码 (可选, 留空则随机生成 8-10 位)"
    echo "  -c  CPU 核心限制 (可选, 默认: 1)"
    echo "  -m  内存限制 MB (可选, Debian 默认: 512, Alpine 默认: 128)"
    echo "  -h  显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 -t debian -p MyPass123"
    echo "  $0 -t alpine -c 0.5 -m 256"
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
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

if [ -z "$TYPE" ]; then
    echo -e "${RED}错误: 必须使用 -t 指定镜像类型${NC}"
    show_help
    exit 1
fi

# 处理默认内存
if [ "$TYPE" = "debian" ]; then
    MIN_MEM=512
elif [ "$TYPE" = "alpine" ]; then
    MIN_MEM=128
else
    echo -e "${RED}错误: 不支持的类型 $TYPE${NC}"
    exit 1
fi

if [ -z "$MEM" ]; then
    MEM=$MIN_MEM
elif [ "$MEM" -lt "$MIN_MEM" ]; then
    echo -e "${YELLOW}警告: $TYPE 最小内存为 ${MIN_MEM}MB，已自动调整${NC}"
    MEM=$MIN_MEM
fi

# 处理密码
if [ -z "$PASS" ]; then
    LEN=$((8 + RANDOM % 3))
    PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $LEN)
    echo -e "${YELLOW}提示: 未指定密码，已生成随机密码: ${CYAN}$PASS${NC}"
fi

# 函数: 检查端口是否被占用
is_port_occupied() {
    local port=$1
    # 1. 优先检查 Docker 容器已映射的端口 (跨平台通用)
    if docker ps --format '{{.Ports}}' | grep -q ":${port}->"; then
        return 0
    fi
    
    # 2. 尝试检查系统端口 (带容错)
    # 针对 Linux 环境使用 netstat -tuln
    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then return 0; fi
    # 针对 Windows (Git Bash) 环境使用 netstat -ano
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        if netstat -ano | grep -q "LISTENING" | grep -q ":${port} "; then return 0; fi
    fi

    return 1
}

# 寻找可用端口
find_free_ssh_port() {
    local port=$SSH_SEARCH_START
    while [ "$port" -lt 20000 ]; do
        if ! is_port_occupied "$port"; then echo "$port"; return 0; fi
        port=$((port + 1))
    done
    echo "FAILED"
}

find_free_nat_block() {
    local current=$NAT_SEARCH_START
    while [ "$current" -lt 60000 ]; do
        local block_ok=true
        local p=$current
        local end=$((current + NAT_PORT_COUNT))
        while [ "$p" -lt "$end" ]; do
            if is_port_occupied "$p"; then
                block_ok=false
                break
            fi
            p=$((p + 1))
        done
        if [ "$block_ok" = true ]; then echo "$current"; return 0; fi
        current=$((current + NAT_PORT_COUNT))
    done
    echo "FAILED"
}

echo -e "${YELLOW}正在搜寻可用端口资源...${NC}"
SSH_PORT=$(find_free_ssh_port)
NAT_START=$(find_free_nat_block)

if [ "$SSH_PORT" = "FAILED" ] || [ "$NAT_START" = "FAILED" ]; then
    echo -e "${RED}错误: 端口不足!${NC}"
    exit 1
fi

NAT_END=$((NAT_START + NAT_PORT_COUNT - 1))
CONTAINER_NAME="nat-${SSH_PORT}"

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}NAT 小鸡部署${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo "配置信息:"
echo "  容器名称: ${CONTAINER_NAME}"
echo "  镜像系统: ${TYPE}"
echo -e "  CPU 限制: ${CYAN}${CPU} 核${NC}"
echo -e "  内存限制: ${CYAN}${MEM} MB${NC}"
echo "  SSH 端口: ${SSH_PORT}"
echo "  NAT 端口: ${NAT_START}-${NAT_END}"
echo "  Root 密码: ${PASS}"
echo ""

printf "确认部署? (y/n): "
read confirm
if [ "$confirm" != "y" ]; then exit 0; fi

IMAGE_NAME="${TYPE}-ssh:latest"
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}正在构建镜像...${NC}"
    docker build -t "${IMAGE_NAME}" "./${TYPE}"
fi

echo -e "${YELLOW}正在启动容器...${NC}"
# 移除静默模式，以便观察 Windows 下可能出现的错误
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
    
    echo -e "${GREEN}✓ 容器创建指令已发送${NC}"
    
    # 验证端口映射
    MAPPED_PORT=$(docker port "${CONTAINER_NAME}" 22)
    if [ -n "$MAPPED_PORT" ]; then
        echo -e "${GREEN}✓ 端口映射验证成功: ${MAPPED_PORT}${NC}"
    else
        echo -e "${RED}⚠ 警告: 端口映射似乎未生效, 请检查 Docker Desktop 状态${NC}"
    fi
    
    # 验证资源
    ACTUAL_MEM=$(docker inspect "${CONTAINER_NAME}" --format '{{.HostConfig.Memory}}')
    if [ "$ACTUAL_MEM" != "0" ]; then
        echo -e "${GREEN}✓ 内存限制已确认: ${MEM}MB${NC}"
    fi
else
    echo -e "${RED}✗ 容器启动失败${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}部署完成! 🎉${NC}"
echo "SSH 连接: ssh root@服务器IP -p ${SSH_PORT}"
echo "Root 密码: ${PASS}"
