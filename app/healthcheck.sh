#!/bin/bash
# filepath: c:\Users\yxuchang\OneDrive - Capgemini\Documents\999. Dev\twingate-client\healthcheck.sh

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check Twingate status
TWINGATE_STATUS=$(twingate status 2>/dev/null)

if [[ "$TWINGATE_STATUS" = "online" ]]; then
    log "[HEALTHCHECK] Twingate is online."
    exit 0
elif [[ "$TWINGATE_STATUS" = "not running" ]]; then
    log "[HEALTHCHECK] Twingate is not running."
    exit 1
else
    log "[HEALTHCHECK] Twingate status: $TWINGATE_STATUS"
    exit 2
fi
