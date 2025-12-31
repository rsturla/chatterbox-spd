#!/bin/bash
#
# Chatterbox TTS for Speech Dispatcher - Container Installation Script
#
# This script installs the containerized version of Chatterbox TTS
# using Podman Quadlets for systemd integration.
#
# No pip install required - everything runs in a container.
#
# Requirements:
#   - Podman 4.4+ (for Quadlet support)
#   - speech-dispatcher (for integration)
#
# Usage:
#   ./install-container.sh [--user] [--build] [--gpu]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/usr/local"
USER_INSTALL=false
BUILD_LOCAL=false
USE_GPU=auto
UNINSTALL=false

# Container registry configuration
# Override with environment variable: CHATTERBOX_REGISTRY=ghcr.io/myuser/chatterbox-spd
REGISTRY="${CHATTERBOX_REGISTRY:-ghcr.io/rsturla/chatterbox-spd}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            USER_INSTALL=true
            shift
            ;;
        --build)
            BUILD_LOCAL=true
            shift
            ;;
        --gpu|--cuda)
            USE_GPU=true
            shift
            ;;
        --cpu)
            USE_GPU=false
            shift
            ;;
        --uninstall|--remove)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            echo "Chatterbox TTS Container Installation (Quadlet)"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --user      Install as user Quadlet (recommended)"
            echo "  --build     Build container locally instead of pulling"
            echo "  --gpu       Force GPU/CUDA mode"
            echo "  --cpu       Force CPU-only mode"
            echo "  --uninstall Remove the installation"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

check_podman_version() {
    if ! command -v podman &> /dev/null; then
        error "Podman is required for Quadlet support.\n  Install: sudo dnf install podman"
    fi

    local version major minor
    version=$(podman --version | grep -oP '\d+\.\d+' | head -1)
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)

    if [[ $major -lt 4 ]] || [[ $major -eq 4 && $minor -lt 4 ]]; then
        error "Podman 4.4+ required for Quadlet support. Found: $version"
    fi

    success "Podman $version (Quadlet supported)"
}

detect_gpu() {
    if [[ "$USE_GPU" == "true" ]]; then
        echo "cuda"
        return
    fi

    if [[ "$USE_GPU" == "false" ]]; then
        echo "cpu"
        return
    fi

    # Auto-detect
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "cuda"
    else
        echo "cpu"
    fi
}

check_dependencies() {
    info "Checking dependencies..."

    check_podman_version

    local gpu_mode
    gpu_mode=$(detect_gpu)

    if [[ "$gpu_mode" == "cuda" ]]; then
        success "GPU mode: CUDA"

        # Check for NVIDIA container toolkit
        if rpm -q nvidia-container-toolkit &> /dev/null 2>&1 || \
           dpkg -l nvidia-container-toolkit &> /dev/null 2>&1; then
            success "NVIDIA container toolkit found"
        else
            warn "NVIDIA container toolkit not found. GPU may not work."
            warn "Install: sudo dnf install nvidia-container-toolkit"
        fi
    else
        info "GPU mode: CPU (no NVIDIA GPU detected or --cpu specified)"
    fi

    # Check speech-dispatcher
    if command -v speech-dispatcher &> /dev/null; then
        success "speech-dispatcher found"
    else
        warn "speech-dispatcher not found. Install it for full integration."
    fi

    # Check audio player
    local player_found=false
    for player in aplay paplay pw-play mpv; do
        if command -v $player &> /dev/null; then
            success "Audio player: $player"
            player_found=true
            break
        fi
    done
    if ! $player_found; then
        warn "No audio player found. Install aplay, paplay, or mpv."
    fi
}

install_client() {
    info "Installing client script..."

    if [[ $EUID -ne 0 ]] && [[ "$INSTALL_PREFIX" == "/usr/local" ]]; then
        sudo install -m 755 "$SCRIPT_DIR/bin/chatterbox-tts-client" "$INSTALL_PREFIX/bin/"
    else
        install -m 755 "$SCRIPT_DIR/bin/chatterbox-tts-client" "$INSTALL_PREFIX/bin/"
    fi

    success "Client installed to $INSTALL_PREFIX/bin/chatterbox-tts-client"
}

