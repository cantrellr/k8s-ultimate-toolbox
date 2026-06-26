#!/usr/bin/env bash
# setup-ufw-zones-v12.2.sh
#
# Quick-first UFW zone/profile firewall setup for multi-NIC Ubuntu/RKE2 hosts.
#
# v12.2 changes:
#   - Contour/Envoy quick setup asks for restricted_zone/ingress interfaces explicitly.
#   - Each ingress interface gets its own VIP destination prompt.
#   - Quick Contour/Envoy always defaults to tcp/80 tcp/443 without a port prompt.
#   - Import flow prompts for config path and asks whether changes are needed before apply.
#   - Keeps v12 Quick Setup presets, import/export, and tighter RKE2 role-specific port model.

set -euo pipefail

SCRIPT_VERSION="2026-06-26-v12.2-per-interface-ingress-vips"
CONFIG_KIND_EXPECTED="ufw-zone-profile-config"
CONFIG_VERSION_EXPECTED="v12"
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
HARBOR_IFACES=()
CUSTOM_INGRESS_IFACES=()
CONTOUR_IFACES=()
K8S_VIP_IFACES=()

declare -A IFACE_ZONE=()
declare -A IFACE_PROFILES=()
declare -A IFACE_STORAGE_OVERLAY=()
declare -A IFACE_VIP_DESTS=()

LOG_FILE=""
PROMPT_STEP=0
CONFIG_WAS_IMPORTED="no"
IMPORTED_CONFIG_FILE=""
SETUP_MODE=""

ADMIN_SOURCES=""
DOMAIN_PROFILE="ssh-only"
STORAGE_SOURCES=""
NFS_EXTRA_MODE="none"
STORAGE_CUSTOM_SPECS=""
RESTRICTED_SOURCES=""
VIP_SOURCES=""
VIP_DESTS=""
VIP_DESTS_ANY="no"
K8S_API_SOURCES=""
K8S_NODE_SOURCES=""
K8S_SERVER_PEER_SOURCES=""
K8S_LB_HEALTHCHECK_SOURCES=""
CNI_PROFILE="none"
SINGLENODE_ENABLE_CNI="no"
NODEPORTS="no"
KUBE_PROXY_HEALTHCHECK="no"
ISTIO_PROFILE="none"
CUSTOM_INGRESS_SPECS=""
CONTOUR_SPECS="tcp/80 tcp/443"
DOCKER_CIDRS=""
DOCKER_PORTS=""
DOCKER_GUARD="no"
ROUTE_VIP="yes"

C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""

