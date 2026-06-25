#!/usr/bin/env bash
# setup-ufw-zones-v8.sh
#
# Purpose:
#   Configure UFW as interface-scoped firewall "zones" on a multi-NIC Ubuntu/Debian host.
#   Uses zone + workload profiles so an operator can apply the right exposure model to each NIC.
#
# Critical UX note:
#   Functions that return values through command substitution must print menus to stderr. Otherwise
#   the menu text is swallowed into variables and the operator only sees a bare prompt.
#
# Zones:
#   domain_zone:     trusted/admin LAN; SSH and optional HTTP/HTTPS/domain-service ingress.
#   storage_zone:    backend storage LAN; NFS/iSCSI only from explicit storage peers.
#   restricted_zone: service/DMZ-facing LAN; only declared ingress/VIP ports.
#
# Workload profiles:
#   RKE2-Server       multi-node RKE2 server/controller/etcd node
#   RKE2-Agent        multi-node RKE2 agent/worker node
#   RKE2-SingleNode   single-node RKE2 cluster; no Istio overlay prompt by default
#   Harbor-Docker     Harbor or other Docker-published HTTPS service
#   Custom-Ingress    explicit TCP/UDP ingress ports to node IPs and/or Kubernetes VIPs
#
# Kubernetes ingress VIP note:
#   In this script, "Kubernetes ingress VIP" means the destination IP/CIDR used by a Kubernetes Service,
#   LoadBalancer implementation, MetalLB pool, Gateway, or similar virtual IP. This is different from
#   the client/source CIDR that is allowed to reach it.
#
# Tested syntax target: Bash 4+, UFW 0.36+

set -euo pipefail

SCRIPT_VERSION="2026-06-25-v8-choice-reference-menu-fix"
BACKUP_ROOT="/root/ufw-zone-backups"
LOG_ROOT="/var/log/ufw-zone-setup"
SYSCTL_DROPIN="/etc/sysctl.d/99-ufw-zone-hardening.conf"
DOCKER_GUARD_SCRIPT="/usr/local/sbin/ufw-zone-docker-guard.sh"
DOCKER_GUARD_ENV="/etc/default/ufw-zone-docker-guard"
DOCKER_GUARD_SERVICE="/etc/systemd/system/ufw-zone-docker-guard.service"

DETECTED_IFACES=()
ASSIGNED_IFACES=()
DOMAIN_IFACES=()
STORAGE_IFACES=()
RESTRICTED_IFACES=()
K8S_IFACES=()
HARBOR_IFACES=()
CUSTOM_INGRESS_IFACES=()

LOG_FILE=""

declare -A IFACE_ZONE=()
declare -A IFACE_PROFILES=()

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
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "=== UFW Zone/Profile Setup Action Log ==="
  echo "Version: $SCRIPT_VERSION"
  echo "Date: $(date -Is)"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
  echo "Log file: $LOG_FILE"
  echo
}

log() { echo "[$(date -Is)] $*" >&2; }
run_cmd() { log "+ $*"; "$@"; }

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
  local prompt="$1" default="${2:-N}" reply suffix
  if [[ "$default" =~ ^[Yy]$ ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  while true; do
    read -r -p "$prompt $suffix: " reply
    reply="$(trim "$reply")"
    [[ -z "$reply" ]] && reply="$default"
    case "$reply" in
      y|Y|yes|YES|Yes) log "Prompt accepted yes: $prompt"; return 0 ;;
      n|N|no|NO|No) log "Prompt accepted no: $prompt"; return 1 ;;
      *) echo "Please answer y or n." >&2 ;;
    esac
  done
}

array_contains() {
  local needle="$1" item
  shift || true
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

append_unique() {
  local arr_name="$1" value="$2"
  [[ -z "$value" ]] && return 0
  eval "local current=(\"\${${arr_name}[@]:-}\")"
  if ! array_contains "$value" "${current[@]}"; then
    eval "${arr_name}+=(\"\$value\")"
  fi
}

join_by_space() { local IFS=' '; echo "$*"; }
normalize_list() { local input="$1"; input="${input//,/ }"; echo "$input"; }

print_choice_reference() {
  cat <<'EOF'
=== Choice Reference ===
Zones:
  0) Unassigned      - no UFW rules for this interface
  1) domain_zone     - trusted admin/LAN; primary place for SSH and admin access
  2) storage_zone    - backend NFS/iSCSI only; keep boring and narrow
  3) restricted_zone - service/DMZ/VIP ingress only; no broad admin/K8s internals

Workload profiles:
  0) Zone base only  - apply only the selected zone baseline
  1) RKE2-Server     - controller/server/etcd node: 6443, 9345, 2379, 2380, 2381, 10250
  2) RKE2-Agent      - worker/agent node: 10250 plus selected CNI overlay ports
  3) RKE2-SingleNode - single-node cluster: 6443 plus selected CNI; skips Istio prompt by default
  4) Harbor-Docker   - Docker-published Harbor/service; HTTPS plus Docker bridge forwarding guard
  5) Custom-Ingress  - explicit tcp/udp service ports, optionally scoped to Kubernetes VIP destinations

Domain-zone base profiles:
  1) SSH only
  2) SSH + HTTP/HTTPS
  3) SSH + HTTP/HTTPS + AD/DC/Samba domain-service ports

Kubernetes/RKE2 CNI choices:
  0) None
  1) RKE2 Canal VXLAN        - UDP 8472, TCP 9099
  2) RKE2 Canal + WireGuard  - UDP 8472/51820/51821, TCP 9099
  3) Calico BGP             - TCP 179/5473/9098/9099
  4) Calico VXLAN           - UDP 4789, TCP 5473/9098/9099
  5) Flannel VXLAN          - UDP 4789
  6) Cilium VXLAN/WireGuard - TCP 4240, UDP 8472/51871
  7) Custom CNI ports only

Istio choices, only offered for RKE2-Server or RKE2-Agent:
  0) None
  1) Sidecar/control-plane common: 15001,15006,15008,15020,15021,15090,443,15010,15012,15014,15017
  2) Gateway/east-west only: 15021,15443
  3) Both 1 and 2

