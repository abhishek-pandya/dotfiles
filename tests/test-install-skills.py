"""Exercise bootstrap state transitions without touching real agent settings."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FAKE_CLI = r'''
import json
import os
from pathlib import Path
import sys

agent = Path(sys.argv[0]).name
args = sys.argv[1:]
directory = Path(os.environ['CLAUDE_CONFIG_DIR' if agent == 'claude' else 'CODEX_HOME'])
state_path = directory / 'state.json'
state = json.loads(state_path.read_text())
with (directory / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
operation = ' '.join(args[:3])
if state.get('fail') == operation:
    print('fixture command failure', file=sys.stderr)
    sys.exit(1)
if state.get('malformed') == operation:
    print('not JSON')
    sys.exit(0)

if args[:3] == ['plugin', 'marketplace', 'list']:
    markets = state['marketplaces']
    print(json.dumps(markets if agent == 'claude' else {'marketplaces': markets}))
elif args[:2] == ['plugin', 'list']:
    plugins = state['plugins']
    print(json.dumps(plugins if agent == 'claude' else {'installed': plugins}))
elif args[:3] == ['plugin', 'marketplace', 'add']:
    source = args[3]
    if any(m['name'] == 'abhi' for m in state['marketplaces']):
        print('duplicate marketplace add', file=sys.stderr)
        sys.exit(1)
    if agent == 'claude':
        state['marketplaces'].append({'name': 'abhi', 'source': 'directory', 'path': source, 'installLocation': source})
    else:
        state['marketplaces'].append({'name': 'abhi', 'root': source,
            'marketplaceSource': {'sourceType': 'local', 'source': source}})
elif args[:2] in (['plugin', 'install'], ['plugin', 'add']):
    if agent == 'claude':
        assert args[2:] == ['pstack@abhi', '--scope', 'user'], args
    key = 'id' if agent == 'claude' else 'pluginId'
    match = next((p for p in state['plugins'] if p.get(key) == 'pstack@abhi'
                  and (agent != 'claude' or p.get('scope') == 'user')), None)
    if match:
        match['enabled'] = True
    else:
        record = {key: 'pstack@abhi', 'enabled': True}
        if agent == 'claude':
            record['scope'] = 'user'
        state['plugins'].append(record)
elif args[:2] == ['plugin', 'enable'] and agent == 'claude':
    assert args[2:] == ['pstack@abhi', '--scope', 'user'], args
    for plugin in state['plugins']:
        if plugin.get('id') == 'pstack@abhi' and plugin.get('scope') == 'user':
            plugin['enabled'] = True
else:
    print('unexpected fixture invocation: ' + repr(args), file=sys.stderr)
    sys.exit(2)
state_path.write_text(json.dumps(state))
'''


class InstallSkillsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-skills-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        for tool in ('bash', 'dirname', 'jq'):
            executable = shutil.which(tool)
            self.assertIsNotNone(executable, f'{tool} is required to run these tests')
            (self.bin / tool).symlink_to(executable)
        self.env = dict(os.environ, PATH=str(self.bin),
                        CLAUDE_CONFIG_DIR=str(self.base / 'claude'),
                        CODEX_HOME=str(self.base / 'codex'))
        for agent in ('claude', 'codex'):
            (self.base / agent).mkdir()
            self.write_state(agent, marketplaces=[], plugins=[])
            executable = self.bin / agent
            executable.write_text(f'#!{sys.executable}\n' + FAKE_CLI)
            executable.chmod(0o755)

    def write_state(self, agent, **state):
        (self.base / agent / 'state.json').write_text(json.dumps(state))

    def state(self, agent):
        return json.loads((self.base / agent / 'state.json').read_text())

    def calls(self, agent):
        path = self.base / agent / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_installer(self):
        return subprocess.run(['/bin/bash', str(ROOT / 'install-skills.sh')],
                              cwd=self.base, env=self.env, capture_output=True,
                              text=True, timeout=10)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_installed(self, agent):
        key = 'id' if agent == 'claude' else 'pluginId'
        matches = [p for p in self.state(agent)['plugins']
                   if p.get(key) == 'pstack@abhi'
                   and (agent != 'claude' or p.get('scope') == 'user')]
        self.assertEqual(len(matches), 1)
        self.assertTrue(matches[0]['enabled'])

    def test_fresh_install_and_rerun_preserve_state_without_mutations(self):
        self.assert_success(self.run_installer())
        before = {a: self.state(a) for a in ('claude', 'codex')}
        counts = {a: len(self.calls(a)) for a in before}
        self.assert_success(self.run_installer())
        for agent in before:
            self.assert_installed(agent)
            self.assertEqual(self.state(agent), before[agent])
            self.assertEqual(len(self.state(agent)['marketplaces']), 1)
            for call in self.calls(agent)[counts[agent]:]:
                self.assertIn('list', call, f'rerun mutated {agent}: {call}')

    def test_missing_each_agent_is_skipped_and_other_installs(self):
        for missing, present in [('claude', 'codex'), ('codex', 'claude')]:
            with self.subTest(missing=missing):
                executable = self.bin / missing
                saved = executable.read_text()
                executable.unlink()
                result = self.run_installer()
                self.assert_success(result)
                self.assertIn('skip', result.stdout.lower())
                self.assertIn(missing, result.stdout.lower())
                self.assert_installed(present)
                executable.write_text(saved)
                executable.chmod(0o755)

    def test_both_missing_need_no_json_dependency(self):
        for name in ('claude', 'codex', 'jq'):
            (self.bin / name).unlink()
        result = self.run_installer()
        self.assert_success(result)
        self.assertIn('claude', result.stdout.lower())
        self.assertIn('codex', result.stdout.lower())
        self.assertGreaterEqual(result.stdout.lower().count('skip'), 2)

    def test_disabled_user_plugins_are_enabled(self):
        self.assert_success(self.run_installer())
        for agent in ('claude', 'codex'):
            state = self.state(agent)
            state['plugins'][0]['enabled'] = False
            self.write_state(agent, **state)
        self.assert_success(self.run_installer())
        for agent in ('claude', 'codex'):
            self.assert_installed(agent)
        self.assertIn(['plugin', 'enable', 'pstack@abhi', '--scope', 'user'], self.calls('claude'))

    def test_claude_project_install_does_not_replace_user_install(self):
        self.write_state('claude', marketplaces=[], plugins=[
            {'id': 'pstack@abhi', 'scope': 'project', 'enabled': True},
            {'id': 'unrelated@other', 'scope': 'user', 'enabled': True}])
        self.assert_success(self.run_installer())
        self.assert_installed('claude')
        self.assertEqual(len(self.state('claude')['plugins']), 3)

    def test_cli_failures_do_not_prevent_other_agent_install(self):
        for broken, healthy in [('claude', 'codex'), ('codex', 'claude')]:
            with self.subTest(broken=broken):
                self.write_state(broken, marketplaces=[], plugins=[], fail='plugin marketplace list')
                result = self.run_installer()
                self.assertNotEqual(result.returncode, 0)
                self.assert_installed(healthy)
                self.write_state(broken, marketplaces=[], plugins=[])

    def test_malformed_json_is_an_error_not_missing_state(self):
        self.write_state('claude', marketplaces=[], plugins=[], malformed='plugin marketplace list')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any('add' in call for call in self.calls('claude')))
        self.assert_installed('codex')

    def test_marketplace_source_collision_is_not_overwritten(self):
        self.write_state('claude', marketplaces=[
            {'name': 'abhi', 'source': 'directory', 'path': '/different/checkout', 'installLocation': '/different/checkout'}], plugins=[])
        self.write_state('codex', marketplaces=[
            {'name': 'abhi', 'root': '/different/checkout',
             'marketplaceSource': {'sourceType': 'local', 'source': '/different/checkout'}}], plugins=[])
        before = {a: self.state(a) for a in ('claude', 'codex')}
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        for agent in before:
            self.assertEqual(self.state(agent), before[agent])
            self.assertTrue(all('list' in call for call in self.calls(agent)))

    def test_failed_install_recovers_without_registering_marketplace_again(self):
        for agent, operation in [('claude', 'plugin install pstack@abhi'),
                                 ('codex', 'plugin add pstack@abhi')]:
            with self.subTest(agent=agent):
                self.write_state(agent, marketplaces=[], plugins=[], fail=operation)
                failed = self.run_installer()
                self.assertNotEqual(failed.returncode, 0)
                state = self.state(agent)
                registered_marketplaces = state['marketplaces']
                self.assertEqual(len(registered_marketplaces), 1)
                self.assertEqual(state['plugins'], [])
                del state['fail']
                self.write_state(agent, **state)
                calls_before = len(self.calls(agent))
                self.assert_success(self.run_installer())
                self.assert_installed(agent)
                self.assertEqual(self.state(agent)['marketplaces'], registered_marketplaces)
                self.assertFalse(any(call[:3] == ['plugin', 'marketplace', 'add']
                                     for call in self.calls(agent)[calls_before:]))

    def test_error_bearing_installed_plugin_is_rejected(self):
        self.assert_success(self.run_installer())
        for agent in ('claude', 'codex'):
            state = self.state(agent)
            state['plugins'][0]['errors'] = ['fixture plugin load failure']
            self.write_state(agent, **state)
        counts = {a: len(self.calls(a)) for a in ('claude', 'codex')}
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Claude Code reports errors', result.stderr)
        self.assertIn('Codex reports errors', result.stderr)
        for agent in counts:
            self.assertTrue(all('list' in call for call in self.calls(agent)[counts[agent]:]))

    def test_missing_jq_with_agent_present_fails_before_mutation(self):
        (self.bin / 'jq').unlink()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('jq', result.stderr)
        self.assertEqual(self.calls('claude'), [])
        self.assertEqual(self.calls('codex'), [])


if __name__ == '__main__':
    unittest.main()
