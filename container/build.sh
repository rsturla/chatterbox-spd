#!/bin/bash
#
# Build Chatterbox TTS container images
#
# Usage:
#   ./build.sh              # Build both CPU and CUDA images
#   ./build.sh cpu          # Build CPU-only image
#   ./build.sh cuda         # Build CUDA image
#   ./build.sh --push       # Build and push to registry
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-chatterbox-spd/chatterbox-tts}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"
PUSH=false
PLATFORMS="linux/amd64"

# Detect container runtime
if command -v podman &> /dev/null; then
    RUNTIME="podman"
else
    RUNTIME="docker"
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# Parse arguments
TARGETS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        cpu|cuda)
            TARGETS+=("$1")
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"
            shift 2
            ;;
        --help|-h)
            echo "Build Chatterbox TTS container images"
            echo ""
            echo "Usage: $0 [cpu|cuda] [--push] [--registry URL]"
            echo ""
            echo "Targets:"
            echo "  cpu     Build CPU-only image (smaller, no GPU required)"
            echo "  cuda    Build CUDA-enabled image (requires NVIDIA GPU)"
            echo ""
            echo "Options:"
            echo "  --push      Push images to registry after building"
            echo "  --registry  Registry URL (default: ghcr.io)"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build both images"
            echo "  $0 cpu                # Build CPU image only"
            echo "  $0 cuda --push        # Build and push CUDA image"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default to both targets if none specified
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("cpu" "cuda")
fi

# Build function
build_image() {
    local device=$1
    local tag="${FULL_IMAGE}:${device}"
    local local_tag="chatterbox-tts:${device}"

    info "Building $device image..."
    info "Tag: $tag"

    $RUNTIME build \
        --build-arg "DEVICE=$device" \
        -t "$local_tag" \
        -t "$tag" \
        -f "$SCRIPT_DIR/Containerfile" \
        "$PROJECT_DIR"

    success "Built: $tag"

    if $PUSH; then
        info "Pushing $tag..."
        $RUNTIME push "$tag"
        success "Pushed: $tag"
    fi
}

# Main
echo ""
echo "=================================="
echo " Chatterbox TTS Container Builder"
echo "=================================="
echo ""
info "Runtime: $RUNTIME"
info "Registry: $REGISTRY"
info "Targets: ${TARGETS[*]}"
echo ""

for target in "${TARGETS[@]}"; do
    build_image "$target"
    echo ""
done

# Tag latest
if [[ " ${TARGETS[*]} " =~ " cuda " ]]; then
    info "Tagging cuda as latest..."
    $RUNTIME tag "chatterbox-tts:cuda" "chatterbox-tts:latest"
    $RUNTIME tag "${FULL_IMAGE}:cuda" "${FULL_IMAGE}:latest"

    if $PUSH; then
        $RUNTIME push "${FULL_IMAGE}:latest"
    fi
elif [[ " ${TARGETS[*]} " =~ " cpu " ]]; then
    info "Tagging cpu as latest..."
    $RUNTIME tag "chatterbox-tts:cpu" "chatterbox-tts:latest"
    $RUNTIME tag "${FULL_IMAGE}:cpu" "${FULL_IMAGE}:latest"

    if $PUSH; then
        $RUNTIME push "${FULL_IMAGE}:latest"
    fi
fi

echo ""
success "Build complete!"
echo ""
echo "Local images:"
$RUNTIME images | grep chatterbox-tts | head -10
echo ""
echo "To run:"
echo "  chatterbox-container start"
echo ""