Prompt semantics:
  - Source CIDR/IP: who may connect, for example 172.16.15.0/24 or 10.0.4.10/32.
  - Kubernetes ingress VIP: destination IP/CIDR owned by LoadBalancer/MetalLB/Gateway/Service.
  - Ports: use tcp/443, udp/15443, or ranges like tcp/30000:32767.
  - Multiple choices can use commas or spaces, for example: 1,5 or 1 5.
EOF
  echo
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
    echo "ERROR: No usable physical/primary ethernet interfaces were detected." >&2
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

zone_label_for_choice() {
  case "$1" in
    0) echo "unassigned" ;;
    1) echo "domain_zone" ;;
    2) echo "storage_zone" ;;
    3) echo "restricted_zone" ;;
    *) echo "invalid" ;;
  esac
}

profile_label_for_choice() {
  case "$1" in
    0) echo "zone-base" ;;
    1) echo "rke2-server" ;;
    2) echo "rke2-agent" ;;
    3) echo "rke2-singlenode" ;;
    4) echo "harbor-docker" ;;
    5) echo "custom-ingress" ;;
    *) echo "invalid" ;;
  esac
}

read_zone_for_iface() {
  local iface="$1" choice zone
  while true; do
    {
      echo
      echo "Select firewall zone for interface: $iface"
      echo "  0) Unassigned / no rules"
      echo "  1) domain_zone     - trusted admin/LAN"
      echo "  2) storage_zone    - backend NFS/iSCSI"
      echo "  3) restricted_zone - service/DMZ/VIP ingress"
    } >&2
    read -r -p "Zone choice [0-3]: " choice
    choice="$(trim "$choice")"
    [[ -z "$choice" ]] && choice="0"
    log "Zone selection for $iface: ${choice:-blank}"
    zone="$(zone_label_for_choice "$choice")"
    if [[ "$zone" != "invalid" ]]; then echo "$zone"; return 0; fi
    echo "ERROR: Enter 0, 1, 2, or 3." >&2
  done
}

validate_profile_for_zone() {
  local zone="$1" profile="$2"
  case "$profile" in
    zone-base)
      return 0 ;;
    rke2-server|rke2-agent|rke2-singlenode)
      if [[ "$zone" == "restricted_zone" ]]; then
        echo "WARNING: Applying $profile to restricted_zone exposes Kubernetes internals on a service/DMZ NIC." >&2
        yes_no "Continue anyway?" "N" || return 1
      elif [[ "$zone" == "storage_zone" ]]; then
        echo "WARNING: Applying $profile to storage_zone mixes Kubernetes control/node traffic with storage traffic." >&2
        yes_no "Continue anyway?" "N" || return 1
      fi
      return 0 ;;
    harbor-docker)
      if [[ "$zone" == "storage_zone" ]]; then
        echo "ERROR: Harbor-Docker profile is not allowed on storage_zone. Pick domain_zone or restricted_zone." >&2
        return 1
      fi
      return 0 ;;
    custom-ingress)
      if [[ "$zone" == "storage_zone" ]]; then
        echo "WARNING: Custom ingress on storage_zone is usually a footprint problem." >&2
        yes_no "Continue anyway?" "N" || return 1
      fi
      return 0 ;;
    *) return 1 ;;
  esac
}

read_profiles_for_iface() {
  local iface="$1" zone="$2" input normalized token profile
  while true; do
    {
      echo
      echo "Select workload profile(s) for $iface ($zone). Use comma/space-separated numbers."
      echo "  0) Zone base only"
      echo "  1) RKE2-Server      - controller/server/etcd"
      echo "  2) RKE2-Agent       - worker/agent"
      echo "  3) RKE2-SingleNode  - single-node cluster; no Istio overlay prompt by default"
      echo "  4) Harbor-Docker    - Docker-published Harbor/service"
      echo "  5) Custom-Ingress   - explicit TCP/UDP service ports, optionally scoped to K8s VIPs"
    } >&2
    read -r -p "Profile choice(s) [default: 0]: " input
    input="$(trim "$input")"
    [[ -z "$input" ]] && input="0"
    normalized="$(normalize_list "$input")"
    log "Profile selection for $iface: $normalized"

    local ok=1 selected=() seen=" "
    for token in $normalized; do
      if [[ ! "$token" =~ ^[0-5]$ ]]; then
        echo "ERROR: '$token' is invalid. Enter values from 0 to 5." >&2
        ok=0; break
      fi
      profile="$(profile_label_for_choice "$token")"
      if [[ "$seen" == *" $profile "* ]]; then
        echo "ERROR: Profile '$profile' was selected more than once." >&2
        ok=0; break
      fi
      if [[ "$profile" == "zone-base" && "$normalized" != "0" ]]; then
        echo "ERROR: Do not combine 0/zone-base with other profiles." >&2
        ok=0; break
      fi
      if ! validate_profile_for_zone "$zone" "$profile"; then
        ok=0; break
      fi
      selected+=("$profile")
      seen+="$profile "
    done
    if [[ "$ok" -eq 1 ]]; then printf '%s\n' "${selected[*]}"; return 0; fi
  done
}