build_image() {
    local gpu_mode token_file
    gpu_mode=$(detect_gpu)

    info "Building container image locally (mode: $gpu_mode)..."

    # Check for HuggingFace token
    if [[ -z "${HF_TOKEN:-}" ]]; then
        if [[ -f "$HOME/.cache/huggingface/token" ]]; then
            HF_TOKEN=$(cat "$HOME/.cache/huggingface/token")
            export HF_TOKEN
            info "Using HuggingFace token from ~/.cache/huggingface/token"
        else
            warn "No HuggingFace token found."
            warn "Either set HF_TOKEN environment variable or run 'huggingface-cli login' first."
            warn "Get a token at: https://huggingface.co/settings/tokens"
            error "Build requires HF_TOKEN to download models."
        fi
    fi

    # Write token to temp file for secret mount
    token_file=$(mktemp)
    echo -n "$HF_TOKEN" > "$token_file"
    chmod 600 "$token_file"

    # Build with secret (token not stored in image layers)
    podman build \
        --secret id=hf_token,src="$token_file" \
        --build-arg "DEVICE=$gpu_mode" \
        -t "chatterbox-tts:$gpu_mode" \
        -t "chatterbox-tts:latest" \
        -f "$SCRIPT_DIR/container/Containerfile" \
        "$SCRIPT_DIR"

    # Clean up token file
    rm -f "$token_file"

    success "Container image built: chatterbox-tts:$gpu_mode"
}

pull_image() {
    local gpu_mode tag image
    gpu_mode=$(detect_gpu)

    if [[ "$gpu_mode" == "cuda" ]]; then
        tag="cuda"
    else
        tag="latest"  # CPU is the default
    fi

    local image="$REGISTRY:$tag"

    info "Pulling container image: $image"
    info "(This may take a while on first run, ~2-3GB download)"

    if podman pull "$image"; then
        # Tag locally for quadlet to find
        podman tag "$image" "chatterbox-tts:$gpu_mode"
        podman tag "$image" "chatterbox-tts:latest"
        success "Container image pulled: $image"
    else
        warn "Failed to pull from registry. You may need to build locally:"
        warn "  ./install.sh --build"
        warn ""
        warn "Or check if you need to authenticate:"
        warn "  podman login ghcr.io"
        error "Image pull failed"
    fi
}

install_quadlet() {
    local gpu_mode quadlet_src quadlet_dir
    gpu_mode=$(detect_gpu)

    info "Installing Podman Quadlet..."

    # Choose the right quadlet file
    if [[ "$gpu_mode" == "cuda" ]]; then
        quadlet_src="$SCRIPT_DIR/container/chatterbox-tts-cuda.container"
    else
        quadlet_src="$SCRIPT_DIR/container/chatterbox-tts.container"
    fi

    if $USER_INSTALL; then
        quadlet_dir="$HOME/.config/containers/systemd"
        mkdir -p "$quadlet_dir"
        cp "$quadlet_src" "$quadlet_dir/chatterbox-tts.container"

        # Reload systemd to pick up the Quadlet
        systemctl --user daemon-reload

        success "Quadlet installed to $quadlet_dir/chatterbox-tts.container"

        echo ""
        info "To start: systemctl --user start chatterbox-tts"
        info "To enable on boot: systemctl --user enable chatterbox-tts"
        info "To check status: systemctl --user status chatterbox-tts"
    else
        quadlet_dir="/etc/containers/systemd"
        if [[ $EUID -ne 0 ]]; then
            sudo mkdir -p "$quadlet_dir"
            sudo cp "$quadlet_src" "$quadlet_dir/chatterbox-tts.container"
            sudo systemctl daemon-reload
        else
            mkdir -p "$quadlet_dir"
            cp "$quadlet_src" "$quadlet_dir/chatterbox-tts.container"
            systemctl daemon-reload
        fi

        success "Quadlet installed to $quadlet_dir/chatterbox-tts.container"

        echo ""
        info "To start: sudo systemctl start chatterbox-tts"
        info "To enable on boot: sudo systemctl enable chatterbox-tts"
    fi
}

