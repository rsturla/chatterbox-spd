# Chatterbox TTS for Speech Dispatcher
# Development Makefile

.PHONY: help build build-cpu build-cuda install install-user uninstall \
        lint lint-python lint-shell validate validate-packit test clean start stop logs rpm

# Default target
help:
	@echo "Chatterbox TTS for Speech Dispatcher"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Build targets:"
	@echo "  build         Build container image (auto-detect GPU)"
	@echo "  build-cpu     Build CPU-only container image"
	@echo "  build-cuda    Build CUDA container image"
	@echo ""
	@echo "Install targets:"
	@echo "  install       Install as system service"
	@echo "  install-user  Install as user service (recommended)"
	@echo "  uninstall     Remove installation"
	@echo ""
	@echo "Development targets:"
	@echo "  lint          Run all linters"
	@echo "  lint-python   Run Python linter (ruff)"
	@echo "  lint-shell    Run shell script linter (shellcheck)"
	@echo "  validate      Validate container and quadlet files"
	@echo "  validate-packit  Validate Packit configuration"
	@echo "  test          Build and run basic tests"
	@echo ""
	@echo "Service targets:"
	@echo "  start         Start the service"
	@echo "  stop          Stop the service"
	@echo "  restart       Restart the service"
	@echo "  logs          View service logs"
	@echo "  status        Check service status"
	@echo ""
	@echo "Cleanup targets:"
	@echo "  clean         Remove build artifacts"
	@echo "  clean-all     Remove build artifacts and container images"
	@echo ""
	@echo "Package targets:"
	@echo "  rpm           Build RPM package in container"

# Build targets
build:
	./install.sh --build

build-cpu:
	./install.sh --build --cpu

build-cuda:
	./install.sh --build --gpu

# Install targets
install:
	./install.sh --build

install-user:
	./install.sh --user --build

uninstall:
	./install.sh --uninstall

# Linting (runs inside containers for reproducibility)
lint: lint-python lint-shell

lint-python:
	@echo "==> Linting Python files..."
	podman run --rm --security-opt label=disable \
		-v $(PWD):/src:ro -w /src \
		docker.io/pipelinecomponents/ruff:latest \
		ruff check --no-cache bin/chatterbox-tts-client bin/chatterbox-tts-daemon
	@echo "Python linting passed!"

lint-shell:
	@echo "==> Linting shell scripts..."
	podman run --rm --security-opt label=disable --entrypoint=shellcheck \
		-v $(PWD):/mnt:ro \
		docker.io/koalaman/shellcheck:stable \
		/mnt/install.sh
	@echo "Shell linting passed!"

# Local linting (uses host tools if available)
lint-local: lint-python-local lint-shell-local

lint-python-local:
	@echo "==> Linting Python files (local)..."
	@command -v ruff >/dev/null 2>&1 || { echo "ruff not installed. Run: pip install ruff"; exit 1; }
	ruff check bin/
	@echo "Python linting passed!"

lint-shell-local:
	@echo "==> Linting shell scripts (local)..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed."; exit 1; }
	shellcheck install.sh container/build.sh
	@echo "Shell linting passed!"

# Validation
validate:
	@echo "==> Validating Containerfile..."
	podman build --layers=false --no-cache \
		-f container/Containerfile \
		--build-arg DEVICE=cpu \
		--target base \
		. >/dev/null
	@echo "Containerfile validation passed!"
	@echo ""
	@echo "==> Validating Quadlet files..."
	@mkdir -p /tmp/quadlet-test
	@cp container/*.container /tmp/quadlet-test/
	@if command -v /usr/libexec/podman/quadlet >/dev/null 2>&1; then \
		/usr/libexec/podman/quadlet --dryrun --user 2>&1 | head -20 || true; \
	else \
		echo "Quadlet binary not available, skipping validation"; \
	fi
	@rm -rf /tmp/quadlet-test
	@echo "Quadlet validation complete!"

validate-packit:
	@echo "==> Validating Packit configuration..."
	podman run --rm --security-opt label=disable \
		-v $(PWD):/src:ro -w /src \
		quay.io/packit/packit:latest \
		packit validate
	@echo "Packit configuration valid!"

# Testing
test: lint validate
	@echo "==> Running integration test..."
	@echo "Building container..."
	./install.sh --build --cpu 2>&1 | tail -5
	@echo ""
	@echo "Testing client help..."
	python3 bin/chatterbox-tts-client --help >/dev/null
	@echo "Client help works!"
	@echo ""
	@echo "All tests passed!"

# Service management
start:
	systemctl --user start chatterbox-tts

stop:
	systemctl --user stop chatterbox-tts

restart:
	systemctl --user restart chatterbox-tts

logs:
	journalctl --user -u chatterbox-tts -f

status:
	systemctl --user status chatterbox-tts

# Cleanup
clean:
	rm -f *.tar *.tar.gz *.tar.zst
	rm -f *.wav *.mp3
	rm -rf __pycache__ bin/__pycache__
	rm -rf .ruff_cache

clean-all: clean
	-podman rmi localhost/chatterbox-tts:latest 2>/dev/null
	-podman rmi localhost/chatterbox-tts:cpu 2>/dev/null
	-podman rmi localhost/chatterbox-tts:cuda 2>/dev/null

# Development helpers
shell:
	podman run --rm -it --entrypoint=/bin/bash localhost/chatterbox-tts:latest

run-daemon:
	podman run --rm -it \
		-v $(XDG_RUNTIME_DIR)/chatterbox-tts:/run/chatterbox:z \
		-v ~/.cache/chatterbox-spd/voices:/app/voices:z \
		localhost/chatterbox-tts:latest \
		--socket /run/chatterbox/chatterbox-tts.sock

ping:
	@python3 bin/chatterbox-tts-client --ping && echo "Daemon is running" || echo "Daemon not responding"

# RPM build (runs in Fedora container)
VERSION := 0.1.0
RPMDIR := $(PWD)/rpmbuild

rpm:
	@echo "==> Building RPM in Fedora 43 container..."
	@mkdir -p $(RPMDIR)
	podman run --rm --security-opt label=disable \
		-v $(PWD):/src:ro \
		-v $(RPMDIR):/output:z \
		registry.fedoraproject.org/fedora:43 \
		bash -c ' \
			set -e && \
			dnf install -y rpm-build rpmdevtools > /dev/null 2>&1 && \
			rpmdev-setuptree && \
			cp /src/chatterbox-spd.spec ~/rpmbuild/SPECS/ && \
			mkdir -p /tmp/chatterbox-spd-$(VERSION) && \
			cp -r /src/bin /src/config /src/container /src/README.md /src/LICENSE ~/rpmbuild/SOURCES/ && \
			cp -r /src/bin /src/config /src/container /src/README.md /src/LICENSE /tmp/chatterbox-spd-$(VERSION)/ && \
			cd /tmp && tar -czf ~/rpmbuild/SOURCES/chatterbox-spd-$(VERSION).tar.gz chatterbox-spd-$(VERSION) && \
			rpmbuild -ba ~/rpmbuild/SPECS/chatterbox-spd.spec && \
			cp ~/rpmbuild/RPMS/noarch/*.rpm /output/ && \
			cp ~/rpmbuild/SRPMS/*.rpm /output/ \
		'
	@echo ""
	@echo "==> RPM packages built:"
	@ls -la $(RPMDIR)/*.rpm
