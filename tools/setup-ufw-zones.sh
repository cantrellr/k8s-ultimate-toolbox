#!/usr/bin/env bash
# setup-ufw-zones-v6.sh
#
# Purpose:
#   Configure UFW as interface-scoped firewall "zones" on a multi-NIC Ubuntu/Debian host.
#   Includes Docker/Harbor-aware forwarding and optional Kubernetes/RKE2 port profiles on selected NICs.
#
# Zones:
#   domain_zone:     SSH, HTTP, HTTPS inbound; optional AD/DC/Samba domain-service inbound profile
#   storage_zone:    NFS/iSCSI inbound only
#   restricted_zone: HTTPS inbound only
#
# Security posture:
#   - Default deny inbound
#   - Default allow outbound
#   - Default deny routed/forwarded traffic through UFW
#   - Explicit deny routed traffic between assigned physical zone interfaces
#   - Docker/Harbor forwarding is interface-specific: domain_zone, restricted_zone, or both
#   - Kubernetes/RKE2 rules are interface-specific and source-CIDR aware
#   - IPv4 forwarding is enabled only when Docker/Harbor or Kubernetes support requires it
#   - Persistent DOCKER-USER guard blocks storage/non-selected zones from Docker container CIDRs
#   - Basic anti-spoofing and redirect/source-route hardening
#   - Full script action logging to /var/log/ufw-zone-setup
#
# Notes:
#   UFW does not implement native zones like firewalld. This script emulates zones using
#   interface-scoped rules: "allow in on <interface> proto tcp from any to any port <port>".
#
# Docker/Harbor note:
#   Harbor commonly publishes host TCP/443 and DNATs it to a container port such as TCP/8443.
#   That traffic uses the Linux FORWARD path after Docker DNAT, not only normal local INPUT.
#
# Kubernetes/RKE2 note:
#   Kubernetes networking is iptables/nftables heavy. Keep Kubernetes rules restricted to node/admin CIDRs.
#   Never expose etcd, kubelet, VXLAN/WireGuard, or CNI health ports to the Internet.
#
# Tested syntax target: Bash 4+, UFW 0.36+

set -euo pipefail

SCRIPT_VERSION="2026-06-25-v6-docker-kubernetes-interface-rules-logging"
BACKUP_ROOT="/root/ufw-zone-backups"
LOG_ROOT="/var/log/ufw-zone-setup"
SYSCTL_DROPIN="/etc/sysctl.d/99-ufw-zone-hardening.conf"
DOCKER_GUARD_SCRIPT="/usr/local/sbin/ufw-zone-docker-guard.sh"
DOCKER_GUARD_ENV="/etc/default/ufw-zone-docker-guard"
DOCKER_GUARD_SERVICE="/etc/systemd/system/ufw-zone-docker-guard.service"
DETECTED_IFACES=()
LOG_FILE=""

DOMAIN_IFACES_GLOBAL=()
STORAGE_IFACES_GLOBAL=()
RESTRICTED_IFACES_GLOBAL=()

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root or with sudo." >&2
    exit 1
  fi
}

init_logging() {
  mkdir -p "$LOG_ROOT"
  chmod 750 "$LOG_ROOT"
  LOG_FILE="$LOG_ROOT/setup-ufw-zones-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE"

  # Capture all stdout/stderr from this point forward on-screen and on-machine.
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "=== UFW Zone Setup Action Log ==="
  echo "Version: $SCRIPT_VERSION"
  echo "Date: $(date -Is)"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
  echo "Log file: $LOG_FILE"
  echo
}

log() {
  echo "[$(date -Is)] $*" >&2
}

run_cmd() {
  log "+ $*"
  "$@"
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  fi
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

yes_no() {
  local prompt="$1"
  local default="${2:-N}"
  local reply suffix

  if [[ "$default" =~ ^[Yy]$ ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    read -r -p "$prompt $suffix: " reply
    reply="$(trim "$reply")"
    if [[ -z "$reply" ]]; then
      reply="$default"
    fi
    case "$reply" in
      y|Y|yes|YES|Yes) log "Prompt accepted yes: $prompt"; return 0 ;;
      n|N|no|NO|No) log "Prompt accepted no: $prompt"; return 1 ;;
      *) echo "Please answer y or n." >&2 ;;
    esac
  done
}

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

join_by_space() {
  local IFS=' '
  echo "$*"
}

list_interfaces() {
  ip -o link show \
    | awk -F': ' '{print $2}' \
    | sed 's/@.*//' \
    | grep -Ev '^(lo|docker[0-9]*|br-|veth|virbr|zt|tailscale|wg|tun|tap|cni|flannel|vxlan|cali|lxc|nerdctl)' \
    | sort -u
}

discover_interfaces() {
  mapfile -t DETECTED_IFACES < <(list_interfaces)

  if [[ "${#DETECTED_IFACES[@]}" -eq 0 ]]; then
    echo "ERROR: No usable ethernet interfaces were detected." >&2
    echo "Ignored interfaces: lo, docker*, br-*, veth*, virbr*, zt*, tailscale*, wg*, tun*, tap*, cni*, flannel*, vxlan*, cali*, lxc*, nerdctl*." >&2
    exit 1
  fi
}

print_interfaces() {
  echo
  echo "Detected physical/primary interfaces:"
  local i=1 iface state mac addrs
  for iface in "${DETECTED_IFACES[@]}"; do
    [[ -z "$iface" ]] && continue
    state="$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)"
    mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo unknown)"
    addrs="$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd ',' -)"
    [[ -z "$addrs" ]] && addrs="no-ipv4"
    printf '  %2d) %-18s state=%-8s mac=%-17s ipv4=%s\n' "$i" "$iface" "$state" "$mac" "$addrs"
    ((i++))
  done
  echo
}

