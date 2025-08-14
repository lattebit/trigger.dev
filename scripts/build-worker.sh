IMAGE=ghcr.io/lattebit/supervisor

# 自动生成不可变标签：2025-08-14_1015-abc123
DATE=$(date -u +%Y%m%d_%H%M)
SHA=$(git rev-parse --short HEAD)
AUTO_TAG="${DATE}-${SHA}"

# 构建并同时推 latest 和 自动标签
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f apps/supervisor/Containerfile \
  -t $IMAGE:latest \
  -t $IMAGE:${AUTO_TAG} \
  --push .