install_speechd_config() {
    info "Installing speech-dispatcher configuration..."

    local spd_modules_dir="/etc/speech-dispatcher/modules"
    local spd_modules_d="/etc/speech-dispatcher/modules.d"
    local spd_conf="/etc/speech-dispatcher/speechd.conf"

    # Ensure modules directory exists
    if [[ ! -d "$spd_modules_dir" ]]; then
        sudo mkdir -p "$spd_modules_dir"
    fi

    # Install module config (GenericExecuteSynth, voices, etc.)
    sudo install -m 644 "$SCRIPT_DIR/config/chatterbox.conf" "$spd_modules_dir/"
    success "Module config installed to $spd_modules_dir/chatterbox.conf"

    # Create drop-in directory for AddModule statements
    if [[ ! -d "$spd_modules_d" ]]; then
        sudo mkdir -p "$spd_modules_d"
    fi

    # Install drop-in config (AddModule statement)
    sudo install -m 644 "$SCRIPT_DIR/config/modules.d/chatterbox.conf" "$spd_modules_d/"
    success "Drop-in config installed to $spd_modules_d/chatterbox.conf"

    # Ensure speechd.conf includes the drop-in directory
    if [[ -f "$spd_conf" ]]; then
        if ! grep -q 'Include "modules.d/\*.conf"' "$spd_conf"; then
            info "Adding modules.d include to $spd_conf..."
            echo '' | sudo tee -a "$spd_conf" > /dev/null
            echo '# Include drop-in module configurations' | sudo tee -a "$spd_conf" > /dev/null
            echo 'Include "modules.d/*.conf"' | sudo tee -a "$spd_conf" > /dev/null
            success "Include directive added to speechd.conf"
        else
            success "Drop-in directory already configured in speechd.conf"
        fi
    else
        warn "speechd.conf not found at $spd_conf"
        warn "Manually add: Include \"modules.d/*.conf\""
    fi

    # Restart speech-dispatcher to pick up changes
    if pgrep -x speech-dispatcher > /dev/null; then
        info "Restarting speech-dispatcher..."
        killall speech-dispatcher 2>/dev/null || true
        sleep 1
    fi
}

create_directories() {
    mkdir -p "$HOME/.cache/chatterbox-spd/voices"
    mkdir -p "$HOME/.cache/chatterbox-spd/models"

    # Create socket directory in XDG_RUNTIME_DIR
    local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
    mkdir -p "$runtime_dir/chatterbox-tts"

    success "Cache directories created"
    info "Socket will be at: $runtime_dir/chatterbox-tts/chatterbox-tts.sock"
}

uninstall() {
    info "Uninstalling Chatterbox TTS Quadlet installation..."

    # Stop and disable services
    systemctl --user stop chatterbox-tts 2>/dev/null || true
    systemctl --user disable chatterbox-tts 2>/dev/null || true
    sudo systemctl stop chatterbox-tts 2>/dev/null || true
    sudo systemctl disable chatterbox-tts 2>/dev/null || true

    # Remove Quadlet files
    rm -f "$HOME/.config/containers/systemd/chatterbox-tts.container"
    sudo rm -f /etc/containers/systemd/chatterbox-tts.container 2>/dev/null || true

    # Remove client
    sudo rm -f "$INSTALL_PREFIX/bin/chatterbox-tts-client"

    # Remove speech-dispatcher config files
    sudo rm -f /etc/speech-dispatcher/modules/chatterbox.conf 2>/dev/null || true
    sudo rm -f /etc/speech-dispatcher/modules.d/chatterbox.conf 2>/dev/null || true
    rm -f "$HOME/.config/speech-dispatcher/modules/chatterbox.conf" 2>/dev/null || true
    success "Speech-dispatcher config files removed"

    # Reload systemd
    systemctl --user daemon-reload 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true

    success "Uninstallation complete"

    echo ""
    warn "Container images and cached models were not removed."
    warn "To remove them:"
    echo "  podman rmi chatterbox-tts:latest chatterbox-tts:cuda chatterbox-tts:cpu"
    echo "  rm -rf ~/.cache/chatterbox-spd"
}

main() {
    echo ""
    echo "=========================================================="
    echo " Chatterbox TTS for Speech Dispatcher (Quadlet Container)"
    echo "=========================================================="
    echo ""

    if $UNINSTALL; then
        uninstall
        exit 0
    fi

    check_dependencies
    echo ""

    if $BUILD_LOCAL; then
        build_image
        echo ""
    else
        pull_image
        echo ""
    fi

    install_client
    echo ""

    install_quadlet
    echo ""

    install_speechd_config
    echo ""

    create_directories
    echo ""

    echo "=========================================================="
    success "Installation complete!"
    echo "=========================================================="
    echo ""
    info "Quick start:"
    if $USER_INSTALL; then
        echo "  1. Start the service:"
        echo "     systemctl --user start chatterbox-tts"
        echo ""
        echo "  2. Enable on boot:"
        echo "     systemctl --user enable chatterbox-tts"
        echo ""
        echo "  3. Check logs:"
        echo "     journalctl --user -u chatterbox-tts -f"
    else
        echo "  1. Start the service:"
        echo "     sudo systemctl start chatterbox-tts"
        echo ""
        echo "  2. Enable on boot:"
        echo "     sudo systemctl enable chatterbox-tts"
        echo ""
        echo "  3. Check logs:"
        echo "     sudo journalctl -u chatterbox-tts -f"
    fi
    echo ""
    echo "  4. Test speech:"
    echo "     spd-say -o chatterbox 'Hello from Chatterbox!'"
    echo ""
}

main
