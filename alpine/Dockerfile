# Alpine 容器镜像 (OpenRC 模式)
FROM alpine:latest

ENV TZ=Asia/Shanghai

# 安装必要工具
RUN apk update && \
    apk add --no-cache \
    openssh curl wget bash vim htop procps dcron \
    openrc openrc-init \
    ca-certificates tzdata \
    && cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# SSH 配置
RUN ssh-keygen -A && \
    mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's#/bin/ash#/bin/bash#g' /etc/passwd && \
    rc-update add sshd default && \
    rc-update add dcron default

# OpenRC 容器模式配置
RUN sed -i 's/#rc_sys=""/rc_sys="docker"/' /etc/rc.conf && \
    echo 'rc_provide="loopback net"' >> /etc/rc.conf

# 设置默认密码
RUN echo 'root:123456' | chpasswd

# MOTD
COPY banner.txt /etc/motd

EXPOSE 22
CMD ["/sbin/init"]
