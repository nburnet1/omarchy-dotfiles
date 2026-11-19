#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME"
PACKAGES=(hypr omarchy bash nvim)

if ! command -v stow >/dev/null 2>&1; then
  echo "Error: GNU stow is required but not installed." >&2
  echo "Install it (e.g. on Arch: sudo pacman -S stow) and re-run." >&2
  exit 1
fi

backup_if_conflicting() {
  local path="$1"
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    local backup="${path}.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing path: $path -> $backup"
    mv -- "$path" "$backup"
  elif [ -L "$path" ]; then
    # If it's already a symlink into this repo, leave it; otherwise back it up.
    local link_target
    link_target="$(readlink -f "$path" || true)"
    case "$link_target" in
      "$REPO_DIR"/*) : ;;
      *)
        local backup="${path}.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing symlink: $path -> $backup"
        mv -- "$path" "$backup"
        ;;
    esac
  fi
}

echo "Installing omarchy dotfiles from: $REPO_DIR"
mkdir -p "$TARGET/.config"

# Back up real/conflicting targets for managed config dirs
backup_if_conflicting "$TARGET/.config/hypr"
backup_if_conflicting "$TARGET/.config/omarchy"
backup_if_conflicting "$TARGET/.bashrc"
backup_if_conflicting "$TARGET/.config/nvim"

cd "$REPO_DIR"
stow -v -R -t "$TARGET" "${PACKAGES[@]}"

if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  echo "Reloading Hyprland..."
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Done."
