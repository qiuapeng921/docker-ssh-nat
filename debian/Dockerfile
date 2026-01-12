# Debian 容器镜像 (Systemd 模式)
FROM debian:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV ROOT_PASSWORD=123456

# 安装必要工具 + systemd
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    systemd systemd-sysv \
    openssh-server curl wget cron vim htop procps net-tools \
    ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /lib/systemd/system/multi-user.target.wants/* \
    && rm -f /etc/systemd/system/*.wants/* \
    && rm -f /lib/systemd/system/local-fs.target.wants/* \
    && rm -f /lib/systemd/system/sockets.target.wants/*udev* \
    && rm -f /lib/systemd/system/sockets.target.wants/*initctl* \
    && rm -f /lib/systemd/system/basic.target.wants/* \
    && rm -f /lib/systemd/system/anaconda.target.wants/*

# SSH 配置
RUN mkdir -p /var/run/sshd /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    systemctl enable ssh cron

# 入口脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# MOTD
COPY banner.txt /etc/motd

EXPOSE 22
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/sbin/init"]
