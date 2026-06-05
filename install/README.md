# Patchfly CLI — Installer Scripts

One-line installer scripts for the Patchfly CLI, modeled after the
[Shorebird installer pattern](https://github.com/shorebirdtech/install).

## Quick Install

### macOS / Linux

```bash
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.sh -sSf | bash
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.ps1'|iex
```

## What It Does

1. **Detect platform** — OS (Linux/macOS/Windows) and CPU arch (x64/arm64)
2. **Download prebuilt binary** — from the latest GitHub Release
3. **Fallback to source** — if no release yet, clone & build with Dart SDK
4. **Install** — to `~/.patchfly/bin/patchfly` (Unix) or `%USERPROFILE%\.patchfly\bin\patchfly.exe` (Windows)
5. **Add to PATH** — automatically updates user PATH on Windows; on Unix, prompts to add to `~/.bashrc`/`~/.zshrc`

## Asset Naming Convention

Release binaries are uploaded with these names (per matrix in
`.github/workflows/release.yml`):

| Platform | Asset name |
|---|---|
| Linux x64 | `patchfly-linux-x64` |
| Linux arm64 | `patchfly-linux-arm64` |
| macOS x64 | `patchfly-macos-x64` |
| macOS arm64 | `patchfly-macos-arm64` |
| Windows x64 | `patchfly-windows-x64.exe` |

## Environment Variables

| Var | Default | Description |
|---|---|---|
| `PATCHFLY_VERSION` | `latest` | Specific version to install (e.g. `0.1.0`) |
| `PATCHFLY_INSTALL` | `~/.patchfly/bin` | Install location |
| `PATCHFLY_REPO` | `fatmuh/patchfly` | GitHub repo (for fork testing) |

## Examples

```bash
# Install specific version
curl -sSf https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.sh | PATCHFLY_VERSION=0.1.0 bash

# Install to custom location
curl -sSf https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.sh | PATCHFLY_INSTALL=/usr/local/bin bash
```

## Local Testing (no GitHub Release yet)

If no release has been published, the script will:
1. Check for `dart` and `git` in PATH
2. Clone the repo
3. Run `dart pub get && dart compile exe`
4. Install the resulting binary

This means you can use the installer today, before the first release.

## After Install

```bash
patchfly --version

patchfly register --email you@example.com --password yourpass
patchfly apps create --slug com.example.app --name "My App"
patchfly patch
```

See [`../README.md`](../README.md) for full documentation.
