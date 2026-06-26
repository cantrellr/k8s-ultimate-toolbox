#!/usr/bin/env bash
# setup-ufw-zones-v13.sh
# Quick-first UFW zone/profile setup for multi-NIC Ubuntu/RKE2 hosts.
#
# Features:
# - Import saved config from file and optionally edit before applying.
# - Save config for reuse.
# - Quick presets for RKE2 single-node, RKE2 server, RKE2 agent, Contour-only, Harbor/Docker.
# - Per-interface ingress client source CIDRs and VIP destination CIDRs.
# - Contour/Envoy quick mode defaults to tcp/80 and tcp/443 without prompting for ports.
# - Role-specific RKE2 ports.

set -euo pipefail

SCRIPT_VERSION="2026-06-26-v13-per-interface-ingress-sources"
CONFIG_KIND="ufw-zone-profile-config"
CONFIG_VERSION="v13"
BACKUP_ROOT="/root/ufw-zone-backups"
CONFIG_ROOT="$BACKUP_ROOT/configs"
LOG_ROOT="/var/log/ufw-zone-setup"
SYSCTL_DROPIN="/etc/sysctl.d/99-ufw-zone-hardening.conf"

DETECTED_IFACES=()
ASSIGNED_IFACES=()
DOMAIN_IFACES=()
STORAGE_IFACES=()
RESTRICTED_IFACES=()
K8S_IFACES=()
RKE2_SERVER_IFACES=()
RKE2_AGENT_IFACES=()
RKE2_SINGLE_IFACES=()
CONTOUR_IFACES=()
HARBOR_IFACES=()
CUSTOM_INGRESS_IFACES=()

declare -A IFACE_ZONE=()
declare -A IFACE_PROFILES=()
declare -A IFACE_STORAGE_OVERLAY=()
declare -A IFACE_VIP_SOURCES=()
declare -A IFACE_VIP_DESTS=()

LOG_FILE=""
PROMPT_STEP=0
CONFIG_WAS_IMPORTED="no"
IMPORTED_CONFIG_FILE=""
SETUP_MODE=""

ADMIN_SOURCES=""
DOMAIN_PROFILE="ssh-only"
STORAGE_SOURCES=""
RESTRICTED_SOURCES=""
VIP_SOURCES=""
VIP_DESTS=""
K8S_API_SOURCES=""
K8S_NODE_SOURCES=""
K8S_SERVER_PEER_SOURCES=""
K8S_LB_HEALTHCHECK_SOURCES=""
CNI_PROFILE="none"
SINGLENODE_ENABLE_CNI="no"
NODEPORTS="no"
KUBE_PROXY_HEALTHCHECK="no"
CONTOUR_SPECS="tcp/80 tcp/443"
CUSTOM_INGRESS_SPECS=""
DOCKER_CIDRS=""
DOCKER_PORTS=""
ROUTE_VIP="yes"

C_RESET=""
C_BOLD=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_BLUE=""
C_MAGENTA=""
C_CYAN=""

init_colors() {
  if [[ -t 0 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
  fi
}

heading() { printf '\n%b%s%b\n' "${C_BOLD}${C_BLUE}" "$*" "$C_RESET"; }
subheading() { printf '\n%b%s%b\n' "${C_BOLD}${C_CYAN}" "$*" "$C_RESET"; }
info() { printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%bWARNING:%b %s\n' "${C_BOLD}${C_YELLOW}" "$C_RESET" "$*" >&2; }
err() { printf '%bERROR:%b %s\n' "${C_BOLD}${C_RED}" "$C_RESET" "$*" >&2; }

step() {
  PROMPT_STEP=$((PROMPT_STEP + 1))
  printf '\n%b--- Step %02d: %s ---%b\n' "${C_BOLD}${C_MAGENTA}" "$PROMPT_STEP" "$*" "$C_RESET" >&2
}

log() { echo "[$(date -Is)] $*" >&2; }
run() { log "+ $*"; "$@"; }

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing required command: $1"
    exit 1
  }
}

yesno() {
  local prompt="$1" default="${2:-N}" reply suffix
  if [[ "$default" =~ ^[Yy]$ ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  while true; do
    read -r -p "${C_BOLD}${prompt}${C_RESET} ${suffix}: " reply
    reply="$(trim "$reply")"
    [[ -z "$reply" ]] && reply="$default"
    case "$reply" in
      y|Y|yes|YES|Yes) log "yes: $prompt"; return 0 ;;
      n|N|no|NO|No) log "no: $prompt"; return 1 ;;
      *) err "Please answer y or n." ;;
    esac
  done
}

