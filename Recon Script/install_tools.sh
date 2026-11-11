#!/usr/bin/env bash
# install-recon-tools.sh
# One-shot provisioner for recon.sh on a fresh Debian/Kali box.
# Run WITHOUT sudo (it calls sudo only where needed, so Go tools land in YOUR ~/go/bin):
#     bash install-recon-tools.sh
#
# Installs: Go (apt, tarball fallback) + subfinder httpx nuclei gau assetfinder
#           waybackurls subzy gowitness  (go install)  +  nmap chromium (apt).

set -uo pipefail

GO_VERSION="1.23.4"     # bump if you want newer; only used for the tarball fallback
GO_MIN_MINOR=21         # ProjectDiscovery tools need go1.21+

RED=$'\e[1;31m'; RST=$'\e[0m'
banner(){ printf '%s[+]%s %s\n' "$RED" "$RST" "$1"; }
warn(){   printf '%s[!]%s %s\n' "$RED" "$RST" "$1" >&2; }
fail(){   printf '%s[x] FAILED at: %s%s\n' "$RED" "$1" "$RST" >&2; exit 1; }
softfail(){ printf '%s[!] skipped: %s (continuing)%s\n' "$RED" "$1" "$RST" >&2; }

[ "$(id -u)" -eq 0 ] && warn "running as root -> Go tools will go to /root/go/bin, not your user. Prefer running without sudo."

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
need(){ command -v "$1" >/dev/null 2>&1; }

arch_tag(){
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo "unsupported arch: $(uname -m)" >&2; return 1 ;;
  esac
}

go_minor_ok(){
  local v
  v=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | head -1 | sed 's/go//') || return 1
  [ -n "$v" ] || return 1
  local maj="${v%%.*}" min="${v#*.}"
  [ "$maj" -gt 1 ] && return 0
  [ "$maj" -eq 1 ] && [ "$min" -ge "$GO_MIN_MINOR" ]
}

install_go_tarball(){
  local a; a=$(arch_tag) || fail "arch detection"
  local tgz="go${GO_VERSION}.linux-${a}.tar.gz"
  banner "Installing Go ${GO_VERSION} from go.dev (${a})..."
  ( cd /tmp && wget -q "https://go.dev/dl/${tgz}" ) || fail "go download (network/allowlist?)"
  $SUDO rm -rf /usr/local/go || fail "removing old /usr/local/go"
  $SUDO tar -C /usr/local -xzf "/tmp/${tgz}" || fail "go tarball extract"
  export PATH="/usr/local/go/bin:$PATH"
  add_path_line '/usr/local/go/bin'
}

add_path_line(){
  # append an export line to both rc files only if not already present
  local dir="$1" line="export PATH=\"$1:\$PATH\""
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || touch "$rc"
    grep -qF "$dir" "$rc" || printf '%s\n' "$line" >> "$rc"
  done
}

# --- 1. Go toolchain ---
if go_minor_ok; then
  banner "Go present: $(go version | awk '{print $3}')"
else
  if need go; then
    warn "Go is older than 1.${GO_MIN_MINOR} -> using tarball"
    install_go_tarball
  else
    banner "Installing Go via apt..."
    $SUDO apt-get update -y  >/dev/null 2>&1 || warn "apt update had issues"
    $SUDO apt-get install -y golang-go >/dev/null 2>&1 || warn "apt golang-go failed"
    go_minor_ok || install_go_tarball
  fi
fi
go_minor_ok || fail "Go still not usable after install"

# --- 2. PATH for go install output ---
GOBIN_DIR="$(go env GOPATH 2>/dev/null)/bin"; [ -n "$GOBIN_DIR" ] || GOBIN_DIR="$HOME/go/bin"
mkdir -p "$GOBIN_DIR"
export PATH="$GOBIN_DIR:$PATH"
add_path_line "$GOBIN_DIR"
banner "go bin dir on PATH: $GOBIN_DIR"

# --- 3. Go tools ---
declare -a TOOLS=(
  "subfinder|github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  "httpx|github.com/projectdiscovery/httpx/cmd/httpx@latest"
  "nuclei|github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  "gau|github.com/lc/gau/v2/cmd/gau@latest"
  "assetfinder|github.com/tomnomnom/assetfinder@latest"
  "waybackurls|github.com/tomnomnom/waybackurls@latest"
  "subzy|github.com/PentestPad/subzy@latest"
  "gowitness|github.com/sensepost/gowitness@latest"
)
for entry in "${TOOLS[@]}"; do
  name="${entry%%|*}"; path="${entry#*|}"
  banner "go install $name ..."
  go install "$path" 2>&1 | grep -iE 'error|cannot|fatal' >&2 || true
  need "$name" || softfail "$name (go install did not produce a binary)"
done

# --- 4. apt packages (port scan + screenshot browser) ---
banner "Installing nmap + chromium via apt..."
$SUDO apt-get install -y nmap chromium >/dev/null 2>&1 || softfail "apt nmap/chromium"

# --- 5. nuclei templates (needed for the takeover fallback) ---
if need nuclei; then
  banner "Fetching nuclei templates..."
  nuclei -update-templates >/dev/null 2>&1 || softfail "nuclei template update"
fi

# --- 6. verify ---
banner "Verification:"
miss=0
for t in subfinder httpx nuclei gau assetfinder waybackurls subzy gowitness nmap chromium; do
  if need "$t"; then printf '    %sok  %s %s\n' "$RED" "$RST" "$t"
  else printf '    %sMISS%s %s\n' "$RED" "$RST" "$t"; miss=$((miss+1)); fi
done
echo
if [ "$miss" -eq 0 ]; then
  banner "All tools present. Open a new shell (or: source ~/.bashrc) then run recon.sh"
else
  warn "$miss tool(s) missing above. Re-run this script, or install those by hand."
fi
