#!/usr/bin/env python3
"""Build, notarize and verify a release; never publish an unsigned fallback."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(args, *, env=None):
    return subprocess.run(args, cwd=ROOT, env=env, check=True,
                          text=True, capture_output=True)


def choose_identity(requested=None):
    result = run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    identities = re.findall(r'\d+\) ([0-9A-Fa-f]{40}) "(Developer ID Application: [^"\n]+)"', result.stdout)
    if requested:
        identities = [(sha, name) for sha, name in identities
                      if requested.lower() == sha.lower() or requested == name]
    if len(identities) != 1:
        raise RuntimeError('Velg én gyldig Developer ID Application-identitet med --identity. '
                           'Kontroller sertifikat og privat nøkkel i vanlig Terminal/Xcode.')
    return identities[0]


def verify_app(app, expected_team):
    run(['/usr/bin/codesign', '--verify', '--strict', str(app)])
    result = run(['/usr/bin/codesign', '-dv', '--verbose=4', str(app)])
    details = result.stdout + result.stderr
    if ('Identifier=no.magne.agentdock\n' not in details or
            f'TeamIdentifier={expected_team}\n' not in details or
            'Authority=Developer ID Application:' not in details or
            not re.search(r'^CodeDirectory.*\bruntime\b', details, re.M) or
            not re.search(r'^Timestamp=\S', details, re.M)):
        raise RuntimeError('Signaturen mangler forventet Developer ID/team, runtime eller timestamp.')
    ent = run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)]).stdout.strip()
    if ent:
        values = plistlib.loads(ent.encode())
        if values.get('com.apple.security.get-task-allow'):
            raise RuntimeError('Debug-entitlement get-task-allow er ikke tillatt i en utgivelse.')


def verify_distribution(app, team):
    verify_app(app, team)
    run(['/usr/bin/xcrun', 'stapler', 'validate', str(app)])
    run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)])


def release(identity=None, profile='AgentDock-notary'):
    sha, identity_name = choose_identity(identity)
    team_match = re.search(r'\(([A-Z0-9]{10})\)$', identity_name)
    if not team_match:
        raise RuntimeError('Kan ikke identifisere teamet i Developer ID-sertifikatet.')
    team = team_match.group(1)
    info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', version):
        raise RuntimeError('Ugyldig versjonsnummer.')
    distribution = ROOT / 'dist' / ('AgentDock-' + version)
    if distribution.exists():
        raise RuntimeError('Utgivelsesmappen finnes allerede; bevar den og bruk et nytt versjonsnummer.')
    # Verify credentials before expensive work. Secrets stay in Keychain, never argv.
    run(['/usr/bin/xcrun', 'notarytool', 'history', '--keychain-profile', profile,
         '--output-format', 'json'])
    print('Kjører tester og bygger med Developer ID …', flush=True)
    run(['/bin/zsh', 'test.sh'])
    env = dict(os.environ, AGENTDOCK_SIGNING_IDENTITY=sha)
    run(['/bin/zsh', 'build.sh', 'build-release'], env=env)
    app = ROOT / 'build-release/AgentDock.app'
    verify_app(app, team)
    distribution.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.release-', dir=ROOT / 'build-release') as working:
        temporary = Path(working)
        submission = temporary / 'submission.zip'
        run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(submission)])
        print('Sender til Apple og venter på godkjenning …', flush=True)
        result = subprocess.run(['/usr/bin/xcrun', 'notarytool', 'submit', str(submission),
                                 '--keychain-profile', profile, '--wait', '--timeout', '60m',
                                 '--output-format', 'json'], cwd=ROOT, text=True, capture_output=True)
        # Retain response even for rejection/timeout, without publishing it.
        (ROOT / 'build-release/notary-response.json').write_text(result.stdout)
        result.check_returncode()
        receipt = json.loads(result.stdout)
        if receipt.get('status') != 'Accepted':
            raise RuntimeError('Apple har ikke godkjent bygget. Se build-release/notary-response.json.')
        run(['/usr/bin/xcrun', 'stapler', 'staple', str(app)])
        verify_distribution(app, team)
        staged = temporary / 'finished'
        staged.mkdir()
        archive = staged / f'AgentDock-{version}-macOS-arm64.zip'
        run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)])
        unpacked = temporary / 'unpacked'
        run(['/usr/bin/ditto', '-x', '-k', str(archive), str(unpacked)])
        verify_distribution(unpacked / 'AgentDock.app', team)
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        (staged / 'SHA256SUMS').write_text(f'{checksum}  {archive.name}\n')
        (staged / 'release-receipt.json').write_text(json.dumps({
            'version': version, 'build': info['CFBundleVersion'], 'architecture': 'arm64',
            'bundleIdentifier': 'no.magne.agentdock', 'teamIdentifier': team,
            'signingCertificateSHA1': sha, 'notarizationID': receipt.get('id'),
            'notarizationStatus': 'Accepted', 'staplerValidated': True,
            'gatekeeperAccepted': True, 'unpackedArchiveVerified': True,
            'archive': archive.name, 'sha256': checksum,
            'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }, indent=2) + '\n')
        # Same-volume rename publishes all output files together, after verification.
        staged.rename(distribution)
    print('Godkjent og kontrollert utgivelse: ' + str(distribution))
    return distribution


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', help='SHA-1 eller fullt Developer ID Application-navn')
    parser.add_argument('--profile', default='AgentDock-notary', help='Eksisterende nøkkelringprofil')
    args = parser.parse_args()
    try:
        release(args.identity, args.profile)
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print('Utgivelse stoppet: ' + str(error))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
