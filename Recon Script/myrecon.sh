#!/usr/bin/env bash

set -uo pipefail

_start=$(date +%s)

RED=$'\e[1;31m'; RST=$'\e[0m'
banner(){ printf '%s[+]%s %s\n' "$RED" "$RST" "$1"; }
warn(){   printf '%s[!]%s %s\n' "$RED" "$RST" "$1" >&2; }
fail(){   printf '%s[x] FAILED at: %s%s\n' "$RED" "$1" "$RST" >&2; exit 1; }
softfail(){ printf '%s[!] skipped at: %s (continuing, see errors.log)%s\n' "$RED" "$1" "$RST" >&2; }

[ $# -lt 1 ] && { echo "usage: $0 <domain>"; exit 1; }
domain="$1"
out="$domain"

need(){ command -v "$1" >/dev/null 2>&1; }

need subfinder || fail "preflight (subfinder not found ... check \$HOME/go/bin is on PATH)"
need httpx     || fail "preflight (httpx not found ... check \$HOME/go/bin is on PATH)"

if httpx -version 2>&1 | grep -qiE 'OPTIONS\] URL|no such option'; then
    fail "preflight (wrong httpx ... that's Python's httpx CLI, not ProjectDiscovery's. Fix: export PATH=\"\$HOME/go/bin:\$PATH\")"
fi

chrome_bin="$(command -v chromium 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v google-chrome 2>/dev/null || true)"

for t in gau nmap subzy gowitness; do
    need "$t" || warn "optional tool missing: $t (that stage will be skipped)"
done

mkdir -p "$out/recon/scans" \
         "$out/recon/httpx" \
         "$out/recon/takeovers" \
         "$out/recon/wayback/params" \
         "$out/recon/wayback/extensions" \
         "$out/recon/screenshots" || fail "mkdir (can't create output dirs ... permissions?)"

errlog="$out/recon/errors.log"
: > "$errlog"

final="$out/recon/final.txt"
alive_urls="$out/recon/httpx/alive_urls.txt"
alive_hosts="$out/recon/httpx/alive_hosts.txt"
detail="$out/recon/httpx/httpx_detail.txt"
wb="$out/recon/wayback/wayback_output.txt"

banner "Harvesting subdomains with subfinder..."
subfinder -d "$domain" -all -silent 2>>"$errlog" | sort -u > "$final" \
    || fail "subfinder (command errored ... see $errlog)"
if need assetfinder; then
    assetfinder --subs-only "$domain" 2>>"$errlog" | grep -i "$domain" >> "$final"
    sort -u "$final" -o "$final"
fi
[ -s "$final" ] || fail "subfinder (zero subdomains collected ... nothing to recon)"
banner "$(wc -l < "$final") subdomains collected"

banner "Probing for alive hosts with httpx..."
httpx -l "$final" -silent -retries 2 -o "$alive_urls" 2>>"$errlog" \
    || fail "httpx probe (command errored ... see $errlog)"
[ -s "$alive_urls" ] || fail "httpx probe (no live hosts written ... alive_urls.txt is empty)"
sed -E 's~^https?://~~; s~/.*$~~; s~:[0-9]+$~~' "$alive_urls" | sort -u > "$alive_hosts"
banner "$(wc -l < "$alive_urls") live URLs"

httpx -l "$alive_urls" -silent -retries 2 -sc -title -tech-detect -cdn -o "$detail" 2>>"$errlog" \
    || softfail "httpx detail"
cdn_hits=$(grep -ciE 'cloudflare|akamai|fastly|azure front door|cloudfront|incapsula|imperva|sucuri|edgecast|stackpath|fronted by|cdn77' "$detail" 2>/dev/null || true)
[ -z "$cdn_hits" ] && cdn_hits=0

if need subzy; then
    banner "Checking subdomain takeover with subzy..."
    subzy run --targets "$final" > "$out/recon/takeovers/takeovers.txt" 2>>"$errlog" \
        || softfail "subzy takeover"
elif need nuclei; then
    banner "Checking subdomain takeover with nuclei..."
    nuclei -l "$alive_urls" -tags takeover -silent -o "$out/recon/takeovers/takeovers.txt" 2>>"$errlog" \
        || softfail "nuclei takeover"
else
    warn "no takeover tool (subzy/nuclei) ... skipping"
fi

if need nmap; then
    if [ "$cdn_hits" -gt 0 ]; then
        warn "$cdn_hits/$(wc -l < "$alive_urls") alive hosts are CDN-fronted ... nmap scans CDN edges here, not origin IPs"
    fi
    banner "Scanning ports with nmap..."
    nmap -iL "$alive_hosts" --top-ports 100 -Pn -T4 --open -oA "$out/recon/scans/scan" 2>>"$errlog" \
        || softfail "nmap"
fi

if need gau; then
    banner "Scraping archived URLs with gau..."
    gau --subs --threads 5 --timeout 60 --retries 2 --verbose "$domain" > "$wb" 2>>"$errlog" \
        || softfail "gau"
elif need waybackurls; then
    banner "Scraping archived URLs with waybackurls..."
    waybackurls < "$final" > "$wb" 2>>"$errlog" || softfail "waybackurls"
fi

if [ -s "$wb" ]; then
    banner "Extracting parameters..."
    grep -oE '[?&][a-zA-Z0-9_]+=' "$wb" \
        | sed -E 's~[?&]~~; s~=$~~' | sort -u \
        | sed 's/$/=/' > "$out/recon/wayback/params/params.txt" || softfail "param extraction"
fi

if [ -s "$wb" ]; then
    banner "Sorting URLs by extension..."
    extdir="$out/recon/wayback/extensions"
    for ext in js json php aspx jsp html; do
        grep -iE "\.${ext}(\?|$)" "$wb" | sort -u > "$extdir/${ext}.txt"
    done
fi

if need gowitness; then
    banner "Screenshotting live hosts with gowitness..."
    [ -z "$chrome_bin" ] && warn "no chromium/chrome found on PATH ... gowitness may fail to launch a browser"
    gw_args=(scan file -f "$alive_urls" --screenshot-path "$out/recon/screenshots")
    [ -n "$chrome_bin" ] && gw_args+=(--chrome-path "$chrome_bin")
    gowitness "${gw_args[@]}" 2>>"$errlog" \
        || softfail "gowitness screenshots"
elif need aquatone; then
    banner "Screenshotting with aquatone..."
    aquatone -out "$out/recon/screenshots" < "$alive_urls" 2>>"$errlog" || softfail "aquatone screenshots"
else
    warn "no screenshot tool (gowitness/aquatone) ... skipping"
fi

_end=$(date +%s)
_elapsed=$(( _end - _start ))
err_lines=$(wc -l < "$errlog" 2>/dev/null || echo 0)
banner "Done. Output in $out/recon/"
printf '    subdomains : %s\n' "$(wc -l < "$final" 2>/dev/null || echo 0)"
printf '    live URLs  : %s\n' "$(wc -l < "$alive_urls" 2>/dev/null || echo 0)"
printf '    cdn-fronted: %s\n' "$cdn_hits"
printf '    screenshots: %s\n' "$(find "$out/recon/screenshots" -type f 2>/dev/null | wc -l)"
printf '    errors     : %s lines (%s)\n' "$err_lines" "$errlog"
printf '    elapsed    : %dm %ds\n' "$(( _elapsed / 60 ))" "$(( _elapsed % 60 ))"
