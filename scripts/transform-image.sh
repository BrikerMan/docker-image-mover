#!/bin/bash
set -eo pipefail

# Copy one image from any registry into the target registry.
#
# Reference forms and what gets pushed (target repo = HOST/NAMESPACE/name):
#   name:1.2.3            -> name:1.2.3                       (exact tag, copied as-is)
#   name:latest / name    -> name:latest + name:sha-<12hex>    (floating: digest is resolved
#                            and pinned as an immutable tag alongside; SYNC_LATEST=false
#                            pushes only the pinned tag)
#   name@sha256:...       -> name:sha-<12hex>                  (exact digest, no latest)
#   name:1.2.3@sha256:... -> name:1.2.3 + name:sha-<12hex>
#
# Why pinning: `latest` in the target registry drifts whenever upstream republishes.
# The pinned sha-<digest> tag is immutable, so stacks can reference an exact build and
# `docker pull` / compose files stay reproducible.
#
# Env:
#   REGISTRY_HOST, REGISTRY_NAMESPACE  required
#   PIN_FLOATING_TAGS  (default true)  also push sha-<digest> tag for floating refs
#   SYNC_LATEST        (default true)  also push the `latest` tag for floating refs
#   DRY_RUN            (default false) print the plan without touching any registry

SOURCE_IMAGE=$1

if [ -z "$SOURCE_IMAGE" ]; then
  echo "Usage: $0 <source-image> [platforms]"
  exit 1
fi

