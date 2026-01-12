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

# 启动 cron 服务 (因为你在 Dockerfile 中安装了 dcron)
if command -v crond >/dev/null 2>&1; then
    crond
    echo "✓ 定时任务服务已启动"
elif command -v cron >/dev/null 2>&1; then
    service cron start
    echo "✓ 定时任务服务已启动"
fi

echo "✓ SSH 服务启动中..."

# 执行传入的命令
exec "$@"
