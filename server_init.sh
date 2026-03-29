#!/bin/bash

# =========================================================
# 脚本名称: server_init.sh
# 功能: 系统更新、基础工具安装、Swap配置、Docker/ZeroTier/Cloudflare安装、BBR优化
# 适用系统: Debian / Ubuntu
# =========================================================

# 定义颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限或 sudo 运行此脚本。${NC}"
    exit 1
fi

# 获取真正的用户（用于 Docker 权限）
REAL_USER=${SUDO_USER:-$USER}

# 动态识别当前的操作系统名称
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
else
    OS_NAME="Linux"
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}    开始自动初始化 ${OS_NAME} 服务器     ${NC}"
echo -e "${GREEN}    当前操作用户: ${REAL_USER}             ${NC}"
echo -e "${GREEN}=========================================${NC}"

# 1. 更新系统软件包
echo -e "${YELLOW}>>> 1. 正在更新系统软件包索引...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# 2. 安装基础工具
echo -e "${YELLOW}>>> 2. 正在安装必备工具...${NC}"
apt-get install -y \
    curl wget git htop vim unzip zip \
    software-properties-common jq tmux lsof net-tools \
    sudo ca-certificates gnupg

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
    # 使用 dd 兼容性更好
    dd if=/dev/zero of=/swapfile bs=1M count=$(echo $SWAP_SIZE | sed 's/G/1024/')
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Swap 创建并启用成功！${NC}"
fi

# 5. 安装 Docker & Docker Compose
echo -e "${YELLOW}>>> 5. 正在检查并安装 Docker...${NC}"
if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker 已经安装，跳过下载。${NC}"
else
    echo -e "${GREEN}未检测到 Docker，正在执行官方安装脚本...${NC}"
    curl -fsSL https://get.docker.com | bash
    # 将实际用户加入 docker 组
    if [ "$REAL_USER" != "root" ]; then
        usermod -aG docker "$REAL_USER"
        echo -e "${GREEN}已将用户 ${REAL_USER} 加入 docker 组。${NC}"
    fi
    echo -e "${GREEN}Docker 安装完成！${NC}"
fi

# 6. 安装 ZeroTier
echo -e "${YELLOW}>>> 6. 正在检查并安装 ZeroTier...${NC}"
if command -v zerotier-cli &> /dev/null; then
    echo -e "${GREEN}ZeroTier 已经安装。${NC}"
else
    curl -s https://install.zerotier.com | bash
    echo -e "${GREEN}ZeroTier 安装完成！${NC}"
fi

# 7. 安装 Cloudflare Tunnel
echo -e "${YELLOW}>>> 7. 正在检查并安装 Cloudflare Tunnel...${NC}"
if command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}cloudflared 已经安装。${NC}"
else
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-public-v2.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y && apt-get install -y cloudflared
    echo -e "${GREEN}cloudflared 安装完成！${NC}"
fi

# 8. 网络加速：开启原生 BBR
echo -e "${YELLOW}>>> 8. 配置网络加速 (BBR)...${NC}"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    # 清理旧配置并使用 tee 写入，确保权限无虞
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf > /dev/null
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf > /dev/null
    sysctl -p > /dev/null
    echo -e "${GREEN}原生 BBR 已激活。${NC}"
fi

# 9. 系统清理
echo -e "${YELLOW}>>> 9. 正在清理冗余软件包...${NC}"
apt-get autoremove -y
apt-get clean

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}    服务器初始化完成！Enjoy your coding!    ${NC}"
echo -e "${GREEN}=========================================${NC}"
