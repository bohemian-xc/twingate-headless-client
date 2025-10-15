#!/bin/bash
set -euo pipefail

# Global logging related variables
LOG_FILE="${LOG_FILE:-/var/log/twingate-client.log}"
LOG_ROTATE_HOURS="${LOG_ROTATE_HOURS:-24}"

# Function to add timestamps to log messages
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Get last rotation time. Return 0 if it is not time to rotate yet.
# Return current epoch time if it is time to rotate.
flag_rotate_logs() {
  local archive_file="$1"

  local stamp_file="${archive_file}.lastrotated"
  local last_rotated now_epoch diff_hours

  if [ -f "$stamp_file" ]; then
    last_rotated=$(cat "$stamp_file")
  else
    last_rotated=0
  fi

  now_epoch=$(date +%s)
  diff_hours=$(( (now_epoch - last_rotated) / 3600 ))

  if [ "$diff_hours" -ge "$LOG_ROTATE_HOURS" ]; then
    echo "$now_epoch"
  else
    echo 0
  fi
}

# Function to rotate logs if needed
rotate_logs() {
  local archive_file="$1"
  local stamp_file="${archive_file}.lastrotated"
  local now_epoch ts

  now_epoch=$(flag_rotate_logs "$archive_file")

  if [ "$now_epoch" -gt 0 ]; then
    if [ -f "$archive_file" ]; then
      ts=$(date '+%Y%m%d_%H%M%S')
      if mv "$archive_file" "${archive_file}.${ts}"; then
        log "Log rotated: ${archive_file}.${ts}"
        if ! echo "$now_epoch" > "$stamp_file"; then
          log "ERROR: Failed to write stamp file $stamp_file"
        fi
      else
        log "ERROR: Failed to rotate log $archive_file"
      fi
    else
      log "No log file to rotate: $archive_file"
    fi
  fi
}

# Ensure log directory exists and is writable
mkdir -p "$(dirname "$LOG_FILE")"
if ! touch "$LOG_FILE" 2>/dev/null; then
  echo "Cannot write to log file $LOG_FILE. Exiting."
  exit 1
fi

# Redirect all output to a log file and stdout
exec > >(tee -a "$LOG_FILE") 2>&1


# Global traffic forwarding related variables
TG_HST_IFACE=${TG_HST_IFACE:-eth0}  # Add this line for configurable WAN interface
TG_WAN_IFACE=${TG_WAN_IFACE:-wan0}  # Add this line for configurable WAN interface
TG_IPTABLES_LEGACY=${TG_IPTABLES_LEGACY:-true}  # Add this line for configuring iptables legacy. interface

# function to forward ipv4 traffic to twingate interface
forward_traffic() {
  # Wait for the twingate interface to be available
  local max_attempts=12   # e.g., try for up to 1 minute (12 * 5s)
  local attempt=1
  while ! ip link show | grep -qE "$TG_WAN_IFACE"; do
    if [ "$attempt" -ge "$max_attempts" ]; then
      log "[Twingate Gateway] Tunnel interface not found after $((max_attempts * 5)) seconds. Exiting."
      return 1
    fi
    log "[Twingate Gateway] Waiting for tunnel interface ($TG_WAN_IFACE) to be available... (attempt $attempt/$max_attempts)"
    sleep 5
    attempt=$((attempt + 1))
  done

  IFACE=$(ip link show | grep -Eo "$TG_WAN_IFACE" | head -n1)
  log "[Twingate Gateway] Tunnel interface: $IFACE"

  # Enable IP forwarding
  local ip_forwarding
  ip_forwarding=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
  if [ "$ip_forwarding" -eq 1 ]; then
    log "[Twingate Gateway] IPv4 forwarding is already enabled."
  elif [ -w /proc/sys/net/ipv4/ip_forward ]; then
    log "[Twingate Gateway] Enabling IPv4 forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    log "[Twingate Gateway] IPv4 forwarding enabled."
  else
    log "[Twingate Gateway] Warning: Cannot enable /proc/sys/net/ipv4/ip_forward (read-only)."
  fi

  #Update iptables to legacy if needed
  if [ "$TG_IPTABLES_LEGACY" = "true" ]; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    log "[Twingate Gateway] Iptables legacy mode enabled."
  fi

  # Clear and reconfigure NAT rules
  iptables -t nat -F POSTROUTING
  iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

  # Allow forwarding from Windows traffic (via $TG_HST_IFACE)
  iptables -A FORWARD -i $TG_HST_IFACE -o $IFACE -j ACCEPT
  iptables -A FORWARD -i $IFACE -o $TG_HST_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

  log "[Twingate Gateway] Routing active. Forwarding Windows traffic through Twingate."
}


# Set global twingate variables
pid_twingate=0
SERVICE_KEY=${SERVICE_KEY:-""}
TWINGATE_MAX_RETRIES=${TWINGATE_MAX_RETRIES:--1}
TWINGATE_RETRY_DELAY=${TWINGATE_RETRY_DELAY:-10}

# Graceful twingate termination handler
term_handler() {
  if [ "$pid_twingate" -ne 0 ] && kill -0 "$pid_twingate" 2>/dev/null; then
    kill -SIGTERM "$pid_twingate"
    wait "$pid_twingate"
  fi

  # Kill any remaining twingate processes owned by this user
  pkill -u "$(id -u)" -x twingate 2>/dev/null || true
}

# Register signal handlers for graceful shutdown
trap term_handler SIGTERM SIGINT

# Function to start Twingate
start_twingate() {
  twingate config log-level debug
  twingate setup --headless $SERVICE_KEY
  log "Start twingate..."
  twingate start &
  pid_twingate="$!"

  if ! kill -0 "$pid_twingate" 2>/dev/null; then
    log "ERROR: Failed to start twingate process."
    exit 1
  fi
}

# Main entrypoint handling section

if [ -n "$SERVICE_KEY" ]; then
    log "Service key to use is: $SERVICE_KEY."
    log "Retry interval is set to $TWINGATE_RETRY_DELAY seconds."

    # Start traffic forwarding in the background
    forward_traffic &

    start_twingate

    # Retry logic for Twingate connection
    retries=0
    while :; do
      sleep "$TWINGATE_RETRY_DELAY"
      TWINGATE_STATUS=$(twingate status)
      if [[ "$TWINGATE_STATUS" == *online* ]]; then
        log "Twingate is connected."
        retries=0
        sleep "$TWINGATE_RETRY_DELAY"
      else
        log "Twingate not connected (attempt $((retries+1))/$TWINGATE_MAX_RETRIES). Retrying..."
        retries=$((retries+1))
        term_handler
        start_twingate
      fi

      # Exit if retries reached and not unlimited
      if [[ "$TWINGATE_MAX_RETRIES" -ne -1 && $retries -ge $TWINGATE_MAX_RETRIES ]]; then
        log "Exiting with an error as Twingate is not connected after $TWINGATE_MAX_RETRIES attempts."
        exit 1
      fi

      # Rotate logs if needed
      rotate_logs "$LOG_FILE"
      rotate_logs "/var/log/twingated.log"
    done
else
    log "ERROR! No service key found, exit..."
    exit 1
fi