init_colors() {
  if [[ -t 0 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
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
warn() { printf '%bWARNING:%b %s\n' "${C_BOLD}${C_YELLOW}" "$C_RESET" "$*" >&2; }
err() { printf '%bERROR:%b %s\n' "${C_BOLD}${C_RED}" "$C_RESET" "$*" >&2; }
info() { printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }

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

need() { command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }; }

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
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

append() {
  local array_name="$1" value="$2"
  [[ -z "$value" ]] && return 0
  eval "local current=(\"\${${array_name}[@]:-}\")"
  if ! contains "$value" "${current[@]}"; then eval "${array_name}+=(\"\$value\")"; fi
}

join() { local IFS=' '; echo "$*"; }
norm() { local input="$1"; echo "${input//,/ }"; }
skey() { local s="$1"; echo "${s//[^A-Za-z0-9_]/_}"; }

need_root() { [[ "${EUID}" -eq 0 ]] || { err "Run as root or with sudo."; exit 1; }; }

init_log() {
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

discover() {
  mapfile -t DETECTED_IFACES < <(list_ifaces)
  [[ "${#DETECTED_IFACES[@]}" -gt 0 ]] || { err "No usable physical/primary interfaces detected."; exit 1; }
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
  [[ "$choice" =~ ^[0-9]+$ ]] || { echo ""; return 1; }
  (( choice >= 1 && choice <= ${#DETECTED_IFACES[@]} )) || { echo ""; return 1; }
  echo "${DETECTED_IFACES[$((choice - 1))]}"
}

prompt_iface() {
  local prompt="$1" allow_none="${2:-yes}" default="${3:-}" choice iface
  while true; do
    print_ifaces >&2
    [[ "$allow_none" == "yes" ]] && echo "   0) None / skip" >&2
    read -r -p "${C_BOLD}${prompt}${C_RESET}" choice
    choice="$(trim "$choice")"
    [[ -z "$choice" && -n "$default" ]] && choice="$default"
    if [[ "$allow_none" == "yes" && "$choice" == "0" ]]; then echo ""; return 0; fi
    iface="$(iface_by_number "$choice")"
    if [[ -n "$iface" ]]; then echo "$iface"; return 0; fi
    err "Invalid interface selection."
  done
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
  HARBOR_IFACES=()
  CUSTOM_INGRESS_IFACES=()
  CONTOUR_IFACES=()
  K8S_VIP_IFACES=()
  IFACE_ZONE=()
  IFACE_PROFILES=()
  IFACE_STORAGE_OVERLAY=()
  IFACE_VIP_DESTS=()
}

set_zone_if_unset() {
  local iface="$1" zone="$2"
  [[ -z "$iface" ]] && return 0
  append ASSIGNED_IFACES "$iface"
  if [[ -z "${IFACE_ZONE[$iface]:-}" || "${IFACE_ZONE[$iface]:-}" == "unassigned" ]]; then
    IFACE_ZONE[$iface]="$zone"
  fi
}

add_profile() {
  local iface="$1" profile="$2" existing
  [[ -z "$iface" || -z "$profile" ]] && return 0
  existing=" ${IFACE_PROFILES[$iface]:-} "
  if [[ "$existing" != *" $profile "* ]]; then
    IFACE_PROFILES[$iface]="$(trim "${IFACE_PROFILES[$iface]:-} $profile")"
  fi
}

rebuild() {
  DOMAIN_IFACES=(); STORAGE_IFACES=(); RESTRICTED_IFACES=(); K8S_IFACES=()
  RKE2_SERVER_IFACES=(); RKE2_AGENT_IFACES=(); RKE2_SINGLE_IFACES=()
  HARBOR_IFACES=(); CUSTOM_INGRESS_IFACES=(); CONTOUR_IFACES=()
  local iface profile
  for iface in "${ASSIGNED_IFACES[@]}"; do
    case "${IFACE_ZONE[$iface]:-}" in
      domain_zone) append DOMAIN_IFACES "$iface" ;;
      storage_zone) append STORAGE_IFACES "$iface" ;;
      restricted_zone) append RESTRICTED_IFACES "$iface" ;;
    esac
    for profile in ${IFACE_PROFILES[$iface]:-}; do
      case "$profile" in
        rke2-server) append K8S_IFACES "$iface"; append RKE2_SERVER_IFACES "$iface" ;;
        rke2-agent) append K8S_IFACES "$iface"; append RKE2_AGENT_IFACES "$iface" ;;
        rke2-singlenode) append K8S_IFACES "$iface"; append RKE2_SINGLE_IFACES "$iface" ;;
        harbor-docker) append HARBOR_IFACES "$iface" ;;
        custom-ingress) append CUSTOM_INGRESS_IFACES "$iface" ;;
        contour-envoy-ingress) append CONTOUR_IFACES "$iface" ;;
      esac
    done
  done
}

stor_of() { case "$1" in 1) echo "nfs-only" ;; 2) echo "iscsi-only" ;; 3) echo "nfs-iscsi" ;; 4) echo "custom" ;; *) echo "invalid" ;; esac; }
zone_of() { case "$1" in 0) echo "unassigned" ;; 1) echo "domain_zone" ;; 2) echo "storage_zone" ;; 3) echo "restricted_zone" ;; *) echo "invalid" ;; esac; }
prof_of() { case "$1" in 0) echo "zone-base" ;; 1) echo "rke2-server" ;; 2) echo "rke2-agent" ;; 3) echo "rke2-singlenode" ;; 4) echo "harbor-docker" ;; 5) echo "custom-ingress" ;; 6) echo "storage-workload" ;; 7) echo "contour-envoy-ingress" ;; *) echo "invalid" ;; esac; }

