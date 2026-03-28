#!/bin/bash
set -eo pipefail

SOURCE_IMAGE=$1

if [ -z "$SOURCE_IMAGE" ]; then
  echo "Usage: $0 <source-image> [platforms]"
  exit 1
fi

PLATFORMS=${2:-linux/amd64,linux/arm64}

if [ -z "$REGISTRY_HOST" ] || [ -z "$REGISTRY_NAMESPACE" ]; then
  echo "Error: REGISTRY_HOST and REGISTRY_NAMESPACE must be set"
  exit 1
fi

IMAGE_NAME=$(echo "$SOURCE_IMAGE" | awk -F: '{print $1}' | awk -F/ '{print $NF}')
TAG=$(echo "$SOURCE_IMAGE" | awk -F: '{print $2}')
TAG=${TAG:-latest}

TARGET_IMAGE="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${TAG}"

TARGET_SHORT="${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${TAG}"

echo "Copying  ${SOURCE_IMAGE} -> ${TARGET_SHORT} (platforms: ${PLATFORMS})"

if docker buildx imagetools create \
  --platform "${PLATFORMS}" \
  -t "${TARGET_IMAGE}" \
  "${SOURCE_IMAGE}"; then
  echo "Done: ${SOURCE_IMAGE} -> ${TARGET_SHORT} (platforms: ${PLATFORMS})"
else
  echo "WARN: Some platforms not available for ${SOURCE_IMAGE}, falling back to all available platforms..."
  if docker buildx imagetools create \
    -t "${TARGET_IMAGE}" \
    "${SOURCE_IMAGE}"; then
    echo "Done: ${SOURCE_IMAGE} -> ${TARGET_SHORT} (all available platforms)"
  else
    echo "ERROR: Failed to copy ${SOURCE_IMAGE}"
    exit 1
  fi
fi

mkdir -p logs
jq -n \
  --arg source "$SOURCE_IMAGE" \
  --arg target "$TARGET_SHORT" \
  --arg platforms "$PLATFORMS" \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{source: $source, target: $target, platforms: $platforms, timestamp: $timestamp}' \
  >> logs/image-mappings.json
