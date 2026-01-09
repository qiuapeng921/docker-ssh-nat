FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    curl \
    wget \
    iproute2 \
    net-tools \
    vim \
    ping \
    traceroute \
    telnet \
    dnsutils \
    htop \
    iotop \
    lsof \
    tar \
    gzip \
    unzip \
    tree \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /var/run/sshd

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

COPY banner.txt /etc/ssh/banner.txt
RUN chmod 644 /etc/ssh/banner.txt
RUN echo 'Banner /etc/ssh/banner.txt' >> /etc/ssh/sshd_config

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 22
EXPOSE 10000-10100

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