read_iface_selection() {
  local zone_name="$1"
  local prompt="$2"
  shift 2
  local already_assigned=("$@")
  local input normalized token idx iface assigned

  while true; do
    read -r -p "$prompt" input
    input="$(trim "$input")"
    log "Interface selection input for $zone_name: '${input:-blank}'"

    if [[ -z "$input" ]]; then
      echo ""
      return 0
    fi

    normalized="${input//,/ }"

    local ok=1
    local selected=()
    local seen=" "

    for token in $normalized; do
      if [[ ! "$token" =~ ^[0-9]+$ ]]; then
        echo "ERROR: '$token' is not a valid menu number. Enter one or more numbers from the list, for example: 1 or 1,2." >&2
        ok=0
        break
      fi

      idx=$((token - 1))
      if (( token < 1 || token > ${#DETECTED_IFACES[@]} )); then
        echo "ERROR: '$token' is outside the valid range 1-${#DETECTED_IFACES[@]}. Try again." >&2
        ok=0
        break
      fi

      iface="${DETECTED_IFACES[$idx]}"
      if [[ "$seen" == *" $iface "* ]]; then
        echo "ERROR: Interface '$iface' was selected more than once for $zone_name. Try again." >&2
        ok=0
        break
      fi

      for assigned in "${already_assigned[@]}"; do
        if [[ "$iface" == "$assigned" ]]; then
          echo "ERROR: Interface '$iface' is already assigned to another zone. Pick a different interface for $zone_name." >&2
          ok=0
          break
        fi
      done
      [[ "$ok" -eq 0 ]] && break

      selected+=("$iface")
      seen+="$iface "
    done

    if [[ "$ok" -eq 1 ]]; then
      log "Interface selection resolved for $zone_name: ${selected[*]}"
      printf '%s\n' "${selected[*]}"
      return 0
    fi
  done
}

iface_zone_label() {
  local iface="$1"
  if array_contains "$iface" "${DOMAIN_IFACES_GLOBAL[@]}"; then
    echo "domain_zone"
  elif array_contains "$iface" "${RESTRICTED_IFACES_GLOBAL[@]}"; then
    echo "restricted_zone"
  elif array_contains "$iface" "${STORAGE_IFACES_GLOBAL[@]}"; then
    echo "storage_zone"
  else
    echo "unassigned"
  fi
}

read_iface_selection_from_allowed_list() {
  local selection_name="$1"
  local prompt="$2"
  shift 2
  local allowed_ifaces=("$@")
  local input normalized token idx iface

  if [[ "${#allowed_ifaces[@]}" -eq 0 ]]; then
    echo ""
    return 0
  fi

  echo >&2
  echo "Eligible interfaces for $selection_name:" >&2
  local i=1 zone_label
  for iface in "${allowed_ifaces[@]}"; do
    zone_label="$(iface_zone_label "$iface")"
    printf '  %2d) %-18s zone=%s\n' "$i" "$iface" "$zone_label" >&2
    ((i++))
  done

  while true; do
    read -r -p "$prompt" input
    input="$(trim "$input")"
    log "Interface selection input for $selection_name: '${input:-blank}'"

    if [[ -z "$input" ]]; then
      echo ""
      return 0
    fi

    normalized="${input//,/ }"
    local ok=1
    local selected=()
    local seen=" "

    for token in $normalized; do
      if [[ ! "$token" =~ ^[0-9]+$ ]]; then
        echo "ERROR: '$token' is not a valid menu number. Enter one or more numbers from the list, for example: 1 or 1,2." >&2
        ok=0
        break
      fi

      idx=$((token - 1))
      if (( token < 1 || token > ${#allowed_ifaces[@]} )); then
        echo "ERROR: '$token' is outside the valid range 1-${#allowed_ifaces[@]}. Try again." >&2
        ok=0
        break
      fi

      iface="${allowed_ifaces[$idx]}"
      if [[ "$seen" == *" $iface "* ]]; then
        echo "ERROR: Interface '$iface' was selected more than once. Try again." >&2
        ok=0
        break
      fi

      selected+=("$iface")
      seen+="$iface "
    done

    if [[ "$ok" -eq 1 ]]; then
      log "Interface selection resolved for $selection_name: ${selected[*]}"
      printf '%s\n' "${selected[*]}"
      return 0
    fi
  done
}

validate_no_overlap() {
  local all_ifaces=("$@")
  local seen=" " iface
  for iface in "${all_ifaces[@]}"; do
    [[ -z "$iface" ]] && continue
    if [[ "$seen" == *" $iface "* ]]; then
      echo "ERROR: Interface '$iface' was assigned to more than one zone." >&2
      echo "Each NIC should belong to exactly one firewall zone for clean segmentation." >&2
      exit 1
    fi
    seen+="$iface "
  done
}

parse_cidrs() {
  local input="$1"
  local cidrs=()
  local cidr octets octet prefix
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0

  for cidr in $input; do
    if [[ "$cidr" == "any" ]]; then
      continue
    fi

    if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
      local ip="${cidr%%/*}"
      prefix=""
      [[ "$cidr" == */* ]] && prefix="${cidr##*/}"
      IFS='.' read -r -a octets <<< "$ip"
      for octet in "${octets[@]}"; do
        if (( octet < 0 || octet > 255 )); then
          echo "ERROR: '$cidr' has an invalid IPv4 octet." >&2
          exit 1
        fi
      done
      if [[ -n "$prefix" ]] && (( prefix < 0 || prefix > 32 )); then
        echo "ERROR: '$cidr' has an invalid IPv4 CIDR prefix." >&2
        exit 1
      fi
      cidrs+=("$cidr")
    elif [[ "$cidr" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
      cidrs+=("$cidr")
    else
      echo "ERROR: '$cidr' does not look like an IPv4/IPv6 address or CIDR." >&2
      exit 1
    fi
  done

  printf '%s\n' "${cidrs[@]}"
}

validate_port_or_range() {
  local p="$1"
  local a b
  if [[ "$p" =~ ^[0-9]+$ ]]; then
    (( p >= 1 && p <= 65535 )) || return 1
    return 0
  fi
  if [[ "$p" =~ ^[0-9]+:[0-9]+$ ]]; then
    a="${p%%:*}"
    b="${p##*:}"
    (( a >= 1 && a <= 65535 && b >= 1 && b <= 65535 && a <= b )) || return 1
    return 0
  fi
  return 1
}

parse_ports() {
  local input="$1"
  local ports=()
  local p
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="${input//,/ }"

  for p in $input; do
    if ! validate_port_or_range "$p"; then
      echo "ERROR: '$p' is not a valid TCP/UDP port or range. Use 443 or 30000:32767." >&2
      exit 1
    fi
    ports+=("$p")
  done

  printf '%s\n' "${ports[@]}"
}

backup_current_config() {
  local ts backup_dir
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="$BACKUP_ROOT/$ts"
  run_cmd mkdir -p "$backup_dir"

  log "Creating backup in: $backup_dir"
  ufw status verbose > "$backup_dir/ufw-status-before.txt" 2>&1 || true
  ufw status numbered > "$backup_dir/ufw-status-numbered-before.txt" 2>&1 || true
  ufw show added > "$backup_dir/ufw-show-added-before.txt" 2>&1 || true
  ufw show raw > "$backup_dir/ufw-show-raw-before.txt" 2>&1 || true
  iptables-save > "$backup_dir/iptables-save-before.txt" 2>&1 || true
  ip6tables-save > "$backup_dir/ip6tables-save-before.txt" 2>&1 || true
  nft list ruleset > "$backup_dir/nft-ruleset-before.txt" 2>&1 || true
  sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding > "$backup_dir/sysctl-forwarding-before.txt" 2>&1 || true
  cp -a /etc/ufw "$backup_dir/etc-ufw" 2>/dev/null || true
  cp -a /etc/default/ufw "$backup_dir/default-ufw" 2>/dev/null || true
  cp -a "$SYSCTL_DROPIN" "$backup_dir/previous-$(basename "$SYSCTL_DROPIN")" 2>/dev/null || true
  cp -a "$DOCKER_GUARD_SCRIPT" "$backup_dir/previous-$(basename "$DOCKER_GUARD_SCRIPT")" 2>/dev/null || true
  cp -a "$DOCKER_GUARD_ENV" "$backup_dir/previous-$(basename "$DOCKER_GUARD_ENV")" 2>/dev/null || true
  cp -a "$DOCKER_GUARD_SERVICE" "$backup_dir/previous-$(basename "$DOCKER_GUARD_SERVICE")" 2>/dev/null || true

  echo "$backup_dir"
}

apply_sysctl_hardening() {
  local forwarding_required="$1"
  local reason="$2"
  local ipv4_forward_value="0"
  local forwarding_comment="Do not route traffic between interfaces/zones."

  if [[ "$forwarding_required" == "yes" ]]; then
    ipv4_forward_value="1"
    forwarding_comment="IPv4 forwarding required for: $reason. UFW routed default-deny and explicit guard rules preserve segmentation."
  fi

  log "Writing sysctl hardening drop-in: $SYSCTL_DROPIN"
  cat > "$SYSCTL_DROPIN" <<SYSCTL_EOF
# Created by setup-ufw-zones-v6.sh
# Multi-NIC firewall hardening.

# $forwarding_comment
net.ipv4.ip_forward = $ipv4_forward_value
net.ipv6.conf.all.forwarding = 0

# Drop source-routed packets and ICMP redirects.
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Do not send redirects; this host should not advertise itself as a router.
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Spoofing hygiene. Loose mode is safer for multi-homed systems than strict mode.
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# Log spoofed/martian packets.
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
SYSCTL_EOF

  run_cmd sysctl --system
}

configure_ufw_defaults() {
  log "Configuring UFW defaults"
  run_cmd sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

  if grep -q '^IPV6=' /etc/default/ufw; then
    run_cmd sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
  fi

  run_cmd ufw --force reset
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw default deny routed

  # High during commissioning. Drop to medium later if too noisy.
  run_cmd ufw logging high
}

ufw_allow_in() {
  local iface="$1"
  local proto="$2"
  local port="$3"
  local comment="$4"
  shift 4
  local sources=("$@")

  if [[ "${#sources[@]}" -eq 0 ]]; then
    run_cmd ufw allow in on "$iface" proto "$proto" from any to any port "$port" comment "$comment"
  else
    local src
    for src in "${sources[@]}"; do
      run_cmd ufw allow in on "$iface" proto "$proto" from "$src" to any port "$port" comment "$comment from $src"
    done
  fi
}

ufw_route_allow_to_cidr_port() {
  local in_iface="$1"
  local proto="$2"
  local port="$3"
  local dst_cidr="$4"
  local comment="$5"

  run_cmd ufw route allow in on "$in_iface" proto "$proto" from any to "$dst_cidr" port "$port" comment "$comment"
}

apply_restricted_zone() {
  local iface
  for iface in "$@"; do
    [[ -z "$iface" ]] && continue
    ufw_allow_in "$iface" tcp 443 "restricted_zone HTTPS inbound"
  done
}

apply_storage_zone() {
  local sources_csv="$1"
  local include_nfs_udp="$2"
  local include_legacy_nfs="$3"
  shift 3

  local sources=()
  if [[ -n "$sources_csv" ]]; then
    mapfile -t sources < <(printf '%s\n' "$sources_csv" | sed '/^$/d')
  fi

  local iface p
  for iface in "$@"; do
    [[ -z "$iface" ]] && continue

    ufw_allow_in "$iface" tcp 2049 "storage_zone NFSv4 inbound" "${sources[@]}"

    if [[ "$include_nfs_udp" == "yes" ]]; then
      ufw_allow_in "$iface" udp 2049 "storage_zone NFS UDP inbound" "${sources[@]}"
    fi

    ufw_allow_in "$iface" tcp 3260 "storage_zone iSCSI target inbound" "${sources[@]}"

    if [[ "$include_legacy_nfs" == "yes" ]]; then
      for p in 111 20048 662 875 892 32765 32766 32767 32768; do
        ufw_allow_in "$iface" tcp "$p" "storage_zone legacy NFSv3 pinned port $p inbound" "${sources[@]}"
        ufw_allow_in "$iface" udp "$p" "storage_zone legacy NFSv3 pinned port $p inbound" "${sources[@]}"
      done
    fi
  done
}

apply_domain_zone() {
  local ssh_sources_csv="$1"
  local domain_profile="$2"
  shift 2

  local ssh_sources=()
  if [[ -n "$ssh_sources_csv" ]]; then
    mapfile -t ssh_sources < <(printf '%s\n' "$ssh_sources_csv" | sed '/^$/d')
  fi

  local iface
  for iface in "$@"; do
    [[ -z "$iface" ]] && continue

    ufw_allow_in "$iface" tcp 22 "domain_zone SSH inbound" "${ssh_sources[@]}"
    ufw_allow_in "$iface" tcp 80 "domain_zone HTTP inbound"
    ufw_allow_in "$iface" tcp 443 "domain_zone HTTPS inbound"

    if [[ "$domain_profile" == "dc" ]]; then
      ufw_allow_in "$iface" tcp 53 "domain_zone DNS TCP inbound"
      ufw_allow_in "$iface" udp 53 "domain_zone DNS UDP inbound"
      ufw_allow_in "$iface" tcp 88 "domain_zone Kerberos TCP inbound"
      ufw_allow_in "$iface" udp 88 "domain_zone Kerberos UDP inbound"
      ufw_allow_in "$iface" tcp 464 "domain_zone Kerberos password TCP inbound"
      ufw_allow_in "$iface" udp 464 "domain_zone Kerberos password UDP inbound"
      ufw_allow_in "$iface" tcp 389 "domain_zone LDAP TCP inbound"
      ufw_allow_in "$iface" udp 389 "domain_zone LDAP UDP inbound"
      ufw_allow_in "$iface" tcp 636 "domain_zone LDAPS TCP inbound"
      ufw_allow_in "$iface" tcp 445 "domain_zone SMB inbound"
      ufw_allow_in "$iface" tcp 135 "domain_zone RPC endpoint mapper inbound"
      ufw_allow_in "$iface" tcp 3268 "domain_zone Global Catalog inbound"
      ufw_allow_in "$iface" tcp 3269 "domain_zone Global Catalog SSL inbound"
      ufw_allow_in "$iface" udp 123 "domain_zone NTP inbound"

      if yes_no "Add high dynamic RPC TCP range 49152:65535 for AD/DC compatibility? This is a wide range; only use on trusted internal domain networks." "N"; then
        run_cmd ufw allow in on "$iface" proto tcp from any to any port 49152:65535 comment "domain_zone AD dynamic RPC high range inbound"
      fi
    fi
  done
}

k8s_profile_menu() {
  echo
  echo "Kubernetes/RKE2 port profiles:"
  echo "  1) RKE2 server/control-plane/etcd baseline"
  echo "     TCP: 6443, 9345, 2379, 2380, 2381, 10250"
  echo "  2) RKE2 agent/worker baseline"
  echo "     TCP: 10250"
  echo "  3) Upstream kubeadm-style control-plane baseline"
  echo "     TCP: 6443, 2379, 2380, 10250, 10257, 10259"
  echo "  4) Upstream Kubernetes worker baseline"
  echo "     TCP: 10250, 10256"
  echo "  5) Kubernetes API only"
  echo "     TCP: 6443"
  echo "  6) NodePort only"
  echo "     TCP/UDP: 30000:32767"
  echo "  7) Custom only"
  echo
}

read_k8s_profile() {
  local choice
  while true; do
    k8s_profile_menu >&2
    read -r -p "Select Kubernetes/RKE2 profile [1-7]: " choice
    choice="$(trim "$choice")"
    log "Kubernetes profile selection: '${choice:-blank}'"
    case "$choice" in
      1) echo "rke2-server"; return 0 ;;
      2) echo "rke2-agent"; return 0 ;;
      3) echo "kubeadm-control-plane"; return 0 ;;
      4) echo "kube-worker"; return 0 ;;
      5) echo "api-only"; return 0 ;;
      6) echo "nodeport-only"; return 0 ;;
      7) echo "custom-only"; return 0 ;;
      *) echo "ERROR: Enter a number from 1 to 7." >&2 ;;
    esac
  done
}

k8s_cni_menu() {
  echo
  echo "Kubernetes/RKE2 CNI profiles:"
  echo "  0) None"
  echo "  1) RKE2 Canal VXLAN"
  echo "     UDP: 8472; TCP: 9099"
  echo "  2) RKE2 Canal VXLAN + WireGuard"
  echo "     UDP: 8472, 51820, 51821; TCP: 9099"
  echo "  3) Calico BGP"
  echo "     TCP: 179, 5473, 9098, 9099"
  echo "  4) Calico VXLAN"
  echo "     UDP: 4789; TCP: 5473, 9098, 9099"
  echo "  5) Flannel VXLAN"
  echo "     UDP: 4789"
  echo "  6) Cilium VXLAN/WireGuard baseline"
  echo "     TCP: 4240; UDP: 8472, 51871"
  echo "  7) Custom CNI ports only"
  echo
}

read_k8s_cni_profile() {
  local choice
  while true; do
    k8s_cni_menu >&2
    read -r -p "Select Kubernetes/RKE2 CNI profile [0-7]: " choice
    choice="$(trim "$choice")"
    log "Kubernetes CNI profile selection: '${choice:-blank}'"
    case "$choice" in
      0) echo "none"; return 0 ;;
      1) echo "canal-vxlan"; return 0 ;;
      2) echo "canal-wireguard"; return 0 ;;
      3) echo "calico-bgp"; return 0 ;;
      4) echo "calico-vxlan"; return 0 ;;
      5) echo "flannel-vxlan"; return 0 ;;
      6) echo "cilium-vxlan-wireguard"; return 0 ;;
      7) echo "custom-cni"; return 0 ;;
      *) echo "ERROR: Enter a number from 0 to 7." >&2 ;;
    esac
  done
}

