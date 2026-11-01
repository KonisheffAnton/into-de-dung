# Character skins v1

Четыре облика с выбранными анимационными листами. Пакет содержит PNG, `SpriteFrames` и `skin.tres` типа `CharacterSkinDefinition`; runtime-сцены и shader/материалы находятся у владельцев показа.

## Выбор U

| Skin | Class/id/model | PixelLab clips |
|---|---|---|
| `watch_shield` — Щит дозора | `shieldbearer` / `02` / `model02` | idle-1, idle-secondary-2, death-3, ability-2 |
| `grey_bastion` — Седой бастион | `shieldbearer` / `17` / `model17` | idle-1, death-3, ability-2 |
| `red_bastion` — Красный бастион | `fighter` / `11` / `model11` | idle-1, death-3, ability-2 |
| `short_cape` — Короткая накидка | `rogue` / `02` / `model02` | idle-3, death-2, ability-3 |

`buff` в `SpriteFrames` — имя runtime-анимации для выбранного источника `ability`; новую механику оно не вводит. Idle-secondary существует только у `watch_shield`.

## Происхождение и геометрия

`still.png` является побайтной копией выбранного `input-256.png` из warrior или Rogue02 package. Каждый clip PNG — побайтная копия выбранного PixelLab `spritesheet.png`. Все листы RGBA, 2048×1280, восемь колонок по 256 px и 33 позы. Кадры не извлекаются/пересохраняются: `SpriteFrames` использует `AtlasTexture`-регионы исходного листа.

В каталоге: `still.png`, выбранные `idle.png`, `idle_secondary.png` (только 02), `death.png`, `buff.png`, `frames.tres` и `skin.tres` типа `CharacterSkinDefinition`. Координаты опоры исходника — (128,200). Для ожидаемого силуэта около61 px применяется scale0.5 внутри существующего `ArtRoot` scale0.8; посадка сцены этим пакетом не меняется. В skin resource сохранены `source_facing_x`: 02=1, 17=1, 11=-1; palette strength: 02=0, 17=1, 11=0.

## Тайминг и ограничения источников

Тайминги и loop берутся из выбранных `clip.json`. Частота `SpriteFrames.speed` равна `1000 / base_duration_ms`, где базовая длительность — наиболее частая для клипа; frame `duration` хранит отношение его `duration_ms` к этой базе. Rogue02 по исходным метаданным: idle-3 — 33×90ms (2.97s), death-2 — 32×70ms и последний кадр1500ms (3.74s), ability-3 — 33×70ms (2.31s). Warrior clips также сохраняют собственные тайминги метаданных.

Во всех13 источниках `first_frame_rgba_equal` и `last_frame_rgba_equal` относительно `input-256.png` равны false: первый/последний кадр анимации не является точной копией still. Пять idle-клипов (включая вторичный у Щитоносца02) помечены loop, но непрерывность стыка отдельно не подтверждена. Death содержит32 обычных кадра по70ms и последний кадр1500ms. Способность —33 кадра по70ms. Это выбранные PixelLab результаты, не утверждение о ручной художественной приёмке.

Исходные картинки не изменяются, кадры не генерируются. Покадровые PNG используются только необязательной проверкой видимых пикселей и alpha с областью листа, если полный набор доступен; скрытый RGB прозрачных пикселей может отличаться. Частично присутствующий набор считается ошибкой. Сборка требует лишь sheets, input images и clip metadata.

## Сборка и проверка

`python tools/art/build_character_skins.py` собирает пакет. `python tools/art/build_character_skins.py --check` выполняет ту же проверку и сравнивает все выходы байт-в-байт без записи. `manifest.json` содержит выбранные источники и SHA-256 17 PNG; `validation.json` фиксирует 429 регионов и тайминги.