contains() {
  local needle="$1" item
  shift || true
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

append_unique() {
  local array_name="$1" value="$2"
  [[ -z "$value" ]] && return 0
  eval "local current=(\"\${${array_name}[@]:-}\")"
  if ! contains "$value" "${current[@]}"; then
    eval "${array_name}+=(\"\$value\")"
  fi
}

join_unique_words() {
  local output="" word
  for word in $*; do
    [[ -z "$word" ]] && continue
    if [[ " $output " != *" $word "* ]]; then
      output="$(trim "$output $word")"
    fi
  done
  echo "$output"
}

sanitize_key() {
  local s="$1"
  echo "${s//[^A-Za-z0-9_]/_}"
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || {
    err "Run as root or with sudo."
    exit 1
  }
}

init_logging() {
  mkdir -p "$LOG_ROOT"
  chmod 750 "$LOG_ROOT"
  LOG_FILE="$LOG_ROOT/setup-ufw-zones-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1

  heading "=== UFW Zone/Profile Setup Action Log ==="
  echo "Version: $SCRIPT_VERSION"
  echo "Date: $(date -Is)"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
  echo "Log file: $LOG_FILE"
}

list_ifaces() {
  ip -o link show \
    | awk -F': ' '{print $2}' \
    | sed 's/@.*//' \
    | grep -Ev '^(lo|docker[0-9]*|br-|veth|virbr|zt|tailscale|wg|tun|tap|cni|flannel|vxlan|cali|lxc|nerdctl)' \
    | sort -u
}

discover_ifaces() {
  mapfile -t DETECTED_IFACES < <(list_ifaces)
  [[ "${#DETECTED_IFACES[@]}" -gt 0 ]] || {
    err "No usable physical/primary interfaces detected."
    exit 1
  }
}

print_ifaces() {
  subheading "Detected physical/primary interfaces"
  local i=1 iface state mac ip4
  for iface in "${DETECTED_IFACES[@]}"; do
    state="$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)"
    mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo unknown)"
    ip4="$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd ',' -)"
    [[ -z "$ip4" ]] && ip4="no-ipv4"
    printf '  %b%2d)%b %-18s state=%-8s mac=%-17s ipv4=%s\n' "$C_BOLD" "$i" "$C_RESET" "$iface" "$state" "$mac" "$ip4"
    ((i++))
  done
}

iface_by_number() {
  local choice="$1"
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#DETECTED_IFACES[@]} )) || return 1
  echo "${DETECTED_IFACES[$((choice - 1))]}"
}

prompt_iface() {
  local prompt="$1" allow_none="${2:-yes}" default="${3:-}" choice iface
  while true; do
    print_ifaces >&2
    [[ "$allow_none" == "yes" ]] && echo "   0) None / finish" >&2
    read -r -p "${C_BOLD}${prompt}${C_RESET}" choice
    choice="$(trim "$choice")"
    [[ -z "$choice" && -n "$default" ]] && choice="$default"
    if [[ "$allow_none" == "yes" && "$choice" == "0" ]]; then
      echo ""
      return 0
    fi
    iface="$(iface_by_number "$choice" 2>/dev/null || true)"
    if [[ -n "$iface" ]]; then
      echo "$iface"
      return 0
    fi
    err "Invalid interface selection."
  done
}

