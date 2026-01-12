#!/bin/bash
set -e

# 只有在第一次启动时才设置密码和公钥
if [ ! -f "/etc/.initialized" ]; then
    echo "▶ 正在进行首次启动初始化..."
    
    # 设置 root 密码
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✓ 已设置 root 密码"

    # 如果提供了 SSH 公钥
    if [ -n "$SSH_PUBLIC_KEY" ]; then
        echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "✓ 已添加 SSH 公钥"
    fi

    # 创建标记文件
    touch /etc/.initialized
else
    echo "✓ 检测到已完成初始化，跳过密码设置（保持现有密码）"
fi

# 启动定时任务
[ -x /usr/sbin/crond ] && crond

# ==================== 原生服务启动 (OpenRC 增强版) ====================
# 1. 准备 OpenRC 运行环境 (仅保留必须的 softlevel 和 started 状态)
mkdir -p /run/openrc/started && echo "default" > /run/openrc/softlevel

# 2. 这里的重点：逐个显式拉起服务，确保 OpenRC 脚本被正确解析
if [ -d "/etc/runlevels/default" ]; then
    echo "▶ 正在检测已注册服务..."
    for s_link in /etc/runlevels/default/*; do
        [ -L "$s_link" ] || [ -f "$s_link" ] || continue
        s_name=$(basename "$s_link")
        
        # 排除掉我们已经手动起过或者不需要起的服务
        case "$s_name" in
            sshd|ssh|cron*|networking|cgroups|hostname|sysfs|killprocs|savecache|net|local)
                continue 
                ;;
            *)
                echo "  → 启动原生服务: $s_name"
                # 先强制清除可能存在的残留状态，再启动
                rc-service "$s_name" zap >/dev/null 2>&1 || true
                rc-service "$s_name" start >/dev/null 2>&1 &
                sleep 1 # 给后台进程一点时间稳定
                ;;
        esac
    done
fi
# ==============================================================

echo "✓ 系统就绪"

# 执行传入的命令
exec "$@"
