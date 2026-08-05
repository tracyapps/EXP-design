#!/usr/bin/env bash
set -euo pipefail

# Fetch Kintone UI Component's already-published Web Components + Vite
# Storybook branch. This intentionally receives static output only; it never
# installs dependencies or executes a framework/Storybook build.

repository="https://github.com/kintone-labs/kintone-ui-component.git"
expected_commit="77c9855ac944b44ea539ea5190585c4bae18c26f"
expected_index="6bf58b1074e970ef44f201c23f30b55e698dab333bcfcfafe0df04a6885b0788"
expected_project="1f480f3f74e2d07a5e565c8158c5cd0415a778e36911a03484d742ac110c6c9d"
fixture_dir="${1:-$(mktemp -d /tmp/exp-kintone-web-components-storybook.XXXXXX)}"

if [[ -e "$fixture_dir/.git" || -e "$fixture_dir/index.json" ]]; then
    echo "Kintone fixture destination must be empty: $fixture_dir" >&2
    exit 1
fi

# mktemp creates the directory, while git clone requires a nonexistent or empty
# destination. The empty directory is accepted by git and keeps the target exact.
git clone --quiet --depth 1 --single-branch --branch gh-pages \
    "$repository" "$fixture_dir"

actual_commit="$(git -C "$fixture_dir" rev-parse HEAD)"
actual_index="$(shasum -a 256 "$fixture_dir/index.json" | awk '{print $1}')"
actual_project="$(shasum -a 256 "$fixture_dir/project.json" | awk '{print $1}')"

if [[ "$actual_commit" != "$expected_commit" \
   || "$actual_index" != "$expected_index" \
   || "$actual_project" != "$expected_project" ]]; then
    echo "Kintone Web Components Storybook receipts changed; inspect before updating the regression." >&2
    exit 1
fi

file_count="$(find "$fixture_dir" -type f -not -path '*/.git/*' | wc -l | tr -d ' ')"
total_bytes="$(find "$fixture_dir" -type f -not -path '*/.git/*' -exec stat -f '%z' {} + \
    | awk '{sum += $1} END {print sum + 0}')"
if (( file_count > 500 || total_bytes > 50000000 )); then
    echo "Kintone published fixture exceeded its bounded static-artifact receipt." >&2
    exit 1
fi

echo "Fetched $file_count published resources ($total_bytes bytes) at $actual_commit" >&2
echo "$fixture_dir"
