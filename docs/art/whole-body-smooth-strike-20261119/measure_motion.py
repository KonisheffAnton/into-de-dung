"""Измеряет шаги привязок и стыки PNG; не оценивает художественную естественность."""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent
OLD = ROOT.parent / 'whole-body-weighted-strike-20261118'


def measure(folder: Path) -> dict:
    manifest = json.loads((folder / 'assets/manifest.json').read_text(encoding='utf-8'))
    clip = manifest['clips']['attack']
    rows, at = [], 0
    for index, (first, second) in enumerate(zip(clip['sockets'], clip['sockets'][1:])):
        at += clip['durations'][index]
        delta = (second['weaponAngle'] - first['weaponAngle'] + math.pi) % (2 * math.pi) - math.pi
        rows.append({'from': index, 'to': index + 1, 'at_attack_ms': at,
                     'previous_duration_ms': clip['durations'][index],
                     'hand_step_px': round(math.dist(first['hand'], second['hand']), 3),
                     'head_step_px': round(math.dist(first['head'], second['head']), 3),
                     'weapon_turn_radians': round(abs(delta), 3)})
    def rgba_equal(a: str, b: str) -> bool:
        with Image.open(folder / a) as ia, Image.open(folder / b) as ib:
            # RGB тоже сравнивается: равенства одной alpha-маски недостаточно.
            difference = ImageChops.difference(ia.convert('RGBA'), ib.convert('RGBA'))
            return all(channel.getbbox() is None for channel in difference.split())
    body = manifest['bodies']['light']
    idle, attack = manifest['clips']['idle']['sockets'], clip['sockets']
    return {
        'attack_frames': len(clip['durations']), 'attack_duration_ms': sum(clip['durations']),
        'largest_hand_step': max(rows, key=lambda row: row['hand_step_px']),
        'largest_head_step': max(rows, key=lambda row: row['head_step_px']),
        'largest_weapon_turn': max(rows, key=lambda row: row['weapon_turn_radians']),
        'steps': rows,
        'seams': {
            'idle_to_attack_rgba_identical': rgba_equal(body['idle'][-1], body['attack'][0]),
            'attack_to_idle_rgba_identical': rgba_equal(body['attack'][-1], body['idle'][0]),
            'idle_to_attack_socket_identical': idle[-1] == attack[0],
            'attack_to_idle_socket_identical': attack[-1] == idle[0],
        },
    }


def main() -> None:
    report = {'before': measure(OLD), 'after': measure(ROOT),
              'interpretation': 'Diagnostics only: smaller socket steps and exact seams do not prove natural anatomy or visual acceptance.'}
    (ROOT / 'motion-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                                            encoding='utf-8', newline='\n')
    print(json.dumps({name: {'hand_max': value['largest_hand_step'], 'seams': value['seams']}
                      for name, value in report.items() if name in ('before', 'after')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
