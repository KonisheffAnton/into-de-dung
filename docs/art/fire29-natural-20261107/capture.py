"""GPU capture in an already imported isolated project; no root import or focus."""
from pathlib import Path
import json
import os
import subprocess
import sys
import shutil
import hashlib

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[2]
REPORT = REPO / 'test_reports/fire29-natural-20261107'
PROJECT = REPO / 'test_reports/demo-4be21bfba38a402b8880410cf3072793/project'
GODOT = Path('D:/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')

def main():
    label = sys.argv[1]
    assert label.replace('-', '').isalnum(), label
    script_name = sys.argv[2] if len(sys.argv) > 2 else 'capture_preview.gd'
    assert script_name in ('capture_preview.gd', 'redistribute_preview.gd')
    assert PROJECT.is_dir() and GODOT.is_file()
    active = subprocess.check_output(['powershell', '-NoProfile', '-Command',
        "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -like '*Godot*' }).Count"],
        creationflags=subprocess.CREATE_NO_WINDOW).decode().strip()
    assert active == '0', 'A Godot runner is already active; do not start another.'
    capture = REPORT / label
    # Отчёт одноразовый: прерванный запуск не должен смешать старые и новые кадры.
    capture.mkdir(exist_ok=False)
    for name in ['128', '384', 'profile']: (capture / name).mkdir()
    shutil.copyfile(PACKAGE / 'selection.json', capture / 'selection.json')
    shutil.copyfile(PACKAGE / script_name, capture / 'capture_preview.gd')
    env = os.environ.copy()
    env['APPDATA'] = str(capture / 'profile')
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    command = [str(GODOT), '--path', str(PROJECT), '--screen', '0', '--script',
               str(capture / 'capture_preview.gd'), '--', '--package=' + str(PACKAGE),
               '--repository=' + str(REPO), '--captures=' + str(capture),
               '--selection=' + str(capture / 'selection.json')]
    (capture / 'command.json').write_text(json.dumps(command, indent=2) + '\n', encoding='utf-8')
    with (capture / 'capture.log').open('wb') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
            startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=90)
    output = (capture / 'capture.log').read_text(encoding='utf-8')
    print(output)
    assert result.returncode == 0 and 'NATURAL PREVIEW PASS:' in output
    assert 'ERROR' not in output and 'SCRIPT ERROR' not in output
    selection = json.loads((capture / 'selection.json').read_bytes())
    files = {}
    for size in ('128', '384'):
        expected = [f'{index:03d}.png' for index in range(selection['slots'])]
        assert sorted(path.name for path in (capture / size).glob('*.png')) == expected
        for name in expected:
            files[f'{size}/{name}'] = hashlib.sha256((capture / size / name).read_bytes()).hexdigest()
    completion = {'selection_sha256': hashlib.sha256((capture / 'selection.json').read_bytes()).hexdigest(),
                  'script_sha256': hashlib.sha256((capture / 'capture_preview.gd').read_bytes()).hexdigest(),
                  'files': files, 'exit_code': result.returncode}
    (capture / 'completion.json').write_text(json.dumps(completion, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__': main()
