#!/bin/bash
set -e

# 设置 root 密码(如果环境变量中有设置)
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✓ 已设置 root 密码"
else
    # 自动生成 8-10 位随机密码
    PASSWORD_LENGTH=$((8 + RANDOM % 3))  # 随机 8-10 位
    AUTO_PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $PASSWORD_LENGTH)
    echo "root:$AUTO_PASSWORD" | chpasswd
    echo "⚠ 未设置 ROOT_PASSWORD 环境变量"
    echo "✓ 已自动生成随机密码: $AUTO_PASSWORD"
    echo "⚠ 请妥善保存此密码!"
fi

# 如果提供了 SSH 公钥,添加到 authorized_keys
if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "✓ 已添加 SSH 公钥"
fi

echo "✓ SSH 服务启动中..."

# 执行传入的命令
exec "$@"
