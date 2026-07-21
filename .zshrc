
# Ona-specific setup
if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Ona secrets
  [[ -f /etc/profile.d/ona-secrets.sh ]] && source /etc/profile.d/ona-secrets.sh

  # Auto-Warpify
  [[ "$-" == *i* ]] && printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "'"$(uname)"'" }}\x9c'
fi