parse_cidrs() {
  local input="$1" cidrs=() cidr octets octet prefix
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="$(normalize_list "$input")"
  for cidr in $input; do
    if [[ "$cidr" == "any" ]]; then cidrs+=("any"); continue; fi
    if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
      local ip="${cidr%%/*}"
      prefix=""
      [[ "$cidr" == */* ]] && prefix="${cidr##*/}"
      IFS='.' read -r -a octets <<< "$ip"
      for octet in "${octets[@]}"; do
        if (( octet < 0 || octet > 255 )); then echo "ERROR: '$cidr' has an invalid IPv4 octet." >&2; exit 1; fi
      done
      if [[ -n "$prefix" ]] && (( prefix < 0 || prefix > 32 )); then echo "ERROR: '$cidr' has an invalid IPv4 CIDR prefix." >&2; exit 1; fi
      cidrs+=("$cidr")
    elif [[ "$cidr" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
      cidrs+=("$cidr")
    else
      echo "ERROR: '$cidr' does not look like an IPv4/IPv6 address or CIDR." >&2
      exit 1
    fi
  done
  if array_contains "any" "${cidrs[@]}" && [[ "${#cidrs[@]}" -gt 1 ]]; then
    echo "ERROR: Do not combine 'any' with specific CIDRs." >&2
    exit 1
  fi
  printf '%s\n' "${cidrs[@]}"
}

validate_port_or_range() {
  local p="$1" a b
  if [[ "$p" =~ ^[0-9]+$ ]]; then (( p >= 1 && p <= 65535 )) || return 1; return 0; fi
  if [[ "$p" =~ ^[0-9]+:[0-9]+$ ]]; then
    a="${p%%:*}"; b="${p##*:}"
    (( a >= 1 && a <= 65535 && b >= 1 && b <= 65535 && a <= b )) || return 1
    return 0
  fi
  return 1
}

parse_ports() {
  local input="$1" ports=() p
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="$(normalize_list "$input")"
  for p in $input; do
    if ! validate_port_or_range "$p"; then echo "ERROR: '$p' is not a valid TCP/UDP port or range. Use 443 or 30000:32767." >&2; exit 1; fi
    ports+=("$p")
  done
  printf '%s\n' "${ports[@]}"
}

parse_proto_port_specs() {
  local input="$1" specs=() item proto port
  input="$(trim "$input")"
  [[ -z "$input" ]] && return 0
  input="$(normalize_list "$input")"
  for item in $input; do
    if [[ ! "$item" =~ ^(tcp|udp)/[0-9]+(:[0-9]+)?$ ]]; then
      echo "ERROR: '$item' is invalid. Use tcp/443, udp/15443, or tcp/30000:32767." >&2
      exit 1
    fi
    proto="${item%%/*}"; port="${item#*/}"
    if ! validate_port_or_range "$port"; then echo "ERROR: '$item' has an invalid port or range." >&2; exit 1; fi
    specs+=("$proto/$port")
  done
  printf '%s\n' "${specs[@]}"
}

prompt_cidrs() {
  local prompt="$1" default="${2:-}" raw
  read -r -p "$prompt" raw
  raw="$(trim "$raw")"
  [[ -z "$raw" && -n "$default" ]] && raw="$default"
  log "CIDR input for prompt '$prompt': '${raw:-blank}'"
  parse_cidrs "$raw"
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
  local forwarding_required="$1" reason="$2" ipv4_forward_value="0" forwarding_comment="Do not route traffic between interfaces/zones."
  if [[ "$forwarding_required" == "yes" ]]; then
    ipv4_forward_value="1"
    forwarding_comment="IPv4 forwarding required for: $reason. UFW routed default-deny and explicit guard rules preserve segmentation."
  fi
  log "Writing sysctl hardening drop-in: $SYSCTL_DROPIN"
  cat > "$SYSCTL_DROPIN" <<SYSCTL_EOF
# Created by setup-ufw-zones-v8.sh
# Multi-NIC firewall hardening.

# $forwarding_comment
net.ipv4.ip_forward = $ipv4_forward_value
net.ipv6.conf.all.forwarding = 0

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
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
SYSCTL_EOF
  run_cmd sysctl --system
}

configure_ufw_defaults() {
  log "Configuring UFW defaults"
  run_cmd sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw
  if grep -q '^IPV6=' /etc/default/ufw; then run_cmd sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw; fi
  run_cmd ufw --force reset
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw default deny routed
  run_cmd ufw logging high
}

normalize_endpoint_for_ufw() { local v="$1"; if [[ -z "$v" || "$v" == "any" ]]; then echo "any"; else echo "$v"; fi; }

ufw_allow_in_scoped() {
  local iface="$1" proto="$2" port="$3" comment="$4" sources_csv="$5" dests_csv="$6"
  local sources=() dests=() src dst ufw_src ufw_dst
  [[ -n "$sources_csv" ]] && mapfile -t sources < <(printf '%s\n' "$sources_csv" | sed '/^$/d')
  [[ -n "$dests_csv" ]] && mapfile -t dests < <(printf '%s\n' "$dests_csv" | sed '/^$/d')
  [[ "${#sources[@]}" -eq 0 ]] && sources=("any")
  [[ "${#dests[@]}" -eq 0 ]] && dests=("any")
  for src in "${sources[@]}"; do
    ufw_src="$(normalize_endpoint_for_ufw "$src")"
    for dst in "${dests[@]}"; do
      ufw_dst="$(normalize_endpoint_for_ufw "$dst")"
      run_cmd ufw allow in on "$iface" proto "$proto" from "$ufw_src" to "$ufw_dst" port "$port" comment "$comment src=$ufw_src dst=$ufw_dst"
    done
  done
}

ufw_route_allow_scoped() {
  local iface="$1" proto="$2" port="$3" comment="$4" sources_csv="$5" dests_csv="$6"
  local sources=() dests=() src dst ufw_src
  [[ -n "$sources_csv" ]] && mapfile -t sources < <(printf '%s\n' "$sources_csv" | sed '/^$/d')
  [[ -n "$dests_csv" ]] && mapfile -t dests < <(printf '%s\n' "$dests_csv" | sed '/^$/d')
  [[ "${#sources[@]}" -eq 0 ]] && sources=("any")
  [[ "${#dests[@]}" -eq 0 ]] && return 0
  for src in "${sources[@]}"; do
    ufw_src="$(normalize_endpoint_for_ufw "$src")"
    for dst in "${dests[@]}"; do
      [[ "$dst" == "any" ]] && continue
      run_cmd ufw route allow in on "$iface" proto "$proto" from "$ufw_src" to "$dst" port "$port" comment "$comment route src=$ufw_src dst=$dst"
    done
  done
}

apply_domain_zone_base() {
  local iface="$1" admin_sources="$2" domain_profile="$3"
  ufw_allow_in_scoped "$iface" tcp 22 "domain_zone SSH inbound" "$admin_sources" ""
  if [[ "$domain_profile" == "web" || "$domain_profile" == "dc" ]]; then
    ufw_allow_in_scoped "$iface" tcp 80 "domain_zone HTTP inbound" "$admin_sources" ""
    ufw_allow_in_scoped "$iface" tcp 443 "domain_zone HTTPS inbound" "$admin_sources" ""
  fi
  if [[ "$domain_profile" == "dc" ]]; then
    for spec in tcp/53 udp/53 tcp/88 udp/88 tcp/464 udp/464 tcp/389 udp/389 tcp/636 tcp/445 tcp/135 tcp/3268 tcp/3269 udp/123; do
      ufw_allow_in_scoped "$iface" "${spec%%/*}" "${spec#*/}" "domain_zone AD/DC service $spec inbound" "$admin_sources" ""
    done
    if yes_no "Add high dynamic RPC TCP range 49152:65535 for AD/DC compatibility on $iface? Wide range; trusted domain networks only." "N"; then
      ufw_allow_in_scoped "$iface" tcp 49152:65535 "domain_zone AD dynamic RPC high range inbound" "$admin_sources" ""
    fi
  fi
}

apply_storage_zone_base() {
  local iface="$1" storage_sources="$2" include_nfs_udp="$3" include_legacy_nfs="$4" p
  ufw_allow_in_scoped "$iface" tcp 2049 "storage_zone NFSv4 inbound" "$storage_sources" ""
  [[ "$include_nfs_udp" == "yes" ]] && ufw_allow_in_scoped "$iface" udp 2049 "storage_zone NFS UDP inbound" "$storage_sources" ""
  ufw_allow_in_scoped "$iface" tcp 3260 "storage_zone iSCSI target inbound" "$storage_sources" ""
  if [[ "$include_legacy_nfs" == "yes" ]]; then
    for p in 111 20048 662 875 892 32765 32766 32767 32768; do
      ufw_allow_in_scoped "$iface" tcp "$p" "storage_zone legacy NFSv3 pinned port $p inbound" "$storage_sources" ""
      ufw_allow_in_scoped "$iface" udp "$p" "storage_zone legacy NFSv3 pinned port $p inbound" "$storage_sources" ""
    done
  fi
}

apply_custom_ingress_rules() {
  local iface="$1" sources_csv="$2" vip_dests_csv="$3" proto_port_specs_csv="$4" route_vip="$5" spec proto port
  [[ -z "$proto_port_specs_csv" ]] && return 0
  while read -r spec; do
    [[ -z "$spec" ]] && continue
    proto="${spec%%/*}"; port="${spec#*/}"
    ufw_allow_in_scoped "$iface" "$proto" "$port" "custom/k8s ingress $proto/$port inbound" "$sources_csv" "$vip_dests_csv"
    [[ "$route_vip" == "yes" ]] && ufw_route_allow_scoped "$iface" "$proto" "$port" "custom/k8s ingress $proto/$port routed VIP" "$sources_csv" "$vip_dests_csv"
  done <<< "$proto_port_specs_csv"
}

apply_rke2_profile_rules() {
  local iface="$1" profile="$2" api_sources="$3" node_sources="$4"
  case "$profile" in
    rke2-server)
      ufw_allow_in_scoped "$iface" tcp 6443 "rke2-server Kubernetes API inbound" "$api_sources" ""
      for p in 9345 2379 2380 2381 10250; do ufw_allow_in_scoped "$iface" tcp "$p" "rke2-server node/internal port $p inbound" "$node_sources" ""; done ;;
    rke2-agent)
      ufw_allow_in_scoped "$iface" tcp 10250 "rke2-agent kubelet inbound" "$node_sources" "" ;;
    rke2-singlenode)
      ufw_allow_in_scoped "$iface" tcp 6443 "rke2-singlenode Kubernetes API inbound" "$api_sources" "" ;;
  esac
}

