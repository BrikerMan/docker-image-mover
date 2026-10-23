# docker-image-mover

Sync Docker images from any registry to your own — by **exact version/digest**, not just `latest`.

## Why pinned versions

A `latest` tag in the target registry drifts: every time upstream republishes, the
same reference silently points at a different image. This tool therefore resolves
the upstream manifest **digest** at sync time and pushes an immutable
`sha-<first 12 hex of digest>` tag alongside, so every synced build stays
addressable forever and compose files can pin exactly what was tested.

## Setup

Add these **Repository Secrets**:

| Secret | Description | Example |
|--------|-------------|---------|
| `REGISTRY_HOST` | Target registry host with port | `git.my-company.com` |
| `REGISTRY_NAMESPACE` | Target namespace/organization | `base` |
| `REGISTRY_USER` | Registry username | `your-user` |
| `REGISTRY_TOKEN` | Registry password or token | `gitea_xxx` |

## Usage

### Sync all images

Edit `config/target-images.txt` then trigger **Sync All Docker Images** workflow.

### Sync single image

Trigger **Sync Single Docker Image** workflow, enter source image like `nginx:alpine`.

### Naming rule

`org/image:tag` → `{REGISTRY_HOST}/{REGISTRY_NAMESPACE}/image:tag`

Only the last segment of the image name is kept, regardless of source registry:

- `pgvector/pgvector:pg18` → `git.my-company.com/base/pgvector:pg18`
- `postgres:15-alpine` → `git.my-company.com/base/postgres:15-alpine`

### What gets pushed per reference form

| Source form | Target refs | Notes |
|-------------|-------------|-------|
| `name:1.2.3` (exact tag) | `name:1.2.3` | copied as-is, no extra tags |
| `name:latest` or `name` (floating) | `name:latest` **+** `name:sha-<12hex>` | digest resolved at sync time |
| `name@sha256:...` (exact digest) | `name:sha-<12hex>` | no `latest` pushed |
| `name:1.2.3@sha256:...` | `name:1.2.3` **+** `name:sha-<12hex>` | both tags point at that digest |

Example: `lscr.io/linuxserver/sonarr:latest` synced today produces
`base/sonarr:latest` and `base/sonarr:sha-3f2a1b9c4d5e`. Next week's sync of a
new upstream `latest` updates `base/sonarr:latest` and **adds** a new `sha-` tag;
the old one keeps pointing at the old build.

### Behavior switches (env)

| Variable | Default | Effect |
|----------|---------|--------|
| `PIN_FLOATING_TAGS` | `true` | Also push the `sha-<digest>` tag for floating refs. `false` restores the legacy latest-only behavior. |
| `SYNC_LATEST` | `true` | Also push the `latest` tag for floating refs. Set `false` to mirror **only** pinned tags (breaking for stacks that pull `latest` from the mirror). |
| `DRY_RUN` | `false` | Print the planned target refs without touching any registry. |

Set them as workflow env/vars, or prefix the script locally:

```bash
REGISTRY_HOST=git.my-company.com REGISTRY_NAMESPACE=base \
  ./scripts/transform-image.sh "alpine:latest"
```

### Skip logic

An image is skipped when every target ref already exists in the target registry
**and** either the pinned `sha-` tag for that source build is present, or the
target digests equal the source digest (carbon copy). Platform-filtered copies
rebuild the manifest index, so digest equality alone can't detect them — the
pinned tag is what makes re-runs idempotent.

### Tests / dry-run

```bash
./scripts/test-transform.sh   # dry-run over config/target-images.txt, no network
```

The **Test** workflow runs shellcheck plus this dry-run on every push/PR.

Any registry is supported (Docker Hub, GHCR, gcr.io, lscr.io, private registries, etc.).
