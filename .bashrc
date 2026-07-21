
# Ona-specific setup
if [[ "${IS_ON_ONA}" == "true" ]]; then
  # Auto-Warpify
  [[ "$-" == *i* ]] && printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "bash", "uname": "'"$(uname)"'" }}\x9c'
fi
