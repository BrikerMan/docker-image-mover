#!/bin/bash
set -eo pipefail

# Dry-run over config/target-images.txt: prints the planned target refs for
# every entry without touching any registry (no digest resolution, no network).
#
# Override the fake target with:
#   REGISTRY_HOST=... REGISTRY_NAMESPACE=... ./scripts/test-transform.sh

cd "$(dirname "$0")/.."

export DRY_RUN=true
export REGISTRY_HOST=${REGISTRY_HOST:-crpi-f73blqxqf21robbz.cn-heyuan.personal.cr.aliyuncs.com}
export REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-base}

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue

    ./scripts/transform-image.sh "$line"
done < config/target-images.txt