parse_cidrs() {
  local input="$1" item
  input="$(trim "${input//,/ }")"
  [[ -z "$input" ]] && return 0
  for item in $input; do
    if [[ "$item" == "any" || "$item" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ || "$item" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
      echo "$item"
    else
      err "Invalid CIDR/IP: $item"
      exit 1
    fi
  done
}

prompt_cidrs() {
  local prompt="$1" default="${2:-}" raw
  read -r -p "${C_BOLD}${prompt}${C_RESET}" raw
  raw="$(trim "$raw")"
  [[ -z "$raw" && -n "$default" ]] && raw="$default"
  parse_cidrs "$raw" | paste -sd ' ' -
}

prompt_specs() {
  local prompt="$1" default="$2" raw spec output=""
  read -r -p "${C_BOLD}${prompt}${C_RESET}" raw
  raw="$(trim "$raw")"
  [[ -z "$raw" ]] && raw="$default"
  raw="${raw//,/ }"
  for spec in $raw; do
    [[ "$spec" =~ ^(tcp|udp)/[0-9]+(:[0-9]+)?$ ]] || {
      err "Invalid port spec: $spec. Use tcp/443 or udp/8472."
      exit 1
    }
    output="$(trim "$output $spec")"
  done
  echo "$output"
}

reset_model() {
  ASSIGNED_IFACES=()
  DOMAIN_IFACES=()
  STORAGE_IFACES=()
  RESTRICTED_IFACES=()
  K8S_IFACES=()
  RKE2_SERVER_IFACES=()
  RKE2_AGENT_IFACES=()
  RKE2_SINGLE_IFACES=()
  CONTOUR_IFACES=()
  HARBOR_IFACES=()
  CUSTOM_INGRESS_IFACES=()
  IFACE_ZONE=()
  IFACE_PROFILES=()
  IFACE_STORAGE_OVERLAY=()
  IFACE_VIP_SOURCES=()
  IFACE_VIP_DESTS=()
  VIP_SOURCES=""
  VIP_DESTS=""
}

set_iface() {
  local iface="$1" zone="$2" profile="$3"
  [[ -z "$iface" ]] && return 0
  append_unique ASSIGNED_IFACES "$iface"
  [[ -z "${IFACE_ZONE[$iface]:-}" ]] && IFACE_ZONE[$iface]="$zone"
  if [[ -n "$profile" && " ${IFACE_PROFILES[$iface]:-} " != *" $profile "* ]]; then
    IFACE_PROFILES[$iface]="$(trim "${IFACE_PROFILES[$iface]:-} $profile")"
  fi
}

rebuild_lists() {
  DOMAIN_IFACES=()
  STORAGE_IFACES=()
  RESTRICTED_IFACES=()
  K8S_IFACES=()
  RKE2_SERVER_IFACES=()
  RKE2_AGENT_IFACES=()
  RKE2_SINGLE_IFACES=()
  CONTOUR_IFACES=()
  HARBOR_IFACES=()
  CUSTOM_INGRESS_IFACES=()

  local iface profile
  for iface in "${ASSIGNED_IFACES[@]}"; do
    case "${IFACE_ZONE[$iface]:-}" in
      domain_zone) append_unique DOMAIN_IFACES "$iface" ;;
      storage_zone) append_unique STORAGE_IFACES "$iface" ;;
      restricted_zone) append_unique RESTRICTED_IFACES "$iface" ;;
    esac

    for profile in ${IFACE_PROFILES[$iface]:-}; do
      case "$profile" in
        rke2-server) append_unique K8S_IFACES "$iface"; append_unique RKE2_SERVER_IFACES "$iface" ;;
        rke2-agent) append_unique K8S_IFACES "$iface"; append_unique RKE2_AGENT_IFACES "$iface" ;;
        rke2-singlenode) append_unique K8S_IFACES "$iface"; append_unique RKE2_SINGLE_IFACES "$iface" ;;
        contour-envoy-ingress) append_unique CONTOUR_IFACES "$iface" ;;
        custom-ingress) append_unique CUSTOM_INGRESS_IFACES "$iface" ;;
        harbor-docker) append_unique HARBOR_IFACES "$iface" ;;
      esac
    done
  done
}

valid_config() {
  local file="$1"
  [[ -r "$file" ]] || { err "Config not readable: $file"; return 1; }
  grep -q '^CONFIG_KIND="ufw-zone-profile-config"$' "$file" || { err "Missing CONFIG_KIND marker."; return 1; }
  if grep -nEv '^[[:space:]]*$|^[[:space:]]*#|^[A-Za-z_][A-Za-z0-9_]*="[-A-Za-z0-9_./: ,+]*"[[:space:]]*$' "$file"; then
    err "Unsafe config syntax shown above. Refusing to source this file."
    return 1
  fi
}

load_config() {
  local file="$1" iface key imported zone profiles overlay vip_src vip_dst
  valid_config "$file" || exit 1
  reset_model
  # shellcheck disable=SC1090
  source "$file"

  imported="${ASSIGNED_IFACES:-}"
  ASSIGNED_IFACES=()
  for iface in $imported; do
    append_unique ASSIGNED_IFACES "$iface"
    key="$(sanitize_key "$iface")"
    eval "zone=\${IFACE_ZONE_${key}:-}"
    eval "profiles=\${IFACE_PROFILES_${key}:-}"
    eval "overlay=\${IFACE_STORAGE_OVERLAY_${key}:-}"
    eval "vip_src=\${IFACE_VIP_SOURCES_${key}:-}"
    eval "vip_dst=\${IFACE_VIP_DESTS_${key}:-}"
    [[ -n "$zone" ]] && IFACE_ZONE[$iface]="$zone"
    [[ -n "$profiles" ]] && IFACE_PROFILES[$iface]="$profiles"
    [[ -n "$overlay" ]] && IFACE_STORAGE_OVERLAY[$iface]="$overlay"
    [[ -n "$vip_src" ]] && IFACE_VIP_SOURCES[$iface]="$vip_src"
    [[ -n "$vip_dst" ]] && IFACE_VIP_DESTS[$iface]="$vip_dst"
    contains "$iface" "${DETECTED_IFACES[@]}" || warn "Config references missing interface on this host: $iface"
  done

  for iface in "${ASSIGNED_IFACES[@]}"; do
    [[ -n "${IFACE_VIP_SOURCES[$iface]:-}" ]] && VIP_SOURCES="$(join_unique_words "$VIP_SOURCES" "${IFACE_VIP_SOURCES[$iface]}")"
    [[ -n "${IFACE_VIP_DESTS[$iface]:-}" ]] && VIP_DESTS="$(join_unique_words "$VIP_DESTS" "${IFACE_VIP_DESTS[$iface]}")"
  done

  rebuild_lists
  IMPORTED_CONFIG_FILE="$file"
  CONFIG_WAS_IMPORTED="yes"
}