apply_cni_profile_rules() {
  local iface="$1" cni_profile="$2" node_sources="$3"
  case "$cni_profile" in
    none) : ;;
    canal-vxlan) for spec in udp/8472 tcp/9099; do ufw_allow_in_scoped "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal $spec inbound" "$node_sources" ""; done ;;
    canal-wireguard) for spec in udp/8472 udp/51820 udp/51821 tcp/9099; do ufw_allow_in_scoped "$iface" "${spec%%/*}" "${spec#*/}" "rke2 Canal/WireGuard $spec inbound" "$node_sources" ""; done ;;
    calico-bgp) for p in 179 5473 9098 9099; do ufw_allow_in_scoped "$iface" tcp "$p" "Calico BGP/Typha/health port $p inbound" "$node_sources" ""; done ;;
    calico-vxlan) ufw_allow_in_scoped "$iface" udp 4789 "Calico VXLAN inbound" "$node_sources" ""; for p in 5473 9098 9099; do ufw_allow_in_scoped "$iface" tcp "$p" "Calico Typha/health port $p inbound" "$node_sources" ""; done ;;
    flannel-vxlan) ufw_allow_in_scoped "$iface" udp 4789 "Flannel VXLAN inbound" "$node_sources" "" ;;
    cilium-vxlan-wireguard) ufw_allow_in_scoped "$iface" tcp 4240 "Cilium health inbound" "$node_sources" ""; for p in 8472 51871; do ufw_allow_in_scoped "$iface" udp "$p" "Cilium VXLAN/WireGuard port $p inbound" "$node_sources" ""; done ;;
    custom-cni) : ;;
    *) echo "ERROR: Unknown CNI profile: $cni_profile" >&2; exit 1 ;;
  esac
}

apply_nodeport_rules() {
  local iface="$1" nodeport_sources="$2"
  ufw_allow_in_scoped "$iface" tcp 30000:32767 "Kubernetes NodePort TCP range inbound" "$nodeport_sources" ""
  ufw_allow_in_scoped "$iface" udp 30000:32767 "Kubernetes NodePort UDP range inbound" "$nodeport_sources" ""
}

apply_istio_rules() {
  local iface="$1" istio_profile="$2" sources_csv="$3" p
  case "$istio_profile" in
    none) return 0 ;;
    sidecar-common)
      for p in 15001 15006 15008 15020 15021 15090 443 15010 15012 15014 15017; do
        ufw_allow_in_scoped "$iface" tcp "$p" "Istio sidecar/control-plane port $p inbound" "$sources_csv" ""
      done ;;
    gateway-eastwest)
      for p in 15021 15443; do ufw_allow_in_scoped "$iface" tcp "$p" "Istio gateway/east-west port $p inbound" "$sources_csv" ""; done ;;
    all-safe)
      apply_istio_rules "$iface" sidecar-common "$sources_csv"
      apply_istio_rules "$iface" gateway-eastwest "$sources_csv" ;;
    *) echo "ERROR: Unknown Istio profile: $istio_profile" >&2; exit 1 ;;
  esac
}

