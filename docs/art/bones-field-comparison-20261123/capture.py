"""Render a temporary field comparison in an isolated project/profile, never the root project."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, uuid

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
DEFAULT_GODOT = Path(r'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run_engine(godot, project, out, label, args):
    env = os.environ.copy()
    env['APPDATA'] = str(out/'profile')
    Path(env['APPDATA']).mkdir(exist_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    command = [str(godot), '--path', str(project)] + args
    print(label + ': starting isolated Godot', flush=True)
    with (out/(label+'.log')).open('w', encoding='utf-8') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=240)
    text = (out/(label+'.log')).read_text(encoding='utf-8', errors='replace')
    if result.returncode or any(p in text for p in ['SCRIPT ERROR:', 'Parse Error:', 'ERROR:']):
        print(text[-6500:])
        raise RuntimeError(label+' failed')
    print(label+': PASS', flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['prepare', 'capture', 'capture-all'])
    parser.add_argument('--out', type=Path)
    parser.add_argument('--godot', type=Path, default=DEFAULT_GODOT)
    args = parser.parse_args()
    if args.phase == 'prepare':
        out = args.out or REPO/'test_reports'/('bones-field-'+uuid.uuid4().hex)
        assert not out.exists(), 'Use a new output directory for prepare'
        project = out/'project'
        project.mkdir(parents=True)
        names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=REPO).decode().split('\0')
        manifest = []
        for name in sorted(set(names)-{''}):
            if name.startswith(('docs/', 'test_reports/', '.godot/')):
                continue
            source = REPO/name
            if not source.is_file():
                continue
            target = project/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            manifest.append({'path': name, 'sha256': sha(source)})
        (out/'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        (ROOT/'run-location.json').write_text(json.dumps({'out': str(out), 'base': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()}, indent=2), encoding='utf-8')
        print('Isolated project: '+str(out), flush=True)
        run_engine(args.godot, project, out, 'import', ['--headless', '--editor', '--import'])
    else:
        out = args.out or Path(json.loads((ROOT/'run-location.json').read_text())['out'])
        project = out/'project'
        assert (project/'project.godot').is_file()
        all_variants = args.phase == 'capture-all'
        shutil.copyfile(ROOT/('capture_all.gd' if all_variants else 'capture.gd'), project/'tools/demo/capture_bones_comparison.gd')
        source_root = REPO/'docs/art/bones-twenty-more-20261123'
        selection = json.loads((source_root/'selection.json').read_text())
        captures = out/'captures'
        captures.mkdir(exist_ok=True)
        source_args = ['--variants='+str(ROOT/'variants.json')] if all_variants else [
            '--pl29='+str(source_root/selection['PL29']), '--pl34='+str(source_root/selection['PL34'])]
        run_engine(args.godot, project, out, 'capture-all' if all_variants else 'capture', ['--screen', '0', '--script', 'res://tools/demo/capture_bones_comparison.gd', '--',
            '--captures='+str(captures)]+source_args)
        for name in (['field-all-100.png', 'capture-all.json'] if all_variants else ['field-100.png', 'capture.json']):
            shutil.copyfile(captures/name, ROOT/name)
        print('Captured '+str(ROOT/('field-all-100.png' if all_variants else 'field-100.png')), flush=True)

if __name__ == '__main__':
    main()
