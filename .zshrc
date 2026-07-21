
# Auto-Warpify
[[ "$-" == *i* ]] && printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "'"$(uname)"'" }}\x9c'

# Ona-specific setup
if [[ "${IS_ON_ONA}" == "true" ]] && [[ -f /etc/profile.d/ona-secrets.sh ]]; then
  source /etc/profile.d/ona-secrets.sh
fi
