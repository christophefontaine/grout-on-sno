#!/bin/bash

echo "WARNING: This will delete the following files/directories:"
echo "  - auth/"
echo "  - rendezvousIP"
echo "  - .openshift_install_state.json"
echo "  - .openshift_install.log"
echo "  - agent.x86_64.iso"
echo ""
echo "And restore agent-config.yaml and install-config.yaml from git."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

rm -rf auth rendezvousIP .openshift_install_state.json .openshift_install.log agent.x86_64.iso
git restore agent-config.yaml install-config.yaml
./generate-openshift-configs.sh
#OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=registry.foobar.space:5000/openshift-release-dev/ocp-release:4.19.13-x86_64 openshift-install --dir . --log-level debug agent create image
openshift-install --dir . --log-level debug agent create image
scp agent.x86_64.iso droplet01.foobar.space:/var/www/html/droplet05.iso
openshift-install --log-level debug  --dir .  agent wait-for install-complete
