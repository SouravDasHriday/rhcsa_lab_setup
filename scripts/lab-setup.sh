#!/bin/bash
# =============================================================================
# lab-setup.sh - Post-start initialization for the RHCSA lab environment
# =============================================================================
# Run this after 'docker compose up' to:
#   1. Generate and distribute SSH keys
#   2. Verify connectivity between all machines
#   3. Print lab environment status
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_NAME="rhcsa"
MACHINES=("workstation" "servera" "serverb" "bastion")
STUDENT_MACHINES=("workstation" "servera" "serverb")
TARGET_MACHINES=("servera" "serverb")

echo -e "${BOLD}${BLUE}"
echo '╔══════════════════════════════════════════════════════════╗'
echo '║       RHCSA Lab Environment Setup & Verification       ║'
echo '╚══════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# Function: Wait for container to be healthy
wait_for_container() {
    local name=$1
    local max_wait=60
    local waited=0
    echo -ne "  Waiting for ${CYAN}${name}${NC}... "
    while [ $waited -lt $max_wait ]; do
        if docker exec "$name" systemctl is-system-running --wait &>/dev/null 2>&1; then
            echo -e "${GREEN}✓ Ready${NC}"
            return 0
        fi
        # Also accept "degraded" since some masked services cause this
        state=$(docker exec "$name" systemctl is-system-running 2>/dev/null || true)
        if [[ "$state" == "running" || "$state" == "degraded" ]]; then
            echo -e "${GREEN}✓ Ready${NC} (${state})"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo -e "${RED}✗ Timeout${NC}"
    return 1
}

# Step 1: Wait for all containers
echo -e "${BOLD}[1/4] Waiting for containers to initialize...${NC}"
for machine in "${MACHINES[@]}"; do
    wait_for_container "$machine"
done
echo ""

# Step 2: Generate and distribute SSH keys
echo -e "${BOLD}[2/4] Setting up SSH key authentication...${NC}"

# Generate key on workstation for student user
echo -ne "  Generating SSH key pair for student@workstation... "
docker exec workstation bash -c '
    if [ ! -f /home/student/.ssh/id_rsa ]; then
        su - student -c "ssh-keygen -t rsa -b 2048 -f /home/student/.ssh/id_rsa -N \"\" -q"
    fi
' 2>/dev/null
echo -e "${GREEN}✓${NC}"

# Distribute student key to all machines
for target in "${STUDENT_MACHINES[@]}"; do
    echo -ne "  Copying student key to ${CYAN}${target}${NC}... "
    # Get the public key from workstation
    PUB_KEY=$(docker exec workstation cat /home/student/.ssh/id_rsa.pub 2>/dev/null)
    if [ -n "$PUB_KEY" ]; then
        docker exec "$target" bash -c "
            mkdir -p /home/student/.ssh
            echo '$PUB_KEY' >> /home/student/.ssh/authorized_keys
            sort -u /home/student/.ssh/authorized_keys -o /home/student/.ssh/authorized_keys
            chmod 700 /home/student/.ssh
            chmod 600 /home/student/.ssh/authorized_keys
            chown -R student:student /home/student/.ssh
        " 2>/dev/null
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Failed to read public key${NC}"
    fi
done

# Generate and distribute root keys too
echo -ne "  Generating SSH key pair for root@workstation... "
docker exec workstation bash -c '
    if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N "" -q
    fi
' 2>/dev/null
echo -e "${GREEN}✓${NC}"

for target in "${STUDENT_MACHINES[@]}"; do
    echo -ne "  Copying root key to ${CYAN}${target}${NC}... "
    ROOT_PUB_KEY=$(docker exec workstation cat /root/.ssh/id_rsa.pub 2>/dev/null)
    if [ -n "$ROOT_PUB_KEY" ]; then
        docker exec "$target" bash -c "
            mkdir -p /root/.ssh
            echo '$ROOT_PUB_KEY' >> /root/.ssh/authorized_keys
            sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
            chmod 700 /root/.ssh
            chmod 600 /root/.ssh/authorized_keys
        " 2>/dev/null
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done

