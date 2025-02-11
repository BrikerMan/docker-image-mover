#!/bin/bash
set -eo pipefail

TARGET_REGISTRY="crpi-f73blqxqf21robbz.cn-heyuan.personal.cr.aliyuncs.com"

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue

    # Process the image
    SOURCE_IMAGE=$line
    
    # Get just the image name (last part after last slash) and tag
    IMAGE_NAME=$(echo $SOURCE_IMAGE | awk -F: '{print $1}' | awk -F/ '{print $NF}')
    TAG=$(echo $SOURCE_IMAGE | awk -F: '{print $2}')
    TAG=${TAG:-latest}

    TARGET_IMAGE="${TARGET_REGISTRY}/${IMAGE_NAME}:${TAG}"

    echo "Source: $SOURCE_IMAGE"
    echo "Target: $TARGET_IMAGE"
    echo "---"
done < config/target-images.txt
