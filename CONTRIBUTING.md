# Contributing to Chatterbox TTS for Speech Dispatcher

Thank you for your interest in contributing! This document provides guidelines and instructions for development.

## Development Setup

### Prerequisites

- Podman 4.4+ (for Quadlet support)
- Python 3.11+
- A HuggingFace account and token (for building container images)

### Clone and Setup

```bash
git clone https://github.com/rsturla/chatterbox-spd.git
cd chatterbox-spd

# Install development dependencies (optional, for linting)
pip install ruff
```

### Building Container Images Locally

```bash
# Set your HuggingFace token
export HF_TOKEN="your_token_here"

# Build CPU variant
./install.sh --build --cpu

# Build CUDA variant
./install.sh --build --gpu

# Or use make
make build-cpu
make build-cuda
```

### Running Tests

```bash
# Lint Python code
make lint

# Validate container build (without full build)
make validate

# Run full test (builds and tests)
make test
```

## Project Structure

```
chatterbox-spd/
├── bin/                    # Executable scripts
│   ├── chatterbox-tts-daemon   # Runs inside container
│   └── chatterbox-tts-client   # Runs on host
├── config/                 # Configuration files
│   └── chatterbox.conf     # Speech-dispatcher module config
├── container/              # Container-related files
│   ├── Containerfile       # Multi-stage container build
│   ├── chatterbox-tts.container       # Quadlet (CPU)
│   └── chatterbox-tts-cuda.container  # Quadlet (GPU)
├── .github/                # GitHub configuration
│   ├── workflows/          # CI/CD workflows
│   └── dependabot.yml      # Dependency updates
├── install.sh              # Installation script
└── Makefile                # Development tasks
```

## Code Style

### Python

We use [Ruff](https://docs.astral.sh/ruff/) for Python linting and formatting:

```bash
# Check for issues
ruff check bin/

# Auto-fix issues
ruff check --fix bin/

# Format code
ruff format bin/
```

### Shell Scripts

- Use `shellcheck` for linting shell scripts
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `set -e` at the top of scripts
- Quote variables: `"$var"` not `$var`

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for multilingual model
fix: handle empty voice names correctly
docs: update GPU setup instructions
ci: add container validation step
```

## Making Changes

### Adding a New Feature

1. Create a branch: `git checkout -b feature/my-feature`
2. Make your changes
3. Add tests if applicable
4. Run linting: `make lint`
5. Test locally: `make test`
6. Commit with a descriptive message
7. Push and create a Pull Request

### Fixing a Bug

1. Create a branch: `git checkout -b fix/issue-description`
2. Write a test that reproduces the bug (if possible)
3. Fix the bug
4. Verify the fix
5. Push and create a Pull Request

### Updating Dependencies

Container base images are managed by Dependabot. For manual updates:

1. Update the `FROM` line in `container/Containerfile`
2. Test the build locally
3. Submit a PR

## Container Development

### Testing Container Changes

```bash
# Build and test interactively
podman build -t chatterbox-test -f container/Containerfile .

# Run with shell access
podman run --rm -it --entrypoint=/bin/bash chatterbox-test

# Test daemon startup
podman run --rm -it \
    -v $XDG_RUNTIME_DIR/chatterbox-tts:/run/chatterbox:z \
    chatterbox-test --socket /run/chatterbox/test.sock
```

### Quadlet Development

```bash
# Test Quadlet parsing
/usr/libexec/podman/quadlet --dryrun --user

# View generated systemd unit
cat ~/.config/containers/systemd/chatterbox-tts.container
systemctl --user cat chatterbox-tts
```

## Release Process

Releases are automated via GitHub Actions:

1. Update version references in README if needed
2. Create and push a tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. GitHub Actions will:
   - Build container images
   - Push to GHCR with version tags
   - Create a GitHub Release

## Getting Help

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing issues before creating new ones

## Code of Conduct

Be respectful and inclusive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/).
