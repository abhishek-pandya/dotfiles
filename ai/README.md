# Skills marketplace

This repository exposes plugins through the `abhi` marketplace for Claude Code
and Codex:

- `personal`: your own skills; currently an empty skeleton.
- `pstack`: coding-agent workflows from [your fork](https://github.com/abhishek-pandya/plugins/tree/main/pstack) of [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack).

Pstack is fetched directly from your fork, using the same
`harness/pstack/claude-code` package as upstream's marketplace. It is pinned to
commit `21fa802da437a0f7e70f3a0f17538f9cae6d0278` (plugin version `0.15.36`).
The pin keeps installations consistent across environments. No upstream skill
files are copied into this repository. The fork adds native-harness delegation
guidance to `poteto-mode` and its generated package. Some pstack workflows assume particular
agent tools or models; installation does not guarantee every workflow works in
every agent.

## Layout

```text
.claude-plugin/marketplace.json       # Repository-level catalog
ai/plugin/.claude-plugin/plugin.json # Plugin metadata and version
ai/plugin/skills/<name>/SKILL.md      # Shared skill instructions
```

Each skill gets its own folder under `ai/plugin/skills/`, with a `SKILL.md`
containing `name` and `description` YAML front matter and the workflow instructions.
Keep optional `references/`, `scripts/`, and `assets/` inside that skill's folder.
Add evaluation runners or design notes outside `ai/plugin/` as needed.

## Install from this checkout

Run the skills installer from any directory:

```sh
bash /path/to/dotfiles/install-skills.sh
```

The full `install.sh` bootstrap calls it after completing shell and tool setup.
If skills installation fails, the full bootstrap prints a warning and still
succeeds, so plugin download failures do not prevent Ona shell setup or fail
container initialization. The standalone skills installer still exits nonzero
on failure and can be rerun independently.

It registers this checkout as the
`abhi` marketplace and installs `pstack@abhi` for each agent on `PATH`. Claude
uses user scope. Missing agents print a skip message; rerun after installing them.
The installer requires `jq` when either agent is present.

Repeated runs keep an installed, enabled plugin unchanged. They repair an
incomplete installation or a disabled plugin, and do not upgrade existing
versions. Both agents are attempted even if one fails. A command failure, policy
rejection, or conflicting `abhi` marketplace source makes the installer exit
with an error. It does not replace a marketplace registered from another source.

Keep the checkout at that path while using it as a marketplace source. For manual
installation, run the following commands from the repository root:

Claude Code:

```sh
claude plugin marketplace add "$PWD"
claude plugin install pstack@abhi --scope user
```

Codex:

```sh
codex plugin marketplace add "$PWD"
codex plugin add pstack@abhi
```

Start a new agent session after installation. Plugins may be cached; editing this
checkout does not guarantee an already installed copy or running session reloads.
After adding your own skills, install `personal@abhi` with the same commands.
If pstack is already installed from `cursor-plugins`, keep only one enabled copy
to avoid duplicate skills.

## Install in other environments

After publishing the marketplace and skills to GitHub, register
`abhishek-pandya/dotfiles` instead of `"$PWD"`, then run the same plugin install
command. Choose one marketplace source per environment: local checkout for
development, or GitHub for distribution.

For environments that clone dotfiles, run `install.sh` or `install-skills.sh`
after installing the agents. The skills installer uses that environment's local
checkout, so it also works before these changes are published.
Claude's user scope makes the plugin available across projects on that machine.
The empty `personal` plugin is not installed automatically.

### Ona prerequisites

The marketplace layout works on Linux as well as macOS. Each Ona instance needs
the dotfiles checkout, the desired agent CLIs on `PATH`, `jq`, Git, and network
access to GitHub to fetch the pinned pstack package. Run the bootstrap as the user
who runs the agents, not as root.

Claude Code may reject the marketplace if an organization's
`strictKnownMarketplaces` policy does not allow its source. This installer uses
the absolute local checkout path. Allowing a GitHub source alone does not allow
that local-directory source. An administrator must permit the source used by the
installer on managed environments. The script does not change enterprise policy.

A macOS managed-preferences file does not automatically transfer to Ona, but a
Linux image or account-delivered policy can impose restrictions there. Run
`/status` inside Claude Code on the target instance to identify its managed
settings sources. See [Claude's managed settings documentation](https://code.claude.com/docs/en/settings#check-what-your-organization-enforces).

## Verify the installer

```sh
python3 tests/test-install-skills.py
python3 tests/test-bootstrap.py
```

The tests run the installer with isolated CLI fixtures and temporary state.
They check first installs, repeated runs, missing agents, recovery, and failures
without changing your real agent configuration or downloading plugins. They do
not prove that your machine's network or organization policy permits installing
pstack. Those checks require the real CLIs in the target environment.
The bootstrap test runs the Ona setup with external setup commands stubbed and
checks that a failing skills install still leaves the shell source line in place.

## Publish and update

Bump the version in `ai/plugin/.claude-plugin/plugin.json` when releasing changes.
Commit and push only when ready to make them available to other environments.

For Claude Code, refresh the catalog and update the installed plugin:

```sh
claude plugin marketplace update abhi
claude plugin update pstack@abhi
```

For Codex, refresh the marketplace and install its current plugin version:

```sh
codex plugin marketplace upgrade abhi
codex plugin add pstack@abhi
```

Start a new session to use the updated skills.

To upgrade pstack, merge changes from `cursor/plugins` into your fork, preserve
local changes, and run `node scripts/generate-pstack-harness-trees.mjs` followed by
`node scripts/generate-pstack-harness-trees.mjs --check`. Commit and push the source
and generated changes. Then update `source.sha` in
`.claude-plugin/marketplace.json` to that fork commit, and refresh and update as
above. Update commands alone do not move the pin. Use `personal@abhi` instead
when updating your own plugin.

For a local checkout that keeps only pstack and its build scripts visible:

```sh
git clone --filter=blob:none --sparse https://github.com/abhishek-pandya/plugins.git pstack-fork
cd pstack-fork
git sparse-checkout set pstack harness/pstack scripts
git remote add upstream https://github.com/cursor/plugins.git
```

The GitHub fork retains the full repository for upstream merges. The marketplace's
`git-subdir` source installs only `harness/pstack/claude-code`; no extra clone step
is needed in the dotfiles installer.
