#!/usr/bin/env bash
set -e

if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Set default shell to zsh
  sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

  # Append source lines to rc files (idempotent)
  grep -qxF "source ~/dotfiles/.bashrc" ~/.bashrc || echo "source ~/dotfiles/.bashrc" >> ~/.bashrc
  grep -qxF "source ~/dotfiles/.zshrc" ~/.zshrc   || echo "source ~/dotfiles/.zshrc"  >> ~/.zshrc
fi