parse_cidrs() {
  local input="$1" item
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="$(norm "$input")"
  for item in $input; do
    if [[ "$item" == "any" || "$item" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ || "$item" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
      echo "$item"
    else
      err "Invalid CIDR/IP: $item"
      exit 1
    fi
  done
}

parse_specs() {
  local input="$1" item
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="$(norm "$input")"
  for item in $input; do
    [[ "$item" =~ ^(tcp|udp)/[0-9]+(:[0-9]+)?$ ]] || {
      err "Invalid port spec: $item. Use tcp/443 or udp/8472."
      exit 1
    }
    echo "$item"
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
  local prompt="$1" default="${2:-}" raw
  read -r -p "${C_BOLD}${prompt}${C_RESET}" raw
  raw="$(trim "$raw")"
  [[ -z "$raw" && -n "$default" ]] && raw="$default"
  parse_specs "$raw" | paste -sd ' ' -
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
  local file="$1" iface key zone profiles overlay vip imported
  valid_config "$file" || exit 1
  reset_model
  source "$file"
  [[ "${CONFIG_KIND:-}" == "$CONFIG_KIND_EXPECTED" ]] || { err "Config kind mismatch."; exit 1; }

  imported="${ASSIGNED_IFACES:-}"
  ASSIGNED_IFACES=()
  for iface in $imported; do
    append ASSIGNED_IFACES "$iface"
    key="$(skey "$iface")"
    eval "zone=\${IFACE_ZONE_${key}:-unassigned}"
    eval "profiles=\${IFACE_PROFILES_${key}:-none}"
    eval "overlay=\${IFACE_STORAGE_OVERLAY_${key}:-}"
    eval "vip=\${IFACE_VIP_DESTS_${key}:-}"
    IFACE_ZONE[$iface]="$zone"
    IFACE_PROFILES[$iface]="$profiles"
    [[ -n "$overlay" ]] && IFACE_STORAGE_OVERLAY[$iface]="$overlay"
    [[ -n "$vip" ]] && IFACE_VIP_DESTS[$iface]="$vip"
    contains "$iface" "${DETECTED_IFACES[@]}" || warn "Config references missing interface on this host: $iface"
  done
  rebuild
  IMPORTED_CONFIG_FILE="$file"
  CONFIG_WAS_IMPORTED="yes"
}

maybe_import() {
  local latest="$CONFIG_ROOT/$(hostname -s)-latest.conf" file default_path
  step "Optional configuration import"
  [[ -f "$latest" ]] && default_path="$latest" || default_path=""
  if [[ -n "$default_path" ]]; then
    echo "Default import file: $default_path" >&2
  fi
  if yesno "Import configuration from file?" "N"; then
    if [[ -n "$default_path" ]]; then
      read -r -p "${C_BOLD}Config file path [$default_path]:${C_RESET} " file
      file="$(trim "$file")"
      [[ -z "$file" ]] && file="$default_path"
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
  local path iface key var latest
  read -r -p "${C_BOLD}Save path [$default_path]:${C_RESET} " path
  path="$(trim "$path")"
  [[ -z "$path" ]] && path="$default_path"

  {
    echo "# UFW Zone/Profile saved configuration"
    echo "CONFIG_KIND=\"${CONFIG_KIND_EXPECTED}\""
    echo "CONFIG_VERSION=\"${CONFIG_VERSION_EXPECTED}\""
    echo "SCRIPT_VERSION_SAVED=\"${SCRIPT_VERSION}\""
    echo "HOSTNAME_HINT=\"$(hostname -f 2>/dev/null || hostname)\""
    echo "SETUP_MODE=$(quote_value "$SETUP_MODE")"
    echo "ASSIGNED_IFACES=$(quote_value "$(join "${ASSIGNED_IFACES[@]}")")"
    for iface in "${ASSIGNED_IFACES[@]}"; do
      key="$(skey "$iface")"
      echo "IFACE_ZONE_${key}=$(quote_value "${IFACE_ZONE[$iface]:-unassigned}")"
      echo "IFACE_PROFILES_${key}=$(quote_value "${IFACE_PROFILES[$iface]:-none}")"
      echo "IFACE_STORAGE_OVERLAY_${key}=$(quote_value "${IFACE_STORAGE_OVERLAY[$iface]:-}")"
      echo "IFACE_VIP_DESTS_${key}=$(quote_value "${IFACE_VIP_DESTS[$iface]:-}")"
    done
    for var in ADMIN_SOURCES DOMAIN_PROFILE STORAGE_SOURCES NFS_EXTRA_MODE STORAGE_CUSTOM_SPECS \
      RESTRICTED_SOURCES VIP_SOURCES VIP_DESTS VIP_DESTS_ANY K8S_API_SOURCES K8S_NODE_SOURCES \
      K8S_SERVER_PEER_SOURCES K8S_LB_HEALTHCHECK_SOURCES CNI_PROFILE SINGLENODE_ENABLE_CNI \
      NODEPORTS KUBE_PROXY_HEALTHCHECK ISTIO_PROFILE CUSTOM_INGRESS_SPECS CONTOUR_SPECS \
      DOCKER_CIDRS DOCKER_PORTS DOCKER_GUARD ROUTE_VIP; do
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
    {
      echo "Choose the closest preset. Advanced/manual is still available."
      echo "  1) RKE2 single-node + optional Contour + optional storage"
      echo "  2) RKE2 server/controller + optional Contour + optional storage"
      echo "  3) RKE2 agent/worker + optional Contour + optional storage"
      echo "  4) Contour/Envoy ingress only"
      echo "  5) Harbor/Docker service"
      echo "  6) Advanced/manual"
      echo
    } >&2
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

read_storage_overlay_quick() {
  local choice overlay
  while true; do
    {
      echo "Storage overlay:"
      echo "  1) NFS only"
      echo "  2) iSCSI only"
      echo "  3) NFS + iSCSI"
      echo "  4) Custom"
      echo
    } >&2
    read -r -p "${C_BOLD}Storage overlay [1-4, default 3]:${C_RESET} " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="3"
    overlay="$(stor_of "$choice")"
    [[ "$overlay" != "invalid" ]] && { echo "$overlay"; return; }
    err "Enter 1 through 4."
  done
}

choose_cni_quick() {
  local choice
  while true; do
    {
      echo "Primary CNI under Multus, if Multus is used:"
      echo "  0) None"
      echo "  1) RKE2 Canal VXLAN - common RKE2 default"
      echo "  2) RKE2 Canal + WireGuard"
      echo "  3) Calico BGP"
      echo "  4) Calico VXLAN"
      echo "  5) Flannel VXLAN"
      echo "  6) Cilium VXLAN/WireGuard"
      echo
    } >&2
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

collect_quick_common_storage() {
  local storage_iface overlay
  step "Optional storage interface"
  storage_iface="$(prompt_iface "Storage interface number [0 for none]: " "yes" "0")"
  if [[ -n "$storage_iface" ]]; then
    set_zone_if_unset "$storage_iface" "storage_zone"
    add_profile "$storage_iface" "storage-workload"
    overlay="$(read_storage_overlay_quick)"
    IFACE_STORAGE_OVERLAY[$storage_iface]="$overlay"
    STORAGE_SOURCES="$(prompt_cidrs "Storage peer CIDR(s), blank for any on storage NIC: ")"
    if [[ "$overlay" == "custom" ]]; then
      STORAGE_CUSTOM_SPECS="$(prompt_specs "Custom storage specs, e.g. tcp/2049 tcp/3260: ")"
    fi
  fi
  return 0
}

collect_quick_contour() {
  local ask_default="${1:-N}" ingress_iface vip_dest added_any="no"
  step "Optional Contour/Envoy ingress"
  if yesno "Add Contour/Envoy ingress VIP rules?" "$ask_default"; then
    CONTOUR_SPECS="tcp/80 tcp/443"
    echo "Using default Contour/Envoy ports: tcp/80 tcp/443" >&2

    while true; do
      ingress_iface="$(prompt_iface "restricted_zone/Ingress interface number [0 to finish]: " "yes" "0")"
      if [[ -z "$ingress_iface" ]]; then
        if [[ "$added_any" == "no" ]]; then
          warn "No restricted_zone/Ingress interface selected. Skipping Contour/Envoy rules."
        fi
        break
      fi

      set_zone_if_unset "$ingress_iface" "restricted_zone"
      add_profile "$ingress_iface" "contour-envoy-ingress"
      append CONTOUR_IFACES "$ingress_iface"

      vip_dest=""
      while [[ -z "$vip_dest" ]]; do
        vip_dest="$(prompt_cidrs "VIP destination CIDR(s) for $ingress_iface, required: ")"
        [[ -z "$vip_dest" ]] && err "Enter at least one VIP destination CIDR/IP for $ingress_iface."
      done
      IFACE_VIP_DESTS[$ingress_iface]="$vip_dest"
      if [[ -z "$VIP_DESTS" ]]; then VIP_DESTS="$vip_dest"; else VIP_DESTS="$(trim "$VIP_DESTS $vip_dest")"; fi

      added_any="yes"
      if yesno "Is there another interface that will receive ingress traffic?" "N"; then
        continue
      fi
      break
    done

    if [[ "$added_any" == "yes" ]]; then
      RESTRICTED_SOURCES="$(prompt_cidrs "Ingress client source CIDR(s), blank for any: ")"
      VIP_SOURCES="$RESTRICTED_SOURCES"
      ROUTE_VIP="yes"
    fi
  fi
  return 0
}

collect_quick() {
  reset_model
  print_ifaces
  choose_mode

  local rke_iface harbor_iface
  case "$SETUP_MODE" in
    rke2-single-quick)
      step "RKE2 single-node interface"
      rke_iface="$(prompt_iface "Admin/RKE2 interface number: " "no")"
      set_zone_if_unset "$rke_iface" "domain_zone"
      add_profile "$rke_iface" "rke2-singlenode"
      DOMAIN_PROFILE="ssh-only"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/API source CIDR(s), blank for any: ")"
      K8S_API_SOURCES="$ADMIN_SOURCES"
      CNI_PROFILE="none"
      SINGLENODE_ENABLE_CNI="no"
      collect_quick_common_storage
      collect_quick_contour "Y"
      ;;
    rke2-server-quick)
      step "RKE2 server/controller interface"
      rke_iface="$(prompt_iface "Admin/RKE2 server interface number: " "no")"
      set_zone_if_unset "$rke_iface" "domain_zone"
      add_profile "$rke_iface" "rke2-server"
      DOMAIN_PROFILE="ssh-only"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/API source CIDR(s), blank for any: ")"
      K8S_API_SOURCES="$ADMIN_SOURCES"
      K8S_NODE_SOURCES="$(prompt_cidrs "All RKE2 node CIDR(s), used for 9345/10250/CNI: " "$ADMIN_SOURCES")"
      K8S_SERVER_PEER_SOURCES="$(prompt_cidrs "RKE2 server/etcd peer CIDR(s), blank to reuse node CIDR(s): " "$K8S_NODE_SOURCES")"
      CNI_PROFILE="$(choose_cni_quick)"
      collect_quick_common_storage
      collect_quick_contour "Y"
      ;;
    rke2-agent-quick)
      step "RKE2 agent/worker interface"
      rke_iface="$(prompt_iface "RKE2 agent/worker interface number: " "no")"
      set_zone_if_unset "$rke_iface" "domain_zone"
      add_profile "$rke_iface" "rke2-agent"
      DOMAIN_PROFILE="ssh-only"
      ADMIN_SOURCES="$(prompt_cidrs "Admin/SSH source CIDR(s), blank for any: ")"
      K8S_NODE_SOURCES="$(prompt_cidrs "RKE2 server/node CIDR(s), used for 10250/CNI: " "$ADMIN_SOURCES")"
      CNI_PROFILE="$(choose_cni_quick)"
      collect_quick_common_storage
      collect_quick_contour "N"
      ;;
    contour-only-quick)
      collect_quick_contour "Y"
      ;;
    harbor-docker-quick)
      step "Harbor/Docker service interface"
      harbor_iface="$(prompt_iface "Harbor/service interface number: " "no")"
      set_zone_if_unset "$harbor_iface" "restricted_zone"
      add_profile "$harbor_iface" "harbor-docker"
      RESTRICTED_SOURCES="$(prompt_cidrs "Allowed Harbor client source CIDR(s), blank for any: ")"
      DOCKER_CIDRS="$(prompt_cidrs "Docker bridge destination CIDR(s), e.g. 172.17.0.0/16: ")"
      DOCKER_PORTS="$(prompt_specs "Docker/Harbor destination TCP ports [default tcp/80 tcp/443 tcp/8080 tcp/8443]: " "tcp/80 tcp/443 tcp/8080 tcp/8443")"
      DOCKER_GUARD="yes"
      ;;
    advanced-manual)
      collect_advanced_manual
      return
      ;;
  esac
  rebuild
}

