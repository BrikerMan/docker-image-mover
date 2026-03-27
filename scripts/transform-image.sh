#!/bin/bash
set -eo pipefail

SOURCE_IMAGE=$1

if [ -z "$SOURCE_IMAGE" ]; then
  echo "Usage: $0 <source-image>"
  exit 1
fi

if [ -z "$REGISTRY_HOST" ] || [ -z "$REGISTRY_NAMESPACE" ]; then
  echo "Error: REGISTRY_HOST and REGISTRY_NAMESPACE must be set"
  exit 1
fi

IMAGE_NAME=$(echo "$SOURCE_IMAGE" | awk -F: '{print $1}' | awk -F/ '{print $NF}')
TAG=$(echo "$SOURCE_IMAGE" | awk -F: '{print $2}')
TAG=${TAG:-latest}

TARGET_IMAGE="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${TAG}"

TARGET_SHORT="${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${TAG}"

echo "Pulling  ${SOURCE_IMAGE}"
docker pull "${SOURCE_IMAGE}"

echo "Tagging  ${SOURCE_IMAGE} -> ${TARGET_SHORT}"
docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"

echo "Pushing  ${TARGET_SHORT}"
docker push "${TARGET_IMAGE}"

echo "Done: ${SOURCE_IMAGE} -> ${TARGET_SHORT}"

mkdir -p logs
jq -n \
  --arg source "$SOURCE_IMAGE" \
  --arg target "$TARGET_SHORT" \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{source: $source, target: $target, timestamp: $timestamp}' \
  >> logs/image-mappings.json