maybe_import() {
  local latest="$CONFIG_ROOT/$(hostname -s)-latest.conf" file
  step "Optional configuration import"
  [[ -f "$latest" ]] && echo "Default import file: $latest" >&2
  if yesno "Import configuration from file?" "N"; then
    if [[ -f "$latest" ]]; then
      read -r -p "${C_BOLD}Config file path [$latest]:${C_RESET} " file
      file="$(trim "$file")"
      [[ -z "$file" ]] && file="$latest"
    else
      read -r -p "${C_BOLD}Config file path:${C_RESET} " file
      file="$(trim "$file")"
    fi
    [[ -n "$file" ]] || { err "No config file entered."; exit 1; }
    load_config "$file"
    show_plan
    if yesno "Make changes to imported config before applying?" "N"; then
      collect_quick
    fi
    return 0
  fi
  return 1
}

quote_value() {
  local value="${1//\"/}"
  printf '"%s"' "$value"
}

save_config() {
  mkdir -p "$CONFIG_ROOT"
  chmod 750 "$CONFIG_ROOT"
  local default_path="$CONFIG_ROOT/$(hostname -s)-ufw-zone-config-$(date +%Y%m%d-%H%M%S).conf"
  local path iface key var latest assigned
  read -r -p "${C_BOLD}Save path [$default_path]:${C_RESET} " path
  path="$(trim "$path")"
  [[ -z "$path" ]] && path="$default_path"
  assigned="$(printf '%s ' "${ASSIGNED_IFACES[@]}" | xargs)"

  {
    echo "# UFW Zone/Profile saved configuration"
    echo "CONFIG_KIND=\"$CONFIG_KIND\""
    echo "CONFIG_VERSION=\"$CONFIG_VERSION\""
    echo "SCRIPT_VERSION_SAVED=\"$SCRIPT_VERSION\""
    echo "HOSTNAME_HINT=\"$(hostname -f 2>/dev/null || hostname)\""
    echo "SETUP_MODE=$(quote_value "$SETUP_MODE")"
    echo "ASSIGNED_IFACES=$(quote_value "$assigned")"
    for iface in "${ASSIGNED_IFACES[@]}"; do
      key="$(sanitize_key "$iface")"
      echo "IFACE_ZONE_${key}=$(quote_value "${IFACE_ZONE[$iface]:-}")"
      echo "IFACE_PROFILES_${key}=$(quote_value "${IFACE_PROFILES[$iface]:-}")"
      echo "IFACE_STORAGE_OVERLAY_${key}=$(quote_value "${IFACE_STORAGE_OVERLAY[$iface]:-}")"
      echo "IFACE_VIP_SOURCES_${key}=$(quote_value "${IFACE_VIP_SOURCES[$iface]:-}")"
      echo "IFACE_VIP_DESTS_${key}=$(quote_value "${IFACE_VIP_DESTS[$iface]:-}")"
    done
    for var in ADMIN_SOURCES DOMAIN_PROFILE STORAGE_SOURCES RESTRICTED_SOURCES VIP_SOURCES VIP_DESTS \
      K8S_API_SOURCES K8S_NODE_SOURCES K8S_SERVER_PEER_SOURCES K8S_LB_HEALTHCHECK_SOURCES \
      CNI_PROFILE SINGLENODE_ENABLE_CNI NODEPORTS KUBE_PROXY_HEALTHCHECK CONTOUR_SPECS \
      CUSTOM_INGRESS_SPECS DOCKER_CIDRS DOCKER_PORTS ROUTE_VIP; do
      eval "echo $var=\$(quote_value \"\${$var}\")"
    done
  } > "$path"

  chmod 600 "$path"
  latest="$CONFIG_ROOT/$(hostname -s)-latest.conf"
  ln -sfn "$path" "$latest"
  info "Saved configuration: $path"
  info "Latest symlink: $latest"
}