add_k8s_rule() {
  local iface="$1"
  local proto="$2"
  local port="$3"
  local comment="$4"
  shift 4
  local sources=("$@")

  ufw_allow_in "$iface" "$proto" "$port" "$comment" "${sources[@]}"
}

apply_kubernetes_rules() {
  local sources_csv="$1"
  local k8s_profile="$2"
  local cni_profile="$3"
  local add_nodeports="$4"
  local custom_specs_csv="$5"
  shift 5

  local sources=()
  if [[ -n "$sources_csv" ]]; then
    mapfile -t sources < <(printf '%s\n' "$sources_csv" | sed '/^$/d')
  fi

  local iface spec proto port
  for iface in "$@"; do
    [[ -z "$iface" ]] && continue
    local zone_label
    zone_label="$(iface_zone_label "$iface")"

    case "$k8s_profile" in
      rke2-server)
        add_k8s_rule "$iface" tcp 6443 "kubernetes/rke2 $zone_label API server inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9345 "kubernetes/rke2 $zone_label supervisor API inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 2379 "kubernetes/rke2 $zone_label etcd client inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 2380 "kubernetes/rke2 $zone_label etcd peer inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 2381 "kubernetes/rke2 $zone_label etcd metrics inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 10250 "kubernetes/rke2 $zone_label kubelet inbound" "${sources[@]}"
        ;;
      rke2-agent)
        add_k8s_rule "$iface" tcp 10250 "kubernetes/rke2 $zone_label kubelet inbound" "${sources[@]}"
        ;;
      kubeadm-control-plane)
        add_k8s_rule "$iface" tcp 6443 "kubernetes $zone_label API server inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 2379 "kubernetes $zone_label etcd client inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 2380 "kubernetes $zone_label etcd peer inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 10250 "kubernetes $zone_label kubelet inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 10257 "kubernetes $zone_label controller-manager secure port inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 10259 "kubernetes $zone_label scheduler secure port inbound" "${sources[@]}"
        ;;
      kube-worker)
        add_k8s_rule "$iface" tcp 10250 "kubernetes $zone_label kubelet inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 10256 "kubernetes $zone_label kube-proxy healthz inbound" "${sources[@]}"
        ;;
      api-only)
        add_k8s_rule "$iface" tcp 6443 "kubernetes $zone_label API server inbound" "${sources[@]}"
        ;;
      nodeport-only|custom-only)
        :
        ;;
      *)
        echo "ERROR: Unknown Kubernetes profile: $k8s_profile" >&2
        exit 1
        ;;
    esac

    if [[ "$add_nodeports" == "yes" || "$k8s_profile" == "nodeport-only" ]]; then
      add_k8s_rule "$iface" tcp 30000:32767 "kubernetes $zone_label NodePort TCP range inbound" "${sources[@]}"
      add_k8s_rule "$iface" udp 30000:32767 "kubernetes $zone_label NodePort UDP range inbound" "${sources[@]}"
    fi

    case "$cni_profile" in
      none)
        :
        ;;
      canal-vxlan)
        add_k8s_rule "$iface" udp 8472 "kubernetes/rke2 $zone_label Canal VXLAN inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9099 "kubernetes/rke2 $zone_label Canal health inbound" "${sources[@]}"
        ;;
      canal-wireguard)
        add_k8s_rule "$iface" udp 8472 "kubernetes/rke2 $zone_label Canal VXLAN inbound" "${sources[@]}"
        add_k8s_rule "$iface" udp 51820 "kubernetes/rke2 $zone_label Canal WireGuard IPv4 inbound" "${sources[@]}"
        add_k8s_rule "$iface" udp 51821 "kubernetes/rke2 $zone_label Canal WireGuard IPv6 inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9099 "kubernetes/rke2 $zone_label Canal health inbound" "${sources[@]}"
        ;;
      calico-bgp)
        add_k8s_rule "$iface" tcp 179 "kubernetes $zone_label Calico BGP inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 5473 "kubernetes $zone_label Calico Typha inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9098 "kubernetes $zone_label Calico Typha health inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9099 "kubernetes $zone_label Calico health inbound" "${sources[@]}"
        ;;
      calico-vxlan)
        add_k8s_rule "$iface" udp 4789 "kubernetes $zone_label Calico VXLAN inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 5473 "kubernetes $zone_label Calico Typha inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9098 "kubernetes $zone_label Calico Typha health inbound" "${sources[@]}"
        add_k8s_rule "$iface" tcp 9099 "kubernetes $zone_label Calico health inbound" "${sources[@]}"
        ;;
      flannel-vxlan)
        add_k8s_rule "$iface" udp 4789 "kubernetes $zone_label Flannel VXLAN inbound" "${sources[@]}"
        ;;
      cilium-vxlan-wireguard)
        add_k8s_rule "$iface" tcp 4240 "kubernetes $zone_label Cilium health inbound" "${sources[@]}"
        add_k8s_rule "$iface" udp 8472 "kubernetes $zone_label Cilium VXLAN inbound" "${sources[@]}"
        add_k8s_rule "$iface" udp 51871 "kubernetes $zone_label Cilium WireGuard inbound" "${sources[@]}"
        ;;
      custom-cni)
        :
        ;;
      *)
        echo "ERROR: Unknown Kubernetes CNI profile: $cni_profile" >&2
        exit 1
        ;;
    esac

    if [[ -n "$custom_specs_csv" ]]; then
      while read -r spec; do
        [[ -z "$spec" ]] && continue
        proto="${spec%%/*}"
        port="${spec#*/}"
        add_k8s_rule "$iface" "$proto" "$port" "kubernetes $zone_label custom $proto/$port inbound" "${sources[@]}"
      done <<< "$custom_specs_csv"
    fi
  done
}

