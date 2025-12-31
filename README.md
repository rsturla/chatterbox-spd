# Chatterbox TTS for Speech Dispatcher

This project integrates [Chatterbox TTS](https://huggingface.co/ResembleAI/chatterbox-turbo) from ResembleAI with Linux Speech Dispatcher using Podman Quadlets.

## Features

- High-quality neural TTS powered by Chatterbox
- Automatic model download on first use
- Voice cloning support (provide a 10-second reference clip)
- Container-based - no pip install required on host
- Native systemd integration via Podman Quadlets
- GPU acceleration with NVIDIA CUDA (optional)

## Requirements

- Podman 4.4+ (for Quadlet support)
- speech-dispatcher
- An audio player (aplay, paplay, pw-play, or mpv)
- For GPU acceleration:
  - NVIDIA GPU with driver installed
  - nvidia-container-toolkit (provides CUDA to container at runtime)
  - CDI spec generated: `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`

**Note:** The container image does NOT bundle NVIDIA CUDA libraries. This avoids
CUDA redistribution licensing issues. CUDA is injected at runtime from your host
by nvidia-container-toolkit.

## Installation

```bash
cd chatterbox-spd

# Build and install (auto-detects GPU)
./install.sh --user --build

# Or force CPU-only mode
./install.sh --user --build --cpu

# Start the service
systemctl --user enable --now chatterbox-tts

# Watch model download progress (first run only, ~2GB)
journalctl --user -u chatterbox-tts -f
```

Then add this line to `/etc/speech-dispatcher/speechd.conf`:

```
AddModule "chatterbox" "sd_generic" "chatterbox.conf"
```

And restart speech-dispatcher:

```bash
killall speech-dispatcher
```

## Usage

```bash
# Speak text using speech-dispatcher
spd-say -o chatterbox "Hello world"

# Or use the client directly
echo "Hello world" | chatterbox-tts-client
chatterbox-tts-client --text "Hello world"
```

### Voice Cloning

1. Add a 10-second WAV reference clip:

```bash
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
```

## Manual Quadlet Installation

If you prefer to install manually:

```bash
# Build the container image
podman build -t chatterbox-tts:latest -f container/Containerfile .

# For CPU-only build
podman build --build-arg DEVICE=cpu -t chatterbox-tts:cpu -f container/Containerfile .

# Install the Quadlet
mkdir -p ~/.config/containers/systemd
cp container/chatterbox-tts.container ~/.config/containers/systemd/

# For GPU support, use the CUDA variant
cp container/chatterbox-tts-cuda.container ~/.config/containers/systemd/chatterbox-tts.container

# Reload and start
systemctl --user daemon-reload
systemctl --user start chatterbox-tts
```

## File Structure

```
chatterbox-spd/
├── bin/
│   ├── chatterbox-tts-daemon   # TTS daemon (runs inside container)
│   └── chatterbox-tts-client   # Client for speech-dispatcher (runs on host)
├── config/
│   └── chatterbox.conf         # Speech-dispatcher module config
├── container/
│   ├── Containerfile           # Container build file
│   ├── chatterbox-tts.container       # Quadlet unit (CPU)
│   ├── chatterbox-tts-cuda.container  # Quadlet unit (GPU)
│   └── build.sh                # Build script for images
├── install.sh                  # Installation script
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
                                      ▼ Unix Socket (/tmp/chatterbox-tts.sock)
┌─────────────────────────────────────────────────────────────┐
│                    Podman Container (Quadlet)                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ chatterbox-tts-daemon                                 │   │
│  │   - Chatterbox TTS model                             │   │
│  │   - PyTorch + torchaudio                             │   │
│  │   - CUDA (if GPU variant)                            │   │
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
```

### GPU not working

```bash
# Verify NVIDIA GPU access on host
nvidia-smi

# Check nvidia-container-toolkit is installed
rpm -q nvidia-container-toolkit  # Fedora/RHEL
dpkg -l nvidia-container-toolkit  # Debian/Ubuntu

# Generate CDI spec (required on Fedora/newer systems)
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Test container GPU access
podman run --rm --device nvidia.com/gpu=all --security-opt=label=disable \
    docker.io/nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi

# If "Insufficient Permissions" error, also try:
podman run --rm --hooks-dir=/usr/share/containers/oci/hooks.d \
    --security-opt=label=disable docker.io/nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi
```

### No audio output

```bash
# Check audio player
which aplay paplay pw-play mpv

# Test client directly
echo "test" | chatterbox-tts-client
```

### Socket not found

```bash
# Check if socket exists
ls -la /tmp/chatterbox-tts.sock

# Verify container is running
podman ps

# Check container logs
podman logs chatterbox-tts
```

## Distributing Pre-built Images

```bash
# Build and save as tar
podman build -t chatterbox-tts:cuda --build-arg DEVICE=cuda -f container/Containerfile .
podman save chatterbox-tts:cuda | gzip > chatterbox-tts-cuda.tar.gz

# Load on target machine
podman load < chatterbox-tts-cuda.tar.gz
```

## Uninstalling

```bash
./install.sh --uninstall

# Remove container images
podman rmi chatterbox-tts:latest chatterbox-tts:cuda chatterbox-tts:cpu

# Remove cached models
rm -rf ~/.cache/chatterbox-spd
```

## License

MIT License

Chatterbox TTS is licensed by ResembleAI - see their license terms at:
https://huggingface.co/ResembleAI/chatterbox-turbo
