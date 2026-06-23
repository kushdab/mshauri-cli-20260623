#!/usr/bin/env bash
# mshauri-cli-20260623 - Linux Server Hardening & M-Pesa API Diagnostics
# Author: mshauri-cli project
# License: MIT

set -euo pipefail

VERSION="1.0.0"
LOG_FILE="/tmp/mshauri_$(date +%Y%m%d_%H%M%S).log"
MPESA_BASE_URL="https://sandbox.safaricom.co.ke"
REPORT_FILE="mshauri_report_$(date +%Y%m%d_%H%M%S).txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; log "INFO: $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; log "OK: $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; log "WARN: $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; log "ERROR: $*"; }

usage() {
  cat <<EOF
mshauri-cli v${VERSION} - Linux Hardening & M-Pesa Diagnostics

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  harden          Run full server hardening checklist
  mpesa-check     Run M-Pesa API connectivity diagnostics
  report          Generate combined system + API report
  version         Show version
  help            Show this help

Options for mpesa-check:
  --consumer-key  KEY     M-Pesa consumer key
  --consumer-secret SEC   M-Pesa consumer secret
  --shortcode CODE        M-Pesa shortcode (default: 174379)

Examples:
  $0 harden
  $0 mpesa-check --consumer-key abc123 --consumer-secret xyz789
  $0 report
EOF
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    warn "Not running as root. Some hardening checks may be skipped."
    return 1
  fi
  return 0
}

harden_ssh() {
  info "Checking SSH configuration..."
  local ssh_cfg="/etc/ssh/sshd_config"
  [[ ! -f "$ssh_cfg" ]] && warn "sshd_config not found, skipping SSH checks." && return
  grep -qE '^PermitRootLogin no' "$ssh_cfg" && success "SSH: PermitRootLogin is disabled" || warn "SSH: PermitRootLogin should be set to 'no'"
  grep -qE '^PasswordAuthentication no' "$ssh_cfg" && success "SSH: PasswordAuthentication is disabled" || warn "SSH: Consider disabling PasswordAuthentication"
  grep -qE '^X11Forwarding no' "$ssh_cfg" && success "SSH: X11Forwarding is disabled" || warn "SSH: X11Forwarding should be set to 'no'"
  grep -qE '^MaxAuthTries [1-3]$' "$ssh_cfg" && success "SSH: MaxAuthTries is restricted" || warn "SSH: Set MaxAuthTries to 3 or less"
}

harden_firewall() {
  info "Checking firewall status..."
  if command -v ufw &>/dev/null; then
    ufw status | grep -qi "active" && success "UFW firewall is active" || warn "UFW firewall is inactive. Run: sudo ufw enable"
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --state &>/dev/null && success "firewalld is running" || warn "firewalld is not running"
  else
    warn "No supported firewall found (ufw or firewalld). Install one."
  fi
}

harden_updates() {
  info "Checking for pending security updates..."
  if command -v apt-get &>/dev/null; then
    local count
    count=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)
    [[ "$count" -eq 0 ]] && success "System is up to date" || warn "$count package(s) need updating. Run: sudo apt-get upgrade"
  elif command -v yum &>/dev/null; then
    local count
    count=$(yum check-update --quiet 2>/dev/null | grep -c '^[a-zA-Z]' || true)
    [[ "$count" -eq 0 ]] && success "System is up to date" || warn "$count package(s) need updating. Run: sudo yum update"
  else
    warn "Package manager not detected. Check updates manually."
  fi
}

harden_users() {
  info "Checking for users with empty passwords..."
  local empty_pw
  empty_pw=$(awk -F: '($2 == "" ) {print $1}' /etc/shadow 2>/dev/null || true)
  [[ -z "$empty_pw" ]] && success "No users with empty passwords found" || warn "Users with empty passwords: $empty_pw"
  info "Checking sudoers group members..."
  local sudoers
  sudoers=$(getent group sudo 2>/dev/null | cut -d: -f4 || getent group wheel 2>/dev/null | cut -d: -f4 || echo "unknown")
  info "Sudo/wheel group members: ${sudoers:-none}"
}

harden_sysctl() {
  info "Checking kernel security parameters..."
  declare -A params=(
    ["net.ipv4.ip_forward"]="0"
    ["net.ipv4.conf.all.accept_redirects"]="0"
    ["net.ipv4.conf.all.send_redirects"]="0"
    ["kernel.randomize_va_space"]="2"
  )
  for key in "${!params[@]}"; do
    local expected="${params[$key]}"
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null || echo "unavailable")
    [[ "$actual" == "$expected" ]] && success "sysctl $key = $expected" || warn "sysctl $key is '$actual', recommended: $expected"
  done
}

run_harden() {
  echo -e "\n${BLUE}========== SERVER HARDENING CHECKLIST ==========${NC}\n"
  check_root || true
  harden_ssh
  harden_firewall
  harden_updates
  harden_users
  harden_sysctl
  echo -e "\n${GREEN}Hardening check complete. Log saved to: ${LOG_FILE}${NC}\n"
}

