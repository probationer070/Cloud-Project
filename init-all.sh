#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMAND=${1:-""}
TF_INIT_FLAGS=${TF_INIT_FLAGS:-""}

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
  echo "=== $name ==="
  (
    cd "$dir"
    terraform init -input=false $TF_INIT_FLAGS
    [ "$COMMAND" = "validate" ] && terraform validate
    if [ "$COMMAND" = "plan" ]; then
      terraform plan -input=false -detailed-exitcode -out=tfplan || [ $? -eq 2 ]
      terraform show -no-color tfplan > plan.txt
    fi
  )
done

echo "=== All ${#projects[@]} projects: ${COMMAND:-init} complete ==="
