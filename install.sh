#!/usr/bin/env bash
set -eo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# macOS: install everything declared in the Brewfile.
install_macos() {
  log "Installing packages from Brewfile..."
  brew bundle --file "$DOTFILES/Brewfile"
}

# eza isn't in Ubuntu's default repos, so add its official apt repo. Only
# called when eza is actually missing, since adding a repo forces an apt update.
# Best-effort: called via `|| log`, so a failure here doesn't abort the run.
setup_eza_repo() {
  local list="/etc/apt/sources.list.d/gierens.list"
  [[ -f "$list" ]] && return
  command -v curl &>/dev/null || { log "curl missing; skipping eza apt repo"; return; }
  log "Adding eza apt repository..."
  command -v gpg &>/dev/null || sudo env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y gpg </dev/null
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  # Never register the repo with a missing/empty key: apt would then fail — and
  # slowly retry — on every future update.
  [[ -s /etc/apt/keyrings/gierens.gpg ]] \
    || { log "eza key fetch failed; not adding repo"; return 1; }
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    | sudo tee "$list" >/dev/null
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg "$list"
}

# apt ships neovim 0.9.5 and drags in ~14 extra packages (python3-pynvim,
# python3-greenlet, xclip, luajit). The official static tarball is a single
# download from a fast CDN and tracks the current release, so prefer it.
NVIM_RELEASE="stable"
install_neovim() {
  command -v nvim &>/dev/null && return
  command -v curl &>/dev/null || { log "curl missing; skipping neovim"; return; }

  local asset
  case "$(uname -m)" in
    x86_64)        asset="nvim-linux-x86_64.tar.gz" ;;
    aarch64|arm64) asset="nvim-linux-arm64.tar.gz" ;;
    *) log "No neovim tarball for $(uname -m); skipping."; return ;;
  esac

  log "Installing neovim ($NVIM_RELEASE)..."
  local tmp
  tmp="$(mktemp -d)"
  if curl -fsSL --retry 3 --connect-timeout 10 \
      "https://github.com/neovim/neovim/releases/download/$NVIM_RELEASE/$asset" \
      -o "$tmp/nvim.tar.gz"; then
    sudo mkdir -p /opt/nvim
    sudo tar -xzf "$tmp/nvim.tar.gz" -C /opt/nvim --strip-components=1
    sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  else
    log "neovim download failed; skipping."
  fi
  rm -rf "$tmp"
}