choose_mode() {
  local choice
  while true; do
    step "Setup mode"
    cat >&2 <<EOF_MENU
Choose the closest preset:
  1) RKE2 single-node + optional Contour/Envoy + optional storage
  2) RKE2 server/controller + optional Contour/Envoy + optional storage
  3) RKE2 agent/worker + optional Contour/Envoy + optional storage
  4) Contour/Envoy ingress only
  5) Harbor/Docker service
  6) Advanced/manual
EOF_MENU
    read -r -p "${C_BOLD}Setup mode [1-6, default 1]:${C_RESET} " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="1"
    case "$choice" in
      1) SETUP_MODE="rke2-single-quick"; return ;;
      2) SETUP_MODE="rke2-server-quick"; return ;;
      3) SETUP_MODE="rke2-agent-quick"; return ;;
      4) SETUP_MODE="contour-only-quick"; return ;;
      5) SETUP_MODE="harbor-docker-quick"; return ;;
      6) SETUP_MODE="advanced-manual"; return ;;
      *) err "Enter 1 through 6." ;;
    esac
  done
}

choose_storage_overlay() {
  local choice
  while true; do
    cat >&2 <<EOF_STORAGE
Storage overlay:
  1) NFS only
  2) iSCSI only
  3) NFS + iSCSI
  4) Custom
EOF_STORAGE
    read -r -p "${C_BOLD}Storage overlay [1-4, default 3]:${C_RESET} " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="3"
    case "$choice" in
      1) echo "nfs-only"; return ;;
      2) echo "iscsi-only"; return ;;
      3) echo "nfs-iscsi"; return ;;
      4) echo "custom"; return ;;
      *) err "Enter 1 through 4." ;;
    esac
  done
}

choose_cni() {
  local choice
  while true; do
    cat >&2 <<EOF_CNI
Primary CNI under Multus, if used:
  0) None
  1) RKE2 Canal VXLAN
  2) RKE2 Canal + WireGuard
  3) Calico BGP
  4) Calico VXLAN
  5) Flannel VXLAN
  6) Cilium VXLAN/WireGuard
EOF_CNI
    read -r -p "${C_BOLD}CNI [0-6, default 1]:${C_RESET} " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="1"
    case "$choice" in
      0) echo "none"; return ;;
      1) echo "canal-vxlan"; return ;;
      2) echo "canal-wireguard"; return ;;
      3) echo "calico-bgp"; return ;;
      4) echo "calico-vxlan"; return ;;
      5) echo "flannel-vxlan"; return ;;
      6) echo "cilium-vxlan-wireguard"; return ;;
      *) err "Enter 0 through 6." ;;
    esac
  done
}

quick_storage() {
  local iface overlay
  step "Optional storage interface"
  iface="$(prompt_iface "Storage interface number [0 for none]: " "yes" "0")"
  [[ -z "$iface" ]] && return 0
  set_iface "$iface" "storage_zone" "storage-workload"
  overlay="$(choose_storage_overlay)"
  IFACE_STORAGE_OVERLAY[$iface]="$overlay"
  STORAGE_SOURCES="$(prompt_cidrs "Storage peer CIDR(s), blank for any on storage NIC: ")"
  if [[ "$overlay" == "custom" ]]; then
    warn "Custom storage overlay selected. Use Advanced/manual later if you need custom storage ports."
  fi
}

quick_ingress() {
  local default_yes="${1:-N}" iface vip_src vip_dst added_any="no"
  step "Optional Contour/Envoy ingress"
  yesno "Add Contour/Envoy ingress VIP rules?" "$default_yes" || return 0
  CONTOUR_SPECS="tcp/80 tcp/443"
  echo "Using default Contour/Envoy ports: tcp/80 tcp/443" >&2

  while true; do
    iface="$(prompt_iface "restricted_zone/Ingress interface number [0 to finish]: " "yes" "0")"
    [[ -z "$iface" ]] && break

    set_iface "$iface" "restricted_zone" "contour-envoy-ingress"

    vip_src="$(prompt_cidrs "Ingress client source CIDR(s) for $iface, blank for any: ")"
    [[ -z "$vip_src" ]] && vip_src="any"
    IFACE_VIP_SOURCES[$iface]="$vip_src"
    VIP_SOURCES="$(join_unique_words "$VIP_SOURCES" "$vip_src")"

    vip_dst=""
    while [[ -z "$vip_dst" ]]; do
      vip_dst="$(prompt_cidrs "VIP destination CIDR(s) for $iface, required: ")"
      [[ -z "$vip_dst" ]] && err "Enter at least one VIP destination CIDR/IP for $iface."
    done
    IFACE_VIP_DESTS[$iface]="$vip_dst"
    VIP_DESTS="$(join_unique_words "$VIP_DESTS" "$vip_dst")"

    added_any="yes"
    yesno "Is there another interface that will receive ingress traffic?" "N" || break
  done

  if [[ "$added_any" == "yes" ]]; then
    RESTRICTED_SOURCES="$VIP_SOURCES"
    ROUTE_VIP="yes"
  else
    warn "No ingress interface selected. Skipping Contour/Envoy rules."
  fi
}