parse_proto_port_specs() {
  local input="$1"
  local specs=()
  local item proto port
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="${input//,/ }"

  for item in $input; do
    if [[ ! "$item" =~ ^(tcp|udp)/[0-9]+(:[0-9]+)?$ ]]; then
      echo "ERROR: '$item' is invalid. Use tcp/6443, udp/8472, or tcp/30000:32767." >&2
      exit 1
    fi
    proto="${item%%/*}"
    port="${item#*/}"
    if ! validate_port_or_range "$port"; then
      echo "ERROR: '$item' has an invalid port or range." >&2
      exit 1
    fi
    specs+=("$proto/$port")
  done

  printf '%s\n' "${specs[@]}"
}

docker_available() {
  command -v docker >/dev/null 2>&1
}

docker_daemon_running() {
  docker_available || return 1
  docker info >/dev/null 2>&1
}

docker_publishes_443() {
  docker_daemon_running || return 1
  docker ps --format '{{.Ports}}' 2>/dev/null | grep -Eq '(^|,| )0\.0\.0\.0:443->|(^|,| )\[::\]:443->|(^|,| ):::443->|(^|,| )443/tcp' || return 1
}

print_docker_context() {
  echo
  echo "Docker context:"
  if ! docker_available; then
    echo "  docker command: not found"
    return 0
  fi

  if ! docker_daemon_running; then
    echo "  docker command: found"
    echo "  docker daemon: not running or not reachable"
    return 0
  fi

  echo "  docker daemon: running"
  docker ps --format '  container={{.Names}} image={{.Image}} ports={{.Ports}}' 2>/dev/null || true
  echo
  echo "Docker bridge networks/subnets:"
  docker network ls --format '{{.ID}} {{.Name}} {{.Driver}}' 2>/dev/null | while read -r id name driver; do
    [[ "$driver" != "bridge" ]] && continue
    local subnets bridge_name
    subnets="$(docker network inspect "$id" --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
    bridge_name="$(docker network inspect "$id" --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
    [[ -z "$bridge_name" || "$bridge_name" == "<no value>" ]] && bridge_name="br-${id:0:12}"
    printf '  network=%-20s bridge=%-15s subnet=%s\n' "$name" "$bridge_name" "${subnets:-none}"
  done
}

default_docker_cidrs() {
  docker_daemon_running || return 0
  docker network ls --format '{{.ID}} {{.Driver}}' 2>/dev/null | while read -r id driver; do
    [[ "$driver" != "bridge" ]] && continue
    docker network inspect "$id" --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null || true
  done | grep -Ev '^$' | sort -u
}

