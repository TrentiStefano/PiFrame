#!/usr/bin/env bash
set -euo pipefail

version="${1:?Usage: package-linux-deb.sh <version>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid Debian package version: $version" >&2
  exit 1
}

bundle="apps/pi_frame/build/linux/x64/release/bundle"
web="apps/pi_frame/build/web"
daemon="apps/agentd/dist/pi-agentd.cjs"
node_bin="$(command -v node)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

app_dir="$stage/opt/pi-frame"
install -d "$app_dir" "$stage/usr/share/applications"
cp -a "$bundle/." "$app_dir/"
install -m 0755 "$node_bin" "$app_dir/node"
install -m 0644 "$(dirname "$(dirname "$node_bin")")/LICENSE" "$app_dir/NODE-LICENSE.txt"
install -m 0644 "$daemon" "$app_dir/pi-agentd.cjs"
# The daemon serves the web build for remote phone/browser access.
cp -R "$web" "$app_dir/web"

cat > "$stage/usr/share/applications/pi-frame.desktop" <<'EOF'
[Desktop Entry]
Name=PiFrame
Comment=Desktop interface for Pi Coding Agent
Exec=/opt/pi-frame/pi_frame
Terminal=false
Type=Application
Categories=Development;IDE;
EOF

control="$stage/DEBIAN"
install -d "$control"
cat > "$control/control" <<EOF
Package: pi-frame
Version: $version
Section: devel
Priority: optional
Architecture: amd64
Maintainer: PiFrame contributors <piframe@users.noreply.github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libblkid1 | libblkid1t64, liblzma5, libstdc++6
Description: Desktop interface for Pi Coding Agent
 PiFrame includes its local daemon and Node.js runtime.
EOF

[[ -x "$app_dir/pi_frame" ]]
[[ -x "$app_dir/node" ]]
[[ -s "$app_dir/NODE-LICENSE.txt" ]]
[[ -s "$app_dir/pi-agentd.cjs" ]]
[[ -s "$app_dir/web/index.html" ]]
node --check "$app_dir/pi-agentd.cjs"
mkdir -p dist
package="dist/PiFrame-${version}-linux-amd64.deb"
dpkg-deb --build --root-owner-group "$stage" "$package"
dpkg-deb --field "$package" Package Version Architecture
