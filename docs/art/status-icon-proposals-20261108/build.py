#!/usr/bin/env python3
"""Build the self-contained native-SVG concept gallery. Uses Python stdlib only."""

from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "icons"
INK = "#252a2c"

# Each glyph is authored as simple SVG geometry; headings live only in the gallery.
FAMILIES = [
    ("effects", "Эффекты персонажа", [
        ("bleeding", "Кровотечение", "#d9575f", [
            '<path d="M16 3C13 9 7 15 7 21a9 9 0 0 0 18 0c0-6-6-12-9-18Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M11 21c1 3 3 4 6 4" fill="none" stroke="#ffd3c9" stroke-width="2" stroke-linecap="round"/>',
            '<path d="M6 10 11 12 14 6 18 12 25 9 23 16 28 20 21 22 19 28 14 23 8 27 9 20 3 17 8 14Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="16" cy="17" r="3" fill="#ffd3c9" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M5 8h22v5l-3 3 3 3v5H5v-5l3-3-3-3Z" fill="#e7d6c3" stroke="{i}" stroke-width="2"/><path d="M12 8v16m8-16v16" stroke="{i}" stroke-width="1.5"/><path d="M16 10c-2 3-3 4-3 6a3 3 0 0 0 6 0c0-2-1-3-3-6Z" fill="{c}" stroke="{i}" stroke-width="1.5"/>',
        ]),
        ("burning", "Горение", "#f1843e", [
            '<path d="M17 3c2 7-5 9-3 15 1-3 4-4 5-7 6 5 8 10 5 16-4 6-16 5-19-1-3-7 3-12 7-17-1 5 1 7 2 8 2-4 3-9 3-14Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 19c3 3 4 6 1 8-3 1-5-1-4-4Z" fill="#ffe19a" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M5 25c-2-5 3-7 4-12 2 3 3 5 2 7 3-2 4-5 4-10 6 5 8 10 7 15Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M20 4c1 4-2 5-2 8" fill="none" stroke="#ffe19a" stroke-width="2" stroke-linecap="round"/><path d="M9 24c1-3 3-4 5-7 2 3 4 5 3 8" fill="#ffe19a" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M7 24a9 9 0 1 1 18 0" fill="none" stroke="{c}" stroke-width="5"/><path d="M7 24a9 9 0 1 1 18 0" fill="none" stroke="{i}" stroke-width="2"/><path d="M16 4c2 4-2 5-1 8m7-5c2 3 0 5-1 7" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="M16 18c3 3 3 5 0 7-3 0-4-2-2-4Z" fill="#ffe19a" stroke="{i}" stroke-width="1.5"/>',
        ]),
        ("poison", "Яд", "#51965d", [
            '<path d="M16 4c-7 0-11 5-10 12l2 8 8 4 8-4 2-8c1-7-3-12-10-12Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M10 16h4v3h-4zm8 0h4v3h-4zM12 23h8l-4 3Z" fill="#d6e7b6" stroke="{i}" stroke-width="1.5"/><path d="M4 7 2 4m26 3 2-3" stroke="{i}" stroke-width="2"/>',
            '<path d="M10 5h12l4 7-2 12-8 5-8-5-2-12Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M12 15h3v4h-3zm5 0h3v4h-3zM13 25l3-3 3 3" fill="#d6e7b6" stroke="{i}" stroke-width="1.5"/><path d="M4 13c3-2 4-4 4-7m16 7c-3-2-4-4-4-7" fill="none" stroke="{i}" stroke-width="2"/>',
            '<path d="M16 3 27 9v10l-11 9L5 19V9Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M8 14h5v4H8zm11 0h5v4h-5zM12 24l4-3 4 3" fill="#d6e7b6" stroke="{i}" stroke-width="1.5"/><circle cx="5" cy="5" r="2" fill="{c}" stroke="{i}" stroke-width="1.5"/><circle cx="27" cy="25" r="2" fill="{c}" stroke="{i}" stroke-width="1.5"/>',
        ]),
        ("acid", "Кислота", "#b3ee38", [
            '<path d="M5 9h21l-2 15-8 5-8-5Z" fill="#858d82" stroke="{i}" stroke-width="2"/><path d="m5 10 4-2m13 2 4-2" stroke="#858d82" stroke-width="4"/><path d="M16 2c-2 4-4 6-4 9a4 4 0 0 0 8 0c0-3-2-5-4-9Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="10" cy="19" r="1.5" fill="{i}"/><circle cx="20" cy="22" r="1.5" fill="{i}"/><path d="m12 16 2 2m4-1-1 2" stroke="{c}" stroke-width="2"/>',
            '<path d="m6 24 4 4 4-4L27 8l-1-5-5 1Z" fill="#858d82" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="m21 4 4 4L9 25l-3-3Z" fill="#a2a899" stroke="{i}" stroke-width="1.5"/><path d="M16 2c-2 4-4 6-4 9a4 4 0 0 0 8 0c0-3-2-5-4-9Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="15" cy="17" r="1.5" fill="{i}"/><path d="m18 13 2 2m-8 9 2 1" stroke="{c}" stroke-width="2"/>',
            '<path d="M9 4h8v11l4 5 5 3c2 2 1 5-2 5H7c-3-1-3-4 0-6l2-5Z" fill="#858d82" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="M24 2c-2 4-4 6-4 9a4 4 0 0 0 8 0c0-3-2-5-4-9Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="m8 23 3-2m3 4 2-3m3-4 2-2" stroke="{i}" stroke-width="2" stroke-linecap="round"/><circle cx="15" cy="21" r="1.2" fill="{c}"/>',
        ]),
        ("stunned", "Оглушение", "#f2f1e8", [
            '<path d="M16 8c-6 0-10 4-10 10v7h20v-7c0-6-4-10-10-10Z" fill="#d2d2c7" stroke="{i}" stroke-width="2"/><path d="m8 5 2 3m14-3-2 3" stroke="{i}" stroke-width="2"/><path d="m6 5 2-3 2 3-2 3Zm18 0 2-3 2 3-2 3Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><path d="M12 17h2m4 0h2" stroke="{i}" stroke-width="2"/>',
            '<path d="M16 7c-6 0-10 5-9 12l2 6h14l2-6c1-7-3-12-9-12Z" fill="#deded4" stroke="{i}" stroke-width="2"/><path d="m5 8 2-4 2 4-2 3Zm18-2 4-2-1 5-4 1Zm-9-2 2-3 2 3-2 2Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><path d="M11 17h3m4 0h3" stroke="{i}" stroke-width="2"/>',
            '<path d="M16 9c-6 0-9 4-9 10v6h18v-6c0-6-3-10-9-10Z" fill="#d6d7ce" stroke="{i}" stroke-width="2"/><path d="m5 13-3-2 3-2 3 2Zm22 0 3-2-3-2-3 2Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><path d="m12 19 2-2m4 2-2-2" stroke="{i}" stroke-width="2"/><path d="M12 5 14 2l2 3 2-3 2 3" fill="none" stroke="{c}" stroke-width="2"/>',
        ]),
        ("entangled", "Путы", "#b68a5c", [
            '<path d="M10 4v13l-3 9h7l2-7 2 7h7l-3-9V4" fill="#b99b79" stroke="{i}" stroke-width="2"/><path d="M6 17c5-5 15 6 20 0M7 22c5-5 13 5 18 0" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round"/>',
            '<path d="M6 26c2-7 4-12 4-20m12 20c-2-7-4-12-4-20" fill="none" stroke="#7e9b61" stroke-width="3" stroke-linecap="round"/><path d="M8 18c4-7 12 7 16 0M8 22c4-7 12 7 16 0" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="M10 5 8 2m14 3 2-3" stroke="{i}" stroke-width="2"/>',
            '<path d="M6 24h20l-3-7V5H9v12Z" fill="#b99b79" stroke="{i}" stroke-width="2"/><path d="M7 12c5-6 12 7 18 1M7 17c5-6 12 7 18 1M9 22c4-4 10 4 14 0" fill="none" stroke="{c}" stroke-width="2.5" stroke-linecap="round"/><path d="M11 5V2m10 3V2" stroke="{i}" stroke-width="2"/>',
        ]),
        ("frozen", "Заморозка", "#62c7e8", [
            '<path d="M16 3v26M5 9l22 14M5 23 27 9M12 6l4 3 4-3m-8 20 4-3 4 3M5 9l1 5 5 1m10 2 5 1 1 5M5 23l1-5 5-1m10-2 5-1 1-5" fill="none" stroke="{c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M16 3v26M5 9l22 14M5 23 27 9" fill="none" stroke="{i}" stroke-width="1"/>',
            '<path d="m16 3 9 8-3 13-6 5-6-5-3-13Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="m16 7-5 8 5 2 5-2Zm0 10v8m-5-5 5-3 5 3" fill="#d7f7ff" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M7 25 11 6l5-3 5 3 4 19-9 5Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="m11 7 5 8 5-8m-5 8v10m-5-5 5-5 5 5" fill="none" stroke="#d7f7ff" stroke-width="2" stroke-linejoin="round"/>',
        ]),
        ("wet", "Мокрый", "#68bddd", [
            '<path d="M16 3C12 10 6 16 6 21a10 10 0 0 0 20 0C26 16 20 10 16 3Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M11 20c1-3 3-5 5-8" fill="none" stroke="#e5f8ff" stroke-width="2" stroke-linecap="round"/>',
            '<path d="M16 5c-3 5-6 8-6 12a6 6 0 0 0 12 0c0-4-3-7-6-12Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M5 12c-2 3-3 4-3 6a4 4 0 0 0 8 0c0-2-2-4-5-6Zm22 4c-2 3-3 4-3 6a4 4 0 0 0 8 0c0-2-2-4-5-6Z" fill="#9ee2f2" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M4 20c3-5 7 5 11 0s8 5 13 0v6H4Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 3c-2 4-4 6-4 9a4 4 0 0 0 8 0c0-3-2-5-4-9Z" fill="#9ee2f2" stroke="{i}" stroke-width="1.5"/><path d="M7 16c2-2 4-2 6 0m7 0c2-2 4-2 6 0" fill="none" stroke="#e5f8ff" stroke-width="1.5"/>',
        ]),
        ("shield", "Магический щит", "#dfc77c", [
            '<path d="M16 3 27 7v8c0 7-5 11-11 14C10 26 5 22 5 15V7Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 7 23 10v5c0 4-3 7-7 9-4-2-7-5-7-9v-5Z" fill="#fff0b0" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M4 24V13a12 12 0 0 1 24 0v11h-5V13a7 7 0 0 0-14 0v11Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M8 12a8 8 0 0 1 16 0" fill="none" stroke="#fff0b0" stroke-width="2"/><circle cx="16" cy="18" r="3" fill="#fff0b0" stroke="{i}" stroke-width="1.5"/>',
            '<path d="m16 3 3 7 7-3-3 7 7 2-7 3 3 7-7-3-3 7-3-7-7 3 3-7-7-3 7-2-3-7 7 3Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="16" cy="16" r="5" fill="#fff0b0" stroke="{i}" stroke-width="1.5"/>',
        ]),
        ("raised_shield", "Поднятый стальной щит", "#9aa7ad", [
            '<path d="M16 4 27 8v8c0 6-5 10-11 13C10 26 5 22 5 16V8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M3 16h10m-4-4 4 4-4 4" fill="none" stroke="#d7dfe0" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M17 10v12" stroke="#e1e5e4" stroke-width="1.5"/>',
            '<path d="M5 8 16 4l11 4v8c0 6-5 10-11 13C10 26 5 22 5 16Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="16" cy="13" r="3" fill="#d7dfe0" stroke="{i}" stroke-width="1.5"/><path d="M10 25v-4a6 6 0 0 1 12 0v4" fill="#d7dfe0" stroke="{i}" stroke-width="1.7"/>',
            '<path d="M16 3 27 8v8c0 6-5 10-11 13C10 26 5 22 5 16V8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M2 16h9m2 0c3 0 4-2 4-5m-4 1 4-1 1 4" fill="none" stroke="#d7dfe0" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/><path d="m14 11 4 5-4 5" fill="none" stroke="{i}" stroke-width="1.5"/>',
        ]),
    ]),
    ("combat", "Боевые реакции и ожидание", [
        ("opportunist", "Оппортунист", "#ca8e52", [
            '<circle cx="15" cy="18" r="10" fill="none" stroke="#d8c6a7" stroke-width="1.7" stroke-dasharray="3 2"/><path d="m8 22 3-4 5 2 3 4-5 2-5-1Z" fill="#d8c6a7" stroke="{i}" stroke-width="1.7"/><path d="m21 6 5 5-8 8-3-3Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="m20 18 4-1-1 4" fill="none" stroke="{c}" stroke-width="1.7"/>',
            '<circle cx="11" cy="8" r="3" fill="#d8c6a7" stroke="{i}" stroke-width="1.7"/><path d="m10 12 6 4-3 5 5 5m-7-9-5 5" fill="none" stroke="#d8c6a7" stroke-width="3" stroke-linecap="round"/><path d="m19 4 3 5-7 5-2-3Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="m7 27 4-3m14-8 4 2" stroke="{c}" stroke-width="1.7"/>',
            '<path d="M6 26c2-3 5-3 7-1m1 1c2-3 5-3 7-1" fill="none" stroke="#d8c6a7" stroke-width="3" stroke-linecap="round"/><path d="M9 22v-4m10 4v-4" stroke="#d8c6a7" stroke-width="2.5" stroke-linecap="round"/><path d="m19 4 3 5-7 5-2-3Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="m6 12 4 3m12 4 4-2" stroke="{c}" stroke-width="1.7"/>',
        ]),
        ("counterattack", "Контратака", "#d7b879", [
            '<path d="m5 25 16-16m-4-3 7 7M4 20l8 8m-9-5 5-5" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="m21 9 5-5 2 2-5 5M8 22l-3 3" stroke="{i}" stroke-width="2"/><path d="M28 8c2 5 0 10-4 13" fill="none" stroke="#dfe4e1" stroke-width="1.7"/><path d="m21 19 3 2 1-4" fill="none" stroke="#dfe4e1" stroke-width="1.7"/>',
            '<path d="M4 16h18m-5-5 5 5-5 5" fill="none" stroke="{c}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M27 7 12 22m4-17 2 2m-8 20 2 2" fill="none" stroke="#dfe4e1" stroke-width="2"/><path d="M28 8c2 5 0 10-4 13m0-5-1 5 5-1" fill="none" stroke="#dfe4e1" stroke-width="1.7"/>',
            '<path d="M7 6 24 23M5 10l4-4m10 22 4-4" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="m5 23 5-5 5 5-5 5Z" fill="#dfe4e1" stroke="{i}" stroke-width="1.5"/><path d="M27 7c3 5 1 11-4 14m0-5-1 5 5-1" fill="none" stroke="#dfe4e1" stroke-width="1.7"/><path d="M16 3v5m0 16v5" stroke="{i}" stroke-width="2"/>',
        ]),
        ("cover", "Прикрытие союзника", "#aeb6b0", [
            '<path d="M5 6 18 10v8c0 5-6 8-10 10-4-2-8-5-8-10v-8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M19 17c0-3 2-5 5-5s5 2 5 5v8H19Z" fill="#e2d0ac" stroke="{i}" stroke-width="2"/><circle cx="24" cy="9" r="3" fill="#e2d0ac" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M4 8 16 4l12 4v8c0 6-7 10-12 13C11 26 4 22 4 16Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="16" cy="15" r="3" fill="#e2d0ac" stroke="{i}" stroke-width="1.5"/><path d="M10 25v-4a6 6 0 0 1 12 0v4" fill="#e2d0ac" stroke="{i}" stroke-width="2"/>',
            '<path d="M5 8h11v18H5z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 13h7c3 0 5 2 5 5v8H16Z" fill="#e2d0ac" stroke="{i}" stroke-width="2"/><circle cx="22" cy="9" r="3" fill="#e2d0ac" stroke="{i}" stroke-width="1.5"/><path d="M2 5h13" stroke="{i}" stroke-width="2"/>',
        ]),
        ("pending", "Ожидание", "#d9bf78", [
            '<path d="M5 5h11v9H5zm0 13h11v9H5z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M8 7h5v5l-2 2-3-2Zm0 13h5v5H8Z" fill="#eee3bd" stroke="{i}" stroke-width="1.5"/><circle cx="23" cy="10" r="3" fill="#d8c39e" stroke="{i}" stroke-width="1.5"/><path d="M18 25v-6a5 5 0 0 1 10 0v6Z" fill="#d8c39e" stroke="{i}" stroke-width="2"/>',
            '<circle cx="15" cy="15" r="11" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M15 8v7l5 3" fill="none" stroke="#eee3bd" stroke-width="2.5" stroke-linecap="round"/><circle cx="25" cy="23" r="3" fill="#d8c39e" stroke="{i}" stroke-width="1.5"/><path d="M20 30v-2a5 5 0 0 1 10 0v2" fill="#d8c39e" stroke="{i}" stroke-width="2"/>',
            '<path d="M7 3h14v4c0 4-4 5-4 9s4 5 4 9v4H7v-4c0-4 4-5 4-9S7 11 7 7Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M10 6h8l-4 6Zm0 20h8l-4-6Z" fill="#eee3bd" stroke="{i}" stroke-width="1.5"/><circle cx="25" cy="9" r="3" fill="#d8c39e" stroke="{i}" stroke-width="1.5"/><path d="M22 19v8m6-8v8m-8 0h10" stroke="#d8c39e" stroke-width="2"/>',
        ]),
    ]),
    ("terrain", "Тайлы и опасности", [
        ("fire_on_tile", "Огонь на тайле", "#ee833a", [
            '<path d="m3 18 13-7 13 7-13 8Z" fill="#887a65" stroke="{i}" stroke-width="2"/><path d="M17 6c2 4-3 5-1 9 1-2 3-3 4-5 4 4 4 7 2 10-3 4-9 3-11 0-2-4 1-7 4-10-1 3 1 4 1 5 1-3 1-5 1-9Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="M17 15c2 2 2 4 0 5-2 0-3-1-2-3Z" fill="#ffe19a" stroke="{i}" stroke-width="1"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#887a65" stroke="{i}" stroke-width="2"/><path d="M9 18c-2-4 2-6 4-9 0 3 1 4 2 5 1-4 3-7 3-10 4 5 7 9 5 14-2 5-12 5-14 0Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="M17 17c3 3 1 5-1 5-2-1-2-3 1-5Z" fill="#ffe19a" stroke="{i}" stroke-width="1"/>',
            '<path d="m3 19 13-7 13 7-13 8Z" fill="#887a65" stroke="{i}" stroke-width="2"/><path d="M8 19c-2-3 0-5 3-7 0 3 2 4 3 5 0-5 2-8 4-12 1 4 5 7 5 12 0 4-4 6-8 6s-6-1-7-4Z" fill="{c}" stroke="{i}" stroke-width="1.7"/><path d="m12 16 3-3m5 3-2-4" stroke="#ffe19a" stroke-width="1.5"/>',
        ]),
        ("acid_pool", "Кислотная лужа", "#b3ee38", [
            '<path d="m3 19 13-7 13 7-13 8Z" fill="#8ca076" stroke="{i}" stroke-width="2"/><path d="m7 19 9-5 9 5-9 5Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><circle cx="12" cy="17" r="1.5" fill="#e6ff9b"/><circle cx="19" cy="20" r="1.5" fill="#e6ff9b"/><circle cx="17" cy="10" r="2" fill="{c}" stroke="{i}" stroke-width="1.5"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#8ca076" stroke="{i}" stroke-width="2"/><ellipse cx="16" cy="20" rx="10" ry="4" fill="{c}" stroke="{i}" stroke-width="1.5"/><circle cx="11" cy="17" r="2" fill="{c}" stroke="{i}" stroke-width="1.5"/><circle cx="21" cy="14" r="1.5" fill="#e6ff9b" stroke="{i}" stroke-width="1"/><circle cx="18" cy="10" r="1" fill="#e6ff9b"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#8ca076" stroke="{i}" stroke-width="2"/><path d="m7 21 9-5 9 5-9 4Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><path d="M10 17c-2-3 1-4 1-6 3 2 2 4 1 5m8 1c-2-3 1-4 1-6 3 2 2 4 1 5" fill="none" stroke="#e6ff9b" stroke-width="1.5" stroke-linecap="round"/><circle cx="16" cy="10" r="1.5" fill="{c}" stroke="{i}" stroke-width="1"/>',
        ]),
        ("spikes", "Шипы / кальтропы", "#aab1b1", [
            '<path d="m3 25 7-14 4 6 3-12 4 12 4-6 5 14Z" fill="{c}" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="m10 22 6-3 6 3" fill="none" stroke="#e4e8e5" stroke-width="1.5"/>',
            '<path d="m16 4 4 10 8 2-8 3-4 9-4-9-8-3 8-2Z" fill="{c}" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="m7 8 4 2m10 12 4 2" stroke="#e4e8e5" stroke-width="2" stroke-linecap="round"/>',
            '<path d="m5 25 8-4-5-5 3-8 5 7 5-7 3 8-5 5 8 4Z" fill="{c}" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="m13 21 3-6 3 6" fill="none" stroke="#e4e8e5" stroke-width="1.5"/>',
        ]),
        ("corpse", "Труп", "#c0b49c", [
            '<path d="M3 25h26" stroke="{i}" stroke-width="2"/><path d="M6 21c2-3 5-4 9-4l4-3 5 2 2 5-5 3H8Z" fill="{c}" stroke="{i}" stroke-width="2"/><circle cx="21" cy="14" r="3.5" fill="#e3d9c7" stroke="{i}" stroke-width="1.5"/><path d="M19 14h1m3 0h1m-5 2 2 1 2-1" stroke="{i}" stroke-width="1"/>',
            '<path d="M2 25h28" stroke="{i}" stroke-width="2"/><path d="m5 21 5-4 5 2 4-4 5 2 4 5-5 2H8Z" fill="#9c9b8a" stroke="{i}" stroke-width="2"/><circle cx="8" cy="16" r="4" fill="#ded5c3" stroke="{i}" stroke-width="2"/><path d="m6 15 1 1m3-1-1 1m-2 2 1 1 1-1" stroke="{i}" stroke-width="1.2"/>',
            '<path d="M3 26h26" stroke="{i}" stroke-width="2"/><path d="M5 21 10 17l5 2 4-3 7 3 2 4H7Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M10 14c0-3 2-5 5-5s5 2 5 5v3H10Z" fill="#e3d9c7" stroke="{i}" stroke-width="1.7"/><path d="M12 13h2m4 0h-2m-3 3h5" stroke="{i}" stroke-width="1.2"/>',
        ]),
        ("collapse_warning", "Обрушение", "#d79b58", [
            '<path d="m3 10 13-7 13 7-13 7Z" fill="#8a8170" stroke="{i}" stroke-width="2"/><path d="m3 10 13 7v12L3 22Zm26 0-13 7v12l13-7Z" fill="#6f6b61" stroke="{i}" stroke-width="2"/><path d="m16 8-2 5 4 2-3 5 2 3" fill="none" stroke="{c}" stroke-width="2"/>',
            '<path d="m4 11 12-7 12 7-12 7Z" fill="#8a8170" stroke="{i}" stroke-width="2"/><path d="m4 11 12 7 12-7M16 18v11" fill="none" stroke="{i}" stroke-width="2"/><path d="m15 7-3 5 4 2-3 4m7-5-3 4 3 2" fill="none" stroke="{c}" stroke-width="2"/><path d="m12 24 4 4 4-4" fill="none" stroke="{c}" stroke-width="2"/>',
            '<path d="m3 12 13-8 13 8-13 7Z" fill="#8a8170" stroke="{i}" stroke-width="2"/><path d="m4 13 12 7 12-7M16 20v8" fill="none" stroke="{i}" stroke-width="2"/><path d="m9 11 4 2-2 3 5 2 3-5-2-3 4-2" fill="none" stroke="{c}" stroke-width="2.2"/><path d="m13 25 3 3 3-3" fill="none" stroke="{c}" stroke-width="2"/>',
        ]),
        ("floor_trap", "Напольная ловушка", "#b98a58", [
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#8b806e" stroke="{i}" stroke-width="2"/><path d="m8 20 8-4 8 4-8 4Z" fill="#aa9b7d" stroke="{i}" stroke-width="2"/><path d="M12 16V8m8 8V8m-10 0 2-4 2 4m2 0 2-4 2 4" fill="none" stroke="{c}" stroke-width="2" stroke-linecap="round"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#8b806e" stroke="{i}" stroke-width="2"/><path d="m8 20 8-4 8 4-8 4Z" fill="#aa9b7d" stroke="{i}" stroke-width="2"/><path d="M16 17V7m-4 4 4-5 4 5" fill="none" stroke="{c}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 26v-3m16 3v-3" stroke="{i}" stroke-width="2"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="#8b806e" stroke="{i}" stroke-width="2"/><path d="m8 20 8-4 8 4-8 4Z" fill="#aa9b7d" stroke="{i}" stroke-width="2"/><path d="m10 15-2-6 4 2 2-6 3 6 4-2-2 6" fill="{c}" stroke="{i}" stroke-width="1.7" stroke-linejoin="round"/><path d="M8 24h16" stroke="#dfd4bf" stroke-width="1.5"/>',
        ]),
        ("wall_trap", "Настенная ловушка", "#ae966e", [
            '<path d="M3 4h13v24H3Z" fill="#928b79" stroke="{i}" stroke-width="2"/><path d="M7 8h5v5H7zm0 9h5v6H7z" fill="#c2b292" stroke="{i}" stroke-width="1.5"/><path d="M16 16h12m-5-4 5 4-5 4" fill="none" stroke="{c}" stroke-width="2.5" stroke-linejoin="round"/><path d="m28 13 2 3-2 3" fill="{c}" stroke="{i}" stroke-width="1"/>',
            '<path d="M4 3h12v26H4Z" fill="#928b79" stroke="{i}" stroke-width="2"/><path d="M7 7h6v18H7Z" fill="#c2b292" stroke="{i}" stroke-width="1.5"/><path d="M16 10h10v4H16zm0 9h10v4H16Z" fill="{c}" stroke="{i}" stroke-width="1.5"/><path d="m26 8 4 4-4 4m0 1 4 4-4 4" fill="none" stroke="{i}" stroke-width="1.5"/>',
            '<path d="M3 4h13v24H3Z" fill="#928b79" stroke="{i}" stroke-width="2"/><path d="M7 8h5v5H7zm0 9h5v6H7z" fill="#c2b292" stroke="{i}" stroke-width="1.5"/><path d="m17 10 10 6-10 6Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M21 16h8" stroke="#e7d9be" stroke-width="1.5"/>',
        ]),
        ("deep_acid", "Глубокая кислота", "#9fc934", [
            '<path d="m3 20 13-7 13 7-13 8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M9 16v-3a7 7 0 0 1 14 0v3" fill="#c5c4b2" stroke="{i}" stroke-width="2"/><circle cx="16" cy="14" r="5" fill="#aeb3a0" stroke="{i}" stroke-width="1.7"/><path d="M12 12h2m5 0h2m-5 3 2 1" stroke="{i}" stroke-width="1.3"/><path d="M8 16 5 13m19 3 3-3" stroke="#c5c4b2" stroke-width="3" stroke-linecap="round"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 27v-9m0 4-5-4m5 7 5-4m-5 1-4 4m4-1 4 3" fill="none" stroke="#c5c4b2" stroke-width="2.5" stroke-linecap="round"/><path d="m12 19 4 3 4-3" fill="none" stroke="{i}" stroke-width="1.4"/>',
            '<path d="m3 20 13-7 13 7-13 8Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M9 3h12l-1 12h-3v4h-4v-4h-3Z" fill="#89928b" stroke="{i}" stroke-width="2"/><path d="m6 8 10 5 10-5" fill="none" stroke="#e3efae" stroke-width="1.5"/><path d="M16 4v7m-3-3 3 3 3-3" fill="none" stroke="{i}" stroke-width="1.7" stroke-linejoin="round"/>',
        ]),
        ("void", "Пустота / провал", "#12171e", [
            '<path d="m3 10 13-7 13 7-5 3-8-4-8 4Z" fill="#867f70" stroke="{i}" stroke-width="2"/><path d="m3 10 5 3v7l8 8V9Zm26 0-5 3v7l-8 8V9Z" fill="#625d54" stroke="{i}" stroke-width="2"/><path d="m8 13 8-4 8 4-8 13Z" fill="{c}" stroke="{i}" stroke-width="2"/>',
            '<path d="m3 10 13-7 13 7-5 3-8-4-8 4Z" fill="#867f70" stroke="{i}" stroke-width="2"/><path d="m3 10 5 3v7l8 8V9m13 1-5 3v7l-8 8" fill="none" stroke="#625d54" stroke-width="2"/><path d="m8 13 8-4 8 4-8 13Z" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M12 14v7m8-7v7" stroke="#252a2c" stroke-width="1.5"/>',
            '<path d="M2 9h10l4 5-4 3H2Zm28 0H20l-4 5 4 3h10Z" fill="#867f70" stroke="{i}" stroke-width="2"/><path d="M2 9v10m28-10v10" stroke="#625d54" stroke-width="2"/><path d="M12 17 16 29l4-12" fill="{c}" stroke="{i}" stroke-width="2"/><path d="M16 18v7" stroke="#252a2c" stroke-width="2"/>',
        ]),
        ("hazard", "Опасность", "#d4a44f", [
            '<path d="m16 3 13 24H3Z" fill="{c}" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="M16 10v8" stroke="#fff0c2" stroke-width="3" stroke-linecap="round"/><circle cx="16" cy="22" r="1.5" fill="#fff0c2"/>',
            '<path d="m5 22 4-8 4 5 4-13 4 13 4-5 3 8Z" fill="{c}" stroke="{i}" stroke-width="2" stroke-linejoin="round"/><path d="M16 14v5m0 2v1" stroke="#fff0c2" stroke-width="2.5" stroke-linecap="round"/>',
            '<circle cx="16" cy="16" r="12" fill="none" stroke="{c}" stroke-width="3"/><path d="m8 8 16 16m0-16L8 24" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="m16 8 2 5-2 3-2-3Z" fill="#fff0c2" stroke="{i}" stroke-width="1.5"/>',
        ]),
    ]),
]


