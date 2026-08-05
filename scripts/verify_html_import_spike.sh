#!/usr/bin/env bash
#
# E0 spike runner — HTML-IMPORT-CONTRACT.md §10.
#
# Builds the probe, generates fixture 1 from EXP's own exporter, and runs all
# three fixtures. This does NOT pass or fail on its own: the spike's job is to
# produce evidence a human reads against the §10 criteria. What it does
# guarantee is that the evidence is generated the same way every time.
#
# usage: scripts/verify_html_import_spike.sh [fixture1|fixture2|fixture3]
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spike="$root/spike/html-import"
scratch="$(mktemp -d)"
server_pid=""

cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

rule() { printf '\n\033[1m%s\033[0m\n%s\n' "$1" "$(printf '─%.0s' $(seq 1 60))"; }

# ── Build the probe ──────────────────────────────────────────────────────────
# -swift-version 5 on purpose: this is a throwaway harness whose delegate
# callbacks would otherwise need Swift 6 concurrency annotations that teach us
# nothing about HTML import. Shipped E1 code does NOT get this exemption.
rule "Building probe"
xcrun swiftc \
  -swift-version 5 \
  -framework WebKit \
  -framework AppKit \
  "$root/scripts/HTMLImportSpike.swift" \
  -o "$scratch/html-import-probe"

# WKWebView is unreliable in a bare command-line process — it wants a bundle
# identifier. Wrapping the binary in a throwaway .app is cheaper than debugging
# WebKit's opinion about it.
appdir="$scratch/HTMLImportProbe.app/Contents/MacOS"
mkdir -p "$appdir"
mv "$scratch/html-import-probe" "$appdir/HTMLImportProbe"
cat > "$scratch/HTMLImportProbe.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>HTMLImportProbe</string>
  <key>CFBundleIdentifier</key><string>org.thisroad.exp.html-import-probe</string>
  <key>CFBundleName</key><string>HTMLImportProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict></plist>
PLIST
probe="$appdir/HTMLImportProbe"
echo "ok: probe built"

which="${1:-all}"

# ── Fixture 1 — EXP's own exported semantic HTML ─────────────────────────────
if [[ "$which" == "all" || "$which" == "fixture1" ]]; then
  rule "Fixture 1 — EXP's own export (ground truth via data-exp-id)"
  xcrun swiftc \
    "$root/EXP [design]/Model/Paint.swift" \
    "$root/EXP [design]/Model/Document.swift" \
    "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
    "$root/EXP [design]/Color/ColorMath.swift" \
    "$root/EXP [design]/Color/DesignLanguageIO.swift" \
    "$root/EXP [design]/Export/SemanticHTMLContract.swift" \
    "$root/EXP [design]/Export/SemanticHTMLExporter.swift" \
    "$root/EXP [design]/Export/HandoffPackageWriter.swift" \
    "$root/scripts/SemanticHTMLGoldenFixtureCheck.swift" \
    "$root/scripts/SemanticHTMLPackageCheck.swift" \
    -o "$scratch/package-check"

  rm -rf "$spike/fixture1-exp-export/Fixture.exph"
  mkdir -p "$spike/fixture1-exp-export"
  "$scratch/package-check" "$spike/fixture1-exp-export/Fixture.exph" >/dev/null
  page="$(find "$spike/fixture1-exp-export/Fixture.exph" -name '*.html' | head -1)"
  if [[ -z "$page" ]]; then
    echo "FAIL: exporter produced no HTML page" >&2; exit 1
  fi
  echo "exported: ${page#$root/}"
  echo "data-exp-id count: $(grep -o 'data-exp-id' "$page" | wc -l | tr -d ' ')"
  # Probed at ONE size on purpose. An EXP export describes a fixed-geometry
  # artboard, so probing it at two web viewports measures the exporter's CSS
  # reflow, not round-trip accuracy. Round-trip is a same-size comparison.
  "$probe" --url "$page" --viewports 1440x1024 \
           --json "$spike/fixture1-exp-export/probe.json"
fi

# ── Fixture 2 — hand-written, not from EXP ───────────────────────────────────
if [[ "$which" == "all" || "$which" == "fixture2" ]]; then
  rule "Fixture 2 — hand-written page, two viewports across one breakpoint"
  echo "Expect: the 768px media query matches at 393 and not at 1440, the cards"
  echo "stack at 393 only, and nothing else differs between the two viewports."
  "$probe" --url "$spike/fixture2-handwritten/index.html" \
           --viewports 393x852,1440x1024 \
           --json "$spike/fixture2-handwritten/probe.json"
fi

