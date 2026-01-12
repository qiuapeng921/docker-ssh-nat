#!/bin/bash

# 初始化密码（仅首次启动）
if [ ! -f /etc/.initialized ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✓ 已设置密码: $ROOT_PASSWORD"
    touch /etc/.initialized
fi

# 执行 CMD（/sbin/init）
exec "$@"