apply_forwarded_docker_web_rules() {
  local dst_cidrs_csv="$1"
  local dst_ports_csv="$2"
  shift 2
  local allowed_ifaces=("$@")

  [[ -z "$dst_cidrs_csv" || -z "$dst_ports_csv" || "${#allowed_ifaces[@]}" -eq 0 ]] && return 0

  local dst_cidrs=()
  local dst_ports=()
  mapfile -t dst_cidrs < <(printf '%s\n' "$dst_cidrs_csv" | sed '/^$/d')
  mapfile -t dst_ports < <(printf '%s\n' "$dst_ports_csv" | sed '/^$/d')

  local iface dst port zone_label
  for iface in "${allowed_ifaces[@]}"; do
    [[ -z "$iface" ]] && continue
    zone_label="$(iface_zone_label "$iface")"
    for dst in "${dst_cidrs[@]}"; do
      for port in "${dst_ports[@]}"; do
        ufw_route_allow_to_cidr_port "$iface" tcp "$port" "$dst" "$zone_label Docker/Harbor forwarded TCP/$port to $dst"
      done
    done
  done
}

apply_interzone_route_denies() {
  local ifaces=("$@")
  local in_if out_if

  for in_if in "${ifaces[@]}"; do
    [[ -z "$in_if" ]] && continue
    for out_if in "${ifaces[@]}"; do
      [[ -z "$out_if" ]] && continue
      [[ "$in_if" == "$out_if" ]] && continue
      run_cmd ufw route deny in on "$in_if" out on "$out_if" comment "deny routed traffic $in_if to $out_if"
    done
  done
}