read_cni_profile() {
  local choice
  while true; do
    {
      echo
      echo "Kubernetes/RKE2 CNI profile:"
      echo "  0) None"
      echo "  1) RKE2 Canal VXLAN        - UDP 8472, TCP 9099"
      echo "  2) RKE2 Canal + WireGuard  - UDP 8472/51820/51821, TCP 9099"
      echo "  3) Calico BGP             - TCP 179/5473/9098/9099"
      echo "  4) Calico VXLAN           - UDP 4789, TCP 5473/9098/9099"
      echo "  5) Flannel VXLAN          - UDP 4789"
      echo "  6) Cilium VXLAN/WireGuard - TCP 4240, UDP 8472/51871"
      echo "  7) Custom CNI ports only"
    } >&2
    read -r -p "Select CNI profile [0-7]: " choice
    choice="$(trim "$choice")"; [[ -z "$choice" ]] && choice="0"
    log "CNI profile selection: $choice"
    case "$choice" in
      0) echo "none"; return 0 ;;
      1) echo "canal-vxlan"; return 0 ;;
      2) echo "canal-wireguard"; return 0 ;;
      3) echo "calico-bgp"; return 0 ;;
      4) echo "calico-vxlan"; return 0 ;;
      5) echo "flannel-vxlan"; return 0 ;;
      6) echo "cilium-vxlan-wireguard"; return 0 ;;
      7) echo "custom-cni"; return 0 ;;
      *) echo "ERROR: Enter 0 through 7." >&2 ;;
    esac
  done
}

read_istio_profile() {
  local choice
  while true; do
    {
      echo
      echo "Istio service mesh firewall profile:"
      echo "  0) None"
      echo "  1) Sidecar/control-plane common official ports"
      echo "     TCP: 15001,15006,15008,15020,15021,15090,443,15010,15012,15014,15017"
      echo "  2) Gateway/east-west only"
      echo "     TCP: 15021,15443"
      echo "  3) Both 1 and 2"
      echo "  - Single-node clusters are intentionally not prompted for this overlay."
    } >&2
    read -r -p "Select Istio profile [0-3]: " choice
    choice="$(trim "$choice")"; [[ -z "$choice" ]] && choice="0"
    log "Istio profile selection: $choice"
    case "$choice" in
      0) echo "none"; return 0 ;;
      1) echo "sidecar-common"; return 0 ;;
      2) echo "gateway-eastwest"; return 0 ;;
      3) echo "all-safe"; return 0 ;;
      *) echo "ERROR: Enter 0 through 3." >&2 ;;
    esac
  done
}

docker_available() { command -v docker >/dev/null 2>&1; }
docker_daemon_running() { docker_available || return 1; docker info >/dev/null 2>&1; }

