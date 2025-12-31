# Chatterbox TTS for Speech Dispatcher

[![CI](https://github.com/rsturla/chatterbox-spd/actions/workflows/ci.yml/badge.svg)](https://github.com/rsturla/chatterbox-spd/actions/workflows/ci.yml)
[![Container Build](https://github.com/rsturla/chatterbox-spd/actions/workflows/build-container.yml/badge.svg)](https://github.com/rsturla/chatterbox-spd/actions/workflows/build-container.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Integrate [Chatterbox TTS](https://github.com/resemble-ai/chatterbox) from Resemble AI with Linux Speech Dispatcher using Podman Quadlets.

> **Chatterbox** is a state-of-the-art open-source TTS model that outperforms ElevenLabs in side-by-side evaluations. It supports voice cloning from just 10 seconds of audio.

## Features

- High-quality neural TTS powered by Chatterbox (350M-500M parameters)
- Models baked into container image - no download on first use
- Voice cloning support (provide a 10-second reference clip)
- Container-based - no pip install required on host
- Native systemd integration via Podman Quadlets
- GPU acceleration with NVIDIA CUDA (optional)
- CPU-only mode for systems without GPU

## Quick Start

### Using Pre-built Container Images

```bash
# Clone the repository
git clone https://github.com/rsturla/chatterbox-spd.git
cd chatterbox-spd

# Install (pulls container from GHCR)
./install.sh --user

# Start the service
systemctl --user enable --now chatterbox-tts

# Test it
spd-say -o chatterbox "Hello from Chatterbox!"
```

### Building Locally

```bash
# Requires HuggingFace token for model download during build
# Get one at: https://huggingface.co/settings/tokens
export HF_TOKEN="your_token_here"

# Build and install
./install.sh --user --build

# For GPU support
./install.sh --user --build --gpu
```

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Podman | 4.4+ | For Quadlet support |
| speech-dispatcher | any | For TTS integration |
| Audio player | any | aplay, paplay, pw-play, or mpv |
| NVIDIA GPU | optional | For GPU acceleration |
| nvidia-container-toolkit | optional | Provides CUDA to container |

### GPU Setup (Optional)

The container image does **NOT** bundle NVIDIA CUDA libraries. This avoids CUDA redistribution licensing issues. CUDA is injected at runtime from your host by nvidia-container-toolkit.

```bash
# Install nvidia-container-toolkit
sudo dnf install nvidia-container-toolkit  # Fedora/RHEL
sudo apt install nvidia-container-toolkit  # Debian/Ubuntu

# Generate CDI spec (required on newer systems)
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Usage

### Basic Speech

```bash
# Via speech-dispatcher
spd-say -o chatterbox "Hello world"

# Via client directly
echo "Hello world" | chatterbox-tts-client
chatterbox-tts-client --text "Hello world"

# Save to file instead of playing
chatterbox-tts-client --text "Hello world" --output hello.wav
```

### Voice Cloning

1. Add a 10-second WAV reference clip:

```bash
mkdir -p ~/.cache/chatterbox-spd/voices
cp my_voice.wav ~/.cache/chatterbox-spd/voices/alice.wav
```

2. Update `/etc/speech-dispatcher/modules/chatterbox.conf`:

```
AddVoice "en" "FEMALE1" "alice"
```

3. Use the voice:

```bash
spd-say -o chatterbox -y FEMALE1 "Hello, I sound like Alice now"
```

### Paralinguistic Tags (Turbo model)

The Turbo model supports non-speech sounds:

```bash
spd-say -o chatterbox "[laugh] That's hilarious!"
spd-say -o chatterbox "I'm not sure... [sigh] let me think."
```

## Container Images

Pre-built images are available from GitHub Container Registry:

```bash
# CUDA/GPU version (recommended if you have NVIDIA GPU)
podman pull ghcr.io/rsturla/chatterbox-spd:latest-cuda

# CPU-only version
podman pull ghcr.io/rsturla/chatterbox-spd:latest-cpu

# Latest (defaults to CUDA)
podman pull ghcr.io/rsturla/chatterbox-spd:latest
```

### Available Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable (CUDA) |
| `latest-cuda` | Latest with CUDA support |
| `latest-cpu` | Latest CPU-only |
| `v1.0.0-cuda` | Specific version with CUDA |
| `v1.0.0-cpu` | Specific version CPU-only |
| `main-cuda` | Latest from main branch (CUDA) |
| `main-cpu` | Latest from main branch (CPU) |

## Managing the Service

```bash
# Check status
systemctl --user status chatterbox-tts

# View logs
journalctl --user -u chatterbox-tts -f

# Restart
systemctl --user restart chatterbox-tts

# Stop
systemctl --user stop chatterbox-tts

# Disable
systemctl --user disable chatterbox-tts
```

## Configuration

### Environment Variables

The client supports these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CHATTERBOX_SOCKET` | `$XDG_RUNTIME_DIR/chatterbox-tts/chatterbox-tts.sock` | Socket path |
| `CHATTERBOX_VOICE` | `default` | Voice name |
| `CHATTERBOX_EXAGGERATION` | `0.5` | Emotion exaggeration (0.0-1.0) |
| `CHATTERBOX_CFG_WEIGHT` | `0.5` | CFG weight (0.0-1.0) |
| `CHATTERBOX_PLAYER` | `auto` | Audio player |

### Speech Dispatcher Module Config

The module configuration is at `/etc/speech-dispatcher/modules/chatterbox.conf`. Key settings:

```
# Add custom voices
AddVoice "en" "MALE1" "default"
AddVoice "en" "FEMALE1" "alice"    # Uses ~/.cache/chatterbox-spd/voices/alice.wav

# Adjust text chunk size
GenericMaxChunkLength 10000
```

## Project Structure

```
chatterbox-spd/
├── .github/
│   ├── workflows/
│   │   ├── build-container.yml  # Build and push to GHCR
│   │   ├── ci.yml               # Linting and validation
│   │   └── release.yml          # GitHub releases
│   └── dependabot.yml           # Dependency updates
├── bin/
│   ├── chatterbox-tts-daemon    # TTS daemon (runs in container)
│   └── chatterbox-tts-client    # Client (runs on host)
├── config/
│   └── chatterbox.conf          # Speech-dispatcher module config
├── container/
│   ├── Containerfile            # Container build file
│   ├── chatterbox-tts.container       # Quadlet (CPU)
│   └── chatterbox-tts-cuda.container  # Quadlet (GPU)
├── install.sh                   # Installation script
├── Makefile                     # Development tasks
├── LICENSE                      # MIT License
├── CONTRIBUTING.md              # Contribution guide
└── README.md
```

## Architecture

```
┌─────────────────────┐     ┌──────────────────────┐
│  speech-dispatcher  │────▶│ sd_generic module    │
└─────────────────────┘     └──────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │ chatterbox-tts-client│ (host)
                            └──────────────────────┘
                                      │
                                      ▼ Unix Socket
┌─────────────────────────────────────────────────────────────┐
│                    Podman Container (Quadlet)                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ chatterbox-tts-daemon                                 │   │
│  │   - Chatterbox TTS model (baked in)                  │   │
│  │   - PyTorch + torchaudio                             │   │
│  │   - CUDA support (via nvidia-container-toolkit)      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │    Audio Player      │ (host)
                            └──────────────────────┘
```

## Troubleshooting

### Service won't start

```bash
# Check logs
journalctl --user -u chatterbox-tts -f

# Verify Quadlet generation
/usr/libexec/podman/quadlet --dryrun --user

# Check if container image exists
podman images | grep chatterbox
```

### GPU not working

```bash
# Verify NVIDIA GPU access on host
nvidia-smi

# Check nvidia-container-toolkit
rpm -q nvidia-container-toolkit  # Fedora/RHEL
dpkg -l nvidia-container-toolkit  # Debian/Ubuntu

# Generate CDI spec
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Test container GPU access
podman run --rm --device nvidia.com/gpu=all \
    --security-opt=label=disable \
    docker.io/nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi
```

### No audio output

```bash
# Check available audio players
which aplay paplay pw-play mpv

# Test client directly
echo "test" | chatterbox-tts-client

# Check if socket exists
ls -la $XDG_RUNTIME_DIR/chatterbox-tts/
```

### Module not loading in speech-dispatcher

```bash
# Check module is listed
spd-say -O

# Verify config file permissions (should be 644)
ls -la /etc/speech-dispatcher/modules/chatterbox.conf

# Check speechd.conf has the module
grep chatterbox /etc/speech-dispatcher/speechd.conf
```

## Uninstalling

```bash
# Uninstall everything
./install.sh --uninstall

# Also remove container images
podman rmi ghcr.io/rsturla/chatterbox-spd:latest-cuda
podman rmi ghcr.io/rsturla/chatterbox-spd:latest-cpu

# Remove cached voices
rm -rf ~/.cache/chatterbox-spd
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

This project integrates with [Chatterbox TTS](https://github.com/resemble-ai/chatterbox) from Resemble AI, which is also MIT licensed.

## Acknowledgments

- [Resemble AI](https://www.resemble.ai/) for creating Chatterbox TTS
- The [Speech Dispatcher](https://freebsoft.org/speechd) project
- The Podman team for Quadlet support