def svg_document(markup: str, color: str) -> str:
    body = markup.format(c=color, i=INK)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\n'
        f'  {body}\n</svg>\n'
    )


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    icon_count = 0
    for section, section_title, families in FAMILIES:
        for family, title, color, variants in families:
            cells = []
            for label, markup in zip("ABC", variants, strict=True):
                filename = f"{family}_{label.lower()}.svg"
                (OUT / filename).write_text(svg_document(markup, color), encoding="utf-8")
                icon_count += 1
                cells.append(
                    '<td><figure>'
                    f'<figcaption>Вариант {label}</figcaption>'
                    f'<div class="samples"><img src="icons/{filename}" width="16" height="16" alt="" />'
                    f'<img src="icons/{filename}" width="32" height="32" alt="" />'
                    f'<img class="double" src="icons/{filename}" width="64" height="64" alt="" /></div>'
                    '</figure></td>'
                )
            rows.append((section, title, "".join(cells)))

    groups = []
    current_section = None
    body_rows = []
    for section, title, cells in rows:
        if section != current_section:
            if body_rows:
                groups.append("\n".join(body_rows))
                body_rows = []
            section_title = next(name for key, name, _ in FAMILIES if key == section)
            body_rows.append(f'<tr class="section"><th colspan="4">{escape(section_title)}</th></tr>')
            current_section = section
        body_rows.append(f'<tr><th scope="row">{escape(title)}</th>{cells}</tr>')
    if body_rows:
        groups.append("\n".join(body_rows))

    html = f'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Проба пиктограмм статусов и тайлов — 2026-11-08</title>
