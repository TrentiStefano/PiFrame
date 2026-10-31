#!/usr/bin/env bash
set -euo pipefail

# Ensure script runs from repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Check OS: macOS is required for native macos compilation and hdiutil
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: macOS packaging requires macOS (Darwin) with Xcode and hdiutil." >&2
  echo "Apple SDKs and Cocoa frameworks cannot be built on Windows or Linux." >&2
  exit 1
fi

skip_build=0
force_build=0
version=""
arch=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      skip_build=1
      shift
      ;;
    --build)
      force_build=1
      shift
      ;;
    *)
      if [[ -z "$version" ]]; then
        version="$1"
      elif [[ -z "$arch" ]]; then
        arch="$1"
      fi
      shift
      ;;
  esac
done

# Resolve version from package.json if not specified
if [[ -z "$version" ]]; then
  if [[ -f package.json ]]; then
    version="$(node -p 'require("./package.json").version' 2>/dev/null || true)"
  fi
fi

if [[ -z "$version" ]]; then
  echo "Error: Version not specified and could not be determined from package.json" >&2
  exit 1
fi

# Resolve architecture if not specified
if [[ -z "$arch" ]]; then
  m="$(uname -m)"
  if [[ "$m" == "arm64" || "$m" == "aarch64" ]]; then
    arch="arm64"
  else
    arch="x64"
  fi
fi

app="apps/pi_frame/build/macos/Build/Products/Release/pi_frame.app"
daemon="apps/agentd/dist/pi-agentd.cjs"
web_index="apps/pi_frame/build/web/index.html"

needs_build=0
if [[ "$force_build" -eq 1 ]]; then
  needs_build=1
elif [[ "$skip_build" -eq 0 ]]; then
  if [[ ! -d "$app" || ! -f "$daemon" || ! -f "$web_index" ]]; then
    needs_build=1
  fi
fi

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi

  # 1. Probe user login shell PATH (e.g. zsh, bash)
  if [[ -n "${SHELL:-}" ]]; then
    login_path="$("$SHELL" -l -c 'printf "%s" "$PATH"' 2>/dev/null || true)"
    if [[ -n "$login_path" ]]; then
      export PATH="$PATH:$login_path"
    fi
  fi

  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi

  # 2. Check well-known macOS installation paths for Flutter SDK
  for candidate in \
    "$HOME/flutter/bin" \
    "$HOME/development/flutter/bin" \
    "$HOME/Development/flutter/bin" \
    "$HOME/Developer/flutter/bin" \
    "$HOME/src/flutter/bin" \
    "$HOME/.flutter/bin" \
    "$HOME/fvm/default/bin" \
    "$HOME/.fvm/default/bin" \
    "/opt/homebrew/bin" \
    "/usr/local/bin" \
    /opt/homebrew/Caskroom/flutter/*/flutter/bin \
    /usr/local/Caskroom/flutter/*/flutter/bin; do
    if [[ -x "$candidate/flutter" ]]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done

  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi

  echo "" >&2
  echo "================================================================================" >&2
  echo " ERRORE: Flutter SDK non trovato nel PATH" >&2
  echo "================================================================================" >&2
  echo "Per compilare l'applicazione desktop macOS e la web app da sorgente è" >&2
  echo "necessario avere Flutter installato su questo Mac." >&2
  echo "" >&2
  echo "• Se hai già installato Flutter sul Mac:" >&2
  echo "    Assicurati che sia presente nel PATH nel file ~/.zshrc (o ~/.zprofile):" >&2
  echo "      export PATH=\"\$PATH:\$HOME/development/flutter/bin\"" >&2
  echo "    poi ricarica la configurazione con: source ~/.zshrc" >&2
  echo "" >&2
  echo "• Se NON hai ancora installato Flutter:" >&2
  echo "    Puoi installarlo rapidamente con Homebrew:" >&2
  echo "      brew install --cask flutter" >&2
  echo "    oppure scaricandolo dalla guida ufficiale:" >&2
  echo "      https://docs.flutter.dev/get-started/install/macos" >&2
  echo "" >&2
  echo "• Se desideri solo testare l'installer (.dmg) senza compilare da sorgenti:" >&2
  echo "    Puoi scaricare direttamente il file .dmg già pronto dalle GitHub Releases" >&2
  echo "    o dalla scheda Actions del repository." >&2
  echo "================================================================================" >&2
  echo "" >&2
  return 1
}

if [[ "$needs_build" -eq 1 ]]; then
  ensure_flutter

  echo "=== Building PiFrame components for macOS v${version} (${arch}) ==="
  echo "1. Building protocol and agentd bundle..."
  pnpm --filter @piframe/pcp-ts run build
  pnpm --filter @piframe/agentd run build:bundle

  echo "2. Building Flutter web app (for remote daemon access)..."
  (cd apps/pi_frame && flutter build web --release --no-web-resources-cdn --dart-define="PI_FRAME_VERSION=${version}")

  echo "3. Building Flutter macOS application..."
  (cd apps/pi_frame && flutter build macos --release --dart-define="PI_FRAME_VERSION=${version}")
fi

if [[ ! -d "$app" ]]; then
  echo "Error: macOS application bundle not found at $app" >&2
  exit 1
fi

echo "=== Packaging PiFrame macOS DMG v${version} (${arch}) ==="
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/dmg

cp "$daemon" "$app/Contents/MacOS/pi-agentd.cjs"
node_bin="$(command -v node)"
cp "$node_bin" "$app/Contents/MacOS/node"
cp "$(dirname "$(dirname "$node_bin")")/LICENSE" "$app/Contents/Resources/NODE-LICENSE.txt"
chmod +x "$app/Contents/MacOS/node"

rm -rf "$app/Contents/MacOS/web"
cp -R apps/pi_frame/build/web "$app/Contents/MacOS/web"
test -s "$app/Contents/MacOS/web/index.html"

cp -R "$app" dist/dmg/PiFrame.app
codesign --force --deep --sign - dist/dmg/PiFrame.app
ln -s /Applications dist/dmg/Applications

cp "packaging/macos/LEGGIMI - Come aprire l'app.txt" dist/dmg/
cp "packaging/macos/README - How to open.txt" dist/dmg/

test -x "$app/Contents/MacOS/pi_frame"
test -x "$app/Contents/MacOS/node"
test -s "$app/Contents/MacOS/pi-agentd.cjs"
test -s "$app/Contents/MacOS/web/index.html"
test -s "$app/Contents/Resources/NODE-LICENSE.txt"
test -s "dist/dmg/LEGGIMI - Come aprire l'app.txt"
test -s "dist/dmg/README - How to open.txt"

mkdir -p dist
dmg_path="dist/PiFrame-${version}-macos-${arch}.dmg"
rm -f "$dmg_path"

echo "Creating compressed DMG image at $dmg_path..."
hdiutil create -volname 'PiFrame' -srcfolder dist/dmg -ov -format UDZO "$dmg_path"
rm -rf dist/dmg

echo "Successfully created $dmg_path"