install_docker_guard() {
  local allowed_ifaces_csv="$1"
  local blocked_ifaces_csv="$2"
  local docker_cidrs_csv="$3"
  local docker_ports_csv="$4"

  [[ -z "$docker_cidrs_csv" || -z "$docker_ports_csv" ]] && return 0

  log "Installing persistent Docker/Harbor DOCKER-USER guard"
  cat > "$DOCKER_GUARD_ENV" <<ENV_EOF
# Created by setup-ufw-zones-v6.sh
# Space-separated or comma-separated values.
ALLOWED_DOCKER_ZONE_IFACES="$allowed_ifaces_csv"
BLOCKED_DOCKER_ZONE_IFACES="$blocked_ifaces_csv"
DOCKER_CIDRS="$(echo "$docker_cidrs_csv" | paste -sd ' ' -)"
DOCKER_WEB_PORTS="$(echo "$docker_ports_csv" | paste -sd ',' -)"
LOG_FILE="$LOG_ROOT/docker-guard.log"
ENV_EOF
  chmod 640 "$DOCKER_GUARD_ENV"

  cat > "$DOCKER_GUARD_SCRIPT" <<'GUARD_EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/default/ufw-zone-docker-guard"
[[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"

ALLOWED_DOCKER_ZONE_IFACES="${ALLOWED_DOCKER_ZONE_IFACES:-}"
BLOCKED_DOCKER_ZONE_IFACES="${BLOCKED_DOCKER_ZONE_IFACES:-}"
DOCKER_CIDRS="${DOCKER_CIDRS:-}"
DOCKER_WEB_PORTS="${DOCKER_WEB_PORTS:-80,443,8080,8443}"
LOG_FILE="${LOG_FILE:-/var/log/ufw-zone-setup/docker-guard.log}"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE" 2>/dev/null || true
exec >> "$LOG_FILE" 2>&1

echo "[$(date -Is)] Applying Docker/Harbor firewall guard"
echo "ALLOWED_DOCKER_ZONE_IFACES=$ALLOWED_DOCKER_ZONE_IFACES"
echo "BLOCKED_DOCKER_ZONE_IFACES=$BLOCKED_DOCKER_ZONE_IFACES"
echo "DOCKER_CIDRS=$DOCKER_CIDRS"
echo "DOCKER_WEB_PORTS=$DOCKER_WEB_PORTS"

if ! command -v iptables >/dev/null 2>&1; then
  echo "iptables not found; skipping Docker guard."
  exit 0
fi

iptables -N DOCKER-USER 2>/dev/null || true
iptables -N UFW-ZONE-DOCKER 2>/dev/null || true
iptables -F UFW-ZONE-DOCKER

iptables -C DOCKER-USER -j UFW-ZONE-DOCKER 2>/dev/null || iptables -I DOCKER-USER 1 -j UFW-ZONE-DOCKER

iptables -A UFW-ZONE-DOCKER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

for iface in $ALLOWED_DOCKER_ZONE_IFACES; do
  for cidr in $DOCKER_CIDRS; do
    [[ "$cidr" == *":"* ]] && continue
    iptables -A UFW-ZONE-DOCKER -i "$iface" -p tcp -d "$cidr" -m multiport --dports "$DOCKER_WEB_PORTS" -m comment --comment "ufw-zone allow selected zone to Docker web" -j RETURN
    iptables -A UFW-ZONE-DOCKER -i "$iface" -d "$cidr" -m limit --limit 6/min --limit-burst 10 -j LOG --log-prefix "UFWZ DOCKER DROP " --log-level 4
    iptables -A UFW-ZONE-DOCKER -i "$iface" -d "$cidr" -m comment --comment "ufw-zone drop non-web selected zone to Docker" -j DROP
  done
done

for iface in $BLOCKED_DOCKER_ZONE_IFACES; do
  for cidr in $DOCKER_CIDRS; do
    [[ "$cidr" == *":"* ]] && continue
    iptables -A UFW-ZONE-DOCKER -i "$iface" -d "$cidr" -m limit --limit 6/min --limit-burst 10 -j LOG --log-prefix "UFWZ DOCKER DROP " --log-level 4
    iptables -A UFW-ZONE-DOCKER -i "$iface" -d "$cidr" -m comment --comment "ufw-zone drop blocked zone to Docker" -j DROP
  done
done

iptables -A UFW-ZONE-DOCKER -j RETURN
iptables -S DOCKER-USER || true
iptables -S UFW-ZONE-DOCKER || true

echo "[$(date -Is)] Docker/Harbor firewall guard applied"
GUARD_EOF
  chmod 750 "$DOCKER_GUARD_SCRIPT"

  cat > "$DOCKER_GUARD_SERVICE" <<SERVICE_EOF
[Unit]
Description=UFW Zone Docker/Harbor DOCKER-USER firewall guard
Documentation=man:iptables(8)
After=network-online.target docker.service ufw.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$DOCKER_GUARD_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

  if command -v systemctl >/dev/null 2>&1; then
    run_cmd systemctl daemon-reload
    run_cmd systemctl enable ufw-zone-docker-guard.service
    run_cmd systemctl restart ufw-zone-docker-guard.service
  else
    run_cmd "$DOCKER_GUARD_SCRIPT"
  fi
}

show_summary() {
  local domain="$1"
  local storage="$2"
  local restricted="$3"
  local storage_sources="$4"
  local ssh_sources="$5"
  local domain_profile="$6"
  local nfs_udp="$7"
  local legacy_nfs="$8"
  local docker_mode="$9"
  local docker_allowed_ifaces="${10}"
  local docker_blocked_ifaces="${11}"
  local docker_cidrs="${12}"
  local docker_ports="${13}"
  local docker_guard="${14}"
  local k8s_mode="${15}"
  local k8s_ifaces="${16}"
  local k8s_sources="${17}"
  local k8s_profile="${18}"
  local k8s_cni_profile="${19}"
  local k8s_nodeports="${20}"
  local k8s_custom="${21}"

  echo
  echo "=== Planned Firewall Configuration Summary ==="
  printf '  domain_zone interface(s):           %s\n' "${domain:-not assigned}"
  printf '  storage_zone interface(s):          %s\n' "${storage:-not assigned}"
  printf '  restricted_zone interface(s):       %s\n' "${restricted:-not assigned}"
  printf '  Storage allowed source CIDR(s):     %s\n' "${storage_sources:-any source on storage NIC}"
  printf '  SSH allowed source CIDR(s):         %s\n' "${ssh_sources:-any source on domain NIC}"
  printf '  Domain profile:                     %s\n' "$domain_profile"
  printf '  NFS UDP/2049:                       %s\n' "$nfs_udp"
  printf '  Legacy NFSv3 pinned ports:          %s\n' "$legacy_nfs"
  printf '  Docker/Harbor forwarding enabled:   %s\n' "$docker_mode"
  printf '  Docker/Harbor allowed ingress NICs: %s\n' "${docker_allowed_ifaces:-not configured}"
  printf '  Docker/Harbor blocked zone NICs:    %s\n' "${docker_blocked_ifaces:-not configured}"
  printf '  Docker/Harbor destination CIDR(s):  %s\n' "${docker_cidrs:-not configured}"
  printf '  Docker/Harbor destination port(s):  %s\n' "${docker_ports:-not configured}"
  printf '  Persistent DOCKER-USER guard:       %s\n' "$docker_guard"
  printf '  Kubernetes/RKE2 rules enabled:      %s\n' "$k8s_mode"
  printf '  Kubernetes/RKE2 selected NICs:      %s\n' "${k8s_ifaces:-not configured}"
  printf '  Kubernetes/RKE2 source CIDR(s):     %s\n' "${k8s_sources:-not configured / any if enabled without CIDRs}"
  printf '  Kubernetes/RKE2 profile:            %s\n' "${k8s_profile:-not configured}"
  printf '  Kubernetes/RKE2 CNI profile:        %s\n' "${k8s_cni_profile:-not configured}"
  printf '  Kubernetes/RKE2 NodePort range:     %s\n' "$k8s_nodeports"
  printf '  Kubernetes/RKE2 custom ports:       %s\n' "${k8s_custom:-none}"
  echo
  echo "This will reset existing UFW rules, then enable UFW. Existing UFW/Docker firewall config will be backed up first."
  echo "All script output will be logged to: $LOG_FILE"
  echo
}

write_audit_report() {
  local backup_dir="$1"
  local domain_input="$2"
  local storage_input="$3"
  local restricted_input="$4"
  local docker_mode="$5"
  local docker_allowed_ifaces="$6"
  local docker_blocked_ifaces="$7"
  local docker_cidrs="$8"
  local docker_ports="$9"
  local k8s_mode="${10}"
  local k8s_ifaces="${11}"
  local k8s_sources="${12}"
  local k8s_profile="${13}"
  local k8s_cni_profile="${14}"
  local k8s_nodeports="${15}"
  local k8s_custom="${16}"
  local report="$backup_dir/ufw-zone-audit-after.txt"

  {
    echo "=== UFW Zone Audit ==="
    echo "Version: $SCRIPT_VERSION"
    echo "Date: $(date -Is)"
    echo "Host: $(hostname -f 2>/dev/null || hostname)"
    echo "Action log: $LOG_FILE"
    echo
    echo "Zone interfaces:"
    echo "  domain_zone:     ${domain_input:-not assigned}"
    echo "  storage_zone:    ${storage_input:-not assigned}"
    echo "  restricted_zone: ${restricted_input:-not assigned}"
    echo
    echo "Docker/Harbor mode: ${docker_mode}"
    echo "Docker/Harbor allowed ingress NICs: ${docker_allowed_ifaces:-not configured}"
    echo "Docker/Harbor blocked zone NICs: ${docker_blocked_ifaces:-not configured}"
    echo "Docker/Harbor CIDRs: ${docker_cidrs:-not configured}"
    echo "Docker/Harbor ports: ${docker_ports:-not configured}"
    echo
    echo "Kubernetes/RKE2 mode: ${k8s_mode}"
    echo "Kubernetes/RKE2 selected NICs: ${k8s_ifaces:-not configured}"
    echo "Kubernetes/RKE2 source CIDRs: ${k8s_sources:-not configured}"
    echo "Kubernetes/RKE2 profile: ${k8s_profile:-not configured}"
    echo "Kubernetes/RKE2 CNI profile: ${k8s_cni_profile:-not configured}"
    echo "Kubernetes/RKE2 NodePorts: ${k8s_nodeports}"
    echo "Kubernetes/RKE2 custom ports: ${k8s_custom:-none}"
    echo
    echo "=== ip -br addr ==="
    ip -br addr || true
    echo
    echo "=== ip route ==="
    ip route || true
    echo
    echo "=== sysctl forwarding ==="
    sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null || true
    echo
    echo "=== UFW status verbose ==="
    ufw status verbose || true
    echo
    echo "=== UFW status numbered ==="
    ufw status numbered || true
    echo
    echo "=== UFW show added ==="
    ufw show added || true
    echo
    echo "=== Listeners for expected zone/Kubernetes ports ==="
    ss -lntup 2>/dev/null | awk 'NR==1 || /:(22|80|443|2049|3260|6443|9345|2379|2380|2381|10250|10256|10257|10259|9098|9099|4240|5473)\b/' || true
    echo
    echo "=== Docker containers and published ports ==="
    if command -v docker >/dev/null 2>&1; then
      docker ps --format 'container={{.Names}} image={{.Image}} ports={{.Ports}}' 2>/dev/null || true
      echo
      echo "=== Docker networks ==="
      docker network ls 2>/dev/null || true
      echo
      echo "=== Docker network inspect summaries ==="
      docker network ls -q 2>/dev/null | while read -r net; do
        docker network inspect "$net" --format 'name={{.Name}} id={{.Id}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}} {{end}} bridge={{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true
      done
    else
      echo "docker command not found"
    fi
    echo
    echo "=== iptables DOCKER-USER ==="
    iptables -S DOCKER-USER 2>/dev/null || true
    echo
    echo "=== iptables UFW-ZONE-DOCKER ==="
    iptables -S UFW-ZONE-DOCKER 2>/dev/null || true
    echo
    echo "=== UFW log location hints ==="
    echo "UFW traffic logs are commonly written to /var/log/ufw.log and/or journalctl -k, depending on rsyslog/journald config."
    echo "Script action log: $LOG_FILE"
    echo "Docker guard log: $LOG_ROOT/docker-guard.log"
    echo "Docker guard drop packet prefix: UFWZ DOCKER DROP"
    echo
    echo "=== Zone expectations ==="
    echo "domain_zone should include TCP/22, TCP/80, TCP/443 inbound on each domain interface."
    echo "storage_zone should include TCP/2049 and TCP/3260 inbound on each storage interface; optional UDP/2049 and legacy NFS ports only if selected."
    echo "restricted_zone should include TCP/443 inbound only on each restricted interface."
    echo "For Docker/Harbor, host TCP/443 may DNAT to container TCP/8443; selected ingress NICs are allowed to configured Docker destination ports only."
    echo "For Kubernetes/RKE2, selected NICs should include only the chosen profile/CNI/NodePort/custom ports, preferably restricted to node/admin CIDRs."
  } > "$report"

  echo "$report"
}

main() {
  need_root
  init_logging
  need_cmd ip
  need_cmd ufw
  need_cmd sysctl
  need_cmd awk
  need_cmd sed
  need_cmd ss
  need_cmd iptables

  echo "=== UFW Interface Zone Setup ==="
  echo "Version: $SCRIPT_VERSION"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"

  discover_interfaces
  print_interfaces
  print_docker_context

  echo
  echo "Assign zones by entering the interface menu number. Multiple interfaces can be entered as space-separated or comma-separated values."
  echo "Example: enter '1' for a single NIC or '1,2' for two NICs. Leave blank to skip a zone."
  echo

  local domain_input storage_input restricted_input
  local domain_ifaces=()
  local storage_ifaces=()
  local restricted_ifaces=()

  domain_input="$(read_iface_selection domain_zone '1) Enter interface number(s) for domain_zone [SSH/HTTP/HTTPS + optional domain services], blank to skip: ')"
  domain_ifaces=($domain_input)

  storage_input="$(read_iface_selection storage_zone '2) Enter interface number(s) for storage_zone [NFS/iSCSI only], blank to skip: ' "${domain_ifaces[@]}")"
  storage_ifaces=($storage_input)

  restricted_input="$(read_iface_selection restricted_zone '3) Enter interface number(s) for restricted_zone [HTTPS inbound only], blank to skip: ' "${domain_ifaces[@]}" "${storage_ifaces[@]}")"
  restricted_ifaces=($restricted_input)

  validate_no_overlap "${domain_ifaces[@]}" "${storage_ifaces[@]}" "${restricted_ifaces[@]}"

  DOMAIN_IFACES_GLOBAL=("${domain_ifaces[@]}")
  STORAGE_IFACES_GLOBAL=("${storage_ifaces[@]}")
  RESTRICTED_IFACES_GLOBAL=("${restricted_ifaces[@]}")

  if [[ ${#restricted_ifaces[@]} -eq 0 && ${#storage_ifaces[@]} -eq 0 && ${#domain_ifaces[@]} -eq 0 ]]; then
    echo "ERROR: No interfaces were assigned. Nothing to do." >&2
    exit 1
  fi

  echo
  echo "Storage-zone source restriction is strongly recommended."
  read -r -p "Enter storage peer CIDR(s), space-separated, or blank for any source on storage NIC: " storage_sources_raw
  log "Storage peer CIDR input: '${storage_sources_raw:-blank}'"
  local storage_sources
  storage_sources="$(parse_cidrs "$storage_sources_raw")"

  echo
  echo "SSH source restriction is strongly recommended."
  read -r -p "Enter trusted SSH source CIDR(s), space-separated, or blank for any source on domain NIC: " ssh_sources_raw
  log "SSH source CIDR input: '${ssh_sources_raw:-blank}'"
  local ssh_sources
  ssh_sources="$(parse_cidrs "$ssh_sources_raw")"

  local nfs_udp="no"
  local legacy_nfs="no"
  if [[ ${#storage_ifaces[@]} -gt 0 ]]; then
    if yes_no "Allow NFS UDP/2049 on storage_zone? TCP-only NFSv4 is the better baseline." "N"; then
      nfs_udp="yes"
    fi
    if yes_no "Add legacy NFSv3/rpcbind/mountd pinned ports on storage_zone? Only use if your NFS server is configured with fixed ports." "N"; then
      legacy_nfs="yes"
    fi
  fi

  local domain_profile="member"
  if [[ ${#domain_ifaces[@]} -gt 0 ]]; then
    if yes_no "Is this host acting as an AD Domain Controller or Samba AD DC and needs inbound domain-service ports?" "N"; then
      domain_profile="dc"
    fi
  fi

  # Kubernetes/RKE2 support.
  local k8s_mode="no"
  local k8s_ifaces=()
  local k8s_input=""
  local k8s_sources_raw=""
  local k8s_sources=""
  local k8s_profile=""
  local k8s_cni_profile=""
  local k8s_nodeports="no"
  local k8s_custom_raw=""
  local k8s_custom=""
  local all_assigned_ifaces=("${domain_ifaces[@]}" "${storage_ifaces[@]}" "${restricted_ifaces[@]}")

  echo
  if yes_no "Add Kubernetes/RKE2 port profile rules on selected NICs?" "N"; then
    k8s_mode="yes"
    echo "Select the physical NIC(s) that should accept Kubernetes/RKE2 traffic. Usually this is the cluster/private domain NIC, not storage or public restricted."
    k8s_input="$(read_iface_selection_from_allowed_list kubernetes_rke2 'Enter interface number(s) for Kubernetes/RKE2 inbound rules, blank to cancel Kubernetes rules: ' "${all_assigned_ifaces[@]}")"
    k8s_ifaces=($k8s_input)
    if [[ ${#k8s_ifaces[@]} -eq 0 ]]; then
      echo "ERROR: Kubernetes/RKE2 support was enabled but no interface was selected." >&2
      exit 1
    fi

    echo
    echo "Kubernetes/RKE2 source restriction is not optional in spirit. Use node/admin CIDRs where possible."
    read -r -p "Enter Kubernetes node/admin source CIDR(s), space-separated, or blank for any source on selected NIC(s): " k8s_sources_raw
    log "Kubernetes/RKE2 source CIDR input: '${k8s_sources_raw:-blank}'"
    k8s_sources="$(parse_cidrs "$k8s_sources_raw")"

    k8s_profile="$(read_k8s_profile)"
    k8s_cni_profile="$(read_k8s_cni_profile)"

    if [[ "$k8s_profile" != "nodeport-only" ]]; then
      if yes_no "Allow Kubernetes NodePort TCP/UDP range 30000:32767 on selected NIC(s)? Only do this if this node exposes NodePort services." "N"; then
        k8s_nodeports="yes"
      fi
    else
      k8s_nodeports="yes"
    fi

    read -r -p "Enter additional Kubernetes custom ports as proto/port specs, e.g. tcp/6443 udp/8472 tcp/30000:32767, or blank for none: " k8s_custom_raw
    k8s_custom_raw="$(trim "$k8s_custom_raw")"
    log "Kubernetes/RKE2 custom port specs input: '${k8s_custom_raw:-blank}'"
    k8s_custom="$(parse_proto_port_specs "$k8s_custom_raw")"
  fi

  # Docker/Harbor support.
  local docker_mode="no"
  local docker_guard="no"
  local docker_cidrs_raw=""
  local docker_ports_raw=""
  local docker_cidrs=""
  local docker_ports=""
  local docker_allowed_input=""
  local docker_allowed_ifaces=()
  local docker_blocked_ifaces=()
  local docker_eligible_ifaces=()

  docker_eligible_ifaces=("${domain_ifaces[@]}" "${restricted_ifaces[@]}")

  echo
  if docker_daemon_running; then
    echo "Docker is running. If Harbor or another container publishes host TCP/443, enable Docker/Harbor forwarding."
    echo "You will choose which domain_zone and/or restricted_zone Ethernet interfaces may forward to Docker bridge subnets/ports."

    local docker_default="N"
    if docker_publishes_443; then
      echo "Docker appears to have TCP/443 published. Harbor-style forwarding should be enabled for the correct ingress NIC."
      docker_default="Y"
    fi

    if [[ ${#docker_eligible_ifaces[@]} -eq 0 ]]; then
      echo "Docker is running, but no domain_zone or restricted_zone interface was assigned. Docker forwarding will not be configured."
    elif yes_no "Enable Docker/Harbor published-port support?" "$docker_default"; then
      docker_mode="yes"
      docker_allowed_input="$(read_iface_selection_from_allowed_list docker_forwarding 'Enter interface number(s) allowed to forward to Docker bridge subnets/ports, blank to disable: ' "${docker_eligible_ifaces[@]}")"
      docker_allowed_ifaces=($docker_allowed_input)

      if [[ ${#docker_allowed_ifaces[@]} -eq 0 ]]; then
        echo "ERROR: Docker/Harbor support was enabled but no forwarding interface was selected." >&2
        exit 1
      fi

      local suggested_cidrs
      suggested_cidrs="$(default_docker_cidrs | paste -sd ' ' -)"
      if [[ -n "$suggested_cidrs" ]]; then
        echo "Detected Docker CIDR candidate(s): $suggested_cidrs"
      fi
      read -r -p "Enter Docker destination CIDR(s), or press Enter to use detected candidate(s): " docker_cidrs_raw
      docker_cidrs_raw="$(trim "$docker_cidrs_raw")"
      if [[ -z "$docker_cidrs_raw" ]]; then
        docker_cidrs_raw="$suggested_cidrs"
      fi
      if [[ -z "$docker_cidrs_raw" ]]; then
        echo "ERROR: Docker/Harbor support requires at least one Docker destination CIDR, e.g. 172.17.0.0/16 or 172.18.0.0/16." >&2
        exit 1
      fi
      log "Docker destination CIDR input: $docker_cidrs_raw"
      docker_cidrs="$(parse_cidrs "$docker_cidrs_raw")"

      echo "For Harbor, keep 8443. Include 443 too if the container listens directly on 443."
      read -r -p "Enter Docker destination TCP port(s), comma/space-separated [default: 80,443,8080,8443]: " docker_ports_raw
      docker_ports_raw="$(trim "$docker_ports_raw")"
      [[ -z "$docker_ports_raw" ]] && docker_ports_raw="80,443,8080,8443"
      log "Docker destination port input: $docker_ports_raw"
      docker_ports="$(parse_ports "$docker_ports_raw")"

      local ziface
      for ziface in "${domain_ifaces[@]}" "${restricted_ifaces[@]}" "${storage_ifaces[@]}"; do
        [[ -z "$ziface" ]] && continue
        if ! array_contains "$ziface" "${docker_allowed_ifaces[@]}"; then
          docker_blocked_ifaces+=("$ziface")
        fi
      done

      if yes_no "Install persistent DOCKER-USER guard to block storage/non-selected zones from Docker container CIDRs?" "Y"; then
        docker_guard="yes"
      fi
    fi
  else
    echo "Docker is not running or is not reachable. Docker/Harbor forwarding will not be configured by default."
    if [[ ${#docker_eligible_ifaces[@]} -gt 0 ]] && yes_no "Configure Docker/Harbor forwarding manually anyway? Only use this if Docker will run later with bridge networks." "N"; then
      docker_mode="yes"
      docker_allowed_input="$(read_iface_selection_from_allowed_list docker_forwarding 'Enter interface number(s) allowed to forward to Docker bridge subnets/ports, blank to disable: ' "${docker_eligible_ifaces[@]}")"
      docker_allowed_ifaces=($docker_allowed_input)
      if [[ ${#docker_allowed_ifaces[@]} -eq 0 ]]; then
        echo "ERROR: Docker/Harbor support was enabled but no forwarding interface was selected." >&2
        exit 1
      fi
      read -r -p "Enter Docker destination CIDR(s), e.g. 172.17.0.0/16 or 172.18.0.0/16: " docker_cidrs_raw
      docker_cidrs_raw="$(trim "$docker_cidrs_raw")"
      if [[ -z "$docker_cidrs_raw" ]]; then
        echo "ERROR: Manual Docker/Harbor support requires at least one Docker destination CIDR." >&2
        exit 1
      fi
      log "Docker destination CIDR input: $docker_cidrs_raw"
      docker_cidrs="$(parse_cidrs "$docker_cidrs_raw")"

      read -r -p "Enter Docker destination TCP port(s), comma/space-separated [default: 80,443,8080,8443]: " docker_ports_raw
      docker_ports_raw="$(trim "$docker_ports_raw")"
      [[ -z "$docker_ports_raw" ]] && docker_ports_raw="80,443,8080,8443"
      log "Docker destination port input: $docker_ports_raw"
      docker_ports="$(parse_ports "$docker_ports_raw")"

      local ziface
      for ziface in "${domain_ifaces[@]}" "${restricted_ifaces[@]}" "${storage_ifaces[@]}"; do
        [[ -z "$ziface" ]] && continue
        if ! array_contains "$ziface" "${docker_allowed_ifaces[@]}"; then
          docker_blocked_ifaces+=("$ziface")
        fi
      done

      if yes_no "Install persistent DOCKER-USER guard to block storage/non-selected zones from Docker container CIDRs?" "Y"; then
        docker_guard="yes"
      fi
    fi
  fi

  local docker_allowed_summary docker_blocked_summary k8s_ifaces_summary forwarding_required forwarding_reason
  docker_allowed_summary="$(join_by_space "${docker_allowed_ifaces[@]:-}")"
  docker_blocked_summary="$(join_by_space "${docker_blocked_ifaces[@]:-}")"
  k8s_ifaces_summary="$(join_by_space "${k8s_ifaces[@]:-}")"

  forwarding_required="no"
  forwarding_reason="none"
  if [[ "$docker_mode" == "yes" && "$k8s_mode" == "yes" ]]; then
    forwarding_required="yes"
    forwarding_reason="Docker/Harbor published-port forwarding and Kubernetes/RKE2 networking"
  elif [[ "$docker_mode" == "yes" ]]; then
    forwarding_required="yes"
    forwarding_reason="Docker/Harbor published-port forwarding"
  elif [[ "$k8s_mode" == "yes" ]]; then
    forwarding_required="yes"
    forwarding_reason="Kubernetes/RKE2 networking"
  fi

  show_summary "$domain_input" "$storage_input" "$restricted_input" "$storage_sources_raw" "$ssh_sources_raw" "$domain_profile" "$nfs_udp" "$legacy_nfs" "$docker_mode" "$docker_allowed_summary" "$docker_blocked_summary" "$docker_cidrs_raw" "$docker_ports_raw" "$docker_guard" "$k8s_mode" "$k8s_ifaces_summary" "$k8s_sources_raw" "$k8s_profile" "$k8s_cni_profile" "$k8s_nodeports" "$k8s_custom_raw"

  if ! yes_no "Apply this firewall configuration now?" "N"; then
    echo "No changes applied. Action log saved at: $LOG_FILE"
    exit 0
  fi

  local backup_dir
  backup_dir="$(backup_current_config)"

  echo "Applying kernel/network hardening..."
  apply_sysctl_hardening "$forwarding_required" "$forwarding_reason"

  echo "Configuring UFW defaults..."
  configure_ufw_defaults

  echo "Applying domain_zone rules..."
  apply_domain_zone "$ssh_sources" "$domain_profile" "${domain_ifaces[@]}"

  echo "Applying storage_zone rules..."
  apply_storage_zone "$storage_sources" "$nfs_udp" "$legacy_nfs" "${storage_ifaces[@]}"

  echo "Applying restricted_zone rules..."
  apply_restricted_zone "${restricted_ifaces[@]}"

  if [[ "$k8s_mode" == "yes" ]]; then
    echo "Applying Kubernetes/RKE2 rules on selected interfaces..."
    apply_kubernetes_rules "$k8s_sources" "$k8s_profile" "$k8s_cni_profile" "$k8s_nodeports" "$k8s_custom" "${k8s_ifaces[@]}"
  fi

  if [[ "$docker_mode" == "yes" ]]; then
    echo "Applying routed/container Docker/Harbor web rules for selected domain/restricted interfaces..."
    apply_forwarded_docker_web_rules "$docker_cidrs" "$docker_ports" "${docker_allowed_ifaces[@]}"
  fi

  echo "Applying explicit inter-zone routed traffic denies..."
  local all_zone_ifaces=("${domain_ifaces[@]}" "${storage_ifaces[@]}" "${restricted_ifaces[@]}")
  apply_interzone_route_denies "${all_zone_ifaces[@]}"

  echo "Enabling UFW..."
  run_cmd ufw --force enable
  run_cmd ufw reload

  if [[ "$docker_mode" == "yes" && "$docker_guard" == "yes" ]]; then
    install_docker_guard "$docker_allowed_summary" "$docker_blocked_summary" "$docker_cidrs" "$docker_ports"
  fi

  echo
  echo "=== Final UFW status ==="
  ufw status verbose
  echo
  echo "Rule numbers:"
  ufw status numbered

  local audit_report
  audit_report="$(write_audit_report "$backup_dir" "$domain_input" "$storage_input" "$restricted_input" "$docker_mode" "$docker_allowed_summary" "$docker_blocked_summary" "$docker_cidrs_raw" "$docker_ports_raw" "$k8s_mode" "$k8s_ifaces_summary" "$k8s_sources_raw" "$k8s_profile" "$k8s_cni_profile" "$k8s_nodeports" "$k8s_custom_raw")"

  echo
  echo "Backup saved at: $backup_dir"
  echo "Audit report saved at: $audit_report"
  echo "Action log saved at: $LOG_FILE"
  if [[ "$docker_guard" == "yes" ]]; then
    echo "Docker guard log: $LOG_ROOT/docker-guard.log"
  fi
  echo "Done. Validate from each network before closing your admin session."
}

main "$@"
