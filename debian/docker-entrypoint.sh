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

# 启动 cron 服务
if command -v crond >/dev/null 2>&1; then
    crond
    echo "✓ 定时任务服务已启动"
elif command -v cron >/dev/null 2>&1; then
    service cron start
    echo "✓ 定时任务服务已启动"
fi

# 启动 cron 服务
[ -x /etc/init.d/cron ] && /etc/init.d/cron start

# ==================== 原生服务启动 (SysVinit) ====================
# 扫描并启动所有注册在 rc2 级别的第三方服务
echo "▶ 正在拉起已注册系统服务..."
if [ -d "/etc/rc2.d" ]; then
    for s in /etc/rc2.d/S*; do
        [ -x "$s" ] || continue
        s_name=$(basename "$s" | cut -c4-) # 提取服务名
        case "$s_name" in
            ssh*|cron*|networking|rmnologin) continue ;;
            *) "$s" start >/dev/null 2>&1 & ;;
        esac
    done
fi
# ================================================================

echo "✓ 系统就绪"

# 执行传入的命令
exec "$@"