print_docker_context() {
  echo
  echo "Docker context:"
  if ! docker_available; then echo "  docker command: not found"; return 0; fi
  if ! docker_daemon_running; then echo "  docker command: found"; echo "  docker daemon: not running or not reachable"; return 0; fi
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

apply_forwarded_docker_rules() {
  local dst_cidrs_csv="$1" dst_ports_csv="$2" sources_csv="$3"
  shift 3
  local ifaces=("$@") ports=() iface port
  [[ -z "$dst_cidrs_csv" || -z "$dst_ports_csv" || "${#ifaces[@]}" -eq 0 ]] && return 0
  mapfile -t ports < <(printf '%s\n' "$dst_ports_csv" | sed '/^$/d')
  for iface in "${ifaces[@]}"; do
    [[ -z "$iface" ]] && continue
    for port in "${ports[@]}"; do
      ufw_route_allow_scoped "$iface" tcp "$port" "Harbor/Docker routed TCP/$port to bridge CIDR" "$sources_csv" "$dst_cidrs_csv"
    done
  done
}

install_docker_guard() {
  local allowed_ifaces_csv="$1" blocked_ifaces_csv="$2" docker_cidrs_csv="$3" docker_ports_csv="$4"
  [[ -z "$docker_cidrs_csv" || -z "$docker_ports_csv" ]] && return 0
  log "Installing persistent Docker/Harbor DOCKER-USER guard"
  cat > "$DOCKER_GUARD_ENV" <<ENV_EOF
# Created by setup-ufw-zones-v8.sh
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
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
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
if ! command -v iptables >/dev/null 2>&1; then echo "iptables not found; skipping Docker guard."; exit 0; fi
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

apply_interzone_route_denies() {
  local ifaces=("$@") in_if out_if
  for in_if in "${ifaces[@]}"; do
    [[ -z "$in_if" ]] && continue
    for out_if in "${ifaces[@]}"; do
      [[ -z "$out_if" || "$in_if" == "$out_if" ]] && continue
      run_cmd ufw route deny in on "$in_if" out on "$out_if" comment "deny routed traffic $in_if to $out_if"
    done
  done
}

show_plan() {
  local admin_sources="$1" storage_sources="$2" restricted_sources="$3" vip_dests="$4" k8s_api_sources="$5" k8s_node_sources="$6" cni_profile="$7" nodeports="$8" istio_profile="$9" custom_ingress_specs="${10}" docker_cidrs="${11}" docker_ports="${12}" docker_guard="${13}"
  echo
  echo "=== Planned Firewall Configuration Summary ==="
  local iface
  for iface in "${ASSIGNED_IFACES[@]}"; do
    printf '  %-18s zone=%-16s profiles=%s\n' "$iface" "${IFACE_ZONE[$iface]}" "${IFACE_PROFILES[$iface]}"
  done
  echo
  printf '  Admin/source CIDR(s):              %s\n' "${admin_sources:-any}"
  printf '  Storage peer CIDR(s):              %s\n' "${storage_sources:-any}"
  printf '  Restricted/client source CIDR(s):  %s\n' "${restricted_sources:-any}"
  printf '  Kubernetes ingress VIP dest(s):    %s\n' "${vip_dests:-not configured}"
  printf '  Kubernetes API/admin source(s):    %s\n' "${k8s_api_sources:-not configured}"
  printf '  Kubernetes node/source CIDR(s):    %s\n' "${k8s_node_sources:-not configured}"
  printf '  Kubernetes CNI profile:            %s\n' "$cni_profile"
  printf '  Kubernetes NodePort range:         %s\n' "$nodeports"
  printf '  Istio profile:                     %s\n' "$istio_profile"
  printf '  Custom ingress ports:              %s\n' "${custom_ingress_specs:-none}"
  printf '  Harbor/Docker bridge CIDR(s):      %s\n' "${docker_cidrs:-not configured}"
  printf '  Harbor/Docker destination ports:   %s\n' "${docker_ports:-not configured}"
  printf '  Persistent Docker guard:           %s\n' "$docker_guard"
  echo
  echo "This will reset existing UFW rules, then enable UFW. Existing UFW/Docker firewall config will be backed up first."
  echo "All script output will be logged to: $LOG_FILE"
  echo
}

write_audit_report() {
  local backup_dir="$1" report="$backup_dir/ufw-zone-audit-after.txt"
  {
    echo "=== UFW Zone/Profile Audit ==="
    echo "Version: $SCRIPT_VERSION"
    echo "Date: $(date -Is)"
    echo "Host: $(hostname -f 2>/dev/null || hostname)"
    echo "Action log: $LOG_FILE"
    echo
    echo "Interface assignments:"
    local iface
    for iface in "${ASSIGNED_IFACES[@]}"; do echo "  $iface zone=${IFACE_ZONE[$iface]} profiles=${IFACE_PROFILES[$iface]}"; done
    echo
    echo "=== ip -br addr ==="; ip -br addr || true
    echo
    echo "=== ip route ==="; ip route || true
    echo
    echo "=== sysctl forwarding ==="; sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null || true
    echo
    echo "=== UFW status verbose ==="; ufw status verbose || true
    echo
    echo "=== UFW status numbered ==="; ufw status numbered || true
    echo
    echo "=== UFW show added ==="; ufw show added || true
    echo
    echo "=== Listeners for expected zone/Kubernetes/Istio ports ==="
    ss -lntup 2>/dev/null | awk 'NR==1 || /:(22|80|443|2049|3260|6443|9345|2379|2380|2381|10250|10256|10257|10259|8472|4789|51820|51821|9098|9099|4240|5473|15001|15006|15008|15010|15012|15014|15017|15020|15021|15090|15443)\b/' || true
    echo
    echo "=== Docker containers and published ports ==="
    if command -v docker >/dev/null 2>&1; then docker ps --format 'container={{.Names}} image={{.Image}} ports={{.Ports}}' 2>/dev/null || true; docker network ls 2>/dev/null || true; else echo "docker command not found"; fi
    echo
    echo "=== iptables DOCKER-USER ==="; iptables -S DOCKER-USER 2>/dev/null || true
    echo
    echo "=== Zone expectations ==="
    echo "domain_zone: admin ingress only; SSH should be source-restricted."
    echo "storage_zone: NFS/iSCSI only from storage peer CIDRs."
    echo "restricted_zone: declared ingress/VIP ports only. No etcd, kubelet, RKE2 supervisor, CNI, storage, or Docker bridge access by default."
    echo "Istio: only optional overlays selected with RKE2-Server/RKE2-Agent should appear; single-node profile skips Istio by default."
  } > "$report"
  echo "$report"
}

has_profile_anywhere() {
  local target="$1" iface
  for iface in "${ASSIGNED_IFACES[@]}"; do [[ " ${IFACE_PROFILES[$iface]} " == *" $target "* ]] && return 0; done
  return 1
}

has_multinode_k8s_profile() {
  local iface
  for iface in "${ASSIGNED_IFACES[@]}"; do
    if [[ " ${IFACE_PROFILES[$iface]} " == *" rke2-server "* || " ${IFACE_PROFILES[$iface]} " == *" rke2-agent "* ]]; then return 0; fi
  done
  return 1
}

main() {
  need_root
  init_logging
  need_cmd ip; need_cmd ufw; need_cmd sysctl; need_cmd awk; need_cmd sed; need_cmd ss; need_cmd iptables

  echo "=== UFW Interface Zone/Profile Setup ==="
  echo "Version: $SCRIPT_VERSION"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"

  discover_interfaces
  print_choice_reference
  print_interfaces
  print_docker_context

  echo
  echo "Assign each physical interface to a firewall zone, then apply workload profiles."
  echo "Use domain_zone for most admin access. Keep storage_zone and restricted_zone deliberately narrow."
  echo

  local iface zone profiles profile
  for iface in "${DETECTED_IFACES[@]}"; do
    zone="$(read_zone_for_iface "$iface")"
    IFACE_ZONE["$iface"]="$zone"
    if [[ "$zone" == "unassigned" ]]; then IFACE_PROFILES["$iface"]="none"; continue; fi

    append_unique ASSIGNED_IFACES "$iface"
    case "$zone" in
      domain_zone) append_unique DOMAIN_IFACES "$iface" ;;
      storage_zone) append_unique STORAGE_IFACES "$iface" ;;
      restricted_zone) append_unique RESTRICTED_IFACES "$iface" ;;
    esac

    profiles="$(read_profiles_for_iface "$iface" "$zone")"
    IFACE_PROFILES["$iface"]="$profiles"
    for profile in $profiles; do
      case "$profile" in
        rke2-server|rke2-agent|rke2-singlenode) append_unique K8S_IFACES "$iface" ;;
        harbor-docker) append_unique HARBOR_IFACES "$iface" ;;
        custom-ingress) append_unique CUSTOM_INGRESS_IFACES "$iface" ;;
      esac
    done
  done

  if [[ "${#ASSIGNED_IFACES[@]}" -eq 0 ]]; then echo "ERROR: No interfaces were assigned. Nothing to do." >&2; exit 1; fi

  local admin_sources_raw admin_sources=""
  echo
  echo "Admin/domain source restriction is strongly recommended."
  admin_sources="$(prompt_cidrs "Enter trusted admin/source CIDR(s), comma/space-separated, or blank for any: ")"
  admin_sources_raw="$(echo "$admin_sources" | paste -sd ' ' -)"

  local domain_profile="ssh-only"
  if [[ "${#DOMAIN_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Domain-zone base profile choices:"
    echo "  1) SSH only"
    echo "  2) SSH + HTTP/HTTPS"
    echo "  3) SSH + HTTP/HTTPS + AD/DC/Samba domain-service ports"
    local domain_choice
    while true; do
      read -r -p "Select domain-zone base profile [1-3, default 1]: " domain_choice
      domain_choice="$(trim "$domain_choice")"; [[ -z "$domain_choice" ]] && domain_choice="1"
      case "$domain_choice" in 1) domain_profile="ssh-only"; break ;; 2) domain_profile="web"; break ;; 3) domain_profile="dc"; break ;; *) echo "ERROR: Enter 1, 2, or 3." >&2 ;; esac
    done
  fi

  local storage_sources="" storage_sources_raw="" nfs_udp="no" legacy_nfs="no"
  if [[ "${#STORAGE_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Storage-zone source restriction is not optional in spirit. Use storage client/initiator CIDRs."
    storage_sources="$(prompt_cidrs "Enter storage peer CIDR(s), comma/space-separated, or blank for any on storage NIC: ")"
    storage_sources_raw="$(echo "$storage_sources" | paste -sd ' ' -)"
    yes_no "Allow NFS UDP/2049 on storage_zone? TCP-only NFSv4 is the better baseline." "N" && nfs_udp="yes"
    yes_no "Add legacy NFSv3/rpcbind/mountd pinned ports on storage_zone? Only if your NFS server is pinned to fixed ports." "N" && legacy_nfs="yes"
  fi

  local restricted_sources="" restricted_sources_raw=""
  if [[ "${#RESTRICTED_IFACES[@]}" -gt 0 || "${#CUSTOM_INGRESS_IFACES[@]}" -gt 0 || "${#HARBOR_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Restricted/custom/Harbor ingress client source CIDRs control who may connect to exposed service/VIP ports."
    restricted_sources="$(prompt_cidrs "Enter allowed client source CIDR(s) for restricted/custom ingress, or blank for any: ")"
    restricted_sources_raw="$(echo "$restricted_sources" | paste -sd ' ' -)"
  fi

  local vip_dests="" vip_dests_raw="" custom_ingress_specs="" custom_ingress_specs_raw="" route_vip="yes"
  if [[ "${#RESTRICTED_IFACES[@]}" -gt 0 || "${#CUSTOM_INGRESS_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Kubernetes ingress VIP destination IP/CIDR(s):"
    echo "  - Use this for MetalLB/LoadBalancer/Gateway/Service VIPs, e.g. 10.0.4.50/32 or 10.0.4.50/31."
    echo "  - Leave blank to allow traffic to any destination IP on the selected interface."
    vip_dests="$(prompt_cidrs "Enter Kubernetes ingress VIP destination IP/CIDR(s), comma/space-separated, or blank for any destination: ")"
    vip_dests_raw="$(echo "$vip_dests" | paste -sd ' ' -)"
    read -r -p "Enter restricted/custom ingress port specs [default: tcp/443], e.g. tcp/80 tcp/443 udp/15443: " custom_ingress_specs_raw
    custom_ingress_specs_raw="$(trim "$custom_ingress_specs_raw")"; [[ -z "$custom_ingress_specs_raw" ]] && custom_ingress_specs_raw="tcp/443"
    custom_ingress_specs="$(parse_proto_port_specs "$custom_ingress_specs_raw")"
    if [[ -n "$vip_dests" ]]; then yes_no "Also add UFW routed allow rules for these K8s VIP destination(s)? Useful for LoadBalancer/MetalLB/kube-proxy paths." "Y" || route_vip="no"; fi
  fi

  local k8s_api_sources="" k8s_api_sources_raw="" k8s_node_sources="" k8s_node_sources_raw="" cni_profile="none" nodeports="no" istio_profile="none"
  if [[ "${#K8S_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Kubernetes/RKE2 API source CIDRs should be admin/jumpbox/Rancher/automation CIDRs only."
    k8s_api_sources="$(prompt_cidrs "Enter Kubernetes API/admin source CIDR(s), or blank to reuse admin/source CIDR(s): " "$admin_sources_raw")"
    k8s_api_sources_raw="$(echo "$k8s_api_sources" | paste -sd ' ' -)"
    echo
    echo "Kubernetes/RKE2 node source CIDRs should be cluster node CIDRs only."
    k8s_node_sources="$(prompt_cidrs "Enter Kubernetes node/server source CIDR(s), or blank to reuse admin/source CIDR(s): " "$admin_sources_raw")"
    k8s_node_sources_raw="$(echo "$k8s_node_sources" | paste -sd ' ' -)"
    cni_profile="$(read_cni_profile)"
    yes_no "Allow Kubernetes NodePort TCP/UDP range 30000:32767 on selected K8s NIC(s)? Usually no when using LoadBalancer/Gateway/Ingress VIPs." "N" && nodeports="yes"
    if has_multinode_k8s_profile; then
      echo
      echo "Istio is optional. This only opens host firewall paths for official Istio service-mesh ports on selected RKE2 server/agent NICs."
      echo "Do not enable this on public/restricted NICs unless you truly intend that exposure."
      if yes_no "Add Istio service mesh port profile on RKE2-Server/RKE2-Agent interfaces?" "N"; then istio_profile="$(read_istio_profile)"; fi
    elif has_profile_anywhere "rke2-singlenode"; then
      echo
      echo "RKE2-SingleNode selected. Skipping Istio service-mesh port prompt by default."
      echo "Single-node clusters can run Istio for app behavior, but they do not need multi-node mesh firewall plumbing."
      echo "Expose Istio Gateway service traffic with Custom-Ingress/VIP rules instead."
    fi
  fi

  local docker_cidrs="" docker_cidrs_raw="" docker_ports="" docker_ports_raw="" docker_guard="no" docker_blocked_ifaces=()
  if [[ "${#HARBOR_IFACES[@]}" -gt 0 ]]; then
    echo
    echo "Harbor-Docker profile selected. Docker bridge CIDRs/ports are needed because published ports may traverse FORWARD after Docker DNAT."
    local suggested_cidrs=""
    suggested_cidrs="$(default_docker_cidrs | paste -sd ' ' -)"
    [[ -n "$suggested_cidrs" ]] && echo "Detected Docker CIDR candidate(s): $suggested_cidrs"
    read -r -p "Enter Docker destination CIDR(s), or press Enter to use detected candidate(s): " docker_cidrs_raw
    docker_cidrs_raw="$(trim "$docker_cidrs_raw")"; [[ -z "$docker_cidrs_raw" ]] && docker_cidrs_raw="$suggested_cidrs"
    if [[ -z "$docker_cidrs_raw" ]]; then echo "ERROR: Harbor-Docker requires Docker destination CIDR(s), e.g. 172.17.0.0/16 or 172.18.0.0/16." >&2; exit 1; fi
    docker_cidrs="$(parse_cidrs "$docker_cidrs_raw")"
    read -r -p "Enter Docker destination TCP port(s), comma/space-separated [default: 80,443,8080,8443]: " docker_ports_raw
    docker_ports_raw="$(trim "$docker_ports_raw")"; [[ -z "$docker_ports_raw" ]] && docker_ports_raw="80,443,8080,8443"
    docker_ports="$(parse_ports "$docker_ports_raw")"
    for iface in "${ASSIGNED_IFACES[@]}"; do if ! array_contains "$iface" "${HARBOR_IFACES[@]}"; then docker_blocked_ifaces+=("$iface"); fi; done
    yes_no "Install persistent DOCKER-USER guard to block storage/non-selected zones from Docker container CIDRs?" "Y" && docker_guard="yes"
  fi

  local harbor_ifaces_summary docker_blocked_summary
  harbor_ifaces_summary="$(join_by_space "${HARBOR_IFACES[@]:-}")"
  docker_blocked_summary="$(join_by_space "${docker_blocked_ifaces[@]:-}")"

  local forwarding_required="no" forwarding_reason="none"
  if [[ "${#HARBOR_IFACES[@]}" -gt 0 && "${#K8S_IFACES[@]}" -gt 0 ]]; then forwarding_required="yes"; forwarding_reason="Harbor/Docker published-port forwarding and Kubernetes/RKE2 networking"
  elif [[ "${#HARBOR_IFACES[@]}" -gt 0 ]]; then forwarding_required="yes"; forwarding_reason="Harbor/Docker published-port forwarding"
  elif [[ "${#K8S_IFACES[@]}" -gt 0 ]]; then forwarding_required="yes"; forwarding_reason="Kubernetes/RKE2 networking"; fi

  show_plan "$admin_sources_raw" "$storage_sources_raw" "$restricted_sources_raw" "$vip_dests_raw" "$k8s_api_sources_raw" "$k8s_node_sources_raw" "$cni_profile" "$nodeports" "$istio_profile" "$custom_ingress_specs_raw" "$docker_cidrs_raw" "$docker_ports_raw" "$docker_guard"
  if ! yes_no "Apply this firewall configuration now?" "N"; then echo "No changes applied. Action log saved at: $LOG_FILE"; exit 0; fi

  local backup_dir
  backup_dir="$(backup_current_config)"
  echo "Applying kernel/network hardening..."; apply_sysctl_hardening "$forwarding_required" "$forwarding_reason"
  echo "Configuring UFW defaults..."; configure_ufw_defaults

  echo "Applying zone base and profile rules..."
  for iface in "${ASSIGNED_IFACES[@]}"; do
    zone="${IFACE_ZONE[$iface]}"; profiles="${IFACE_PROFILES[$iface]}"
    case "$zone" in
      domain_zone) apply_domain_zone_base "$iface" "$admin_sources" "$domain_profile" ;;
      storage_zone) apply_storage_zone_base "$iface" "$storage_sources" "$nfs_udp" "$legacy_nfs" ;;
      restricted_zone) : ;;
    esac
    if [[ " $profiles " == *" custom-ingress "* || "$zone" == "restricted_zone" ]]; then apply_custom_ingress_rules "$iface" "$restricted_sources" "$vip_dests" "$custom_ingress_specs" "$route_vip"; fi
    if [[ " $profiles " == *" rke2-server "* ]]; then
      apply_rke2_profile_rules "$iface" rke2-server "$k8s_api_sources" "$k8s_node_sources"
      apply_cni_profile_rules "$iface" "$cni_profile" "$k8s_node_sources"
      [[ "$nodeports" == "yes" ]] && apply_nodeport_rules "$iface" "$restricted_sources"
      [[ "$istio_profile" != "none" ]] && apply_istio_rules "$iface" "$istio_profile" "$k8s_node_sources"
    fi
    if [[ " $profiles " == *" rke2-agent "* ]]; then
      apply_rke2_profile_rules "$iface" rke2-agent "$k8s_api_sources" "$k8s_node_sources"
      apply_cni_profile_rules "$iface" "$cni_profile" "$k8s_node_sources"
      [[ "$nodeports" == "yes" ]] && apply_nodeport_rules "$iface" "$restricted_sources"
      [[ "$istio_profile" != "none" ]] && apply_istio_rules "$iface" "$istio_profile" "$k8s_node_sources"
    fi
    if [[ " $profiles " == *" rke2-singlenode "* ]]; then
      apply_rke2_profile_rules "$iface" rke2-singlenode "$k8s_api_sources" "$k8s_node_sources"
      apply_cni_profile_rules "$iface" "$cni_profile" "$k8s_node_sources"
      [[ "$nodeports" == "yes" ]] && apply_nodeport_rules "$iface" "$restricted_sources"
    fi
    if [[ " $profiles " == *" harbor-docker "* ]]; then ufw_allow_in_scoped "$iface" tcp 443 "Harbor/Docker HTTPS host inbound" "$restricted_sources" ""; fi
  done

  if [[ "${#HARBOR_IFACES[@]}" -gt 0 ]]; then echo "Applying routed/container Harbor-Docker rules..."; apply_forwarded_docker_rules "$docker_cidrs" "$docker_ports" "$restricted_sources" "${HARBOR_IFACES[@]}"; fi
  echo "Applying explicit inter-zone routed traffic denies..."; apply_interzone_route_denies "${ASSIGNED_IFACES[@]}"
  echo "Enabling UFW..."; run_cmd ufw --force enable; run_cmd ufw reload
  if [[ "${#HARBOR_IFACES[@]}" -gt 0 && "$docker_guard" == "yes" ]]; then install_docker_guard "$harbor_ifaces_summary" "$docker_blocked_summary" "$docker_cidrs" "$docker_ports"; fi

  echo
  echo "=== Final UFW status ==="; ufw status verbose
  echo
  echo "Rule numbers:"; ufw status numbered
  local audit_report
  audit_report="$(write_audit_report "$backup_dir")"
  echo
  echo "Backup saved at: $backup_dir"
  echo "Audit report saved at: $audit_report"
  echo "Action log saved at: $LOG_FILE"
  [[ "$docker_guard" == "yes" ]] && echo "Docker guard log: $LOG_ROOT/docker-guard.log"
  echo "Done. Validate from each network before closing your admin session."
}

main "$@"
