#!/bin/bash

##############################################################################
# OpenShift Appliance Builder Script
#
# This script builds an OpenShift appliance disk image with preloaded
# container images for disconnected/air-gapped installations.
#
# Based on: https://github.com/openshift/appliance
##############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APPLIANCE_IMAGE="${APPLIANCE_IMAGE:-quay.io/edge-infrastructure/openshift-appliance}"
APPLIANCE_ASSETS="${APPLIANCE_ASSETS:-$(pwd)/appliance_assets}"
APPLIANCE_CONFIG="${APPLIANCE_CONFIG:-$(pwd)/appliance-config.yaml}"
PULL_SECRET="${PULL_SECRET:-$(pwd)/auth.json}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenShift Appliance Builder${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v podman &> /dev/null; then
    echo -e "${RED}ERROR: podman is required but not installed.${NC}"
    exit 1
fi

if [ ! -f "$APPLIANCE_CONFIG" ]; then
    echo -e "${RED}ERROR: appliance-config.yaml not found at: $APPLIANCE_CONFIG${NC}"
    exit 1
fi

if [ ! -f "$PULL_SECRET" ]; then
    echo -e "${YELLOW}WARNING: Pull secret not found at: $PULL_SECRET${NC}"
    echo -e "${YELLOW}You'll need to add it to the appliance-config.yaml${NC}"
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Create assets directory
echo -e "${YELLOW}Creating assets directory: $APPLIANCE_ASSETS${NC}"
mkdir -p "$APPLIANCE_ASSETS"

# Copy configuration files
echo -e "${YELLOW}Copying configuration files...${NC}"
cp "$APPLIANCE_CONFIG" "$APPLIANCE_ASSETS/appliance-config.yaml"

if [ -f "$PULL_SECRET" ]; then
    # Update the appliance-config.yaml to reference the pull secret
    echo -e "${YELLOW}Note: Make sure your pull secret is properly configured in appliance-config.yaml${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 1: Generate Configuration Template${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Generate config template (optional - you already have one)
# Uncomment if you want to regenerate
# podman run --rm -it --pull newer \
#   -v "$APPLIANCE_ASSETS:/assets:Z" \
#   "$APPLIANCE_IMAGE" generate-config

echo -e "${YELLOW}Using existing configuration: $APPLIANCE_CONFIG${NC}"
echo ""

# Display configuration summary
echo -e "${GREEN}Configuration Summary:${NC}"
echo "- OpenShift Version: $(grep 'version:' $APPLIANCE_CONFIG | head -1 | awk '{print $2}')"
echo "- Disk Size: $(grep 'diskSizeGB:' $APPLIANCE_CONFIG | awk '{print $2}') GB"
echo "- Assets Directory: $APPLIANCE_ASSETS"
echo "- Additional Images:"
grep '  - name:' "$APPLIANCE_CONFIG" | sed 's/  - name: /    • /'
echo ""

# Confirm before building
read -p "$(echo -e ${YELLOW}Do you want to proceed with building the appliance? \(y/N\): ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Build cancelled.${NC}"
    exit 0
fi

# Read pullSecret from auth.json
if [ -f ~/.config/containers/auth.json ]; then
    PULL_SECRET=$(cat ~/.config/containers/auth.json | tr -d '\n')
    yq -y -i --width 10000 --arg secret "$PULL_SECRET" '.pullSecret = $secret' appliance-config.yaml
    echo "  ✓ pullSecret updated from ~/.config/containers/auth.json"
else
    echo "  ⚠ WARNING: ~/.config/containers/auth.json not found, pullSecret not updated"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 2: Building Appliance Disk Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}This will take several minutes...${NC}"
echo -e "${YELLOW}The appliance will:${NC}"
echo "  1. Pull the OpenShift release images"
echo "  2. Pull all additional container images"
echo "  3. Create a bootable disk image with embedded images"
echo ""

# Build the appliance
# Note: Requires root/sudo for privileged operations
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Building appliance requires root privileges...${NC}"
    sudo podman run --rm -it --pull newer --privileged --net=host \
      -v "$APPLIANCE_ASSETS:/assets:Z" \
      "$APPLIANCE_IMAGE" build
else
    podman run --rm -it --pull newer --privileged --net=host \
      -v "$APPLIANCE_ASSETS:/assets:Z" \
      "$APPLIANCE_IMAGE" build
fi

BUILD_STATUS=$?

echo ""
if [ $BUILD_STATUS -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}The appliance disk image is available at:${NC}"
    echo "  $APPLIANCE_ASSETS/"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. The disk image contains all preloaded container images"
    echo "  2. You can deploy this image to your target hardware"
    echo "  3. Boot from the image to install OpenShift"
    echo ""
    echo -e "${YELLOW}To verify the embedded images:${NC}"
    echo "  skopeo inspect --config oci:<path-to-image-dir>:<image-name>"
    echo ""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Build Failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${RED}Please check the error messages above.${NC}"
    echo ""
    exit 1
fi
