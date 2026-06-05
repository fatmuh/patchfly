#!/usr/bin/env bash
# Patchfly CLI installer for macOS and Linux.
#
# Usage:
#   curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.sh -sSf | bash
#
# Options (via env vars):
#   PATCHFLY_VERSION    Specific version to install (default: latest)
#   PATCHFLY_INSTALL    Install location (default: ~/.patchfly/bin)
#   PATCHFLY_REPO       GitHub repo (default: fatmuh/patchfly)

set -euo pipefail

REPO="${PATCHFLY_REPO:-fatmuh/patchfly}"
BINARY_NAME="patchfly"
INSTALL_DIR="${PATCHFLY_INSTALL:-$HOME/.patchfly/bin}"
VERSION="${PATCHFLY_VERSION:-latest}"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info()    { printf "${BOLD}==>${RESET} %s\n" "$*"; }
success() { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}!${RESET} %s\n" "$*" >&2; }
error()   { printf "${RED}✗${RESET} %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Detect OS and arch
# ---------------------------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux)  OS="linux" ;;
  darwin) OS="macos" ;;
  *) error "Unsupported OS: $OS"; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) error "Unsupported arch: $ARCH"; exit 1 ;;
esac

ASSET="${BINARY_NAME}-${OS}-${ARCH}"
info "Detected: ${OS}/${ARCH}"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  info "Resolving latest version..."
  if command -v curl >/dev/null 2>&1; then
    VERSION=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" \
              | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  elif command -v wget >/dev/null 2>&1; then
    VERSION=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
              | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  fi
  if [ -z "$VERSION" ]; then
    warn "Could not resolve latest version (no releases yet or no network)."
    VERSION="0.0.0-source"
  else
    success "Latest version: v$VERSION"
  fi
else
  info "Requested version: v$VERSION"
fi

# ---------------------------------------------------------------------------
# Set up temp dir
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"
INSTALLED=false

# ---------------------------------------------------------------------------
# Try downloading prebuilt binary from GitHub Releases
# ---------------------------------------------------------------------------
if [ "$VERSION" != "0.0.0-source" ]; then
  RELEASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"
  info "Trying prebuilt binary: $RELEASE_URL"

  HTTP_CODE="000"
  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -sSL -w "%{http_code}" -o "$TMP/$ASSET" "$RELEASE_URL" 2>/dev/null || echo "000")
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -O "$TMP/$ASSET" "$RELEASE_URL" 2>/dev/null; then
      HTTP_CODE="200"
    fi
  fi

  if [ "$HTTP_CODE" = "200" ] && [ -s "$TMP/$ASSET" ]; then
    success "Downloaded prebuilt binary ($(du -h "$TMP/$ASSET" | cut -f1))"
    mv "$TMP/$ASSET" "$TMP/$BINARY_NAME"
    INSTALLED=true
  else
    warn "Prebuilt binary not available (HTTP $HTTP_CODE)"
  fi
fi

# ---------------------------------------------------------------------------
# Fallback: build from source
# ---------------------------------------------------------------------------
if [ "$INSTALLED" = false ]; then
  info "Falling back to build-from-source..."

  if ! command -v dart >/dev/null 2>&1; then
    error "Dart SDK not found. Install from https://dart.dev/get-dart"
    error "Or wait for the first official release."
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    error "git not found. Install git or wait for the first official release."
    exit 1
  fi

  info "Cloning $REPO..."
  git clone --depth 1 "https://github.com/${REPO}.git" "$TMP/repo" 2>&1 | tail -1

  info "Building with Dart SDK..."
  ( cd "$TMP/repo/cli" && dart pub get && dart compile exe bin/patchfly.dart -o "$TMP/$BINARY_NAME" )

  success "Built from source ($(du -h "$TMP/$BINARY_NAME" | cut -f1))"
  INSTALLED=true
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if [ "$INSTALLED" = true ]; then
  mkdir -p "$INSTALL_DIR"
  chmod +x "$TMP/$BINARY_NAME"
  mv -f "$TMP/$BINARY_NAME" "$BINARY_PATH"
  success "Installed to: $BINARY_PATH"
fi

# ---------------------------------------------------------------------------
# PATH setup
# ---------------------------------------------------------------------------
PATH_LINE="export PATH=\"\$PATH:$INSTALL_DIR\""

# Detect shell rc file
SHELL_RC=""
case "${SHELL:-/bin/bash}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac

# Check if already in PATH
case ":$PATH:" in
  *":$INSTALL_DIR:"*) in_path=true ;;
  *) in_path=false ;;
esac

echo ""
if [ "$in_path" = true ]; then
  success "Already in PATH — you can run: $BINARY_NAME --version"
else
  warn "Not in PATH yet. To finish installation, add this to your shell:"
  echo ""
  printf "  ${BOLD}%s${RESET}\n" "$PATH_LINE"
  echo ""
  if [ -n "$SHELL_RC" ] && [ -w "$SHELL_RC" ] && ! grep -qF "$INSTALL_DIR" "$SHELL_RC" 2>/dev/null; then
    printf "  Auto-add to %s? [y/N] " "$SHELL_RC"
    read -r REPLY
    if [ "${REPLY:-n}" = "y" ] || [ "${REPLY:-n}" = "Y" ]; then
      echo "" >> "$SHELL_RC"
      echo "# Patchfly CLI" >> "$SHELL_RC"
      echo "$PATH_LINE" >> "$SHELL_RC"
      success "Added to $SHELL_RC — restart your shell or: source $SHELL_RC"
    fi
  fi
fi

echo ""
info "Verify installation:"
echo "  $BINARY_PATH --version"
echo ""
info "Quick start:"
echo "  patchfly register --email you@example.com --password yourpass"
echo "  patchfly apps create --slug com.example.app --name \"My App\""
echo "  patchfly patch"