read_zone_advanced() {
  local iface="$1" choice zone
  while true; do
    step "Zone selection for $iface"
    {
      echo "  0) Unassigned"
      echo "  1) domain_zone"
      echo "  2) storage_zone"
      echo "  3) restricted_zone"
      echo
    } >&2
    read -r -p "${C_BOLD}Zone choice [0-3]:${C_RESET} " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="0"
    zone="$(zone_of "$choice")"
    [[ "$zone" != "invalid" ]] && { echo "$zone"; return; }
    err "Enter 0 through 3."
  done
}

read_profiles_advanced() {
  local iface="$1" zone="$2" input number profile selected
  while true; do
    step "Profile selection for $iface ($zone)"
    {
      echo "  0) Zone base only"
      echo "  1) RKE2-Server"
      echo "  2) RKE2-Agent"
      echo "  3) RKE2-SingleNode"
      echo "  4) Harbor-Docker"
      echo "  5) Custom-Ingress"
      echo "  6) Storage-Workload"
      echo "  7) Contour-Envoy-Ingress"
      echo
    } >&2
    read -r -p "${C_BOLD}Profile choice(s) [default 0]:${C_RESET} " input
    input="$(trim "$input")"
    [[ -z "$input" ]] && input="0"
    selected=()
    for number in $(norm "$input"); do
      [[ "$number" =~ ^[0-7]$ ]] || { err "Invalid profile: $number"; continue 2; }
      profile="$(prof_of "$number")"
      [[ "$profile" == "zone-base" && "$input" != "0" ]] && { err "Do not combine 0 with other profiles."; continue 2; }
      selected+=("$profile")
    done
    echo "${selected[*]}"
    return
  done
}

