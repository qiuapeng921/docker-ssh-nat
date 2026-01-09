# docker-ssh-nat

专为 NAT 小鸡设计的轻量级 SSH 容器镜像,内置常用网络工具,支持端口转发。

## ✨ 功能特性

- ✅ **双版本支持**: 提供 Debian (bookworm-slim) 和 Alpine Linux 两个版本
- ✅ **常用工具箱**: 内置 30+ 工具 (curl, wget, ping, telnet, traceroute, dig, vim, htop, iotop, lsof, zip, tree 等)
- ✅ **灵活认证**: 支持自定义 root 密码或自动生成随机密码(8-10位)
- ✅ **精美 Banner**: 登录时显示系统信息和命令速查
- ✅ **NAT 优化**: 专为端口段映射场景优化,主机与容器端口完美对应

## 🚀 NAT 小鸡一键部署

使用提供的 `deploy-nat.sh` 脚本可以快速创建 NAT 小鸡容器。

### 1. 准备工作
```bash
# 获取源码
git clone https://github.com/qiuapeng921/docker-ssh-nat.git
cd docker-ssh-nat

# 赋予权限
chmod +x deploy-nat.sh
```

### 2. 启动小鸡
```bash
# 用法: ./deploy-nat.sh -t <镜像类型> [选项]
# 示例: 启动一个密码为 123456 的 Debian 小鸡
./deploy-nat.sh -t debian -p 123456

# 示例: 启动一个随机密码、0.5核、256MB 的 Alpine 小鸡
./deploy-nat.sh -t alpine -c 0.5 -m 256
```

**参数说明:**
- `-t`: 镜像类型 (`debian` 或 `alpine`)，**必填**。
- `-p`: root 密码，如果不填则自动生成 **8-10 位**随机密码。
- `-c`: CPU 限制，默认位 `1` 核。
- `-m`: 内存限制 (MB)，Debian 默认 `512`，Alpine 默认 `128`。

**自动化逻辑 (10000/20000 分离):**
- **SSH 端口**: 自动从 `10000` 段寻找首个空闲端口。
- **NAT 端口**: 自动从 `20000` 段寻找连续的 `100` 个空闲端口。
- **独立搜寻**: SSH 端口与 NAT 端口独立查找，互不交叉。

## 🛠️ 管理与使用

### 连接容器
- **SSH 登录**: `ssh root@<服务器IP> -p <脚本输出的端口>`
- **默认 SSH 端口**: 脚本会自动从 10000 开始寻找可用端口

### 常用管理命令
```bash
# 查看小鸡状态
docker ps | grep nat-

# 查看小鸡日志(包含密码信息)
docker logs nat-10000-10100

# 停止并删除小鸡
docker rm -f nat-10000-10100
```

## 🌐 端口映射逻辑
- 主机端口与容器端口**完全一致**。
- 如果你指定端口范围 `10000-10100`,则在容器内部运行的服务也必须监听在 `10000-10100` 之间的端口才能通过外网访问。

## 📦 包含的常用命令
- **网络**: `ping`, `telnet`, `traceroute`, `dig`, `curl`, `wget`, `ifconfig`, `ip`, `netstat`
- **监控**: `htop`, `iotop`, `lsof`, `ps`
- **编辑**: `vim`
- **工具**: `tar`, `gzip`, `unzip`, `tree`

## 许可证
MIT License
