# 基于 Debian 的基础镜像
FROM debian:latest

# 设置环境变量,避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 设置时区(可根据需要修改)
ENV TZ=Asia/Shanghai

# 设置默认密码
ENV ROOT_PASSWORD=123456

# 更新软件包列表并安装必要的工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-server \
    curl \
    wget \
    cron \
    dos2unix \
    vim \
    htop \
    net-tools \
    procps \
    sysvinit-utils \
    lsb-release \
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# 配置 SSH 服务
RUN mkdir -p /var/run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    # 允许 root 密码登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 允许密码认证
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # 禁用原有 Banner，改用 MOTD (登录后显示)
    sed -i 's/^Banner/#Banner/g' /etc/ssh/sshd_config && \
    # 禁用 PAM
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

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
CMD ["/usr/sbin/sshd", "-D"]
