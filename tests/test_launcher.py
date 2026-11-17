#!/usr/bin/env python3
"""Offline regression tests. All writable paths and app bundles live in a temp HOME."""
import ast
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
INDEX = json.loads((ROOT / 'locales/index.json').read_text())

class LauncherTests(unittest.TestCase):
    def run_command(self, *args, env=None, ok=True):
        result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_dictionaries_and_plugins(self):
        self.assertEqual(set(INDEX), {'zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR'})
        keys = None
        for code, meta in INDEX.items():
            data = json.loads((ROOT / 'locales' / (code + '.json')).read_text())
            self.assertEqual(data['code'], code)
            self.assertTrue(all(isinstance(v, str) and v.strip() for v in data['phrases'].values()))
            self.assertGreater(len(data['phrases']), 250)
            self.assertEqual(len({key.lower() for key in data['phrases']}), len(data['phrases']))
            if keys is None:
                keys = set(data['phrases'])
            self.assertEqual(set(data['phrases']), keys)
            self.assertEqual(len(data['greetings']), 7)
            self.assertTrue(all(data['greetings']))
            plugin = ROOT / 'plugins' / meta['pluginName']
            manifest = json.loads((plugin / 'plugin.json').read_text())
            self.assertEqual(manifest['name'], meta['pluginName'])
            self.assertIs(manifest['disabled'], True)
            self.assertTrue((plugin / 'rules/AGENTS.md').read_text().strip())
        self.assertEqual(INDEX['zh-CN']['command'], 'agy-zh')
        self.assertEqual(INDEX['zh-CN']['appName'], 'Antigravity 中文')
        self.assertEqual(len({m['bundleId'] for m in INDEX.values()}), 9)

    def test_syntax(self):
        for file in ['install.sh','uninstall.sh','bin/agy-zh']:
            self.run_command('bash', '-n', str(ROOT / file))
            # Bash's parser does not validate Python heredocs.
            source = (ROOT / file).read_text()
            for body in re.findall(r"<<'PY'\n(.*?)\nPY", source, re.S):
                ast.parse(body, filename=file)
        for file in (ROOT / 'lib').glob('*.py'):
            ast.parse(file.read_text(), filename=str(file))
        self.run_command('node', '--check', str(ROOT / 'lib/overlay.js'))
        ps1 = (ROOT / 'bin/agy-zh.ps1').read_text()
        self.assertNotIn('return ,$pids', ps1)
        self.assertNotIn('/IM Antigravity.exe', ps1)
        for line in ps1.splitlines():
            if 'taskkill.exe' in line:
                self.assertIn('try {', line)
            if '.GetAwaiter().GetResult()' in line:
                self.assertRegex(line.strip(), r'^\$[A-Za-z0-9_:]+\s*=')
        with tempfile.TemporaryDirectory(prefix='agy-build-') as tmp:
            base = Path(tmp, 'base.js')
            # Test the existing anchor-mismatch fallback without using the network.
            base.write_text('window.__antigravityZhPatchInstalled = true;\n')
            for code in INDEX:
                dest = Path(tmp, code + '.js')
                self.run_command('python3', str(ROOT / 'lib/locale.py'), 'build', code, str(dest), str(base), 'false')
                self.run_command('node', '--check', str(dest))

    def test_argument_errors_and_dry_runs(self):
        for file in ['install.sh','uninstall.sh','bin/agy-zh']:
            for args in [('--lang',), ('--lang','en'), ('--lang=../../bad',), ('--unknown',)]:
                self.run_command('bash', str(ROOT / file), *args, ok=False)
            self.run_command('bash', str(ROOT / file), '--help')
        for file in ['install.sh','uninstall.sh']:
            for code in INDEX:
                self.assertIn('dry-run', self.run_command('bash', str(ROOT/file), '--lang', code, '--dry-run').stdout)

    def test_install_coexistence_and_uninstall(self):
        with tempfile.TemporaryDirectory(prefix="agy regression ' space ") as tmp:
            home = Path(tmp)
            apps = home / 'Applications'
            icon = apps / 'Antigravity.app/Contents/Resources/icon.icns'
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b'original icon sentinel')
            base = home / 'base.js'
            base.write_text('window.__antigravityZhPatchInstalled = true;\n')
            env = dict(os.environ, HOME=tmp, AGY_ZH_APPS_DIR=str(apps),
                       GEMINI_CONFIG_DIR=str(home/'config'), AGY_ZH_DATA_DIR=str(home/'.local/bin'),
                       AGY_ZH_OVERLAY_URL=base.as_uri())
            config = home/'config/config.json'
            config.parent.mkdir()
            config.write_text(json.dumps({'sentinel':42,'plugins':{'unrelated':{'enabled':True}}}))
            for code, meta in INDEX.items():
                args = [] if code == 'zh-CN' else ['--lang', code]
                self.run_command('bash', str(ROOT/'install.sh'), *args, env=env)
                local_bin = home / '.local/bin'
                self.assertTrue((local_bin / meta['command']).is_file())
                self.assertTrue((local_bin/'agy-i18n/installed'/code).is_file())
                info = apps / (meta['appName']+'.app') / 'Contents/Info.plist'
                with info.open('rb') as f:
                    plist = plistlib.load(f)
                self.assertEqual(plist['CFBundleName'], meta['appName'])
                self.assertEqual(plist['CFBundleIdentifier'], meta['bundleId'])
                launcher = info.parent/'MacOS/launcher'
                self.run_command('bash','-n',str(launcher))
                self.assertIn("--lang '"+code+"'",launcher.read_text())
                # Language aliases also resolve paths containing spaces and apostrophes.
                self.run_command(str(local_bin/meta['command']), 'status', env=env)
                self.assertFalse(json.loads(config.read_text())['plugins'][meta['pluginName']]['enabled'])
            cli = home/'.local/bin/agy-zh'
            self.run_command(str(cli),'--lang','ja','prompt','on',env=env)
            self.run_command(str(cli),'prompt','on','--lang','ko',env=env)
            data=json.loads(config.read_text())
            self.assertFalse(data['plugins'][INDEX['ja']['pluginName']]['enabled'])
            self.assertTrue(data['plugins'][INDEX['ko']['pluginName']]['enabled'])
            self.assertTrue(data['plugins']['unrelated']['enabled'])
            # Default uninstall keeps the shared CLI while other language entries exist.
            self.run_command('bash',str(ROOT/'uninstall.sh'),env=env)
            self.assertFalse((apps/'Antigravity 中文.app').exists())
            self.assertTrue(cli.exists())
            self.run_command(str(home/'.local/bin/agy-ja'),'status',env=env)
            for code,meta in list(INDEX.items())[1:]:
                self.run_command('bash',str(ROOT/'uninstall.sh'),'--lang',code,'--purge',env=env)
                self.assertFalse((apps/(meta['appName']+'.app')).exists())
                self.assertFalse((home/'config/plugins'/meta['pluginName']).exists())
            self.assertFalse(cli.exists())
            self.assertFalse((home/'.local/bin/agy-i18n').exists())
            self.assertEqual(icon.read_bytes(), b'original icon sentinel')
            self.assertEqual(json.loads(config.read_text()), {'sentinel':42,'plugins':{'unrelated':{'enabled':True}}})
            # Repeat uninstall and legacy cache purge are harmless.
            self.run_command('bash',str(ROOT/'uninstall.sh'),'--purge',env=env)
            self.assertFalse((home/'.local/bin/antigravity-hans-overlay.base.js').exists())

    def test_remote_pipe_install(self):
        # Exercise the public curl | bash path using file:// sources, offline.
        # Downloaded launcher files have mode 0644 until installed.
        for code in ['zh-CN', 'ja']:
            with tempfile.TemporaryDirectory(prefix='agy-pipe-') as tmp:
                home = Path(tmp)
                base = home / 'base.js'
                base.write_text('window.__antigravityZhPatchInstalled = true;\n')
                env = dict(os.environ, HOME=tmp, AGY_ZH_REPO_RAW=ROOT.as_uri(),
                           AGY_ZH_APPS_DIR=str(home/'apps'), GEMINI_CONFIG_DIR=str(home/'config'),
                           AGY_ZH_DATA_DIR=str(home/'.local/bin'), AGY_ZH_OVERLAY_URL=base.as_uri())
                args = ['bash','-s','--','--no-shortcut']
                if code != 'zh-CN': args += ['--lang',code]
                result = subprocess.run(args, input=(ROOT/'install.sh').read_text(),
                                        cwd=ROOT,env=env,text=True,capture_output=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertTrue((home/'.local/bin/agy-i18n/installed'/code).is_file())
                self.run_command('bash',str(ROOT/'uninstall.sh'),'--lang',code,'--purge',env=env)

if __name__ == '__main__':
    unittest.main(verbosity=2)