collect_advanced_manual() {
  reset_model
  print_ifaces
  local iface zone profiles overlay vip_dest
  for iface in "${DETECTED_IFACES[@]}"; do
    zone="$(read_zone_advanced "$iface")"
    IFACE_ZONE[$iface]="$zone"
    [[ "$zone" == "unassigned" ]] && { IFACE_PROFILES[$iface]="none"; continue; }
    append ASSIGNED_IFACES "$iface"
    if [[ "$zone" == "storage_zone" ]]; then
      overlay="$(read_storage_overlay_quick)"
      IFACE_STORAGE_OVERLAY[$iface]="$overlay"
      IFACE_PROFILES[$iface]="storage-workload"
    else
      profiles="$(read_profiles_advanced "$iface" "$zone")"
      IFACE_PROFILES[$iface]="$profiles"
    fi
  done
  rebuild

  ADMIN_SOURCES="$(prompt_cidrs "Admin/source CIDR(s), blank for any: ")"
  [[ "${#STORAGE_IFACES[@]}" -gt 0 ]] && STORAGE_SOURCES="$(prompt_cidrs "Storage peer CIDR(s), blank for any: ")"

  if [[ "${#RKE2_SERVER_IFACES[@]}" -gt 0 || "${#RKE2_SINGLE_IFACES[@]}" -gt 0 ]]; then
    K8S_API_SOURCES="$(prompt_cidrs "K8s API/admin CIDR(s), blank to reuse admin: " "$ADMIN_SOURCES")"
  fi
  if [[ "${#RKE2_SERVER_IFACES[@]}" -gt 0 || "${#RKE2_AGENT_IFACES[@]}" -gt 0 ]]; then
    K8S_NODE_SOURCES="$(prompt_cidrs "All RKE2 node CIDR(s), used for 9345/10250/CNI: " "$ADMIN_SOURCES")"
    CNI_PROFILE="$(choose_cni_quick)"
  fi
  [[ "${#RKE2_SERVER_IFACES[@]}" -gt 0 ]] && K8S_SERVER_PEER_SOURCES="$(prompt_cidrs "RKE2 server/etcd peer CIDR(s), blank to reuse node CIDR(s): " "$K8S_NODE_SOURCES")"

  if [[ "${#CONTOUR_IFACES[@]}" -gt 0 || "${#CUSTOM_INGRESS_IFACES[@]}" -gt 0 ]]; then
    RESTRICTED_SOURCES="$(prompt_cidrs "Ingress/client source CIDR(s), blank for any: ")"
    VIP_SOURCES="$RESTRICTED_SOURCES"
    for iface in "${CONTOUR_IFACES[@]}" "${CUSTOM_INGRESS_IFACES[@]}"; do
      [[ -z "$iface" ]] && continue
      vip_dest=""
      while [[ -z "$vip_dest" ]]; do
        vip_dest="$(prompt_cidrs "VIP destination CIDR(s) for $iface, required: ")"
        [[ -z "$vip_dest" ]] && err "Enter at least one VIP destination CIDR/IP for $iface."
      done
      IFACE_VIP_DESTS[$iface]="$vip_dest"
      if [[ -z "$VIP_DESTS" ]]; then VIP_DESTS="$vip_dest"; else VIP_DESTS="$(trim "$VIP_DESTS $vip_dest")"; fi
    done
    [[ "${#CONTOUR_IFACES[@]}" -gt 0 ]] && CONTOUR_SPECS="tcp/80 tcp/443"
    [[ "${#CUSTOM_INGRESS_IFACES[@]}" -gt 0 ]] && CUSTOM_INGRESS_SPECS="$(prompt_specs "Custom ingress specs [default tcp/443]: " "tcp/443")"
  fi
}

