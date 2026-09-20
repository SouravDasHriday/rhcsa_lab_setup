#!/bin/bash
# =============================================================================
# host-setup.sh - Prepare Ubuntu host for RHCSA Docker Lab
# =============================================================================
# Run this script on your Ubuntu AWS instance before starting the lab.
# It installs Docker, enables required kernel modules, and optionally
# sets up SELinux support on the host.
#
# Usage: sudo bash host-setup.sh [--with-selinux]
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ENABLE_SELINUX=false
if [[ "$1" == "--with-selinux" ]]; then
    ENABLE_SELINUX=true
fi

echo -e "${BOLD}${BLUE}"
echo '╔══════════════════════════════════════════════════════════╗'
echo '║          RHCSA Lab - Ubuntu Host Setup Script           ║'
echo '╚══════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo bash host-setup.sh)${NC}"
    exit 1
fi

# Step 1: Update system
echo -e "${BOLD}[1/6] Updating system packages...${NC}"
apt-get update -qq
apt-get upgrade -y -qq
echo -e "${GREEN}✓ System updated${NC}"

# Step 2: Install Docker
echo -e "${BOLD}[2/6] Installing Docker...${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}✓ Docker already installed$(docker --version)${NC}"
else
    # Install Docker using official script
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ubuntu 2>/dev/null || true
    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}✓ Docker installed${NC}"
fi

# Step 3: Install Docker Compose plugin
echo -e "${BOLD}[3/6] Checking Docker Compose...${NC}"
if docker compose version &>/dev/null; then
    echo -e "${GREEN}✓ Docker Compose available ($(docker compose version --short))${NC}"
else
    apt-get install -y -qq docker-compose-plugin
    echo -e "${GREEN}✓ Docker Compose installed${NC}"
fi

# Step 4: Load required kernel modules
echo -e "${BOLD}[4/6] Loading kernel modules...${NC}"
modules=("nfs" "nfsd" "loop" "dm_mod" "dm_thin_pool" "overlay" "br_netfilter" "xt_conntrack" "nf_nat" "nf_conntrack")
for mod in "${modules[@]}"; do
    if modprobe "$mod" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $mod"
    else
        echo -e "  ${YELLOW}⚠${NC} $mod (not available - some labs may be limited)"
    fi
done

# Persist modules across reboots
for mod in "${modules[@]}"; do
    echo "$mod" >> /etc/modules-load.d/rhcsa-lab.conf
done
sort -u /etc/modules-load.d/rhcsa-lab.conf -o /etc/modules-load.d/rhcsa-lab.conf
echo -e "${GREEN}✓ Kernel modules configured${NC}"

# Step 5: Configure system settings
echo -e "${BOLD}[5/6] Configuring system settings...${NC}"

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-rhcsa-lab.conf

# Increase max loop devices
echo 'options loop max_loop=64' > /etc/modprobe.d/loop.conf

# Increase inotify watches (for systemd in containers)
echo 'fs.inotify.max_user_instances=8192' >> /etc/sysctl.d/99-rhcsa-lab.conf
echo 'fs.inotify.max_user_watches=524288' >> /etc/sysctl.d/99-rhcsa-lab.conf
sysctl -p /etc/sysctl.d/99-rhcsa-lab.conf > /dev/null 2>&1

echo -e "${GREEN}✓ System settings configured${NC}"

# Step 6: SELinux setup (optional)
echo -e "${BOLD}[6/6] SELinux configuration...${NC}"
if [ "$ENABLE_SELINUX" = true ]; then
    echo -e "${YELLOW}Installing SELinux on Ubuntu host...${NC}"
    apt-get install -y -qq selinux-basics selinux-policy-default auditd
    selinux-activate 2>/dev/null || true
    echo -e "${YELLOW}⚠  SELinux installed. You MUST reboot for it to take effect.${NC}"
    echo -e "${YELLOW}   After reboot, run: sudo setenforce 1${NC}"
    echo -e "${YELLOW}   Note: SELinux on Ubuntu is experimental. For the best SELinux${NC}"
    echo -e "${YELLOW}   practice experience, the containers include all SELinux tools${NC}"
    echo -e "${YELLOW}   and you can practice commands in permissive/simulated mode.${NC}"
else
    echo -e "  SELinux host setup skipped (use --with-selinux to enable)"
    echo -e "  ${CYAN}Note: SELinux tools are installed inside containers for practice.${NC}"
    echo -e "  ${CYAN}You can practice semanage, restorecon, getsebool commands.${NC}"
    echo -e "  ${CYAN}Run with: sudo bash host-setup.sh --with-selinux for full support.${NC}"
fi

# Summary
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              Host Setup Complete!                        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. ${CYAN}cd /path/to/rhcsa${NC}"
echo -e "    2. ${CYAN}./lab.sh build${NC}     - Build container images"
echo -e "    3. ${CYAN}./lab.sh start${NC}     - Start the lab environment"
echo -e "    4. ${CYAN}./lab.sh setup${NC}     - Initialize SSH keys & verify"
echo ""
if [ "$ENABLE_SELINUX" = true ]; then
    echo -e "  ${RED}${BOLD}⚠  REBOOT REQUIRED for SELinux: sudo reboot${NC}"
fi
