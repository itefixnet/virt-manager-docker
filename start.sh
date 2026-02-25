#!/usr/bin/env bash
set -euo pipefail

target_user="${CONTAINER_USER:-app}"

detect_libvirt_uri() {
  if [[ -S /var/run/libvirt/libvirt-sock ]]; then
    echo "qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock"
    return 0
  fi
  if [[ -S /var/run/libvirt/virtqemud-sock ]]; then
    echo "qemu+unix:///system?socket=/var/run/libvirt/virtqemud-sock"
    return 0
  fi
  return 1
}

if [[ "${1:-}" == "--as-user" ]]; then
  shift
elif [[ "$(id -u)" -eq 0 ]]; then
  libvirt_uri="$(detect_libvirt_uri || true)"

  if [[ -n "$libvirt_uri" ]]; then
    export LIBVIRT_URI="$libvirt_uri"
    libvirt_socket="${libvirt_uri##*socket=}"
    if [[ -S "$libvirt_socket" ]]; then
      socket_gid="$(stat -c '%g' "$libvirt_socket")"
      if ! id -G "$target_user" | tr ' ' '\n' | grep -qx "$socket_gid"; then
        group_name="$(getent group "$socket_gid" | cut -d: -f1 || true)"
        if [[ -z "$group_name" ]]; then
          group_name="libvirt-host"
          groupadd -g "$socket_gid" "$group_name" 2>/dev/null || true
        fi
        usermod -aG "$group_name" "$target_user"
      fi
    fi
  fi

  exec gosu "$target_user" "$0" --as-user "$@"
fi

export USER="$(id -un)"
export HOME="${HOME:-$(getent passwd "$USER" | cut -d: -f6)}"
export DISPLAY=:1
export XTERM_FONT="${XTERM_FONT:-Monospace}"
export XTERM_FONT_SIZE="${XTERM_FONT_SIZE:-14}"

libvirt_uri="${LIBVIRT_URI:-}"
if [[ -z "$libvirt_uri" ]]; then
  libvirt_uri="$(detect_libvirt_uri || true)"
fi

if [[ -n "$libvirt_uri" ]]; then
  export LIBVIRT_URI="$libvirt_uri"
  libvirt_socket="${libvirt_uri##*socket=}"
  if [[ -S "$libvirt_socket" ]] && [[ ! -w "$libvirt_socket" ]]; then
    echo "[start.sh] Warning: no write access to $libvirt_socket" >&2
    echo "[start.sh] Current user/groups: $(id)" >&2
    ls -ln "$libvirt_socket" >&2 || true
  fi
fi

mkdir -p "$HOME/.vnc"

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
else
  printf '%s\n' "changeme" | vncpasswd -f > "$HOME/.vnc/passwd"
fi

chmod 600 "$HOME/.vnc/passwd"

cat > "$HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

if command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax)"
fi

xrdb "$HOME/.Xresources" >/dev/null 2>&1 || true

if command -v xfwm4 >/dev/null 2>&1; then
  xfwm4 --replace >/dev/null 2>&1 &
fi

if command -v xfsettingsd >/dev/null 2>&1; then
  xfsettingsd >/dev/null 2>&1 &
fi

if command -v virt-manager >/dev/null 2>&1; then
  if [ -n "${LIBVIRT_URI:-}" ]; then
    virt-manager --connect "${LIBVIRT_URI}" >/dev/null 2>&1 &
  else
    virt-manager >/dev/null 2>&1 &
  fi
fi

exec xterm -fa "$XTERM_FONT" -fs "$XTERM_FONT_SIZE"
EOF

chmod +x "$HOME/.vnc/xstartup"

vncserver -kill :1 >/dev/null 2>&1 || true
vncserver :1 -geometry "${VNC_GEOMETRY:-1280x800}" -depth "${VNC_DEPTH:-24}" -localhost no

tail -F "$HOME/.vnc"/*.log