# docker-image-mover

Sync Docker images from any registry to your own.

## Setup

Add these **Repository Secrets**:

| Secret | Description | Example |
|--------|-------------|---------|
| `REGISTRY_HOST` | Target registry host with port | `g.bmio.net:19443` |
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

Only the last segment of the image name is kept:

- `pgvector/pgvector:pg18` → `g.bmio.net:19443/base/pgvector:pg18`
- `postgres:15-alpine` → `g.bmio.net:19443/base/postgres:15-alpine`
