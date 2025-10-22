#!/bin/bash
set -euo pipefail

# build-and-push.sh - CI script that mimics "app build --push" functionality
# Requires: OCI_REGISTRY environment variable
# Requires: VERSION environment variable

# Validate required environment variables
if [[ -z "${OCI_REGISTRY:-}" ]]; then
    echo "Error: OCI_REGISTRY environment variable is required"
    echo "Example: export OCI_REGISTRY=harbor.example.com/my-project"
    exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
    echo "Error: VERSION environment variable required"
    exit 1
fi

if [[ -z "${APP_NAME:-}" ]]; then
    echo "Error: APP_NAME environment variable required"
    exit 1
fi

# Check required tools
for tool in docker helm flux git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: $tool is required but not installed"
        exit 1
    fi
done

echo "App: $APP_NAME"
echo "Registry: $OCI_REGISTRY"
echo "Version: $VERSION"
echo ""

# Create build directories
BUILD_DIR="./cicd-oci-build"
mkdir -p "${BUILD_DIR}"/{chart,flux}

# Get git info for flux
BRANCH=$(git branch --show-current)
SHORT_SHA=$(git rev-parse --short HEAD)
LONG_SHA=$(git rev-parse HEAD)
SOURCE=$(git config --get remote.origin.url || "")

IMAGE_TAG="${APP_NAME}:${VERSION}"

# Build and push Docker image (if configured)
if [[ -n "$DOCKERFILE_PATH" ]]; then
    echo "🐳 Building Docker image: $IMAGE_TAG"
    docker build -f "$DOCKERFILE_PATH" -t "$IMAGE_TAG" .

    echo "📤 Pushing Docker image..."
    FULL_IMAGE_TAG="${OCI_REGISTRY}/images/${IMAGE_TAG}"
    docker tag "$IMAGE_TAG" "$FULL_IMAGE_TAG"
    docker push "$FULL_IMAGE_TAG"
    echo "✅ Docker image pushed: $FULL_IMAGE_TAG"
    echo ""
else
    echo "⏭️  Skipping Docker build - no dockerfile configured"
    echo ""
fi

# Build and push Helm chart (if configured)
if [[ -n "$HELM_CHART_PARENT_DIR" ]]; then
    HELM_CHART_PATH="${HELM_CHART_PARENT_DIR}/${APP_NAME}"
    echo "⚓ Linting Helm chart: $HELM_CHART_PATH"
    helm lint "$HELM_CHART_PATH"

    echo "📦 Packaging and pushing Helm chart..."
    helm package "$HELM_CHART_PATH" --version "$VERSION" --app-version "$VERSION" --destination "${BUILD_DIR}/chart"
    CHART_FILE="${BUILD_DIR}/chart/${APP_NAME}-${VERSION}.tgz"
    helm push "$CHART_FILE" "oci://${OCI_REGISTRY}/charts"
    echo "✅ Helm chart pushed to: oci://${OCI_REGISTRY}/charts"
    echo ""
else
    echo "⏭️  Skipping Helm chart build - no chart configured"
    echo ""
fi

# Build and push Flux artifact (if configured)
if [[ -n "$FLUX_BUNDLE_PATH" ]]; then
    echo "🌊 Copying and pushing Flux bundle..."
    FLUX_DIR="${BUILD_DIR}/flux/${APP_NAME}-${VERSION}"

    # Remove existing directory if it exists
    if [[ -d "$FLUX_DIR" ]]; then
        rm -rf "$FLUX_DIR"
    fi

    # Copy flux bundle directory to build directory
    cp -r "$FLUX_BUNDLE_PATH" "$FLUX_DIR"

    FLUX_REPO_URL="oci://${OCI_REGISTRY}/flux/${APP_NAME}"
    FLUX_TAG="${FLUX_REPO_URL}:${SHORT_SHA}"

    echo "Pushing flux artifact..."
    flux push artifact "$FLUX_TAG" --path="$FLUX_DIR" --source="$SOURCE" --revision="${BRANCH}@sha1:${LONG_SHA}"
    flux tag artifact "$FLUX_TAG" --tag "$VERSION"
    echo "✅ Flux artifact pushed: ${FLUX_REPO_URL}:${VERSION}"
    echo ""
else
    echo "⏭️  Skipping Flux build - no flux bundle configured"
    echo ""
fi

echo "🎉 Build and push completed successfully!"
echo "Registry: $OCI_REGISTRY"
echo "Version: $VERSION"
echo "App: $APP_NAME"
echo ""
echo "Artifacts saved to: $BUILD_DIR"

