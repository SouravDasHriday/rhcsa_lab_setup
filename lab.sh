#!/bin/bash
# =============================================================================
# lab.sh - RHCSA Lab Environment Management CLI
# =============================================================================
# A user-friendly wrapper for managing the Docker-based RHCSA lab environment.
#
# Usage:
#   ./lab.sh <command> [options]
#
# Commands:
#   build      - Build all container images
#   start      - Start the lab environment
#   stop       - Stop all containers (preserves data)
#   restart    - Restart all containers
#   status     - Show status of all containers
#   ssh <host> - SSH into a container (workstation|servera|serverb|bastion)
#   exec <host> <cmd> - Execute a command in a container
#   setup      - Run post-start initialization (SSH keys, verification)
#   reset      - Full reset: destroy everything and rebuild from scratch
#   destroy    - Remove all containers, images, and volumes
#   logs <host> - View container logs
#   help       - Show this help message
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Project config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
PROJECT_NAME="rhcsa"
MACHINES=("bastion" "workstation" "servera" "serverb")

# Ensure we're in the right directory
cd "$SCRIPT_DIR"

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║   ██████╗ ██╗  ██╗ ██████╗███████╗ █████╗                   ║
    ║   ██╔══██╗██║  ██║██╔════╝██╔════╝██╔══██╗                  ║
    ║   ██████╔╝███████║██║     ███████╗███████║                   ║
    ║   ██╔══██╗██╔══██║██║     ╚════██║██╔══██║                   ║
    ║   ██║  ██║██║  ██║╚██████╗███████║██║  ██║                   ║
    ║   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝                   ║
    ║                                                              ║
    ║            Docker Lab Environment Manager                    ║
    ║         Red Hat System Administration I & II                 ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_help() {
    print_banner
    echo -e "${BOLD}Usage:${NC} ./lab.sh <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo -e "  ${CYAN}build${NC}              Build all container images"
    echo -e "  ${CYAN}start${NC}              Start the lab environment"
    echo -e "  ${CYAN}stop${NC}               Stop all containers (preserves data)"
    echo -e "  ${CYAN}restart${NC}            Restart all containers"
    echo -e "  ${CYAN}status${NC}             Show detailed status of all containers"
    echo -e "  ${CYAN}ssh <host>${NC}         Open a shell in a container"
    echo -e "                     Hosts: workstation, servera, serverb, bastion"
    echo -e "  ${CYAN}exec <host> <cmd>${NC}  Execute a command in a container"
    echo -e "  ${CYAN}setup${NC}              Initialize SSH keys & verify connectivity"
    echo -e "  ${CYAN}reset${NC}              ${RED}Full reset: destroy & rebuild everything${NC}"
    echo -e "  ${CYAN}reset-container <host>${NC}  Reset a single container"
    echo -e "  ${CYAN}destroy${NC}            Remove all containers, images, and volumes"
    echo -e "  ${CYAN}logs <host>${NC}         View container logs (follow mode)"
    echo -e "  ${CYAN}help${NC}               Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${DIM}# First time setup on a fresh Ubuntu machine:${NC}"
    echo -e "  sudo bash scripts/host-setup.sh"
    echo -e "  ./lab.sh build"
    echo -e "  ./lab.sh start"
    echo -e "  ./lab.sh setup"
    echo ""
    echo -e "  ${DIM}# Daily use:${NC}"
    echo -e "  ./lab.sh start"
    echo -e "  ./lab.sh ssh workstation"
    echo ""
    echo -e "  ${DIM}# After messing up, full reset:${NC}"
    echo -e "  ./lab.sh reset"
    echo ""
    echo -e "${BOLD}Credentials:${NC}"
    echo -e "  Student:  ${CYAN}student${NC} / ${CYAN}student${NC}"
    echo -e "  Root:     ${CYAN}root${NC} / ${CYAN}redhat${NC}"
    echo ""
    echo -e "${BOLD}Network:${NC}"
    echo -e "  bastion.lab.example.com     ${DIM}172.25.250.254${NC}"
    echo -e "  workstation.lab.example.com ${DIM}172.25.250.9${NC}"
    echo -e "  servera.lab.example.com     ${DIM}172.25.250.10${NC}"
    echo -e "  serverb.lab.example.com     ${DIM}172.25.250.11${NC}"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Error: Docker is not installed.${NC}"
        echo -e "Run: ${CYAN}sudo bash scripts/host-setup.sh${NC}"
        exit 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo -e "${RED}Error: Docker daemon is not running or you lack permissions.${NC}"
        echo -e "Try: ${CYAN}sudo systemctl start docker${NC}"
        echo -e "Or:  ${CYAN}sudo usermod -aG docker \$USER${NC} (then log out and back in)"
        exit 1
    fi
}

