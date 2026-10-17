# myrecon

One domain in, full recon out. A single bash script that chains the tools I actually use into one run, with the sharp edges filed down.

```bash
./myrecon.sh example.com
```

> For authorized testing only. Run it against your own assets or targets you have explicit written permission / in-scope bug bounty programs to test. What you do with it is on you.

---

## What it does

Takes a domain, runs the full passive-to-active recon chain, and drops everything into a structured output tree. In order:

1. **Preflight** ... verifies required tools exist, catches the wrong-`httpx` trap (see below), finds a Chrome/Chromium binary, warns about any missing optional tools.
2. **Subdomains** ... `subfinder` (plus `assetfinder` if installed), deduped into `final.txt`.
3. **Alive hosts** ... `httpx` probes which subdomains respond, writes live URLs and a bare-hostname list.
4. **Fingerprint** ... status code, page title, tech-detect, and CDN detection. Counts how many live hosts sit behind a CDN.
5. **Takeover check** ... `subzy`, falling back to `nuclei -tags takeover`.
6. **Port scan** ... `nmap` top 100 ports (`-Pn -T4 --open`). Warns if targets are CDN-fronted.
7. **Archived URLs** ... `gau`, falling back to `waybackurls`.
8. **Params** ... pulls query parameters out of the archived URLs into a wordlist.
9. **Extensions** ... buckets archived URLs by type (js, json, php, aspx, jsp, html).
10. **Screenshots** ... `gowitness`, falling back to `aquatone`.
11. **Summary** ... counts, CDN-fronted total, screenshot count, error count, elapsed time.

Two design decisions worth knowing:

- **It degrades instead of dying.** Required tools missing = hard stop. Optional tool missing = that stage skips, the run continues, and the skip is logged to `errors.log`. You never lose a whole run to one uninstalled binary.
- **It knows when it's being lied to.** If a host is behind Cloudflare / Akamai / Fastly / etc., it flags it and warns that `nmap` is scanning the CDN edge, not the real origin. A scan that hides that is just confident garbage.

---

## Requirements

**Required** (script won't run without these):

| Tool | Install |
|------|---------|
| `subfinder` | `go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest` |
| `httpx` | `go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest` |

**Optional** (stage skips if missing):

| Tool | Purpose | Install |
|------|---------|---------|
| `assetfinder` | extra subdomains | `go install github.com/tomnomnom/assetfinder@latest` |
| `nmap` | port scanning | `sudo apt install nmap` |
| `gau` | archived URLs | `go install github.com/lc/gau/v2/cmd/gau@latest` |
| `waybackurls` | archived URLs (fallback) | `go install github.com/tomnomnom/waybackurls@latest` |
| `subzy` | takeover check | `go install -v github.com/PentestPad/subzy@latest` |
| `nuclei` | takeover check (fallback) | `go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest` |
| `gowitness` | screenshots | `go install github.com/sensepost/gowitness@latest` |
| `aquatone` | screenshots (fallback) | [releases](https://github.com/michenriksen/aquatone/releases) |
| `chromium` | browser for gowitness | `sudo apt install chromium` |

---

## The httpx trap (read this before you rage)

There are two completely different tools called `httpx`:

- **ProjectDiscovery's `httpx`** ... the one this script needs (host probing).
- **Python's `httpx`** ... an HTTP client library that also ships a CLI with the same name.

If you've ever `pip install`ed something that pulled in Python's httpx, its binary can end up ahead of the real one on your `PATH`. The script runs, errors in a way that makes no sense, and you waste an afternoon blaming your own syntax.

The preflight catches this and tells you. The fix is making sure Go's bin directory comes first:

```bash
export PATH="$HOME/go/bin:$PATH"
```

Add that to your `~/.bashrc` or `~/.zshrc` so it sticks.

---

## Output

Everything lands under `<domain>/recon/`:

```
<domain>/recon/
├── final.txt                     # all subdomains, deduped
├── errors.log                    # anything that errored or got skipped
├── httpx/
│   ├── alive_urls.txt            # live URLs
│   ├── alive_hosts.txt           # bare hostnames (for nmap)
│   └── httpx_detail.txt          # status, title, tech, cdn
├── takeovers/
│   └── takeovers.txt
├── scans/
│   └── scan.*                    # nmap output (-oA: .nmap/.gnmap/.xml)
├── wayback/
│   ├── wayback_output.txt
│   ├── params/params.txt         # extracted query params
│   └── extensions/               # URLs bucketed by type
│       ├── js.txt
│       ├── json.txt
│       ├── php.txt
│       ├── aspx.txt
│       ├── jsp.txt
│       └── html.txt
└── screenshots/
```

---

## Why it exists

Built it during PNPT prep. The course recon toolchain had conflicts on my setup (the httpx one above being the worst), and I'd rather fix the problem once than fight the same setup every session. It's not a new tool. It's the standard ProjectDiscovery / tomnomnom stack wired together the way I work.

## License

MIT. Use it, fork it, break it.
