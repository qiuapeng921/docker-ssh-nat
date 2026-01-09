# 基于 Alpine 的基础镜像
FROM alpine:latest

# 设置环境变量
ENV TZ=Asia/Shanghai

# 安装必要的工具
RUN apk add --no-cache \
    # 网络工具
    curl \
    wget \
    iputils \
    busybox-extras \
    bind-tools \
    # SSH 服务
    openssh-server \
    # 防火墙和网络配置
    iptables \
    iproute2 \
    net-tools \
    # 文本编辑器
    vim \
    # 系统监控工具
    htop \
    iotop \
    lsof \
    procps \
    # 压缩解压工具
    tar \
    gzip \
    unzip \
    zip \
    # 其他实用工具
    tree \
    bash \
    ca-certificates \
    tzdata \
    && cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# 配置 SSH 服务
RUN ssh-keygen -A && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    # 允许 root 密码登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 启用密码认证
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # 禁用原有 Banner，改用 MOTD (登录后显示)
    sed -i 's/^Banner/#Banner/g' /etc/ssh/sshd_config && \
    # 设置默认 shell 为 bash
    sed -i 's#/bin/ash#/bin/bash#g' /etc/passwd

# 设置 SSH 登录后的欢迎语 (MOTD)
COPY banner.txt /etc/motd

# 暴露 SSH 端口
EXPOSE 22

# 启动脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 设置入口点
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 默认启动 SSH 服务
CMD ["/usr/sbin/sshd", "-D", "-e"]
