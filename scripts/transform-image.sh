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

PLATFORMS=("linux/amd64" "linux/arm64")
PLATFORM_IMAGES=()

for PLATFORM in "${PLATFORMS[@]}"; do
  ARCH=$(echo "$PLATFORM" | awk -F/ '{print $2}')
  PLATFORM_TAG="${TARGET_IMAGE}-${ARCH}"

  echo "Pulling  ${SOURCE_IMAGE} [${PLATFORM}]"
  if PULL_OUTPUT=$(docker pull --platform "${PLATFORM}" "${SOURCE_IMAGE}" 2>&1); then
    echo "$PULL_OUTPUT"
    DIGEST=$(echo "$PULL_OUTPUT" | grep "Digest:" | awk '{print $2}')
    echo "Tagging  ${SOURCE_IMAGE}@${DIGEST} -> ${TARGET_SHORT}-${ARCH}"
    docker tag "${SOURCE_IMAGE}@${DIGEST}" "${PLATFORM_TAG}"

    echo "Pushing  ${TARGET_SHORT}-${ARCH}"
    docker push "${PLATFORM_TAG}"

    PLATFORM_IMAGES+=("${PLATFORM_TAG}")
  else
    echo "Warning: Failed to pull ${SOURCE_IMAGE} for platform ${PLATFORM}, skipping"
  fi
done

if [ ${#PLATFORM_IMAGES[@]} -eq 0 ]; then
  echo "Error: No platform images were successfully pulled for ${SOURCE_IMAGE}"
  exit 1
fi

echo "Creating manifest  ${TARGET_SHORT}"
# Remove any pre-existing local manifest to avoid conflicts with a fresh create
docker manifest rm "${TARGET_IMAGE}" 2>/dev/null || true
docker manifest create "${TARGET_IMAGE}" "${PLATFORM_IMAGES[@]}"
docker manifest push "${TARGET_IMAGE}"

echo "Done: ${SOURCE_IMAGE} -> ${TARGET_SHORT}"

mkdir -p logs
jq -n \
  --arg source "$SOURCE_IMAGE" \
  --arg target "$TARGET_SHORT" \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{source: $source, target: $target, timestamp: $timestamp}' \
  >> logs/image-mappings.json
