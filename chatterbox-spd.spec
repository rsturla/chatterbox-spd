Name:           chatterbox-spd
Version:        0.1.0
Release:        1%{?dist}
Summary:        Chatterbox TTS integration for Speech Dispatcher

License:        MIT
URL:            https://github.com/rsturla/chatterbox-spd
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

Requires:       speech-dispatcher
Requires:       podman >= 4.4
Requires:       python3 >= 3.10

Recommends:     alsa-utils
Recommends:     pipewire-utils

%description
Chatterbox TTS integration for Linux Speech Dispatcher using Podman Quadlets.

Chatterbox is a state-of-the-art open-source TTS model from Resemble AI that
supports voice cloning from just 10 seconds of audio. This package provides
the client and configuration to use Chatterbox with speech-dispatcher.

The TTS model runs in a container, pulled automatically on first use.

%prep
%autosetup

%build
# Nothing to build - pure scripts and config

%install
# Client script
install -Dm755 bin/chatterbox-tts-client %{buildroot}%{_bindir}/chatterbox-tts-client

# Speech-dispatcher module config
install -Dm644 config/chatterbox.conf %{buildroot}%{_sysconfdir}/speech-dispatcher/modules/chatterbox.conf

# Drop-in config for AddModule
install -Dm644 config/modules.d/chatterbox.conf %{buildroot}%{_sysconfdir}/speech-dispatcher/modules.d/chatterbox.conf

# Quadlet files
install -Dm644 container/chatterbox-tts.container %{buildroot}%{_datadir}/%{name}/quadlets/chatterbox-tts.container
install -Dm644 container/chatterbox-tts-cuda.container %{buildroot}%{_datadir}/%{name}/quadlets/chatterbox-tts-cuda.container

# Note: README.md and LICENSE are handled by %doc and %license macros in %files

%post
# Add Include directive to speechd.conf if not present
if [ -f %{_sysconfdir}/speech-dispatcher/speechd.conf ]; then
    if ! grep -q 'Include "modules.d/\*.conf"' %{_sysconfdir}/speech-dispatcher/speechd.conf; then
        echo '' >> %{_sysconfdir}/speech-dispatcher/speechd.conf
        echo '# Include drop-in module configurations' >> %{_sysconfdir}/speech-dispatcher/speechd.conf
        echo 'Include "modules.d/*.conf"' >> %{_sysconfdir}/speech-dispatcher/speechd.conf
    fi
fi

# Restart speech-dispatcher to pick up changes
killall speech-dispatcher 2>/dev/null || true

echo ""
echo "Chatterbox TTS installed successfully!"
echo ""
echo "To set up the service, run as your user:"
echo "  mkdir -p ~/.config/containers/systemd"
echo "  cp %{_datadir}/%{name}/quadlets/chatterbox-tts.container ~/.config/containers/systemd/"
echo "  # Or for CUDA: cp %{_datadir}/%{name}/quadlets/chatterbox-tts-cuda.container ~/.config/containers/systemd/chatterbox-tts.container"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now chatterbox-tts"
echo ""
echo "Then test with: spd-say -o chatterbox 'Hello world'"
echo ""

%postun
# Restart speech-dispatcher to pick up changes
killall speech-dispatcher 2>/dev/null || true

%files
%license LICENSE
%doc README.md
%{_bindir}/chatterbox-tts-client
%config(noreplace) %{_sysconfdir}/speech-dispatcher/modules/chatterbox.conf
%config(noreplace) %{_sysconfdir}/speech-dispatcher/modules.d/chatterbox.conf
%{_datadir}/%{name}/quadlets/chatterbox-tts.container
%{_datadir}/%{name}/quadlets/chatterbox-tts-cuda.container
%dir %{_datadir}/%{name}
%dir %{_datadir}/%{name}/quadlets

%changelog
* Tue Dec 31 2024 Robert Sturla <rsturla@redhat.com> - 0.1.0-1
- Initial package