# =============================================================================
# Command Implementations
# =============================================================================

cmd_build() {
    print_banner
    echo -e "${BOLD}[BUILD] Building all container images...${NC}"
    echo ""

    # First build the base image
    echo -e "${BOLD}[1/4] Building base image (rhcsa-base)...${NC}"
    docker build -t rhcsa-base:latest -f containers/Dockerfile.base .
    echo -e "${GREEN}✓ Base image built${NC}"
    echo ""

    # Build bastion
    echo -e "${BOLD}[2/4] Building bastion image...${NC}"
    docker build -t rhcsa-bastion:latest -f containers/Dockerfile.bastion .
    echo -e "${GREEN}✓ Bastion image built${NC}"
    echo ""

    # Build workstation
    echo -e "${BOLD}[3/4] Building workstation image...${NC}"
    docker build -t rhcsa-workstation:latest -f containers/Dockerfile.workstation .
    echo -e "${GREEN}✓ Workstation image built${NC}"
    echo ""

    # Build server (shared image for servera & serverb)
    echo -e "${BOLD}[4/4] Building server image...${NC}"
    docker build -t rhcsa-server:latest -f containers/Dockerfile.server .
    echo -e "${GREEN}✓ Server image built${NC}"
    echo ""

    echo -e "${BOLD}${GREEN}All images built successfully!${NC}"
    echo -e "Run ${CYAN}./lab.sh start${NC} to start the lab environment."
}

cmd_start() {
    print_banner
    echo -e "${BOLD}[START] Starting RHCSA lab environment...${NC}"
    echo ""

    # Check if images exist, build if not
    if ! docker image inspect rhcsa-base:latest &>/dev/null; then
        echo -e "${YELLOW}Images not found. Building first...${NC}"
        cmd_build
        echo ""
    fi

    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    echo ""
    echo -e "${GREEN}✓ All containers started${NC}"
    echo ""

    # Wait a moment for systemd to initialize
    echo -e "${BOLD}Waiting for systemd to initialize (15s)...${NC}"
    sleep 15

    # Run setup automatically on first start
    echo ""
    cmd_setup_quiet

    echo ""
    cmd_status
}

cmd_stop() {
    echo -e "${BOLD}[STOP] Stopping RHCSA lab environment...${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" stop
    echo -e "${GREEN}✓ All containers stopped (data preserved)${NC}"
    echo -e "Run ${CYAN}./lab.sh start${NC} to resume."
}

cmd_restart() {
    echo -e "${BOLD}[RESTART] Restarting RHCSA lab environment...${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" restart
    echo ""
    echo -e "${GREEN}✓ All containers restarted${NC}"
    sleep 10
    cmd_status
}

