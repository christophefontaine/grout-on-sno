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

# Update install-config.yaml with pullSecret and sshKey
echo "Updating install-config.yaml with pullSecret and sshKey..."

# Read pullSecret from auth.json
if [ -f ~/.config/containers/auth.json ]; then
    PULL_SECRET=$(cat ~/.config/containers/auth.json | tr -d '\n')
    yq -y -i --width 10000 --arg secret "$PULL_SECRET" '.pullSecret = $secret' install-config.yaml
    echo "  ✓ pullSecret updated from ~/.config/containers/auth.json"
else
    echo "  ⚠ WARNING: ~/.config/containers/auth.json not found, pullSecret not updated"
fi

# Read sshKey from SSH public key
if [ -f ~/.ssh/id_ed25519.pub ]; then
    SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
    yq -y -i --width 10000 --arg key "$SSH_KEY" '.sshKey = $key' install-config.yaml
    echo "  ✓ sshKey updated from ~/.ssh/id_ed25519.pub"
else
    echo "  ⚠ WARNING: ~/.ssh/id_ed25519.pub not found, sshKey not updated"
fi

./generate-openshift-configs.sh
openshift-install --dir . --log-level debug agent create config-image
scp agentconfig.noarch.iso droplet01.foobar.space:/var/www/html/droplet05.iso
openshift-install --log-level debug  --dir .  agent wait-for install-complete
