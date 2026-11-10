"""Boundary tests use simulated Apple commands, no credentials or application UI."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = load('release')
public = load('public_source')
SHA = 'A' * 40
TEAM = 'ABC1234567'
IDENTITIES = f'  1) {SHA} "Developer ID Application: Example ({TEAM})"\n'
DETAILS = ('Identifier=no.magne.agentdock\nTeamIdentifier=' + TEAM + '\n'
           'Authority=Developer ID Application: Example (' + TEAM + ')\n'
           'CodeDirectory v=20500 flags=0x10000(runtime) hashes=1\nTimestamp=10 Nov 2026\n')


class ReleaseTests(unittest.TestCase):
    def test_missing_identity_never_falls_back(self):
        with patch.object(release, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            with self.assertRaises(RuntimeError):
                release.choose_identity()

    def test_ambiguous_identity_requires_selection(self):
        other = IDENTITIES.replace(SHA, 'B' * 40)
        with patch.object(release, 'run', return_value=subprocess.CompletedProcess([], 0, IDENTITIES + other, '')):
            with self.assertRaises(RuntimeError):
                release.choose_identity()
            self.assertEqual(release.choose_identity(SHA)[0], SHA)

    def test_debug_or_wrong_signature_rejected(self):
        for details, entitlements in [(DETAILS.replace(TEAM, 'XYZ1234567'), {}),
                                      (DETAILS.replace('Timestamp=', 'NoTimestamp='), {}),
                                      (DETAILS.replace('runtime', 'none'), {}),
                                      (DETAILS, {'com.apple.security.get-task-allow': True})]:
            def fake(args, **kwargs):
                output = plistlib.dumps(entitlements).decode() if '--entitlements' in args else ''
                return subprocess.CompletedProcess(args, 0, output, details)
            with self.subTest(details=details, entitlements=entitlements), patch.object(release, 'run', side_effect=fake):
                with self.assertRaises(RuntimeError):
                    release.verify_app(Path('synthetic.app'), TEAM)

    def simulate(self, outcome='Accepted', failure_at=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'build-release').mkdir()
        (root / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.11.1', 'CFBundleVersion': '13'}))
        calls = []

        def fake(args, **kwargs):
            calls.append(args)
            if failure_at and failure_at in args:
                raise subprocess.CalledProcessError(1, args, stderr='Simulated control rejection')
            stdout = ''
            if args[0] == '/usr/bin/security':
                stdout = IDENTITIES
            elif '-dv' in args:
                return subprocess.CompletedProcess(args, 0, '', DETAILS)
            elif '--entitlements' in args:
                stdout = plistlib.dumps({}).decode()
            elif 'submit' in args:
                stdout = json.dumps({'status': outcome, 'id': 'synthetic-id'})
            elif args[0] == '/usr/bin/ditto' and '-c' in args:
                Path(args[-1]).write_bytes(b'synthetic archive')
            return subprocess.CompletedProcess(args, 0, stdout, '')

        with patch.object(release, 'ROOT', root), patch.object(release, 'run', side_effect=fake), patch.object(release.subprocess, 'run', side_effect=fake):
            if outcome != 'Accepted' or failure_at:
                with self.assertRaises((RuntimeError, subprocess.SubprocessError)):
                    release.release()
                self.assertFalse((root / 'dist/AgentDock-0.11.1').exists())
            else:
                destination = release.release()
                self.assertEqual(len(list(destination.iterdir())), 3)
                receipt = json.loads((destination / 'release-receipt.json').read_text())
                self.assertTrue(receipt['unpackedArchiveVerified'])
                checks = [args for args in calls if '--assess' in args]
                self.assertEqual(len(checks), 2)
                self.assertIn('unpacked', checks[-1][-1])
        return calls

    def test_apple_rejection_never_publishes(self):
        calls = self.simulate('Invalid')
        self.assertFalse(any('staple' in args for args in calls))

    def test_stapler_failure_never_publishes(self):
        self.simulate(failure_at='staple')

    def test_gatekeeper_failure_never_publishes(self):
        self.simulate(failure_at='--assess')

    def test_accepted_release_rechecks_unpacked_zip(self):
        self.simulate()


class PublicSourceTests(unittest.TestCase):
    def test_current_inventory(self):
        names = public.inventory()
        self.assertIn('LICENSE', names)
        self.assertNotIn('board.json', names)

    def test_runtime_paths_symlinks_and_private_content_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, body, symlink in [('board.json', '{}', False), ('backups/note.md', 'old', False),
                                         ('secret.md', '/' + 'Users/example/project', False),
                                         ('link.md', 'note', True), ('../outside.md', 'note', False)]:
                (root / 'PUBLIC_FILES.json').write_text(json.dumps([name]))
                if '..' not in Path(name).parts:
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if symlink:
                        (root / 'actual.md').write_text(body)
                        path.symlink_to(root / 'actual.md')
                    else:
                        path.write_text(body)
                with self.subTest(name=name), self.assertRaises(RuntimeError):
                    public.inventory(root)


if __name__ == '__main__':
    unittest.main()
