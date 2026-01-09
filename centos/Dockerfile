FROM quay.io/centos/centos:stream9

RUN dnf -y update && dnf -y install \
    openssh-server \
    curl \
    wget \
    iproute \
    net-tools \
    vim \
    iputils \
    traceroute \
    telnet \
    bind-utils \
    htop \
    iotop \
    lsof \
    tar \
    gzip \
    unzip \
    tree \
    procps-ng \
    && dnf clean all

# CentOS 需要生成 SSH 主机密钥，否则启动会报错
RUN ssh-keygen -A

RUN   sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

COPY banner.txt /etc/ssh/banner.txt
RUN chmod 644 /etc/ssh/banner.txt
RUN echo 'Banner /etc/ssh/banner.txt' >> /etc/ssh/sshd_config

EXPOSE 22
EXPOSE 10000-10100

CMD ["/usr/sbin/sshd", "-D"]