# ── Fixture 3 — the trust flow ───────────────────────────────────────────────
if [[ "$which" == "all" || "$which" == "fixture3" ]]; then
  rule "Fixture 3 — multi-origin trust flow"
  python3 "$spike/fixture3-multiorigin/serve.py" > "$scratch/server.log" 2>&1 &
  server_pid=$!
  sleep 1.5

  echo ""
  echo "PASS 1 — discovery. Nothing may be fetched but the document itself."
  "$probe" --url "http://127.0.0.1:8731/" --viewports 393x852,1440x1024 \
           --json "$spike/fixture3-multiorigin/probe-pass1.json"

  echo ""
  echo "Server request log during pass 1 — this is the ground truth for"
  echo "\"pass 1 fetched the document and NOTHING else\":"
  LC_ALL=C tr -cd '\11\12\15\40-\176' < "$scratch/server.log" \
    | LC_ALL=C grep -aE '"(GET|POST)' \
    | LC_ALL=C awk '{ print "    " $0 }' || echo "    (no requests logged)"
  cp "$scratch/server.log" "$spike/fixture3-multiorigin/server-pass1.log"
  : > "$scratch/server.log"

  echo ""
  echo "PASS 2 — origin A (:8732) trusted. widget.js should now execute and"
  echo "reveal origin B (:8733), which pass 1 could not have known about."
  "$probe" --url "http://127.0.0.1:8731/" --viewports 393x852,1440x1024 \
           --allow "http://127.0.0.1:8732" \
           --json "$spike/fixture3-multiorigin/probe-pass2.json"

  echo ""
  echo "Server request log during pass 2:"
  LC_ALL=C tr -cd '\11\12\15\40-\176' < "$scratch/server.log" \
    | LC_ALL=C grep -aE '"(GET|POST)' \
    | LC_ALL=C awk '{ print "    " $0 }' || echo "    (no requests logged)"

  cp "$scratch/server.log" "$spike/fixture3-multiorigin/server-pass2.log"
  echo "    (raw logs kept at spike/html-import/fixture3-multiorigin/server-pass*.log)"

  # ── The check that matters most ────────────────────────────────────────────
  # Everything else in this harness is the importer grading its own homework.
  # The server knows what it actually served. Anything it served that never
  # reached the manifest is a resource fetched WITHOUT being listed in the trust
  # receipt — contract §9 category 7 — and that is a finding, not a warning.
  python3 - "$spike/fixture3-multiorigin/probe-pass2.json" \
             "$spike/fixture3-multiorigin/server-pass2.log" <<'PYCHECK'
import json, re, sys

manifest_path, log_path = sys.argv[1], sys.argv[2]

with open(manifest_path) as fh:
    listed = {e["url"] for e in json.load(fh)["entries"]}

served = set()
line_re = re.compile(r'^\[(\d+)\]\s+"(?:GET|POST)\s+(\S+)')
with open(log_path, errors="replace") as fh:
    for line in fh:
        m = line_re.match(line.strip())
        if m:
            served.add("http://127.0.0.1:%s%s" % (m.group(1), m.group(2)))

# The document itself is the navigation, not a subresource.
served = {u for u in served if not u.endswith("/")}
missing = sorted(served - listed)
phantom = sorted({u for u in listed if u.startswith("http://127.0.0.1")} - served)

print("")
print("SERVER LOG vs MANIFEST — the one check the harness cannot fake")
print("  served: %d subresource(s) · listed in manifest: %d" % (len(served), len(listed)))
if missing:
    print("  ⚠ FETCHED BUT NEVER LISTED — blind spot, must be named in §4:")
    for url in missing:
        print("      %s" % url)
else:
    print("  ✓ every subresource the server served appears in the manifest")
if phantom:
    print("  listed but never served at these viewports (declared, not requested):")
    for url in phantom:
        print("      %s" % url)
PYCHECK

  kill "$server_pid" 2>/dev/null || true
  server_pid=""
fi

rule "Read the output against §10"
cat <<'NOTES'
The numbers do not interpret themselves. The three things that decide E1:

  1. RECORDER COVERAGE. If any resource is caught by exactly one recorder, that
     recorder is load-bearing and cannot be dropped. If a resource appears in
     the server log but in NO recorder, the manifest has a blind spot that must
     be named in contract §4 — not quietly tolerated.

  2. PASS 1 PURITY. The fixture-3 pass-1 server log must show exactly one
     request: the document. Anything else means the rule list is not doing what
     the privacy guarantee claims.

  3. THE ITERATIVE CASE. Pass 2's manifest must contain :8733 URLs that pass 1's
     did not. If it does not, the two-pass model's central honesty claim is
     wrong and E1 gets rescoped before it starts. That is what a spike is for.

Also worth reading: the per-viewport "seen at" lines. A resource listed at only
one viewport is the union manifest working (contract §4).
NOTES
