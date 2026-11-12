"""Verify Ona shell setup survives a skills installation failure."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BootstrapTest(unittest.TestCase):
    def test_ona_shell_setup_before_skills_result(self):
        for skills_status in (0, 42):
            with self.subTest(skills_status=skills_status), tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                home = base / 'home'
                repo = home / 'dotfiles'
                repo.mkdir(parents=True)
                for name in ('install.sh', '.zshrc'):
                    shutil.copyfile(ROOT / name, repo / name)
                (repo / 'apt-packages.txt').write_text('')
                (repo / 'install-skills.sh').write_text(f'exit {skills_status}\n')
                (home / '.zshrc').write_text('# existing user configuration\n')
                binaries = base / 'bin'
                binaries.mkdir()
                for tool in ('bash', 'dirname', 'mkdir', 'mktemp', 'mv', 'jq', 'grep'):
                    executable = shutil.which(tool)
                    self.assertIsNotNone(executable, f'{tool} is required for this test')
                    (binaries / tool).symlink_to(executable)
                commands = {
                    'uname': 'echo Linux',
                    'nvim': 'exit 0',
                    'delta': 'exit 0',
                    'git': 'exit 0',
                    'python3': 'exit 0',
                    'id': 'echo fixture-user',
                    'sudo': 'printf "%s\\n" "$*" >> "$BOOTSTRAP_CALLS"',
                    'gh': 'printf "gh %s\\n" "$*" >> "$BOOTSTRAP_CALLS"',
                }
                for name, body in commands.items():
                    path = binaries / name
                    path.write_text('#!/bin/bash\n' + body + '\n')
                    path.chmod(0o755)
                calls = base / 'calls'
                env = dict(os.environ, HOME=str(home), PATH=str(binaries),
                           CODEX_HOME=str(home / '.codex'), IS_ON_ONA='true',
                           BOOTSTRAP_CALLS=str(calls))
                for _ in range(2):
                    result = subprocess.run(['/bin/bash', str(repo / 'install.sh')],
                                            cwd=base, env=env, capture_output=True,
                                            text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    if skills_status:
                        self.assertIn('WARNING: Pstack setup failed', result.stderr)
                        self.assertIn('install-skills.sh', result.stderr)
                    rc = (home / '.zshrc').read_text()
                    self.assertIn('# existing user configuration', rc)
                    self.assertEqual(rc.count('source ~/dotfiles/.zshrc'), 1,
                                     'Ona setup must wire the Warp hook even if skills fail')
                    self.assertIn('chsh fixture-user --shell /usr/bin/zsh', calls.read_text())
                    self.assertIn('gh config set editor nvim', calls.read_text())


if __name__ == '__main__':
    unittest.main()