collect_quick() {
  reset_model
  print_ifaces
  choose_mode

  local iface
  case "$SETUP_MODE" in
    rke2-single-quick)
      step "RKE2 single-node interface"
      iface="$(prompt_iface "Admin/RKE2 interface number: " "no")"
      set_iface "$iface" "domain_zone" "rke2-singlenode"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/API source CIDR(s), blank for any: ")"
      K8S_API_SOURCES="$ADMIN_SOURCES"
      CNI_PROFILE="none"
      SINGLENODE_ENABLE_CNI="no"
      quick_storage
      quick_ingress "Y"
      ;;
    rke2-server-quick)
      step "RKE2 server/controller interface"
      iface="$(prompt_iface "Admin/RKE2 server interface number: " "no")"
      set_iface "$iface" "domain_zone" "rke2-server"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/API source CIDR(s), blank for any: ")"
      K8S_API_SOURCES="$ADMIN_SOURCES"
      K8S_NODE_SOURCES="$(prompt_cidrs "All RKE2 node CIDR(s), used for 9345/10250/CNI: " "$ADMIN_SOURCES")"
      K8S_SERVER_PEER_SOURCES="$(prompt_cidrs "RKE2 server/etcd peer CIDR(s), blank to reuse node CIDR(s): " "$K8S_NODE_SOURCES")"
      CNI_PROFILE="$(choose_cni)"
      quick_storage
      quick_ingress "Y"
      ;;
    rke2-agent-quick)
      step "RKE2 agent/worker interface"
      iface="$(prompt_iface "RKE2 agent/worker interface number: " "no")"
      set_iface "$iface" "domain_zone" "rke2-agent"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/SSH source CIDR(s), blank for any: ")"
      K8S_NODE_SOURCES="$(prompt_cidrs "RKE2 server/node CIDR(s), used for 10250/CNI: " "$ADMIN_SOURCES")"
      CNI_PROFILE="$(choose_cni)"
      quick_storage
      quick_ingress "N"
      ;;
    contour-only-quick)
      quick_ingress "Y"
      ;;
    harbor-docker-quick)
      step "Harbor/Docker service interface"
      iface="$(prompt_iface "Harbor/service interface number: " "no")"
      set_iface "$iface" "restricted_zone" "harbor-docker"
      RESTRICTED_SOURCES="$(prompt_cidrs "Allowed Harbor client source CIDR(s), blank for any: ")"
      DOCKER_CIDRS="$(prompt_cidrs "Docker bridge destination CIDR(s), e.g. 172.17.0.0/16: ")"
      DOCKER_PORTS="$(prompt_specs "Docker/Harbor destination TCP ports [default tcp/80 tcp/443 tcp/8080 tcp/8443]: " "tcp/80 tcp/443 tcp/8080 tcp/8443")"
      ;;
    advanced-manual)
      warn "Advanced/manual currently uses the quick preset engine. Choose the closest preset."
      collect_quick
      return
      ;;
  esac

  rebuild_lists
}

show_plan() {
  heading "=== Planned Firewall Configuration Summary ==="
  [[ "$CONFIG_WAS_IMPORTED" == "yes" ]] && echo "Imported config: $IMPORTED_CONFIG_FILE"
  [[ -n "$SETUP_MODE" ]] && echo "Setup mode: $SETUP_MODE"

  local iface
  for iface in "${ASSIGNED_IFACES[@]}"; do
    printf '  %-18s zone=%-16s profiles=%-28s storage=%-10s ingress_src=%-18s ingress_vip=%s\n' \
      "$iface" \
      "${IFACE_ZONE[$iface]:-}" \
      "${IFACE_PROFILES[$iface]:-}" \
      "${IFACE_STORAGE_OVERLAY[$iface]:-n/a}" \
      "${IFACE_VIP_SOURCES[$iface]:-n/a}" \
      "${IFACE_VIP_DESTS[$iface]:-n/a}"
  done

  echo
  printf '  Admin sources:            %s\n' "${ADMIN_SOURCES:-any}"
  printf '  Storage sources:          %s\n' "${STORAGE_SOURCES:-any}"
  printf '  K8s API/admin sources:    %s\n' "${K8S_API_SOURCES:-not configured}"
  printf '  RKE2 node sources:        %s\n' "${K8S_NODE_SOURCES:-not configured}"
  printf '  RKE2 server peer sources: %s\n' "${K8S_SERVER_PEER_SOURCES:-not configured}"
  printf '  CNI profile:              %s\n' "$CNI_PROFILE"
  printf '  Contour/Envoy ports:      %s\n' "$CONTOUR_SPECS"
  printf '  Docker CIDRs:             %s\n' "${DOCKER_CIDRS:-not configured}"
  echo
  warn "This will reset existing UFW rules, then enable UFW."
}

