#!/bin/bash

# 定义颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 动态识别当前的操作系统名称
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
else
    OS_NAME="Linux"
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}    开始自动初始化 ${OS_NAME} 服务器     ${NC}"
echo -e "${GREEN}=========================================${NC}"

# 1. 更新系统软件包
echo -e "${YELLOW}>>> 1. 正在更新系统软件包索引...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y

# 2. 安装基础工具 (增加了 jq, tmux, lsof, net-tools)
echo -e "${YELLOW}>>> 2. 正在安装必备开发与网络工具...${NC}"
apt-get install -y curl wget git htop vim unzip zip software-properties-common jq tmux lsof net-tools

# 3. 设置时区为 Asia/Shanghai
echo -e "${YELLOW}>>> 3. 正在配置系统时区为 Asia/Shanghai...${NC}"
timedatectl set-timezone Asia/Shanghai

# 4. 动态判断并创建 Swap 虚拟内存
echo -e "${YELLOW}>>> 4. 正在配置 Swap 虚拟内存...${NC}"
if grep -q "swapfile" /etc/fstab; then
    echo -e "${GREEN}Swap 已经存在，跳过创建。${NC}"
else
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -le 2048 ]; then
        SWAP_SIZE="2G"
    else
        SWAP_SIZE="4G"
    fi
    echo -e "${GREEN}检测到物理内存为 ${TOTAL_MEM}MB，准备分配 ${SWAP_SIZE} 的 Swap...${NC}"
    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Swap 创建并启用成功！${NC}"
fi

# 5. 安装 Docker & Docker Compose (官方一键安装脚本，自带幂等性)
echo -e "${YELLOW}>>> 5. 正在检查并安装 Docker...${NC}"
if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker 已经安装，跳过下载。${NC}"
else
    echo -e "${GREEN}未检测到 Docker，正在执行官方安装脚本...${NC}"
    curl -fsSL https://get.docker.com | sudo bash
    # 将当前系统默认用户(ubuntu或debian)加入docker组，免sudo运行
    usermod -aG docker $USER || true
    echo -e "${GREEN}Docker 安装完成！${NC}"
fi

# 6. 安装 ZeroTier
echo -e "${YELLOW}>>> 6. 正在检查并安装 ZeroTier...${NC}"
if command -v zerotier-cli &> /dev/null; then
    echo -e "${GREEN}ZeroTier 已经安装，跳过下载。${NC}"
else
    curl -s https://install.zerotier.com | sudo bash
    echo -e "${GREEN}ZeroTier 安装完成！${NC}"
fi

# 7. 安装 Cloudflare Tunnel (cloudflared)
echo -e "${YELLOW}>>> 7. 正在检查并安装 Cloudflare Tunnel...${NC}"
if command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}cloudflared 已经安装，跳过下载。${NC}"
else
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y
    apt-get install -y cloudflared
    echo -e "${GREEN}cloudflared 安装完成！${NC}"
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  服务器初始化完成！Enjoy your coding!   ${NC}"
echo -e "${GREEN}=========================================${NC}"
