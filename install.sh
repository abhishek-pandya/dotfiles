#!/usr/bin/env bash
set -eo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# macOS: install everything declared in the Brewfile.
install_macos() {
  log "Installing packages from Brewfile..."
  brew bundle --file "$DOTFILES/Brewfile"
}

# eza isn't in Ubuntu's default repos, so add its official apt repo.
# Best-effort: called via `|| log`, so a failure here doesn't abort the run.
setup_eza_repo() {
  local list="/etc/apt/sources.list.d/gierens.list"
  [[ -f "$list" ]] && return
  command -v curl &>/dev/null || { log "curl missing; skipping eza apt repo"; return; }
  log "Adding eza apt repository..."
  sudo apt-get install -y gpg
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    | sudo tee "$list" >/dev/null
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg "$list"
}

# Ona (Ubuntu): install the apt package list.
install_ona() {
  log "Installing apt packages..."
  sudo apt-get update -y || true
  setup_eza_repo || log "eza apt repo setup failed; skipping eza"
  sudo apt-get update -y || true

  local pkg
  while read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    sudo apt-get install -y "$pkg" || log "apt could not install '$pkg'; skipping"
  done < "$DOTFILES/apt-packages.txt"

  # On Debian/Ubuntu the bat binary is installed as 'batcat'; expose it as 'bat'.
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
}

# Point git at delta for diffs, paging, and merge conflicts.
configure_delta() {
  command -v delta &>/dev/null || return
  log "Configuring git to use delta..."
  git config --global core.pager delta
  git config --global interactive.diffFilter 'delta --color-only'
  git config --global delta.navigate true
  git config --global delta.dark true
  git config --global merge.conflictStyle zdiff3
}

# Default Claude Code to bypass-permissions mode (equivalent to
# --dangerously-skip-permissions). Merges into any existing settings.
configure_claude() {
  log "Enabling Claude Code bypass-permissions mode..."
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  if command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    if [[ -f "$settings" ]]; then
      jq '.permissions.defaultMode = "bypassPermissions"' "$settings" > "$tmp"
    else
      echo '{}' | jq '.permissions.defaultMode = "bypassPermissions"' > "$tmp"
    fi
    mv "$tmp" "$settings"
  elif [[ ! -f "$settings" ]]; then
    cat > "$settings" <<'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF
  else
    echo "jq not found and $settings exists; set permissions.defaultMode to \"bypassPermissions\" manually." >&2
  fi
}

# Set GitHub CLI default editor to nvim
command -v gh &>/dev/null && gh config set editor nvim

if [[ "$(uname -s)" == "Darwin" ]]; then
  install_macos
elif [[ "${IS_ON_ONA:-}" == "true" ]]; then
  install_ona
else
  log "Not macOS and not Ona; skipping package install."
fi

configure_delta
configure_claude

if [[ "${IS_ON_ONA:-}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source line to rc file (idempotent)
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc || echo "source ~/dotfiles/.zshrc" >> ~/.zshrc
fi
