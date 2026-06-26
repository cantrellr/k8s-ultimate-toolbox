#!/usr/bin/env bash
set -euo pipefail

# Build an offline tarball containing SELinux utility .deb packages and dependencies.
# Run this on an internet-connected Ubuntu/Debian host that matches the target OS family/release.

OUT_DIR=${OUT_DIR:-dist/selinux-utils-bundle}
BUNDLE_VERSION=${BUNDLE_VERSION:-v1.2.0}
ARCH=$(dpkg --print-architecture)
OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

DEFAULT_PACKAGES=(
  selinux-utils
  policycoreutils
  policycoreutils-python-utils
  semanage-utils
  semodule-utils
  checkpolicy
  setools
  auditd
)

if [[ $# -gt 0 ]]; then
  PACKAGES=("$@")
else
  PACKAGES=("${DEFAULT_PACKAGES[@]}")
fi

WORK_DIR="${OUT_DIR}/work"
DEB_DIR="${WORK_DIR}/debs"
BUNDLE_NAME="selinux-utils-${OS_ID}-${OS_CODENAME}-${ARCH}-${BUNDLE_VERSION}-${STAMP}.tar.gz"
BUNDLE_PATH="${OUT_DIR}/${BUNDLE_NAME}"

mkdir -p "$DEB_DIR"
rm -f "${DEB_DIR}"/*.deb

command -v apt-cache >/dev/null 2>&1 || { echo "apt-cache is required" >&2; exit 1; }
command -v apt-get >/dev/null 2>&1 || { echo "apt-get is required" >&2; exit 1; }

sudo apt-get update

resolve_packages() {
  printf '%s\n' "${PACKAGES[@]}"
  apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "${PACKAGES[@]}" \
    | awk '/^[[:space:]]*\|?[[:space:]]*(PreDepends|Depends):/ {gsub(/[<>]/,"",$2); print $2}'
}

mapfile -t RESOLVED_PACKAGES < <(resolve_packages | sort -u | while read -r pkg; do
  [[ -n "$pkg" ]] || continue
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    printf '%s\n' "$pkg"
  fi
done)

if [[ ${#RESOLVED_PACKAGES[@]} -eq 0 ]]; then
  echo "No packages resolved" >&2
  exit 1
fi

(
  cd "$DEB_DIR"
  apt-get download "${RESOLVED_PACKAGES[@]}"
)

cat > "${WORK_DIR}/install-selinux-utils.sh" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_DIR="${SCRIPT_DIR}/debs"
[[ -d "$DEB_DIR" ]] || { echo "Missing debs directory: $DEB_DIR" >&2; exit 1; }
command -v apt-get >/dev/null 2>&1 || { echo "apt-get is required" >&2; exit 1; }
sudo apt-get install -y "${DEB_DIR}"/*.deb
for tool in getenforce sestatus semanage semodule seinfo sesearch checkpolicy checkmodule audit2allow audit2why ausearch aureport; do
  command -v "$tool" >/dev/null 2>&1 && echo "OK: $tool" || echo "MISSING: $tool"
done
INSTALLER
chmod +x "${WORK_DIR}/install-selinux-utils.sh"

cat > "${WORK_DIR}/README.md" <<EOF
# SELinux Utilities Offline Bundle

Bundle: ${BUNDLE_NAME}
Built: ${STAMP}
Source OS: ${OS_ID} ${OS_CODENAME}
Architecture: ${ARCH}

## Included package request

$(printf -- '- %s\n' "${PACKAGES[@]}")

## Install on the air-gapped target

Extract the bundle, then run:

\`\`\`bash
./install-selinux-utils.sh
\`\`\`

The target should match the source OS family, release codename, and architecture.
EOF

cat > "${WORK_DIR}/manifest.txt" <<EOF
bundle=${BUNDLE_NAME}
built=${STAMP}
os_id=${OS_ID}
os_codename=${OS_CODENAME}
arch=${ARCH}
packages=${RESOLVED_PACKAGES[*]}
EOF

(
  cd "$WORK_DIR"
  sha256sum debs/*.deb > SHA256SUMS
)

tar -czf "$BUNDLE_PATH" -C "$WORK_DIR" .

echo "Created: $BUNDLE_PATH"
echo "Copy to the air-gapped target, extract, and run ./install-selinux-utils.sh"