# Ona (Ubuntu): install whatever from apt-packages.txt isn't already present.
#
# The archive.ubuntu.com mirror reachable from Ona can crawl at ~20-70 kB/s with
# 60s timeouts, so this path is written to touch apt as little as possible: skip
# packages already on PATH, refresh the package lists at most once, and do all
# remaining installs in a single invocation (one download session, one dep
# resolution, one round of dpkg triggers).
install_ona() {
  local line pkg bin missing=()

  while IFS= read -r line; do
    line="${line%%#*}"                # strip comments
    line="${line//[[:space:]]/}"       # strip all whitespace
    [[ -z "$line" ]] && continue
    pkg="${line%%:*}"                  # `git-delta:delta` -> git-delta
    bin="${line#*:}"                   # `git-delta:delta` -> delta; `fzf` -> fzf
    command -v "$bin" &>/dev/null || missing+=("$pkg")
  done < "$DOTFILES/apt-packages.txt"

  if ((${#missing[@]})); then
    log "Installing apt packages: ${missing[*]}"
    # Adding a repo invalidates the package lists, so do it before the update.
    if [[ " ${missing[*]} " == *" eza "* ]]; then
      setup_eza_repo || log "eza apt repo setup failed; eza may not install"
    fi
    sudo apt-get update -y </dev/null || true
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" \
      </dev/null || log "apt could not install one or more of: ${missing[*]}"
  else
    log "All apt packages already present."
  fi

  install_neovim

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
  git config --global delta.dark false
  git config --global delta.light true
  git config --global delta.side-by-side true
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

configure_codex() {
  log "Configuring Codex defaults..."
  python3 - "${CODEX_HOME:-$HOME/.codex}/config.toml" <<'PY'
import json
import pathlib
import sys
import tomllib

path = pathlib.Path(sys.argv[1])
original = path.read_text() if path.exists() else ""
settings = tomllib.loads(original)
defaults = {
    "approval_policy": "never",
    "sandbox_mode": "danger-full-access",
    "model": "gpt-6-astra",
    "model_reasoning_effort": "medium",
    "check_for_update_on_startup": False,
}
kept = []
statement = ""
in_table = False
in_tui = False
vim_written = False
trusted_project = "/workspaces/obsidian"
in_project = False
trust_written = False
for line in original.splitlines(keepends=True):
    statement += line
    try:
        parsed = tomllib.loads(statement)
    except tomllib.TOMLDecodeError:
        continue
    if statement.lstrip().startswith("["):
        in_table = True
        in_tui = parsed == {"tui": {}}
        in_project = parsed == {"projects": {trusted_project: {}}}
        kept.append(statement)
        if in_project:
            if not statement.endswith("\n"):
                kept.append("\n")
            kept.append('trust_level = "trusted"\n')
            trust_written = True
        if in_tui:
            if not statement.endswith("\n"):
                kept.append("\n")
            kept.append("vim_mode_default = true\n")
            vim_written = True
    elif in_project and "trust_level" in parsed:
        pass
    elif in_tui and "vim_mode_default" in parsed:
        pass
    elif not in_table and set(parsed) == {"tui"} and set(parsed["tui"]) == {"vim_mode_default"}:
        pass
    elif in_table or not defaults.keys() & parsed.keys():
        kept.append(statement)
    statement = ""

updated = "".join(f'{key} = {json.dumps(value)}\n' for key, value in defaults.items())
updated += "".join(kept)
if not vim_written:
    updated += "\n[tui]\nvim_mode_default = true\n"
if not trust_written:
    updated += f'\n[projects.{json.dumps(trusted_project)}]\ntrust_level = "trusted"\n'
expected = settings | defaults
expected["tui"] = settings.get("tui", {}) | {"vim_mode_default": True}
projects = settings.get("projects", {})
expected["projects"] = projects | {
    trusted_project: projects.get(trusted_project, {}) | {"trust_level": "trusted"}
}
# Verify that only the requested defaults changed before touching the file.
if statement or tomllib.loads(updated) != expected:
    raise SystemExit("Could not safely update Codex config; existing file unchanged.")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(updated)
PY
}

configure_codex_plugins() {
  if ! command -v codex &>/dev/null; then
    log "Codex not installed; skipping plugins. Rerun install.sh after installing Codex."
    return
  fi
  local marketplaces plugins
  marketplaces="$(codex plugin marketplace list --json)"
  if ! jq -e '.marketplaces | any(.name == "codex-warp")' <<< "$marketplaces" >/dev/null; then
    codex plugin marketplace add warpdotdev/codex-warp
  fi
  plugins="$(codex plugin list --json)"
  if jq -e '.installed | any(.pluginId == "warp@codex-warp" and .enabled)' <<< "$plugins" >/dev/null; then
    log "Warp Codex plugin already installed and enabled."
    return
  fi
  log "Installing Warp Codex plugin..."
  codex plugin add warp@codex-warp
  plugins="$(codex plugin list --json)"
  jq -e '.installed | any(.pluginId == "warp@codex-warp" and .enabled)' <<< "$plugins" >/dev/null
}

# Set GitHub CLI default editor to nvim.
configure_gh() {
  command -v gh &>/dev/null || return
  log "Setting gh default editor to nvim..."
  gh config set editor nvim
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  install_macos
elif [[ "${IS_ON_ONA:-}" == "true" ]]; then
  install_ona
else
  log "Not macOS and not Ona; skipping package install."
fi

configure_delta
configure_claude
configure_codex
configure_codex_plugins
configure_gh

if [[ "${IS_ON_ONA:-}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source line to rc file (idempotent)
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc || echo "source ~/dotfiles/.zshrc" >> ~/.zshrc
fi

if ! bash "$DOTFILES/install-skills.sh"; then
  log "WARNING: Pstack setup failed; dotfiles setup is complete. Retry with: bash \"$DOTFILES/install-skills.sh\"" >&2
fi
