# Силуэтные значки статусов

24 согласованных силуэтных значка скопированы из `docs/art/status-icons-silhouette-20261108/16/` без изменения байтов. Каталог `32/` получен точным nearest-масштабированием 2×. В `framed/16/` и `framed/32/` значки наложены source-over на утверждённые деревянно-железные рамки; исходные наборы A и framed-v1 не менялись.

`hover-panel.png` — прозрачная обрезка `[1,12,127,32)` исходника `docs/art/status-hover04-color-20261108/after.png`; RGBA пикселей панели сохранены. SHA256 источников и результатов записаны в `manifest.json`.

Повторная сборка: `python tools/art/build_status_silhouette_icons.py`; проверка байтов и настроек импорта: `python tools/art/build_status_silhouette_icons.py --check`. PNG должны импортироваться lossless, без mipmaps, alpha border и premultiplication.
