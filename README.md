# Debian SSH 基础镜像

这是一个包含 SSH 和常用工具的基础 Docker 镜像,提供 Debian 和 Alpine 两个版本,**支持密码登录**。

## 功能特性

- ✅ **SSH 服务**: 预装并配置 OpenSSH Server,支持密码和密钥认证
- ✅ **欢迎 Banner**: 精美的 SSH 登录欢迎界面,显示系统信息和常用命令
- ✅ **网络工具**: 包含 curl、wget、ip、ifconfig 等
- ✅ **防火墙**: 预装 iptables
- ✅ **轻量级**: 基于 Debian Slim 或 Alpine Linux

## 包含的软件包

### 网络工具
- `curl` - HTTP 客户端工具
- `wget` - 文件下载工具
- `ping` - 网络连通性测试
- `telnet` - 远程登录和端口测试
- `traceroute` - 路由追踪工具
- `dig` / `nslookup` - DNS 查询工具
- `iproute2` - 网络配置工具(提供 `ip` 命令)
- `net-tools` - 网络工具集(提供 `ifconfig`、`netstat` 等)

### SSH 和安全
- `openssh-server` - SSH 服务端(支持密码登录)
- `iptables` - 防火墙工具

### 文本编辑器
- `vim` - 强大的文本编辑器

### 系统监控工具
- `htop` - 交互式进程查看器
- `iotop` - IO 监控工具
- `lsof` - 列出打开的文件和端口
- `ps` / `top` - 进程监控(procps 包)

### 压缩解压工具
- `tar` - 打包工具
- `gzip` - gzip 压缩
- `unzip` / `zip` - ZIP 格式支持

### 其他实用工具
- `tree` - 目录树显示
- `ca-certificates` - CA 证书
- `tzdata` - 时区数据

## 项目结构

```
debian-ssh/
├── debian/                 # Debian 版本
│   ├── Dockerfile
│   ├── docker-entrypoint.sh
│   └── banner.txt          # SSH 登录欢迎界面
├── alpine/                 # Alpine 版本
│   ├── Dockerfile
│   ├── docker-entrypoint.sh
│   └── banner.txt          # SSH 登录欢迎界面
├── docker-compose.yml      # Docker Compose 配置
└── README.md               # 说明文档
```

## 构建镜像

### Debian 版本
```bash
cd debian
docker build -t debian-ssh:latest .
```

### Alpine 版本
```bash
cd alpine
docker build -t alpine-ssh:latest .
```

### 使用 Docker Compose(推荐)
```bash
docker-compose up -d
```

## 使用方法

### 基本运行(密码登录)

```bash
# Debian 版本 - 手动设置密码
docker run -d -p 2222:22 \
  -e ROOT_PASSWORD=your_password \
  --name debian-ssh \
  debian-ssh:latest

# Debian 版本 - 自动生成随机密码
docker run -d -p 2222:22 \
  --name debian-ssh \
  debian-ssh:latest

# 查看自动生成的密码
docker logs debian-ssh | grep "随机密码"

# Alpine 版本
docker run -d -p 2223:22 \
  -e ROOT_PASSWORD=your_password \
  --name alpine-ssh \
  alpine-ssh:latest
```

### 使用 SSH 公钥认证

```bash
docker run -d -p 2222:22 \
  -e ROOT_PASSWORD=your_password \
  -e SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  --name debian-ssh \
  debian-ssh:latest
```

### 数据持久化

```bash
docker run -d -p 2222:22 \
  -e ROOT_PASSWORD=your_password \
  -v /path/to/data:/data \
  --name debian-ssh \
  debian-ssh:latest
```

### NAT 小鸡场景

适用于需要端口转发的 NAT VPS 场景:

```bash
# 单个容器,映射端口段 10000-10100
docker run -d \
  -p 2222:22 \
  -p 10000-10100:10000-10100 \
  -e ROOT_PASSWORD=your_password \
  --name debian-ssh \
  debian-ssh:latest

# 多个容器,使用不同的端口段
# 容器1: 主机端口 10000-10100 -> 容器端口 10000-10100
docker run -d \
  -p 2222:22 \
  -p 10000-10100:10000-10100 \
  -e ROOT_PASSWORD=password1 \
  --name nat-vps-1 \
  debian-ssh:latest

# 容器2: 主机端口 20000-20100 -> 容器端口 10000-10100
docker run -d \
  -p 2223:22 \
  -p 20000-20100:10000-10100 \
  -e ROOT_PASSWORD=password2 \
  --name nat-vps-2 \
  debian-ssh:latest
```

**端口范围说明:**
- 容器内固定使用 `10000-10100` 端口段
- 主机端口可以灵活映射到不同范围,避免冲突
- 默认提供 101 个端口,可在 Dockerfile 中调整 `EXPOSE` 范围

