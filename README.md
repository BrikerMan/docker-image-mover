# docker-image-mover

## Registry Mirror Configuration

### Required Secrets:
- `NEW_REGISTRY_BASE`: Target registry base URL (e.g. `registry.example.com`)
- `TARGET_REG_USER`: Target registry username
- `TARGET_REG_PASSWORD`: Target registry password

### Usage Example:
```bash
# For image: abc/nginx:1234
# Target becomes: NEW_REGISTRY_BASE/abc-nginx:1234

curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/{owner}/{repo}/actions/workflows/image-mirror.yml/dispatches \
  -d '{"ref":"main", "inputs":{"source_image":"abc/nginx:1234"}}'