backup_current() {
  local backup_dir="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$backup_dir"
  ufw status numbered > "$backup_dir/ufw-status-numbered-before.txt" 2>&1 || true
  ufw show added > "$backup_dir/ufw-show-added-before.txt" 2>&1 || true
  cp -a /etc/ufw "$backup_dir/etc-ufw" 2>/dev/null || true
  echo "$backup_dir"
}

sysctl_harden() {
  local forwarding="$1" value=0
  [[ "$forwarding" == "yes" ]] && value=1
  cat > "$SYSCTL_DROPIN" <<EOF_SYSCTL
# Created by setup-ufw-zones-v13.sh
net.ipv4.ip_forward = $value
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF_SYSCTL
  run sysctl --system
}

ufw_base() {
  run sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw
  run ufw --force reset
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw default deny routed
  run ufw logging high
}

allow_in() {
  local iface="$1" proto="$2" port="$3" comment="$4" sources="$5" dests="$6" src dst
  [[ -z "$sources" ]] && sources="any"
  [[ -z "$dests" ]] && dests="any"
  for src in $sources; do
    for dst in $dests; do
      run ufw allow in on "$iface" proto "$proto" from "$src" to "$dst" port "$port" comment "$comment src=$src dst=$dst"
    done
  done
}

route_in() {
  local iface="$1" proto="$2" port="$3" comment="$4" sources="$5" dests="$6" src dst
  [[ -z "$sources" ]] && sources="any"
  [[ -z "$dests" ]] && return 0
  for src in $sources; do
    for dst in $dests; do
      run ufw route allow in on "$iface" proto "$proto" from "$src" to "$dst" port "$port" comment "$comment route src=$src dst=$dst"
    done
  done
}

apply_cni() {
  local iface="$1" spec port
  case "$CNI_PROFILE" in
    canal-vxlan)
      for spec in udp/8472 tcp/9099; do allow_in "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal $spec inbound" "$K8S_NODE_SOURCES" ""; done ;;
    canal-wireguard)
      for spec in udp/8472 udp/51820 udp/51821 tcp/9099; do allow_in "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal/WireGuard $spec inbound" "$K8S_NODE_SOURCES" ""; done ;;
    calico-bgp)
      for port in 179 5473 9098 9099; do allow_in "$iface" tcp "$port" "Calico port $port inbound" "$K8S_NODE_SOURCES" ""; done ;;
    calico-vxlan|flannel-vxlan)
      allow_in "$iface" udp 4789 "$CNI_PROFILE VXLAN inbound" "$K8S_NODE_SOURCES" "" ;;
    cilium-vxlan-wireguard)
      allow_in "$iface" tcp 4240 "Cilium health inbound" "$K8S_NODE_SOURCES" ""
      allow_in "$iface" udp 8472 "Cilium VXLAN inbound" "$K8S_NODE_SOURCES" ""
      allow_in "$iface" udp 51871 "Cilium WireGuard inbound" "$K8S_NODE_SOURCES" "" ;;
  esac
}

apply_storage() {
  local iface="$1" overlay="${IFACE_STORAGE_OVERLAY[$1]:-}"
  [[ "$overlay" =~ nfs ]] && allow_in "$iface" tcp 2049 "storage_zone NFSv4 inbound" "$STORAGE_SOURCES" ""
  [[ "$overlay" =~ iscsi ]] && allow_in "$iface" tcp 3260 "storage_zone iSCSI target inbound" "$STORAGE_SOURCES" ""
}

apply_ingress() {
  local iface="$1" specs="$2" label="$3" spec proto port sources dests
  sources="${IFACE_VIP_SOURCES[$iface]:-${VIP_SOURCES:-}}"
  dests="${IFACE_VIP_DESTS[$iface]:-${VIP_DESTS:-}}"
  [[ -z "$sources" ]] && sources="any"
  for spec in $specs; do
    proto="${spec%%/*}"
    port="${spec#*/}"
    allow_in "$iface" "$proto" "$port" "$label $spec inbound" "$sources" "$dests"
    [[ "$ROUTE_VIP" == "yes" ]] && route_in "$iface" "$proto" "$port" "$label $spec routed VIP" "$sources" "$dests"
  done
}

