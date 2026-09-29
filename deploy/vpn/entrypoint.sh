#!/usr/bin/env bash

set -Eeuo pipefail

export DISPLAY=:0
easyconnect_dir=/usr/share/sangfor/EasyConnect

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp &
sleep 1
x11vnc -display "$DISPLAY" -forever -shared -localhost -rfbport 5900 -nopw &
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 &

"$easyconnect_dir/resources/bin/EasyMonitor" >/tmp/easy-monitor.log 2>&1 &
sleep 2

cd "$easyconnect_dir"
exec runuser -u easyconnect -- env DISPLAY="$DISPLAY" \
  "$easyconnect_dir/EasyConnect" https://vpn.cuc.edu.cn
