#!/bin/bash
# Script to tag and push RHCSA lab images to Docker Hub

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== RHCSA Docker Hub Uploader ===${NC}"

# Check if logged into Docker Hub
if ! grep -q "auths" ~/.docker/config.json 2>/dev/null; then
    echo -e "${RED}You are not logged into Docker Hub!${NC}"
    echo "Please login first:"
    docker login
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker login failed. Exiting.${NC}"
        exit 1
    fi
    echo ""
fi

# Ask for Docker Hub username
read -p "Enter your Docker Hub username: " DOCKER_USER

if [ -z "$DOCKER_USER" ]; then
    echo -e "${RED}Username cannot be empty. Exiting.${NC}"
    exit 1
fi

echo -e "\n${BLUE}Tagging images with ${DOCKER_USER}...${NC}"

IMAGES=(
    "rhcsa-base"
    "rhcsa-bastion"
    "rhcsa-workstation"
    "rhcsa-server"
)

for img in "${IMAGES[@]}"; do
    echo "Tagging ${img}:latest -> ${DOCKER_USER}/${img}:latest"
    docker tag "${img}:latest" "${DOCKER_USER}/${img}:latest"
done

echo -e "\n${BLUE}Pushing images to Docker Hub...${NC}"
echo "This might take a few minutes depending on your internet connection."

for img in "${IMAGES[@]}"; do
    echo -e "\n${GREEN}Pushing ${DOCKER_USER}/${img}:latest...${NC}"
    docker push "${DOCKER_USER}/${img}:latest"
done

echo -e "\n${GREEN}=== SUCCESS! ===${NC}"
echo "Your images have been uploaded to Docker Hub!"
echo "Your friends can now pull them using:"
for img in "${IMAGES[@]}"; do
    echo "  docker pull ${DOCKER_USER}/${img}:latest"
done
