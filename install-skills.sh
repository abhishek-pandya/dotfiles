#!/usr/bin/env bash
set -eo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

log() { printf '==> %s\n' "$1"; }

install_claude_skills() {
  local state marketplace_query plugin_query
  marketplace_query='
    if type != "array" then error("Expected Claude marketplace array") else . end
    | [.[] | select(.name == "abhi")]
    | if length == 0 then "absent"
      elif length == 1 and .[0].source == "directory" and .[0].path == $root then "present"
      else "conflict" end'
  plugin_query='
    if type != "array" then error("Expected Claude plugin array") else . end
    | [.[] | select(.id == "pstack@abhi" and .scope == "user")]
    | if length == 0 then "absent"
      elif length != 1 or ((.[0].errors // []) | length) > 0 then "error"
      elif .[0].enabled == true then "enabled"
      elif .[0].enabled == false then "disabled"
      else error("Expected Claude plugin enabled boolean") end'

  state="$(claude plugin marketplace list --json | jq -er --arg root "$DOTFILES" "$marketplace_query")" || return 1
  case "$state" in
    absent)
      log "Registering the dotfiles marketplace for Claude Code..."
      claude plugin marketplace add "$DOTFILES" || return 1
      state="$(claude plugin marketplace list --json | jq -er --arg root "$DOTFILES" "$marketplace_query")" || return 1
      if [[ "$state" != present ]]; then
        echo "Claude Code did not register the dotfiles marketplace; check the CLI error or organization policy above." >&2
        return 1
      fi
      ;;
    conflict)
      echo "Claude Code marketplace 'abhi' already points to another source. Resolve it with 'claude plugin marketplace list' before rerunning." >&2
      return 1
      ;;
  esac

  state="$(claude plugin list --json | jq -er "$plugin_query")" || return 1
  case "$state" in
    enabled) log "Claude Code pstack@abhi is already installed and enabled for this user."; return 0 ;;
    absent)
      log "Installing pstack@abhi for Claude Code..."
      claude plugin install pstack@abhi --scope user || return 1
      ;;
    disabled)
      log "Enabling pstack@abhi for Claude Code..."
      claude plugin enable pstack@abhi --scope user || return 1
      ;;
    error)
      echo "Claude Code reports errors for pstack@abhi. Inspect 'claude plugin list --json' before rerunning." >&2
      return 1
      ;;
  esac
  state="$(claude plugin list --json | jq -er "$plugin_query")" || return 1
  if [[ "$state" != enabled ]]; then
    echo "Claude Code pstack@abhi was not enabled after setup. Inspect 'claude plugin list --json'." >&2
    return 1
  fi
  log "Claude Code pstack@abhi is installed and enabled for this user."
}

install_codex_skills() {
  local state marketplace_query plugin_query
  marketplace_query='
    if type != "object" or (.marketplaces | type) != "array"
    then error("Expected Codex marketplaces array") else .marketplaces end
    | [.[] | select(.name == "abhi")]
    | if length == 0 then "absent"
      elif length == 1 and .[0].marketplaceSource.sourceType == "local"
        and .[0].marketplaceSource.source == $root then "present"
      else "conflict" end'
  plugin_query='
    if type != "object" or (.installed | type) != "array"
    then error("Expected Codex installed plugins array") else .installed end
    | [.[] | select(.pluginId == "pstack@abhi")]
    | if length == 0 then "absent"
      elif length != 1 or ((.[0].errors // []) | length) > 0 then "error"
      elif .[0].enabled == true then "enabled"
      elif .[0].enabled == false then "disabled"
      else error("Expected Codex plugin enabled boolean") end'

  state="$(codex plugin marketplace list --json | jq -er --arg root "$DOTFILES" "$marketplace_query")" || return 1
  case "$state" in
    absent)
      log "Registering the dotfiles marketplace for Codex..."
      codex plugin marketplace add "$DOTFILES" --json || return 1
      state="$(codex plugin marketplace list --json | jq -er --arg root "$DOTFILES" "$marketplace_query")" || return 1
      if [[ "$state" != present ]]; then
        echo "Codex did not register the dotfiles marketplace; check the CLI error above." >&2
        return 1
      fi
      ;;
    conflict)
      echo "Codex marketplace 'abhi' already points to another source. Resolve it with 'codex plugin marketplace list' before rerunning." >&2
      return 1
      ;;
  esac

  state="$(codex plugin list --json | jq -er "$plugin_query")" || return 1
  case "$state" in
    enabled) log "Codex pstack@abhi is already installed and enabled."; return 0 ;;
    absent|disabled)
      log "Installing or enabling pstack@abhi for Codex..."
      codex plugin add pstack@abhi --json || return 1
      ;;
    error)
      echo "Codex reports errors for pstack@abhi. Inspect 'codex plugin list --json' before rerunning." >&2
      return 1
      ;;
  esac
  state="$(codex plugin list --json | jq -er "$plugin_query")" || return 1
  if [[ "$state" != enabled ]]; then
    echo "Codex pstack@abhi was not enabled after setup. Inspect 'codex plugin list --json'." >&2
    return 1
  fi
  log "Codex pstack@abhi is installed and enabled."
}

agents=()
if command -v claude >/dev/null 2>&1; then
  agents+=(claude)
else
  log "Claude Code not installed; skipping pstack. Rerun install-skills.sh after installing Claude Code."
fi
if command -v codex >/dev/null 2>&1; then
  agents+=(codex)
else
  log "Codex not installed; skipping pstack. Rerun install-skills.sh after installing Codex."
fi

if ((${#agents[@]} == 0)); then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to inspect plugin state. Install jq and rerun install-skills.sh." >&2
  exit 1
fi

status=0
for agent in "${agents[@]}"; do
  if "install_${agent}_skills"; then
    :
  else
    echo "Pstack setup failed for $agent; resolve the error above and rerun install-skills.sh." >&2
    status=1
  fi
done
exit "$status"
