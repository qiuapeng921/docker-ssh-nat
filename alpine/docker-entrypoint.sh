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

# ==================== 原生服务启动 (OpenRC) ====================
# 1. 配置 OpenRC 容器适配 (避免报错)
sed -i 's/#rc_sys=""/rc_sys="docker"/' /etc/rc.conf 2>/dev/null || true
echo 'rc_provide="loopback net"' >> /etc/rc.conf

# 2. 初始化并启动所有注册到 default 级别的服务 (如哪吒、hysteria)
mkdir -p /run/openrc && touch /run/openrc/softlevel
echo "default" > /run/openrc/softlevel
/sbin/openrc default
# ==============================================================

echo "✓ 系统就绪"

# 执行传入的命令
exec "$@"
