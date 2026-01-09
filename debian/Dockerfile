# 基于 Debian 的基础镜像
FROM debian:bookworm-slim

# 设置环境变量,避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 设置时区(可根据需要修改)
ENV TZ=Asia/Shanghai

# 更新软件包列表并安装必要的工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # 网络工具
    curl \
    wget \
    iputils-ping \
    telnet \
    traceroute \
    dnsutils \
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
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# 配置 SSH 服务
RUN mkdir -p /var/run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    # 允许 root 密码登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 启用密码认证
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # 启用 Banner
    echo "Banner /etc/ssh/banner.txt" >> /etc/ssh/sshd_config && \
    # 禁用 PAM
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

# 复制 SSH Banner
COPY banner.txt /etc/ssh/banner.txt

# 暴露 SSH 端口
EXPOSE 22

# 暴露 NAT 端口范围(可根据需要调整)
# 用于 NAT 小鸡场景,提供给用户使用的端口段
EXPOSE 10000-10100

# 启动脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 设置入口点
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 默认启动 SSH 服务
CMD ["/usr/sbin/sshd", "-D"]
