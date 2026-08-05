#!/usr/bin/env bash
set -euo pipefail

# Download Brave's already-published Leo (Nala) Svelte + Vite Storybook.
# This intentionally fetches static output only; it never clones source,
# installs dependencies, or executes a framework/Storybook build.

base_url="https://nala.s.brave.dev/"
fixture_dir="${1:-$(mktemp -d /tmp/exp-brave-leo-storybook.XXXXXX)}"

mkdir -p "$fixture_dir"

python3 - "$base_url" "$fixture_dir" <<'PY'
from collections import deque
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import unquote, urljoin, urlparse
from urllib.request import Request, urlopen
import re
import sys

base_url = sys.argv[1]
fixture = Path(sys.argv[2])
origin = urlparse(base_url)
maximum_files = 1_000
maximum_file_bytes = 12 * 1024 * 1024
maximum_total_bytes = 160 * 1024 * 1024

queue = deque(urljoin(base_url, path) for path in (
    "index.json", "project.json", "iframe.html",
    # Leo constructs `/icons/${name}.svg` at runtime, so these representative
    # corpus dependencies are not discoverable as literal URLs in Vite chunks.
    "icons/warning-circle-filled.svg",
    "icons/checkbox-checked.svg",
    "icons/checkbox-unchecked.svg",
    "icons/send.svg",
    "icons/check-circle-outline.svg",
    "icons/close.svg",
))
seen = set()
total_bytes = 0
downloaded_count = 0

quoted_resource = re.compile(
    r'''["']((?:\.{0,2}/)[^"'?#\\]+\.(?:js|css|svg|png|webp|jpe?g|gif|woff2?|ttf|json)(?:\?[^"'\\]*)?)["']''',
    re.IGNORECASE,
)
html_resource = re.compile(
    r'''(?:src|href)\s*=\s*["']([^"'#]+)["']''', re.IGNORECASE
)
css_resource = re.compile(r'''url\(\s*["']?([^"')#]+)["']?\s*\)''', re.IGNORECASE)

def local_resource(candidate, referring_url):
    if candidate.startswith(("data:", "blob:", "javascript:", "mailto:")):
        return None
    resolved = urlparse(urljoin(referring_url, candidate))
    if (resolved.scheme, resolved.netloc) != (origin.scheme, origin.netloc):
        return None
    path = unquote(resolved.path).lstrip("/")
    if not path or any(part in ("", ".", "..") for part in Path(path).parts):
        return None
    return resolved._replace(fragment="").geturl()

while queue:
    url = queue.popleft()
    if url in seen:
        continue
    seen.add(url)
    if len(seen) > maximum_files:
        raise SystemExit(f"Brave Leo fixture exceeded {maximum_files} resources")

    request = Request(url, headers={"User-Agent": "EXP-Storybook-Fixture/1.0"})
    try:
        with urlopen(request, timeout=30) as response:
            data = response.read(maximum_file_bytes + 1)
            content_type = response.headers.get_content_type()
    except HTTPError as error:
        if error.code == 404:
            continue
        raise
    if len(data) > maximum_file_bytes:
        raise SystemExit(f"Brave Leo resource exceeded 12 MiB: {url}")
    total_bytes += len(data)
    if total_bytes > maximum_total_bytes:
        raise SystemExit("Brave Leo fixture exceeded 160 MiB")

    relative_path = unquote(urlparse(url).path).lstrip("/")
    destination = fixture / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    downloaded_count += 1

    if content_type not in ("text/html", "text/css", "application/javascript",
                            "text/javascript") and destination.suffix not in (
                                ".html", ".css", ".js"):
        continue
    source = data.decode("utf-8", errors="ignore")
    candidates = []
    if destination.suffix == ".html":
        candidates.extend(html_resource.findall(source))
    candidates.extend(quoted_resource.findall(source))
    candidates.extend(css_resource.findall(source))
    for candidate in candidates:
        resource = local_resource(candidate, url)
        if resource is not None and resource not in seen:
            queue.append(resource)

print(f"Fetched {downloaded_count} bounded same-origin resources ({total_bytes} bytes)",
      file=sys.stderr)
PY

expected_index="c4d1029e385fb55a55c6a62b9b62e95a553bc2e5db8b3563636ffa36ad691ae5"
expected_project="c4f2dc4f0b7c9afb25598e621835987021c27314d48b8cff25a604ae2ef54e28"
actual_index="$(shasum -a 256 "$fixture_dir/index.json" | awk '{print $1}')"
actual_project="$(shasum -a 256 "$fixture_dir/project.json" | awk '{print $1}')"

if [[ "$actual_index" != "$expected_index" || "$actual_project" != "$expected_project" ]]; then
    echo "Brave Leo Storybook receipts changed; inspect before updating the regression." >&2
    exit 1
fi

echo "$fixture_dir"
