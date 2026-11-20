#!/usr/bin/env python3
"""Reapply the verified Designer settings without storing launcher data in git."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile
import time
import uuid


def save(path, content, private=False):
    """Back up changed files and replace atomically; leave matching files alone."""
    if path.exists() and path.read_bytes() == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = 0o600 if private else 0o644
    if path.exists():
        mode = 0o600 if private else path.stat().st_mode & 0o777
        suffix = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
        backup = path.with_name(path.name + '.before-dotfiles-' + suffix)
        with backup.open('xb') as output:
            os.chmod(backup, mode)
            output.write(path.read_bytes())
        print('Backup:', backup)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        os.chmod(temporary, mode)
        output.write(content)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    print('Updated:', path)
    return True


def designer_running():
    # Read arguments only to identify the application; never print them or its
    # environment, which may include gateway credentials or session secrets.
    for process in Path('/proc').glob('[0-9]*'):
        try:
            if process.stat().st_uid != os.getuid():
                continue
            # Containers can share a numeric UID with a different host home.
            if ('HOME=' + str(Path.home())).encode() not in (process / 'environ').read_bytes().split(b'\0'):
                continue
            command = (process / 'cmdline').read_bytes()
            if (process / 'comm').read_text().strip() == 'java' and (
                b'launcher-designer-linux.jar' in command
                or b'com.inductiveautomation.ignition.client.launch' in command
                or b'com.inductiveautomation.ignition.designer' in command
            ):
                return True
        except (OSError, ProcessLookupError):
            continue
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scale', type=int, choices=range(1, 9), metavar='N',
                        help='Set GDK_SCALE in existing user desktop entries (1 for the tested Kasm output)')
    parser.add_argument('--application', help='Saved Designer entry name; required when there are multiple entries')
    parser.add_argument('--check', action='store_true', help='Verify saved settings without modifying anything')
    args = parser.parse_args()
    home = Path.home()
    config = home / '.ignition/clientlauncher-data/designer-launcher.json'
    if not config.is_file():
        parser.error('Install Designer Launcher and save a Designer entry first')
    data = json.loads(config.read_text())
    applications = data.get('applications', [])
    selected = [entry for entry in applications if args.application is None or entry.get('name') == args.application]
    if len(selected) != 1:
        parser.error('Select exactly one saved Designer entry with --application NAME')
    arguments = selected[0].get('jvm.arguments', [])
    if not isinstance(arguments, list) or not all(isinstance(value, str) for value in arguments):
        parser.error('Unsupported jvm.arguments format; launcher settings were not changed')
    xml = home / '.ignition/synthetica-no-popup-capture.xml'
    settings = [
        '-Dignition.synthetica.customXml=' + str(xml),
        '-Dawt.useSystemAAFontSettings=on',
        '-Dswing.aatext=true',
    ]
    updated = list(arguments)
    for setting in settings:
        prefix = setting.split('=', 1)[0] + '='
        existing = [value for value in updated if value.startswith(prefix)]
        if existing and existing != [setting]:
            parser.error('An existing override conflicts with ' + prefix + '; merge it manually first')
        if not existing:
            updated.append(setting)
    source = Path(__file__).resolve().parents[1] / 'applications/ignition/synthetica-no-popup-capture.xml'
    content = source.read_bytes()
    if xml.exists() and xml.read_bytes() != content:
        parser.error('Existing popup XML differs from the supplied file; merge it manually first')
    desktop_updates = []
    if args.scale is not None:
        for name in ('Designer Launcher.desktop', 'ignition-designer.desktop', 'ignition-designer-link.desktop'):
            path = home / '.local/share/applications' / name
            if not path.is_file():
                parser.error('Expected desktop entry is missing: ' + str(path))
            lines = path.read_text().splitlines()
            if sum(line.startswith('Exec=') for line in lines) != 1:
                parser.error('Expected one Exec line in ' + str(path))
            result = []
            for line in lines:
                if line.startswith('Exec='):
                    command = line[5:]
                    replacement = 'GDK_SCALE=' + str(args.scale)
                    if re.search(r'(?<!\S)GDK_SCALE=\S+', command):
                        command = re.sub(r'(?<!\S)GDK_SCALE=\S+', replacement, command, count=1)
                    else:
                        command = 'env ' + replacement + ' ' + command
                    line = 'Exec=' + command
                result.append(line)
            desktop_updates.append((path, ('\n'.join(result) + '\n').encode()))
    if args.check:
        correct = arguments == updated and xml.is_file() and xml.read_bytes() == content
        correct = correct and all(path.read_bytes() == text for path, text in desktop_updates)
        print('Designer settings match.' if correct else 'Designer settings need configuration.')
        return 0 if correct else 1
    if designer_running():
        parser.error('Save and close Designer and Designer Launcher before applying settings')
    selected[0]['jvm.arguments'] = updated
    changed = save(xml, content)
    # Avoid rewriting merely to change JSON formatting on repeat runs.
    if arguments != updated:
        changed = save(config, (json.dumps(data, indent=2) + '\n').encode(), private=True) or changed
    for path, text in desktop_updates:
        changed = save(path, text) or changed
    print('Designer configured.' if changed else 'Designer settings already match.')
    print('Reopen using the desktop launcher. Rerun after a vendor update regenerates its desktop entries.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