cmd_status() {
    echo -e "${BOLD}[STATUS] RHCSA Lab Environment${NC}"
    echo -e "═══════════════════════════════════════════════════════════════"
    printf "  ${BOLD}%-35s %-18s %-12s %-10s${NC}\n" "MACHINE" "IP ADDRESS" "STATUS" "SYSTEMD"
    echo -e "  ───────────────────────────────────────────────────────────"

    for machine in "${MACHINES[@]}"; do
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$machine" 2>/dev/null || echo "N/A")
        state=$(docker inspect -f '{{.State.Status}}' "$machine" 2>/dev/null || echo "stopped")
        
        if [[ "$state" == "running" ]]; then
            systemd_state=$(docker exec "$machine" systemctl is-system-running 2>/dev/null || echo "unknown")
            state_color="${GREEN}● Running${NC}"
            if [[ "$systemd_state" == "running" ]]; then
                sd_color="${GREEN}${systemd_state}${NC}"
            elif [[ "$systemd_state" == "degraded" ]]; then
                sd_color="${YELLOW}${systemd_state}${NC}"
            else
                sd_color="${RED}${systemd_state}${NC}"
            fi
        else
            state_color="${RED}● ${state}${NC}"
            sd_color="${DIM}N/A${NC}"
        fi

        printf "  %-35s %-18s " "${machine}.lab.example.com" "$ip"
        echo -ne "$state_color"
        printf "%*s" $((12 - ${#state} - 2)) ""
        echo -e "$sd_color"
    done
    echo ""
    echo -e "  ${BOLD}Credentials:${NC} student/${CYAN}student${NC}  |  root/${CYAN}redhat${NC}"
    echo -e "  ${BOLD}Quick SSH:${NC}   ${CYAN}./lab.sh ssh workstation${NC}"
    echo ""
}

cmd_ssh() {
    local target="${1:-workstation}"
    
    # Validate target
    local valid=false
    for machine in "${MACHINES[@]}"; do
        if [[ "$machine" == "$target" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != "true" ]]; then
        echo -e "${RED}Error: Unknown machine '${target}'${NC}"
        echo -e "Valid machines: ${CYAN}${MACHINES[*]}${NC}"
        exit 1
    fi

    # Check if container is running
    state=$(docker inspect -f '{{.State.Status}}' "$target" 2>/dev/null || echo "not found")
    if [[ "$state" != "running" ]]; then
        echo -e "${RED}Error: Container '${target}' is not running (status: ${state})${NC}"
        echo -e "Run: ${CYAN}./lab.sh start${NC}"
        exit 1
    fi

    echo -e "${DIM}Connecting to ${target}.lab.example.com as root...${NC}"
    echo -e "${DIM}Type 'su - student' to switch to student user${NC}"
    echo -e "${DIM}Type 'exit' to disconnect${NC}"
    echo ""
    docker exec -it "$target" /bin/bash
}

cmd_exec() {
    local target="$1"
    shift
    local cmd="$*"

    if [[ -z "$target" || -z "$cmd" ]]; then
        echo -e "${RED}Usage: ./lab.sh exec <host> <command>${NC}"
        echo -e "Example: ${CYAN}./lab.sh exec servera systemctl status sshd${NC}"
        exit 1
    fi

    docker exec -it "$target" bash -c "$cmd"
}

cmd_setup() {
    print_banner
    bash "${SCRIPT_DIR}/scripts/lab-setup.sh"
}

cmd_setup_quiet() {
    bash "${SCRIPT_DIR}/scripts/lab-setup.sh"
}

cmd_reset() {
    print_banner
    echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║     ⚠  FULL RESET - This will destroy EVERYTHING!  ⚠   ║${NC}"
    echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "This will:"
    echo -e "  ${RED}✗${NC} Stop and remove all containers"
    echo -e "  ${RED}✗${NC} Remove all volumes (student data, disk images)"
    echo -e "  ${RED}✗${NC} Remove all built images"
    echo -e "  ${GREEN}✓${NC} Rebuild everything from scratch"
    echo ""
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}Reset cancelled.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${BOLD}[1/4] Stopping and removing containers...${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
    echo -e "${GREEN}✓ Containers removed${NC}"

    echo -e "${BOLD}[2/4] Removing images...${NC}"
    docker rmi rhcsa-base:latest rhcsa-bastion:latest rhcsa-workstation:latest rhcsa-server:latest 2>/dev/null || true
    echo -e "${GREEN}✓ Images removed${NC}"

    echo -e "${BOLD}[3/4] Cleaning up orphan volumes...${NC}"
    docker volume ls --filter "name=rhcsa_" -q | xargs -r docker volume rm 2>/dev/null || true
    echo -e "${GREEN}✓ Volumes cleaned${NC}"

    echo -e "${BOLD}[4/4] Rebuilding and starting...${NC}"
    echo ""
    cmd_build
    echo ""
    cmd_start
}

cmd_reset_container() {
    local target="${1}"

    if [[ -z "$target" ]]; then
        echo -e "${RED}Usage: ./lab.sh reset-container <host>${NC}"
        echo -e "Example: ${CYAN}./lab.sh reset-container servera${NC}"
        exit 1
    fi

    # Validate target
    local valid=false
    for machine in "${MACHINES[@]}"; do
        if [[ "$machine" == "$target" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != "true" ]]; then
        echo -e "${RED}Error: Unknown machine '${target}'${NC}"
        echo -e "Valid machines: ${CYAN}${MACHINES[*]}${NC}"
        exit 1
    fi

    echo -e "${BOLD}Resetting ${CYAN}${target}${NC}${BOLD}...${NC}"
    
    # Stop and remove the specific container
    docker stop "$target" 2>/dev/null || true
    docker rm "$target" 2>/dev/null || true

    # Remove associated volumes
    case "$target" in
        bastion)
            docker volume rm "rhcsa_bastion_data" 2>/dev/null || true
            ;;
        workstation)
            docker volume rm "rhcsa_workstation_home" "rhcsa_workstation_data" 2>/dev/null || true
            ;;
        servera)
            docker volume rm "rhcsa_servera_home" "rhcsa_servera_data" "rhcsa_servera_disks" 2>/dev/null || true
            ;;
        serverb)
            docker volume rm "rhcsa_serverb_home" "rhcsa_serverb_data" "rhcsa_serverb_disks" 2>/dev/null || true
            ;;
    esac

    # Recreate
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d "$target"
    echo -e "${GREEN}✓ ${target} has been reset and restarted${NC}"
    
    sleep 10
    
    # Re-run setup for SSH keys
    echo -e "${BOLD}Re-initializing SSH keys...${NC}"
    cmd_setup_quiet
}