show_plan() {
  heading "=== Planned Firewall Configuration Summary ==="
  [[ "$CONFIG_WAS_IMPORTED" == "yes" ]] && echo "Imported config: $IMPORTED_CONFIG_FILE"
  [[ -n "$SETUP_MODE" ]] && echo "Setup mode: $SETUP_MODE"

  local iface
  for iface in "${ASSIGNED_IFACES[@]}"; do
    printf '  %-18s zone=%-16s profiles=%-30s storage_overlay=%-10s vip_dest=%s\n' \
      "$iface" \
      "${IFACE_ZONE[$iface]:-}" \
      "${IFACE_PROFILES[$iface]:-}" \
      "${IFACE_STORAGE_OVERLAY[$iface]:-n/a}" \
      "${IFACE_VIP_DESTS[$iface]:-n/a}"
  done

  echo
  printf '  Admin sources:              %s\n' "${ADMIN_SOURCES:-any}"
  printf '  Restricted/client sources:  %s\n' "${RESTRICTED_SOURCES:-any}"
  printf '  Storage sources:            %s\n' "${STORAGE_SOURCES:-any}"
  printf '  K8s API/admin sources:      %s\n' "${K8S_API_SOURCES:-not configured}"
  printf '  RKE2 node sources:          %s\n' "${K8S_NODE_SOURCES:-not configured}"
  printf '  RKE2 server peer sources:   %s\n' "${K8S_SERVER_PEER_SOURCES:-not configured}"
  printf '  CNI profile:                %s\n' "$CNI_PROFILE"
  printf '  Single-node CNI override:   %s\n' "$SINGLENODE_ENABLE_CNI"
  printf '  NodePort enabled:           %s\n' "$NODEPORTS"
  printf '  kube-proxy 10256 enabled:   %s\n' "$KUBE_PROXY_HEALTHCHECK"
  printf '  VIP client sources:         %s\n' "${VIP_SOURCES:-not configured}"
  if [[ "$VIP_DESTS_ANY" == "yes" ]]; then
    printf '  VIP destinations:           any destination\n'
  else
    printf '  VIP destinations:           %s\n' "${VIP_DESTS:-not configured}"
  fi
  printf '  Contour/Envoy specs:        %s\n' "${CONTOUR_SPECS:-none}"
  printf '  Custom ingress specs:       %s\n' "${CUSTOM_INGRESS_SPECS:-none}"
  printf '  Storage custom specs:       %s\n' "${STORAGE_CUSTOM_SPECS:-none}"
  printf '  Docker CIDRs:               %s\n' "${DOCKER_CIDRS:-not configured}"
  printf '  Docker ports:               %s\n' "${DOCKER_PORTS:-not configured}"
  echo
  warn "This will reset existing UFW rules, then enable UFW."
}

