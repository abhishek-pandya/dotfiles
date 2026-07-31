#!/usr/bin/env bash
set -eo pipefail

# Pinned version for the Linux git-delta download. neovim uses the "stable" tag.
DELTA_VERSION="0.18.2"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# download <url> <dest>
download() {
  if command -v curl &>/dev/null; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# Map `uname -m` to a normalized arch, or "unsupported".
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unsupported" ;;
  esac
}

install_delta() {
  if command -v delta &>/dev/null; then
    log "git-delta already installed"
    return
  fi
  log "Installing git-delta..."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    brew install git-delta
    return
  fi

  local triple tmp
  case "$(detect_arch)" in
    x86_64) triple="x86_64-unknown-linux-gnu" ;;
    arm64) triple="aarch64-unknown-linux-gnu" ;;
    *) echo "Unsupported arch for git-delta: $(uname -m)" >&2; return 1 ;;
  esac
  tmp="$(mktemp -d)"
  download "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${triple}.tar.gz" "$tmp/delta.tar.gz"
  tar -xzf "$tmp/delta.tar.gz" -C "$tmp"
  sudo install -m 0755 "$tmp/delta-${DELTA_VERSION}-${triple}/delta" /usr/local/bin/delta
  rm -rf "$tmp"
}

install_nvim() {
  if command -v nvim &>/dev/null; then
    log "neovim already installed"
    return
  fi
  log "Installing neovim..."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    brew install neovim
    return
  fi

  local arch tmp
  arch="$(detect_arch)"
  if [[ "$arch" == "unsupported" ]]; then
    echo "Unsupported arch for neovim: $(uname -m)" >&2
    return 1
  fi
  tmp="$(mktemp -d)"
  download "https://github.com/neovim/neovim/releases/download/stable/nvim-linux-${arch}.tar.gz" "$tmp/nvim.tar.gz"
  sudo rm -rf "/opt/nvim-linux-${arch}"
  sudo tar -xzf "$tmp/nvim.tar.gz" -C /opt
  sudo ln -sf "/opt/nvim-linux-${arch}/bin/nvim" /usr/local/bin/nvim
  rm -rf "$tmp"
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

# Set GitHub CLI default editor to vim
command -v gh &>/dev/null && gh config set editor vim

install_delta
install_nvim
configure_delta
configure_claude

if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source line to rc file (idempotent)
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc || echo "source ~/dotfiles/.zshrc" >> ~/.zshrc
fi