cmd_destroy() {
    echo -e "${BOLD}${RED}Destroying RHCSA lab environment...${NC}"
    echo ""
    read -p "This will remove all containers, volumes, and images. Continue? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        exit 0
    fi

    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
    docker rmi rhcsa-base:latest rhcsa-bastion:latest rhcsa-workstation:latest rhcsa-server:latest 2>/dev/null || true
    docker volume ls --filter "name=rhcsa_" -q | xargs -r docker volume rm 2>/dev/null || true
    docker network rm rhcsa_labnet 2>/dev/null || true

    echo -e "${GREEN}✓ Everything destroyed. Run ${CYAN}./lab.sh build && ./lab.sh start${NC} to recreate."
}

cmd_logs() {
    local target="${1:-workstation}"
    echo -e "${BOLD}Streaming logs for ${CYAN}${target}${NC}... (Ctrl+C to stop)"
    docker logs -f "$target"
}

# =============================================================================
# Main Entry Point
# =============================================================================

check_docker

case "${1:-help}" in
    build)
        cmd_build
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    ssh)
        cmd_ssh "$2"
        ;;
    exec)
        shift
        cmd_exec "$@"
        ;;
    setup)
        cmd_setup
        ;;
    reset)
        cmd_reset
        ;;
    reset-container)
        cmd_reset_container "$2"
        ;;
    destroy)
        cmd_destroy
        ;;
    logs)
        cmd_logs "$2"
        ;;
    help|--help|-h)
        print_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        print_help
        exit 1
        ;;
esac
