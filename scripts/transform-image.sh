#!/bin/bash
set -eo pipefail

SOURCE_IMAGE=$1

# Extract image components
IMAGE_NAME=$(echo $SOURCE_IMAGE | awk -F: '{print $1}')
TAG=$(echo $SOURCE_IMAGE | awk -F: '{print $2}')
TAG=${TAG:-latest}

# Transform image name
TARGET_IMAGE_NAME=$(echo $IMAGE_NAME | sed 's/\//-/g')
TARGET_IMAGE="${TARGET_REGISTRY}/${TARGET_IMAGE_NAME}:${TAG}"

# Execute image operations
docker pull ${SOURCE_IMAGE}
docker tag ${SOURCE_IMAGE} ${TARGET_IMAGE}
docker push ${TARGET_IMAGE}

echo "Successfully mirrored ${SOURCE_IMAGE} to ${TARGET_IMAGE}"

# Create logs directory if needed
mkdir -p logs

# Record mapping in JSON
jq -n \
  --arg source "$SOURCE_IMAGE" \
  --arg target "$TARGET_IMAGE" \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{source: $source, target: $target, timestamp: $timestamp}' \
  >> logs/image-mappings.json
