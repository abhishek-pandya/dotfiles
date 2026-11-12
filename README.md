# dotfiles

Personal shell configuration and coding-agent skills.

## AI skills

The [skills marketplace](ai/README.md) includes pstack from `cursor/plugins` and
a personal plugin for Claude Code and Codex. Your own skills skeleton lives under
`ai/plugin/`. See that guide for local installation and environment setup.

`install.sh` calls `install-skills.sh` to install `pstack@abhi` for Claude Code
and Codex when available. Run `bash install-skills.sh` for skills-only setup.
Reruns skip enabled installations; missing agents print a skip message.

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
It also marks `/workspaces/obsidian` as trusted so Codex can load that repository's
settings without asking for folder trust on each new environment.

When Codex is on PATH, the installer registers the `warpdotdev/codex-warp`
marketplace and installs `warp@codex-warp` for Warp terminal notifications.
Already installed and enabled plugins are skipped. Restart Codex after installation.
The plugin's `jq` dependency is included in both package lists.

The `.zshrc` wraps `codex` with `--dangerously-bypass-hook-trust` and
`--dangerously-bypass-approvals-and-sandbox`. This skips hook trust review,
including for new or changed hooks, and disables command approvals and sandboxing
for shell launches. Run `command codex` to skip the wrapper; the installed Codex
configuration defaults still apply.

Symlink (or copy) the files into your home directory:

```bash
ln -s "$(pwd)/.bashrc" ~/.bashrc
ln -s "$(pwd)/.zshrc" ~/.zshrc
```

The Auto-Warpify block enables Warp features (blocks, completions, etc.) when
connecting to this machine over SSH from Warp. It only runs in interactive
shells.