# Strip inline comments (e.g. "alpine:latest  # lightweight base") and surrounding
# whitespace. Safe because OCI image names do not allow '#'.
SOURCE_IMAGE=$(echo "$SOURCE_IMAGE" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')

PLATFORMS=${2:-linux/amd64,linux/arm64}

if [ -z "$REGISTRY_HOST" ] || [ -z "$REGISTRY_NAMESPACE" ]; then
  echo "Error: REGISTRY_HOST and REGISTRY_NAMESPACE must be set"
  exit 1
fi

PIN_FLOATING_TAGS=${PIN_FLOATING_TAGS:-true}
SYNC_LATEST=${SYNC_LATEST:-true}
DRY_RUN=${DRY_RUN:-false}

# --- Parse source reference: [name[:tag]][@sha256:...] ---
SRC_DIGEST=""
DIGEST_INPUT=false
if [[ "$SOURCE_IMAGE" == *@sha256:* ]]; then
  SRC_DIGEST="${SOURCE_IMAGE##*@}"
  NAME_PART="${SOURCE_IMAGE%@*}"
  DIGEST_INPUT=true
else
  NAME_PART="$SOURCE_IMAGE"
fi

# Tag lives in the last path segment only, so registries with ports
# (host:5000/img:tag) parse correctly.
LAST_SEG="${NAME_PART##*/}"
if [[ "$LAST_SEG" == *:* ]]; then
  IMAGE_NAME="${LAST_SEG%%:*}"
  TAG="${LAST_SEG#*:}"
else
  IMAGE_NAME="$LAST_SEG"
  TAG=""
fi

TARGET_REPO="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}"

# First 12 hex chars of a sha256 digest (matches the short form `docker images
# --digests` shows; an 8-char prefix also matches homelab tooling output).
digest_short() {
  echo "${1#sha256:}" | cut -c1-12
}

# Manifest digest of a registry ref, or empty if unresolvable.
# Prefers --format (modern buildx); falls back to parsing the plain output
# because older buildx silently ignores --format.
resolve_digest() {
  local out
  out=$(docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>/dev/null) || return 0
  if [[ "$out" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "$out"
    return 0
  fi
  out=$(docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:[[:space:]]*sha256:/{print $2; exit}') || return 0
  [[ "$out" =~ ^sha256:[0-9a-f]{64}$ ]] && echo "$out"
  return 0
}

# --- Resolve source digest (pinned tag, skip check and mapping log need it) ---
if [ "$DRY_RUN" != "true" ] && [ -z "$SRC_DIGEST" ]; then
  SRC_DIGEST=$(resolve_digest "$SOURCE_IMAGE")
  if [ -z "$SRC_DIGEST" ]; then
    if [ -z "$TAG" ] || [ "$TAG" = "latest" ]; then
      echo "ERROR: cannot resolve manifest digest for ${SOURCE_IMAGE}"
      exit 1
    fi
    echo "WARN: cannot resolve manifest digest for ${SOURCE_IMAGE}, copying without pinning"
  fi
fi

# --- Decide target tags ---
# PIN_TAG is always derived from a known digest; PIN_FLOATING_TAGS only gates
# whether floating refs (latest/no tag) get it as an extra tag.
PIN_TAG=""
if [ -n "$SRC_DIGEST" ]; then
  PIN_TAG="sha-$(digest_short "$SRC_DIGEST")"
fi

FLOATING=false
if [ -z "$TAG" ]; then
  if [ "$DIGEST_INPUT" = true ]; then
    # pure digest ref (name@sha256:...): pin only, no latest
    TAG="$PIN_TAG"
  else
    # no tag at all: treated as latest
    FLOATING=true
    TAG="latest"
  fi
elif [ "$TAG" = "latest" ]; then
  FLOATING=true
fi

TARGET_REFS=()
if [ "$FLOATING" = true ] && [ "$SYNC_LATEST" != "true" ]; then
  # pinned-only mode: latest is not mirrored
  if [ "$PIN_FLOATING_TAGS" != "true" ] || [ -z "$PIN_TAG" ]; then
    echo "ERROR: SYNC_LATEST=false but no pinned tag available for ${SOURCE_IMAGE} (PIN_FLOATING_TAGS must be true)"
    exit 1
  fi
  TARGET_REFS+=("${TARGET_REPO}:${PIN_TAG}")
else
  TARGET_REFS+=("${TARGET_REPO}:${TAG}")
  if [ -n "$PIN_TAG" ] && [ "$PIN_TAG" != "$TAG" ] && { [ "$DIGEST_INPUT" = true ] || { [ "$FLOATING" = true ] && [ "$PIN_FLOATING_TAGS" = "true" ]; }; }; then
    TARGET_REFS+=("${TARGET_REPO}:${PIN_TAG}")
  fi
fi

TARGET_DESC=""
for ref in "${TARGET_REFS[@]}"; do
  TARGET_DESC+="${ref#"${REGISTRY_HOST}/"} "
done
TARGET_DESC=${TARGET_DESC% }

DIGEST_DESC=""
[ -n "$SRC_DIGEST" ] && DIGEST_DESC=", digest: ${SRC_DIGEST}"

if [ "$DRY_RUN" = "true" ]; then
  echo "[dry-run] ${SOURCE_IMAGE} -> ${TARGET_DESC} (platforms: ${PLATFORMS}, digest: ${SRC_DIGEST:-<resolved at sync time>})"
  exit 0
fi

# --- Skip if the work is already done ---
# `imagetools create --platform` rebuilds the manifest index, so target digests
# generally differ from the source digest. Skip when every target ref exists AND
# either the pinned sha tag is present (this exact source build was mirrored
# before — both tags are pushed atomically in one create call) or every target
# digest equals the source digest (carbon copy).
ALL_EXIST=true
DIGESTS_MATCH=true
for ref in "${TARGET_REFS[@]}"; do
  TARGET_DIGEST=$(resolve_digest "$ref")
  if [ -z "$TARGET_DIGEST" ]; then
    ALL_EXIST=false
    break
  fi
  if [ "$TARGET_DIGEST" != "$SRC_DIGEST" ]; then
    DIGESTS_MATCH=false
  fi
done

PIN_EXISTS=false
HAS_PIN_REF=false
for ref in "${TARGET_REFS[@]}"; do
  [ "$ref" = "${TARGET_REPO}:${PIN_TAG}" ] && HAS_PIN_REF=true
done
if [ "$ALL_EXIST" = true ] && [ "$DIGESTS_MATCH" != true ] && [ "$HAS_PIN_REF" = true ]; then
  PIN_EXISTS=true
fi

if [ "$ALL_EXIST" = true ] && { [ "$DIGESTS_MATCH" = true ] || [ "$PIN_EXISTS" = true ]; }; then
  echo "Skip: ${SOURCE_IMAGE} -> ${TARGET_DESC} (digest: ${SRC_DIGEST:-n/a})"
  exit 0
fi

echo "Copying  ${SOURCE_IMAGE} -> ${TARGET_DESC} (platforms: ${PLATFORMS}${DIGEST_DESC})"

TAG_ARGS=()
for ref in "${TARGET_REFS[@]}"; do
  TAG_ARGS+=(-t "$ref")
done

if docker buildx imagetools create \
  --platform "${PLATFORMS}" \
  "${TAG_ARGS[@]}" \
  "${SOURCE_IMAGE}"; then
  echo "Done: ${SOURCE_IMAGE} -> ${TARGET_DESC} (platforms: ${PLATFORMS})"
else
  echo "WARN: Some platforms not available for ${SOURCE_IMAGE}, falling back to all available platforms..."
  if docker buildx imagetools create \
    "${TAG_ARGS[@]}" \
    "${SOURCE_IMAGE}"; then
    echo "Done: ${SOURCE_IMAGE} -> ${TARGET_DESC} (all available platforms)"
  else
    echo "ERROR: Failed to copy ${SOURCE_IMAGE}"
    exit 1
  fi
fi

mkdir -p logs
PUSHED_TAGS=$(printf '%s\n' "${TARGET_REFS[@]}" | sed -E 's/.*://' | tr '\n' ' ')
jq -n \
  --arg source "$SOURCE_IMAGE" \
  --arg target "$TARGET_DESC" \
  --arg digest "${SRC_DIGEST}" \
  --arg tags "${PUSHED_TAGS% }" \
  --arg platforms "$PLATFORMS" \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{source: $source, target: $target, source_digest: $digest, tags: $tags, platforms: $platforms, timestamp: $timestamp}' \
  >> logs/image-mappings.json
