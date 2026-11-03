# Character skins v1

Шесть обликов с выбранными анимационными листами. Пакет содержит PNG, `SpriteFrames` и `skin.tres` типа `CharacterSkinDefinition`; runtime-сцены и shader/материалы находятся у владельцев показа.

## Выбор

| Skin | Class/id/model | PixelLab clips |
|---|---|---|
| `watch_shield` — Щит дозора | `shieldbearer` / `02` / `model02` | idle-1, idle-2, death-3, ability-2 |
| `grey_bastion` — Седой бастион | `shieldbearer` / `17` / `model17` | idle-1, death-3, ability-2 |
| `red_bastion` — Красный бастион | `fighter` / `11` / `model11` | idle-1, death-3, ability-2 |
| `short_cape` — Короткая накидка | `rogue` / `02` / `model02` | idle-3, death-2, ability-3 |
| `star_hood` — Капюшон звёзд | `mage` / `02` / `model02` | idle-1, idle-5, death-3, ability-5 |
| `silver_ranger` — Серебряная лучница | `archer` / `14-04` / `model14-04` | idle-1, idle-5, death-3, ability-4 |

`buff` в `SpriteFrames` — имя runtime-анимации для выбранного источника `ability`; новую механику оно не вводит. Idle-secondary есть у `watch_shield`, `star_hood` и `silver_ranger`.

## Происхождение и геометрия

`still.png` — побайтная копия выбранного `input-256.png`; каждый clip PNG — побайтная копия выбранного PixelLab `spritesheet.png`. Листы RGBA, 2048×1280, восемь колонок по 256 px и 33 позы. Кадры не извлекаются и не пересохраняются: `SpriteFrames` использует `AtlasTexture`-регионы исходного листа. Ресурсы четырёх прежних обликов сохраняют прежнее происхождение `base_commit`; поле `extension_base_commit` указывает базу расширения двумя новыми обликами.

В каталоге каждого облика лежат `still.png`, выбранные clip PNG, `frames.tres` и `skin.tres`. Координаты опоры исходника — (128,200), texture scale — 0.5. Палитра Щита дозора и Серого бастиона соответствует заданным значениям; у остальных сила палитры 0. Направление берётся из утверждённого источника.

## Тайминг и ограничения источников

Тайминги и loop берутся из выбранных `clip.json`. Частота `SpriteFrames.speed` равна `1000 / base_duration_ms`, где база — наиболее частая длительность клипа; frame `duration` хранит отношение его `duration_ms` к этой базе. Длинные последние кадры сохраняются: например, ability у новых mage/archer — 32×70ms и последний кадр700ms (2.94s). Источники содержат false для `first_frame_rgba_equal` и `last_frame_rgba_equal`: крайние позы не являются точной RGBA-копией still. Это выбранные PixelLab результаты, не утверждение о ручной художественной приёмке.

Исходные картинки не изменяются, кадры не генерируются. Покадровые PNG служат независимой необязательной проверкой видимых пикселей и alpha, если полный набор доступен; скрытый RGB прозрачных пикселей может отличаться. Частичный набор считается ошибкой. Сборка требует sheets, input images и clip metadata.

## Сборка и проверка

`python tools/art/build_character_skins.py` собирает пакет. `python tools/art/build_character_skins.py --check` сравнивает ожидаемые байты без записи. `manifest.json` содержит источники и SHA-256 27 PNG; `validation.json` фиксирует 693 видимых региона и записи длительностей.