mpesa_get_token() {
  local key="$1" secret="$2"
  info "Fetching M-Pesa OAuth token..."
  local credentials
  credentials=$(echo -n "${key}:${secret}" | base64 -w 0)
  local response
  response=$(curl -sk -X GET \
    "${MPESA_BASE_URL}/oauth/v1/generate?grant_type=client_credentials" \
    -H "Authorization: Basic ${credentials}" \
    -H "Content-Type: application/json" \
    --max-time 10 2>&1) || { error "curl failed: $response"; return 1; }
  local token
  token=$(echo "$response" | grep -oP '(?<="access_token":")[^"]+' 2>/dev/null || true)
  if [[ -n "$token" ]]; then
    success "OAuth token obtained: ${token:0:20}..."
    echo "$token"
  else
    error "Failed to get token. Response: $response"
    return 1
  fi
}

mpesa_check_connectivity() {
  info "Testing M-Pesa sandbox reachability..."
  if curl -sk --max-time 8 "${MPESA_BASE_URL}" -o /dev/null -w "%{http_code}" | grep -qE '^[23]'; then
    success "Reached ${MPESA_BASE_URL} successfully"
  else
    local http_code
    http_code=$(curl -sk --max-time 8 "${MPESA_BASE_URL}" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    warn "Unexpected HTTP code ${http_code} from ${MPESA_BASE_URL}"
  fi
}

mpesa_check_dns() {
  info "Resolving sandbox.safaricom.co.ke..."
  if host sandbox.safaricom.co.ke &>/dev/null || nslookup sandbox.safaricom.co.ke &>/dev/null; then
    success "DNS resolution successful for sandbox.safaricom.co.ke"
  else
    error "DNS resolution failed. Check /etc/resolv.conf"
  fi
}

mpesa_check_ssl() {
  info "Checking TLS/SSL certificate for M-Pesa sandbox..."
  local expiry
  expiry=$(echo | openssl s_client -servername sandbox.safaricom.co.ke \
    -connect sandbox.safaricom.co.ke:443 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unavailable")
  if [[ "$expiry" != "unavailable" ]]; then
    success "SSL certificate valid until: $expiry"
  else
    warn "Could not retrieve SSL certificate info"
  fi
}

run_mpesa_check() {
  local consumer_key="" consumer_secret="" shortcode="174379"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --consumer-key)    consumer_key="$2";    shift 2 ;;
      --consumer-secret) consumer_secret="$2"; shift 2 ;;
      --shortcode)       shortcode="$2";       shift 2 ;;
      *) warn "Unknown option: $1"; shift ;;
    esac
  done
  echo -e "\n${BLUE}========== M-PESA API DIAGNOSTICS ==========${NC}\n"
  mpesa_check_dns
  mpesa_check_connectivity
  mpesa_check_ssl
  if [[ -n "$consumer_key" && -n "$consumer_secret" ]]; then
    mpesa_get_token "$consumer_key" "$consumer_secret" > /dev/null
  else
    warn "No credentials provided. Skipping OAuth token test."
    info "Provide --consumer-key and --consumer-secret to test authentication."
  fi
  echo -e "\n${GREEN}M-Pesa diagnostics complete. Log saved to: ${LOG_FILE}${NC}\n"
}

generate_report() {
  info "Generating combined report: $REPORT_FILE"
  {
    echo "======================================"
    echo " mshauri-cli Report - $(date)"
    echo "======================================"
    echo ""
    echo "--- SYSTEM INFO ---"
    echo "Hostname:   $(hostname)"
    echo "OS:         $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"
    echo "Kernel:     $(uname -r)"
    echo "Uptime:     $(uptime -p 2>/dev/null || uptime)"
    echo "CPU Cores:  $(nproc)"
    echo "Memory:     $(free -h | awk '/^Mem:/{print $2}') total, $(free -h | awk '/^Mem:/{print $7}') available"
    echo "Disk Usage:"
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | head -10 || df -h | head -10
    echo ""
    echo "--- OPEN PORTS ---"
    ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20 || echo "ss/netstat not available"
    echo ""
    echo "--- LAST 5 LOGINS ---"
    last -n 5 2>/dev/null || echo "last command unavailable"
    echo ""
    echo "--- MPESA ENDPOINT ---"
    echo "Sandbox URL: ${MPESA_BASE_URL}"
    echo "DNS check:   $(host sandbox.safaricom.co.ke 2>/dev/null | head -1 || echo 'failed')"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "====================================="
  } > "$REPORT_FILE"
  success "Report saved to: $REPORT_FILE"
  cat "$REPORT_FILE"
}

main() {
  [[ $# -eq 0 ]] && usage && exit 0
  local cmd="$1"; shift || true
  case "$cmd" in
    harden)       run_harden ;;
    mpesa-check)  run_mpesa_check "$@" ;;
    report)       generate_report ;;
    version)      echo "mshauri-cli v${VERSION}" ;;
    help|--help|-h) usage ;;
    *) error "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
