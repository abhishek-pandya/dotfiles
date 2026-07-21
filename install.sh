#!/usr/bin/env bash
set -e

if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source line to rc file (idempotent)
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc || echo "source ~/dotfiles/.zshrc" >> ~/.zshrc
fi