backup() {
  local backup_dir="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$backup_dir"
  ufw status numbered > "$backup_dir/ufw-status-numbered-before.txt" 2>&1 || true
  ufw show added > "$backup_dir/ufw-show-added-before.txt" 2>&1 || true
  cp -a /etc/ufw "$backup_dir/etc-ufw" 2>/dev/null || true
  echo "$backup_dir"
}

sysctl_harden() {
  local forwarding="$1" reason="$2" value=0
  [[ "$forwarding" == "yes" ]] && value=1
  cat > "$SYSCTL_DROPIN" <<EOF
# Created by setup-ufw-zones-v12.2.sh
# $reason
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
EOF
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

apply_ingress_specs() {
  local iface="$1" sources="$2" dests="$3" specs="$4" label="$5" spec proto port effective_dests
  [[ "$VIP_DESTS_ANY" == "yes" ]] && effective_dests="" || effective_dests="$dests"
  for spec in $specs; do
    proto="${spec%%/*}"
    port="${spec#*/}"
    allow_in "$iface" "$proto" "$port" "$label $spec inbound" "$sources" "$effective_dests"
    [[ "$ROUTE_VIP" == "yes" && -n "$effective_dests" ]] && route_in "$iface" "$proto" "$port" "$label $spec routed VIP" "$sources" "$effective_dests"
  done
}

apply_cni() {
  local iface="$1" spec port
  case "$CNI_PROFILE" in
    canal-vxlan) for spec in udp/8472 tcp/9099; do allow_in "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal $spec inbound" "$K8S_NODE_SOURCES" ""; done ;;
    canal-wireguard) for spec in udp/8472 udp/51820 udp/51821 tcp/9099; do allow_in "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal/WireGuard $spec inbound" "$K8S_NODE_SOURCES" ""; done ;;
    calico-bgp) for port in 179 5473 9098 9099; do allow_in "$iface" tcp "$port" "Calico port $port inbound" "$K8S_NODE_SOURCES" ""; done ;;
    calico-vxlan) allow_in "$iface" udp 4789 "Calico VXLAN inbound" "$K8S_NODE_SOURCES" "" ;;
    flannel-vxlan) allow_in "$iface" udp 4789 "Flannel VXLAN inbound" "$K8S_NODE_SOURCES" "" ;;
    cilium-vxlan-wireguard)
      allow_in "$iface" tcp 4240 "Cilium health inbound" "$K8S_NODE_SOURCES" ""
      allow_in "$iface" udp 8472 "Cilium VXLAN inbound" "$K8S_NODE_SOURCES" ""
      allow_in "$iface" udp 51871 "Cilium WireGuard inbound" "$K8S_NODE_SOURCES" ""
      ;;
  esac
}