<style>
:root {{ color-scheme: dark; font-family: system-ui, sans-serif; background: #292e30; color: #e3dfd0; }}
body {{ margin: 24px auto; padding: 0 16px; max-width: 1120px; }}
h1 {{ font-size: 1.45rem; margin: 0 0 8px; }}
p {{ color: #c0c0b4; margin: 0 0 18px; max-width: 72ch; line-height: 1.45; }}
table {{ border-collapse: separate; border-spacing: 0 5px; width: 100%; }}
th, td {{ background: #414749; border-top: 1px solid #626964; border-bottom: 1px solid #292e30; padding: 8px; }}
th:first-child, td:first-of-type {{ border-left: 1px solid #626964; }}
td:last-child {{ border-right: 1px solid #626964; }}
th[scope=row] {{ text-align: left; width: 190px; font-weight: 600; }}
.section th {{ text-align: left; background: #343a3b; color: #d3c9a9; padding-top: 13px; }}
figure {{ margin: 0; }}
figcaption {{ color: #bcb9ac; font-size: 12px; margin-bottom: 5px; }}
.samples {{ min-height: 70px; display: flex; align-items: center; gap: 9px; }}
img {{ display: block; image-rendering: pixelated; }}
.double {{ border: 1px solid #626964; }}
@media(max-width: 760px) {{ body {{ overflow-x: auto; }} table {{ min-width: 760px; }} }}
</style>
</head>
<body>
<h1>Проба пиктограмм статусов и состояний тайла</h1>
<p>Концептуальные SVG-эскизы для выбора направления. Размер 16&nbsp;px — текущий базовый размер; 32 и 64&nbsp;px показывают увеличение. Сравнивайте силуэты прежде всего при 16&nbsp;px. Подписи расположены вне самих символов.</p>
<table aria-label="72 векторных варианта, сгруппированных по смыслу">
<thead><tr><th scope="col">Смысл</th><th scope="col">Вариант A</th><th scope="col">Вариант B</th><th scope="col">Вариант C</th></tr></thead>
<tbody>{''.join(groups)}</tbody>
</table>
</body>
</html>
'''
    (ROOT / "index.html").write_text(html, encoding="utf-8")
    print(f"Built {icon_count} SVG icons in {OUT} and {ROOT / 'index.html'}")


if __name__ == "__main__":
    build()
