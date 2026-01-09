#!/bin/bash
# NAT Container Management Script
# Usage: bash manage-nat.sh

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Display all NAT containers
list_containers() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}NAT Container List${NC}"
    echo -e "${BLUE}===================================${NC}"
    
    # Get all containers starting with nat-
    CONTAINERS=$(docker ps -a --filter "name=^nat-" --format "{{.Names}}\t{{.Status}}" | sort -V)
    
    if [ -z "$CONTAINERS" ]; then
        echo -e "${YELLOW}No NAT containers found${NC}"
        return 1
    fi
    
    printf "${CYAN}%-6s %-14s %-10s %-18s %-10s %-15s${NC}\n" "No." "Name" "Status" "Internal IP" "SSH Port" "NAT Ports"
    echo "--------------------------------------------------------------------------------"
    
    local index=1
    while IFS=$'\t' read -r name status; do
        # Extract IP index (only process nat-number format)
        ip_index=$(echo "$name" | sed 's/nat-//')
        
        # Validate if it's a pure number between 1-254
        if ! [[ "$ip_index" =~ ^[0-9]+$ ]] || [ "$ip_index" -lt 1 ] || [ "$ip_index" -gt 254 ]; then
            # Skip non-standard named containers
            continue
        fi
        
        container_ip="192.168.10.${ip_index}"
        ssh_port=$((10000 + ip_index))
        nat_start=$((20000 + ip_index * 10))
        nat_end=$((nat_start + 9))
        
        # Status display
        if [[ "$status" == *"Up"* ]]; then
            status_text="${GREEN}Running${NC}"
        else
            status_text="${RED}Stopped${NC}"
        fi
        
        printf "${MAGENTA}[%-3s]${NC} %-14s %-18b %-18s %-10s %-15s\n" \
            "$index" "$name" "$status_text" "$container_ip" "$ssh_port" "${nat_start}-${nat_end}"
        
        # Save container name for later selection
        eval "CONTAINER_${index}=$name"
        index=$((index + 1))
    done <<< "$CONTAINERS"
    
    TOTAL_COUNT=$((index - 1))
    
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No standard NAT containers found (nat-1 ~ nat-254)${NC}"
        return 1
    fi
    
    echo "--------------------------------------------------------------------------------"
    echo -e "Total: ${CYAN}${TOTAL_COUNT}${NC} container(s)"
    echo ""
    
    return 0
}

# Start container
start_container() {
    local name=$1
    echo -e "${YELLOW}Starting container ${name}...${NC}"
    if docker start "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Container ${name} started${NC}"
    else
        echo -e "${RED}✗ Failed to start${NC}"
    fi
}

# Stop container
stop_container() {
    local name=$1
    echo -e "${YELLOW}Stopping container ${name}...${NC}"
    if docker stop "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Container ${name} stopped${NC}"
    else
        echo -e "${RED}✗ Failed to stop${NC}"
    fi
}

# Restart container
restart_container() {
    local name=$1
    echo -e "${YELLOW}Restarting container ${name}...${NC}"
    if docker restart "$name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Container ${name} restarted${NC}"
    else
        echo -e "${RED}✗ Failed to restart${NC}"
    fi
}

# Delete container
delete_container() {
    local name=$1
    echo -e "${RED}Warning: About to delete container ${name}${NC}"
    printf "Confirm deletion? (y/n): "
    read confirm
    if [ "$confirm" = "y" ]; then
        echo -e "${YELLOW}Deleting container ${name}...${NC}"
        if docker rm -f "$name" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Container ${name} deleted${NC}"
        else
            echo -e "${RED}✗ Failed to delete${NC}"
        fi
    else
        echo -e "${YELLOW}Deletion cancelled${NC}"
    fi
}

# View container logs
view_logs() {
    local name=$1
    echo -e "${CYAN}Logs for container ${name}:${NC}"
    echo "--------------------------------------------------------------------------------"
    docker logs --tail 50 "$name"
    echo "--------------------------------------------------------------------------------"
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}Select Operation:${NC}"
    echo -e "${BLUE}===================================${NC}"
    echo "  1. Start container"
    echo "  2. Stop container"
    echo "  3. Restart container"
    echo "  4. Delete container"
    echo "  5. View logs"
    echo "  6. Refresh list"
    echo "  0. Exit"
    echo -e "${BLUE}===================================${NC}"
    printf "Enter option [0-6]: "
}

# Select container
select_container() {
    printf "Enter container number [1-${TOTAL_COUNT}]: "
    read choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$TOTAL_COUNT" ]; then
        echo -e "${RED}Invalid number${NC}"
        return 1
    fi
    
    eval "SELECTED_CONTAINER=\$CONTAINER_${choice}"
    echo "$SELECTED_CONTAINER"
}

# Main loop
main() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  _   _    _  _____   __  __                                   "
        echo " | \ | |  / \|_   _| |  \/  | __ _ _ __   __ _  __ _  ___ _ __ "
        echo " |  \| | / _ \ | |   | |\/| |/ _\` | '_ \ / _\` |/ _\` |/ _ \ '__|"
        echo " | |\  |/ ___ \| |   | |  | | (_| | | | | (_| | (_| |  __/ |   "
        echo " |_| \_/_/   \_\_|   |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_|   "
        echo "                                               |___/            "
        echo -e "${NC}"
        
        if ! list_containers; then
            echo ""
            echo -e "${YELLOW}Tip: Use deploy-nat.sh to create new NAT containers${NC}"
            echo ""
            read -p "Press Enter to exit..."
            exit 0
        fi
        
        show_menu
        read option
        
        case $option in
            1)
                container=$(select_container)
                [ -n "$container" ] && start_container "$container"
                ;;
            2)
                container=$(select_container)
                [ -n "$container" ] && stop_container "$container"
                ;;
            3)
                container=$(select_container)
                [ -n "$container" ] && restart_container "$container"
                ;;
            4)
                container=$(select_container)
                [ -n "$container" ] && delete_container "$container"
                ;;
            5)
                container=$(select_container)
                [ -n "$container" ] && view_logs "$container"
                ;;
            6)
                continue
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

main
