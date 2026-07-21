# dotfiles

Personal shell configuration files.

## Contents
- `.bashrc` — Bash configuration, includes the Warp "Auto-Warpify" bootstrap hook.
- `.zshrc` — Zsh configuration, includes the Warp "Auto-Warpify" bootstrap hook.

## Install
Symlink (or copy) the files into your home directory:

```bash
ln -s "$(pwd)/.bashrc" ~/.bashrc
ln -s "$(pwd)/.zshrc" ~/.zshrc
```

The Auto-Warpify block enables Warp features (blocks, completions, etc.) when
connecting to this machine over SSH from Warp. It only runs in interactive
shells.