# Add host keys to known_hosts to prevent prompts
echo -ne "  Configuring known hosts (skip host key checking)... "
for machine in "${STUDENT_MACHINES[@]}"; do
    docker exec "$machine" bash -c '
        mkdir -p /home/student/.ssh /root/.ssh
        echo "StrictHostKeyChecking no" > /home/student/.ssh/config
        echo "UserKnownHostsFile /dev/null" >> /home/student/.ssh/config
        chmod 600 /home/student/.ssh/config
        chown student:student /home/student/.ssh/config
        echo "StrictHostKeyChecking no" > /root/.ssh/config
        echo "UserKnownHostsFile /dev/null" >> /root/.ssh/config
        chmod 600 /root/.ssh/config
    ' 2>/dev/null
done
echo -e "${GREEN}✓${NC}"
echo ""

# Step 3: Verify connectivity
echo -e "${BOLD}[3/4] Verifying connectivity...${NC}"

# Test SSH from workstation to targets
for target in "${TARGET_MACHINES[@]}"; do
    echo -ne "  SSH workstation → ${CYAN}${target}${NC} (student)... "
    result=$(docker exec workstation su - student -c "ssh -o ConnectTimeout=5 student@${target} hostname" 2>/dev/null || echo "FAILED")
    if [[ "$result" == *"${target}"* ]]; then
        echo -e "${GREEN}✓ ${result}${NC}"
    else
        echo -e "${YELLOW}⚠ SSH not ready yet (run this script again in 30s)${NC}"
    fi
done

# Test DNS resolution
for target in "${MACHINES[@]}"; do
    echo -ne "  DNS ${CYAN}${target}.lab.example.com${NC}... "
    result=$(docker exec workstation getent hosts ${target}.lab.example.com 2>/dev/null || echo "FAILED")
    if [[ "$result" != "FAILED" && -n "$result" ]]; then
        echo -e "${GREEN}✓ ${result}${NC}"
    else
        echo -e "${YELLOW}⚠ DNS not resolving (using /etc/hosts fallback)${NC}"
    fi
done

# Test NFS exports on bastion
echo -ne "  NFS exports on ${CYAN}bastion${NC}... "
nfs_result=$(docker exec bastion exportfs -v 2>/dev/null | head -1 || echo "FAILED")
if [[ "$nfs_result" != "FAILED" && -n "$nfs_result" ]]; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${YELLOW}⚠ NFS not ready yet${NC}"
fi
echo ""

# Step 4: Print status summary
echo -e "${BOLD}[4/4] Lab Environment Status${NC}"
echo -e "${BOLD}─────────────────────────────────────────────────────────${NC}"
printf "  ${BOLD}%-35s %-18s %-10s${NC}\n" "MACHINE" "IP ADDRESS" "STATUS"
echo -e "  ─────────────────────────────────────────────────────────"
for machine in "${MACHINES[@]}"; do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$machine" 2>/dev/null || echo "N/A")
    state=$(docker inspect -f '{{.State.Status}}' "$machine" 2>/dev/null || echo "unknown")
    if [[ "$state" == "running" ]]; then
        status="${GREEN}● Running${NC}"
    else
        status="${RED}● ${state}${NC}"
    fi
    printf "  %-35s %-18s ${status}\n" "${machine}.lab.example.com" "$ip"
done
echo ""

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║                  Lab Ready for Practice!                 ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Credentials:${NC}"
echo -e "    Student: ${CYAN}student${NC} / ${CYAN}student${NC}"
echo -e "    Root:    ${CYAN}root${NC} / ${CYAN}redhat${NC}"
echo ""
echo -e "  ${BOLD}Quick Access:${NC}"
echo -e "    ${CYAN}./lab.sh ssh workstation${NC}  - Connect to workstation"
echo -e "    ${CYAN}./lab.sh ssh servera${NC}     - Connect to servera"
echo -e "    ${CYAN}./lab.sh ssh serverb${NC}     - Connect to serverb"
echo -e "    ${CYAN}./lab.sh ssh bastion${NC}     - Connect to bastion"
echo ""
echo -e "  ${BOLD}From workstation, SSH to servers:${NC}"
echo -e "    ${CYAN}ssh student@servera${NC}"
echo -e "    ${CYAN}ssh student@serverb${NC}"
echo ""
