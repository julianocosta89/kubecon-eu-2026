#!/usr/bin/env bash
set -euo pipefail

WEAVER_IMAGE="otel/weaver:v0.21.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_DIR="$SCRIPT_DIR/model"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
OUTPUT_DIR="$SCRIPT_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "==> Generating Java attribute constants..."
docker run --rm \
  --mount "type=bind,source=$REGISTRY_DIR,target=/registry,readonly" \
  --mount "type=bind,source=$TEMPLATES_DIR,target=/templates,readonly" \
  --mount "type=bind,source=$OUTPUT_DIR,target=/output" \
  "$WEAVER_IMAGE" \
  registry generate \
    --registry /registry \
    --templates /templates \
    java /output

echo "==> Generating JavaScript attribute constants..."
docker run --rm \
  --mount "type=bind,source=$REGISTRY_DIR,target=/registry,readonly" \
  --mount "type=bind,source=$TEMPLATES_DIR,target=/templates,readonly" \
  --mount "type=bind,source=$OUTPUT_DIR,target=/output" \
  "$WEAVER_IMAGE" \
  registry generate \
    --registry /registry \
    --templates /templates \
    js /output

echo "==> Generating Markdown documentation..."
docker run --rm \
  --mount "type=bind,source=$REGISTRY_DIR,target=/registry,readonly" \
  --mount "type=bind,source=$TEMPLATES_DIR,target=/templates,readonly" \
  --mount "type=bind,source=$OUTPUT_DIR,target=/output" \
  "$WEAVER_IMAGE" \
  registry generate \
    --registry /registry \
    --templates /templates \
    markdown /output

echo ""
echo "Done! Generated files:"
ls -1 "$OUTPUT_DIR"