apply_harbor() {
  local iface="$1" spec port
  allow_in "$iface" tcp 443 "Harbor/Docker HTTPS host inbound" "$RESTRICTED_SOURCES" ""
  for spec in $DOCKER_PORTS; do
    port="${spec#*/}"
    route_in "$iface" tcp "$port" "Harbor/Docker routed TCP/$port" "$RESTRICTED_SOURCES" "$DOCKER_CIDRS"
  done
}

apply_all() {
  local backup_dir iface other profiles port forwarding="no"
  [[ "${#K8S_IFACES[@]}" -gt 0 || "${#CONTOUR_IFACES[@]}" -gt 0 || "${#HARBOR_IFACES[@]}" -gt 0 ]] && forwarding="yes"

  backup_dir="$(backup_current)"
  sysctl_harden "$forwarding"
  ufw_base

  for iface in "${ASSIGNED_IFACES[@]}"; do
    profiles=" ${IFACE_PROFILES[$iface]:-} "

    case "${IFACE_ZONE[$iface]:-}" in
      domain_zone)
        allow_in "$iface" tcp 22 "domain_zone SSH inbound" "$ADMIN_SOURCES" ""
        ;;
      storage_zone)
        apply_storage "$iface"
        ;;
    esac

    [[ "$profiles" == *" contour-envoy-ingress "* ]] && apply_ingress "$iface" "$CONTOUR_SPECS" "Contour/Envoy ingress"
    [[ "$profiles" == *" harbor-docker "* ]] && apply_harbor "$iface"

    if [[ "$profiles" == *" rke2-server "* ]]; then
      allow_in "$iface" tcp 6443 "rke2-server API admin inbound" "$K8S_API_SOURCES" ""
      allow_in "$iface" tcp 6443 "rke2-server API node inbound" "$K8S_NODE_SOURCES" ""
      allow_in "$iface" tcp 9345 "rke2-server supervisor inbound" "$K8S_NODE_SOURCES" ""
      for port in 2379 2380 2381; do
        allow_in "$iface" tcp "$port" "rke2-server etcd/server-peer $port inbound" "$K8S_SERVER_PEER_SOURCES" ""
      done
      allow_in "$iface" tcp 10250 "rke2-server kubelet inbound" "$K8S_NODE_SOURCES" ""
      [[ "$CNI_PROFILE" != "none" ]] && apply_cni "$iface"
    fi

    if [[ "$profiles" == *" rke2-agent "* ]]; then
      allow_in "$iface" tcp 10250 "rke2-agent kubelet inbound" "$K8S_NODE_SOURCES" ""
      [[ "$CNI_PROFILE" != "none" ]] && apply_cni "$iface"
    fi

    if [[ "$profiles" == *" rke2-singlenode "* ]]; then
      allow_in "$iface" tcp 6443 "rke2-singlenode API inbound" "$K8S_API_SOURCES" ""
      if [[ "$SINGLENODE_ENABLE_CNI" == "yes" && "$CNI_PROFILE" != "none" ]]; then
        apply_cni "$iface"
      fi
    fi

    if [[ "$NODEPORTS" == "yes" ]]; then
      allow_in "$iface" tcp 30000:32767 "Kubernetes NodePort TCP inbound" "$VIP_SOURCES" ""
      allow_in "$iface" udp 30000:32767 "Kubernetes NodePort UDP inbound" "$VIP_SOURCES" ""
    fi

    if [[ "$KUBE_PROXY_HEALTHCHECK" == "yes" ]]; then
      allow_in "$iface" tcp 10256 "kube-proxy health check inbound" "$K8S_LB_HEALTHCHECK_SOURCES" ""
    fi
  done

  for iface in "${ASSIGNED_IFACES[@]}"; do
    for other in "${ASSIGNED_IFACES[@]}"; do
      [[ "$iface" != "$other" ]] && run ufw route deny in on "$iface" out on "$other" comment "deny routed traffic $iface to $other"
    done
  done

  run ufw --force enable
  run ufw reload
  ufw status numbered
  echo "Backup saved at: $backup_dir"
}

main() {
  init_colors
  need_root
  init_logging
  for cmd in ip ufw sysctl awk sed; do need "$cmd"; done

  heading "=== UFW Quick Zone/Profile Setup ==="
  echo "Version: $SCRIPT_VERSION"

  discover_ifaces
  if ! maybe_import; then
    collect_quick
  fi
  rebuild_lists
  show_plan

  step "Optional configuration save"
  yesno "Save this configuration to a file before applying?" "Y" && save_config

  yesno "Apply this firewall configuration now?" "N" || {
    echo "No changes applied. Log: $LOG_FILE"
    exit 0
  }

  apply_all
}

main "$@"
