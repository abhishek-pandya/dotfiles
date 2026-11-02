# dotfiles

Personal shell configuration files.

## Contents
- `.bashrc` — Bash configuration, includes the Warp "Auto-Warpify" bootstrap hook.
- `.zshrc` — Zsh configuration, includes the Warp "Auto-Warpify" bootstrap hook.

## Install
Run `bash install.sh` during environment setup to install packages and configure
tools. The installer requires Python 3.11 or newer for updating Codex's TOML
configuration.

The installer sets Codex full-access defaults (`approval_policy = "never"` and
`sandbox_mode = "danger-full-access"`) in `${CODEX_HOME:-$HOME/.codex}/config.toml`,
preserving other settings. It also defaults to `gpt-6-astra` with medium reasoning,
enables Vim mode in the CLI composer, and disables CLI startup update checks.
Update Codex through your environment's package management or `codex update`.
These apply to new sessions unless overridden by
project settings, profiles, launch options, or organization requirements.

Symlink (or copy) the files into your home directory:

```bash
ln -s "$(pwd)/.bashrc" ~/.bashrc
ln -s "$(pwd)/.zshrc" ~/.zshrc
```

The Auto-Warpify block enables Warp features (blocks, completions, etc.) when
connecting to this machine over SSH from Warp. It only runs in interactive
shells.
