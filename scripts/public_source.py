#!/usr/bin/env python3
"""Validate an explicit public source inventory before staging or archiving."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def inventory(root=ROOT):
    names = json.loads((root / 'PUBLIC_FILES.json').read_text())
    if (not isinstance(names, list) or not names or
            not all(isinstance(name, str) for name in names) or len(names) != len(set(names))):
        raise RuntimeError('Ugyldig kildeinventar.')
    for name in names:
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name:
            raise RuntimeError('Ugyldig offentlig filbane.')
        if (path.parts[0] in {'build', 'build-next', 'build-release', 'backups', 'dist', 'releases', '.git', 'private', 'local'} or
                path.name in {'board.json', 'folders.json', 'archive.json', 'shortcuts.json'} or
                path.suffix.lower() in {'.p8', '.p12', '.pfx', '.key', '.pem', '.cer', '.log'} or path.name.startswith('.env')):
            raise RuntimeError('Privat/generert fil er ikke tillatt i kildeinventaret: ' + name)
        full = root / path
        if not full.is_file() or full.is_symlink() or root.resolve() not in full.resolve().parents:
            raise RuntimeError('Mangler vanlig kildefil: ' + name)
        if any((root / parent).is_symlink() for parent in path.parents if str(parent) != '.'):
            raise RuntimeError('Symbolsk lenke i offentlig filbane: ' + name)
        body = full.read_text()
        sensitive = ('/' + r'Users/[^/\s]+/|/' + r'home/[^/\s]+/|' +
                     r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}')
        if re.search(sensitive, body):
            raise RuntimeError('Privat maskinsti eller mulig hemmelighet i ' + name)
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--check-git', action='store_true', help='Krev at sporede filer samsvarer med inventaret')
    parser.add_argument('--zip', type=Path, help='Lag kilde-ZIP fra bare inventaret')
    args = parser.parse_args()
    try:
        names = inventory()
        if args.check_git:
            result = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, check=True, capture_output=True)
            tracked = set(result.stdout.decode().rstrip('\0').split('\0'))
            if tracked != set(names):
                raise RuntimeError('Git-inventar avviker: ' + repr(sorted(tracked ^ set(names))))
        if args.zip:
            destination = args.zip.expanduser().resolve()
            if destination in [(ROOT / name).resolve() for name in names]:
                raise RuntimeError('ZIP kan ikke overskrive kildefilen.')
            destination.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
                for name in names:
                    archive.write(ROOT / name, 'AgentDock/' + name)
        print(f'OK: {len(names)} eksplisitte offentlige kildefiler; ingen binærer eller runtime-data.')
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print('Kildekontroll stoppet: ' + str(error))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
