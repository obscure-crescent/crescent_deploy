#!/usr/bin/env bash
set -euo pipefail

export HOST_IP="192.168.0.202"        # IP address on which Podman will bind application ports
export DOMAIN="example.com"          # Public DNS name used in generated URLs
export DISCORD_BOT_TOKEN="<bot-token>"
export DISCORD_CHANNEL_ID="<channel-id>"
export DISCORD_OAUTH_CLIENTID="<client-id>"
export DISCORD_OAUTH_CLIENTSECRET="<client-secret>"

# Input / Output
TEMPLATE="mare-template.yaml"
OUTPUT="mare.yaml"

echo "Generating $OUTPUT with:"
echo "  HOST_IP = $HOST_IP"
echo "  DOMAIN  = $DOMAIN"

envsubst < "$TEMPLATE" > "$OUTPUT"

echo "Done. Final manifest written to $OUTPUT"
