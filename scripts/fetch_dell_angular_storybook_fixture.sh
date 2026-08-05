#!/usr/bin/env bash
set -euo pipefail

# Download Dell Design System's already-published Angular v3.0.1 Storybook.
# This intentionally fetches static output only; it never clones source,
# installs dependencies, or executes a framework/Storybook build.

base_url="https://angular.delldesignsystem.com/3.0.1"
fixture_dir="${1:-$(mktemp -d /tmp/exp-dell-angular-storybook.XXXXXX)}"

mkdir -p "$fixture_dir/sb-preview" "$fixture_dir/sb-common-assets"

fetch() {
    local resource="$1"
    mkdir -p "$fixture_dir/$(dirname "$resource")"
    curl --location --fail --silent --show-error \
        "$base_url/$resource" --output "$fixture_dir/$resource"
}

for resource in \
    index.json \
    project.json \
    iframe.html \
    main.css \
    runtime~main.90fcc694.iframe.bundle.js \
    7165.5a2fb7fb.iframe.bundle.js \
    main.e174fd93.iframe.bundle.js \
    sb-preview/runtime.js \
    sb-common-assets/nunito-sans-regular.woff2 \
    sb-common-assets/nunito-sans-italic.woff2 \
    sb-common-assets/nunito-sans-bold.woff2 \
    sb-common-assets/nunito-sans-bold-italic.woff2
do
    fetch "$resource"
done

runtime="$fixture_dir/runtime~main.90fcc694.iframe.bundle.js"
while IFS= read -r resource; do
    fetch "$resource"
done < <(python3 - "$runtime" <<'PY'
import json
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
match = re.search(
    r'__webpack_require__\.u=chunkId=>\(\(\{(.*?)\}\[chunkId\]\|\|chunkId\)'
    r'\+"\."\+\{(.*?)\}\[chunkId\]\+"\.iframe\.bundle\.js"\)',
    source,
)
if not match:
    raise SystemExit("Dell Storybook webpack chunk map was not found")

def parse_object(fragment):
    quoted = re.sub(r'(^|,)(\d+):', r'\1"\2":', fragment)
    return json.loads("{" + quoted + "}")

names = parse_object(match.group(1))
hashes = parse_object(match.group(2))
for chunk_id, digest in hashes.items():
    print(f"{names.get(chunk_id, chunk_id)}.{digest}.iframe.bundle.js")
PY
)

curl --location --fail --silent --show-error \
    "https://angular.delldesignsystem.com/dds-icons.woff2" \
    --output "$fixture_dir/dds-icons.woff2"
curl --location --fail --silent --show-error \
    "https://angular.delldesignsystem.com/dds-icons.woff" \
    --output "$fixture_dir/dds-icons.woff"
curl --location --fail --silent --show-error \
    "https://angular.delldesignsystem.com/dds-icons.svg" \
    --output "$fixture_dir/dds-icons.svg"

expected_index="9dd74882d46ec3efd0fd3543f2aa47783db802eda00cac7ed983a92c17d0a00b"
expected_project="eebc54b6353ffdb0c96754e769e33768948f7558f865f5c9c631bd79a26d2fd1"
actual_index="$(shasum -a 256 "$fixture_dir/index.json" | awk '{print $1}')"
actual_project="$(shasum -a 256 "$fixture_dir/project.json" | awk '{print $1}')"

if [[ "$actual_index" != "$expected_index" || "$actual_project" != "$expected_project" ]]; then
    echo "Dell Angular Storybook v3.0.1 receipts changed; inspect before updating the regression." >&2
    exit 1
fi

echo "$fixture_dir"
