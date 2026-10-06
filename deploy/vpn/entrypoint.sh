#!/usr/bin/env bash

set -Eeuo pipefail

export DISPLAY=:0
easyconnect_dir=/usr/share/sangfor/EasyConnect
public_update_host=download.sangfor.com.cn

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
# Docker keeps /tmp in the container writable layer across restarts. Xvfb can
# therefore leave these files behind after an abrupt stop and then refuse to
# start on the next VPN login attempt.
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

# CUC currently publishes Linux 7.6.7.3, while the generic Sangfor update
# catalog bundled with that package advertises 7.6.7.7 and forces every
# version <= 7.6.7.6 to update. That contradictory catalog blocks the CUC
# login screen even though the installed client matches CUC's own metadata.
# Keep the campus gateway reachable and disable only the generic updater.
if ! grep -qE "[[:space:]]${public_update_host}([[:space:]]|$)" /etc/hosts; then
  printf '127.0.0.1 %s\n::1 %s\n' \
    "$public_update_host" "$public_update_host" >>/etc/hosts
fi
rm -f "$easyconnect_dir/resources/conf/pkg_version.xml"

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp &
sleep 1
x11vnc -display "$DISPLAY" -forever -shared -localhost -rfbport 5900 -nopw &
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 &

"$easyconnect_dir/resources/bin/EasyMonitor" >/tmp/easy-monitor.log 2>&1 &
sleep 2

cd "$easyconnect_dir"
exec runuser -u easyconnect -- env DISPLAY="$DISPLAY" \
  "$easyconnect_dir/EasyConnect" https://vpn.cuc.edu.cn