### 批量部署 NAT 小鸡

使用提供的部署脚本可以快速创建 NAT 容器:

**Linux/Mac 用户:**
```bash
# 赋予执行权限
chmod +x deploy-nat.sh

# 用法: ./deploy-nat.sh <密码> <端口范围> <镜像类型>
./deploy-nat.sh MyPass123 10000-10100 debian
./deploy-nat.sh SecureP@ss 20000-20050 alpine
./deploy-nat.sh Test1234 30000-30100 debian
```

**参数说明:**
- `密码` - root 用户密码 (例如: MyPass123, SecureP@ss)
- `端口范围` - NAT 端口范围 (例如: 10000-10100, 20000-20050)
- `镜像类型` - debian 或 alpine

**部署示例:**
```bash
$ ./deploy-nat.sh MyPass123 10000-10100 debian

===================================
NAT 小鸡部署
===================================

部署信息:
  容器名称: nat-10000-10100
  镜像类型: debian
  SSH 端口: 2222
  NAT 端口: 10000-10100 (101 个端口)
  Root 密码: MyPass123

确认部署? (y/n): y

✓ 容器创建成功
✓ 容器运行正常

连接信息:
  容器名称: nat-10000-10100
  SSH 连接: ssh root@<服务器IP> -p 2222
  Root 密码: MyPass123
  NAT 端口: 10000-10100 (101 个端口)
```

**特性:**
- ✅ 自动查找可用的 SSH 端口
- ✅ 使用指定的密码
- ✅ 自动构建镜像(如果不存在)
- ✅ 检测容器名冲突
- ✅ 验证端口范围有效性
- ✅ 容器名基于端口范围,避免冲突

## 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `ROOT_PASSWORD` | root 用户密码(可选) | 自动生成 8-10 位随机密码 |
| `SSH_PUBLIC_KEY` | SSH 公钥内容 | 无 |
| `TZ` | 时区设置 | Asia/Shanghai |

**密码说明:**
- 如果不设置 `ROOT_PASSWORD`,容器启动时会自动生成 8-10 位随机密码
- 自动生成的密码会在容器日志中显示,请及时查看并保存
- 查看密码: `docker logs <容器名>`

## 连接到容器

```bash
# 使用密码登录
ssh root@localhost -p 2222

# 使用 SSH 密钥登录
ssh -i ~/.ssh/id_rsa root@localhost -p 2222
```

## 常用命令示例

连接到容器后,可以使用以下命令:

### 网络诊断
```bash
# 测试网络连通性
ping google.com
ping -c 4 8.8.8.8

# 端口连通性测试
telnet google.com 80
telnet 192.168.1.1 22

# 路由追踪
traceroute google.com

# DNS 查询
dig google.com
nslookup google.com

# 查看网络接口
ip addr
ifconfig

# 查看路由表
ip route
route -n

# 查看网络连接
netstat -tuln
ss -tuln

# 查看监听端口
lsof -i -P -n | grep LISTEN
```

### 系统监控
```bash
# 交互式进程监控
htop

# 查看进程
ps aux
top

# IO 监控
iotop

# 查看打开的文件
lsof

# 查看端口占用
lsof -i :22
```

### 文件操作
```bash
# 编辑文件
vim /etc/hosts

# 查看目录树
tree /etc
tree -L 2 /var

# 压缩文件
tar -czf backup.tar.gz /data
gzip file.txt
zip archive.zip file1 file2

# 解压文件
tar -xzf backup.tar.gz
gunzip file.txt.gz
unzip archive.zip
```

### HTTP 请求
```bash
# 下载文件
wget https://example.com/file.zip
curl -O https://example.com/file.zip

# 查看 HTTP 响应头
curl -I https://www.google.com

# POST 请求
curl -X POST -d "key=value" https://api.example.com
```

## 安全建议

⚠️ **当前配置**:
- ✅ 已启用 SSH 密码登录
- ✅ 已启用 root 用户密码认证
- ✅ 同时支持密码和密钥认证

**生产环境安全加固建议**:

1. **仅使用 SSH 密钥认证**: 
   ```dockerfile
   sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   ```

2. **禁用 root 密码登录**: 修改 Dockerfile 中的 SSH 配置
   ```dockerfile
   sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
   ```

3. **修改默认 SSH 端口**: 在运行时映射到非标准端口
   ```bash
   docker run -d -p 10022:22 ...
   ```

4. **使用强密码**: 设置复杂密码,至少 12 位,包含大小写字母、数字和特殊字符

## 镜像大小对比

- **Debian (bookworm-slim)**: ~150MB
- **Alpine**: ~50MB

## 版本说明

- Debian 版本基于 `debian:bookworm-slim`
- Alpine 版本基于 `alpine:latest`

## 许可证

MIT License