apply_storage() {
  local iface="$1" overlay="${IFACE_STORAGE_OVERLAY[$1]:-}" port spec
  [[ "$overlay" =~ nfs ]] && allow_in "$iface" tcp 2049 "storage_zone NFSv4 inbound" "$STORAGE_SOURCES" ""
  [[ "$overlay" =~ iscsi ]] && allow_in "$iface" tcp 3260 "storage_zone iSCSI target inbound" "$STORAGE_SOURCES" ""
  [[ "$NFS_EXTRA_MODE" =~ udp ]] && allow_in "$iface" udp 2049 "storage_zone NFS UDP inbound" "$STORAGE_SOURCES" ""
  if [[ "$NFS_EXTRA_MODE" =~ legacy ]]; then
    for port in 111 20048 662 875 892 32765 32766 32767 32768; do
      allow_in "$iface" tcp "$port" "storage_zone legacy NFSv3 pinned port $port inbound" "$STORAGE_SOURCES" ""
      allow_in "$iface" udp "$port" "storage_zone legacy NFSv3 pinned port $port inbound" "$STORAGE_SOURCES" ""
    done
  fi
  if [[ "$overlay" == "custom" ]]; then
    for spec in $STORAGE_CUSTOM_SPECS; do
      allow_in "$iface" "${spec%%/*}" "${spec#*/}" "storage custom $spec inbound" "$STORAGE_SOURCES" ""
    done
  fi
}

apply_harbor_docker() {
  local iface="$1" spec port
  allow_in "$iface" tcp 443 "Harbor/Docker HTTPS host inbound" "$RESTRICTED_SOURCES" ""
  for spec in $DOCKER_PORTS; do
    port="${spec#*/}"
    route_in "$iface" tcp "$port" "Harbor/Docker routed TCP/$port to Docker bridge" "$RESTRICTED_SOURCES" "$DOCKER_CIDRS"
  done
}

apply_all() {
  local backup_dir iface other profiles port forwarding="no" iface_vips
  [[ "${#K8S_IFACES[@]}" -gt 0 || "${#CONTOUR_IFACES[@]}" -gt 0 || "${#HARBOR_IFACES[@]}" -gt 0 ]] && forwarding="yes"

  backup_dir="$(backup)"
  sysctl_harden "$forwarding" "UFW zone setup $SCRIPT_VERSION"
  ufw_base

  for iface in "${ASSIGNED_IFACES[@]}"; do
    profiles=" ${IFACE_PROFILES[$iface]:-} "

    case "${IFACE_ZONE[$iface]}" in
      domain_zone)
        allow_in "$iface" tcp 22 "domain_zone SSH inbound" "$ADMIN_SOURCES" ""
        if [[ "$DOMAIN_PROFILE" == "web" || "$DOMAIN_PROFILE" == "dc" ]]; then
          allow_in "$iface" tcp 80 "domain_zone HTTP inbound" "$ADMIN_SOURCES" ""
          allow_in "$iface" tcp 443 "domain_zone HTTPS inbound" "$ADMIN_SOURCES" ""
        fi
        ;;
      storage_zone)
        apply_storage "$iface"
        ;;
    esac

    if [[ "$profiles" == *" contour-envoy-ingress "* ]]; then
      iface_vips="${IFACE_VIP_DESTS[$iface]:-${VIP_DESTS:-}}"
      apply_ingress_specs "$iface" "$VIP_SOURCES" "$iface_vips" "$CONTOUR_SPECS" "Contour/Envoy ingress"
    fi

    if [[ "$profiles" == *" custom-ingress "* ]]; then
      iface_vips="${IFACE_VIP_DESTS[$iface]:-${VIP_DESTS:-}}"
      apply_ingress_specs "$iface" "$VIP_SOURCES" "$iface_vips" "$CUSTOM_INGRESS_SPECS" "custom ingress"
    fi

    [[ "$profiles" == *" harbor-docker "* ]] && apply_harbor_docker "$iface"

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
      [[ "$SINGLENODE_ENABLE_CNI" == "yes" && "$CNI_PROFILE" != "none" ]] && apply_cni "$iface"
    fi

    if [[ "$NODEPORTS" == "yes" ]]; then
      allow_in "$iface" tcp 30000:32767 "Kubernetes NodePort TCP inbound" "$VIP_SOURCES" ""
      allow_in "$iface" udp 30000:32767 "Kubernetes NodePort UDP inbound" "$VIP_SOURCES" ""
    fi

    [[ "$KUBE_PROXY_HEALTHCHECK" == "yes" ]] && allow_in "$iface" tcp 10256 "kube-proxy health check inbound" "$K8S_LB_HEALTHCHECK_SOURCES" ""
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
  init_log
  for cmd in ip ufw sysctl awk sed ss iptables; do need "$cmd"; done

  heading "=== UFW Quick Zone/Profile Setup ==="
  echo "Version: $SCRIPT_VERSION"

  discover
  if ! maybe_import; then
    collect_quick
  fi
  rebuild
  show_plan

  step "Optional configuration save"
  yesno "Save this configuration to a file before applying?" "Y" && save_config

  yesno "Apply this firewall configuration now?" "N" || {
    echo "No changes applied. Action log saved at: $LOG_FILE"
    exit 0
  }

  apply_all
}

main "$@"
