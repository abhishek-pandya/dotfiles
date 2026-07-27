#!/usr/bin/env bash
set -e

# Set GitHub CLI default editor to vim
command -v gh &>/dev/null && gh config set editor vim

if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source line to rc file (idempotent)
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc || echo "source ~/dotfiles/.zshrc" >> ~/.zshrc
fi
