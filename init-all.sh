#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

projects=()
for dir in "$SCRIPT_DIR"/project*/; do
    [ -d "$dir" ] && [ -f "$dir/main.tf" ] && projects+=("$dir")
done

if [ "${#projects[@]}" -eq 0 ]; then
    echo "Error: No Terraform projects found under $SCRIPT_DIR" >&2
    exit 1
fi

for dir in "${projects[@]}"; do
    name=$(basename "$dir")
    echo "=== Initializing $name ==="
    (cd "$dir" && terraform init -input=false)
done

echo "=== All ${#projects[@]} projects initialized ==="
