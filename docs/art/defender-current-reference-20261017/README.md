# Яркий Защитник как актуальный эталон

U2026-10-17: закрепить внедрённую яркую палитру эталоном в виде Защитника.
Каноническое изображение — [approved/defender_brighter_v1](../../../assets/art_presets/approved/defender_brighter_v1/README.md).

[Сравнение](comparison.png): прежний материал без цветовой коррекции слева,
действующий материал справа. [render_reference.gd](render_reference.gd) читает
PlayerWarriorSprite из production art_trial_unit и рендерит его изолированно.
Шейдер, source region, native grid и масштаб Sprite сохранены; показ увеличен4×,
brighter_palette_strength=1, без тени/HUD/варианта одежды. PNG352×320 прозрачный.

[Проверка](render-validation.json): alpha изменена у0 пикселей, RGB — у38876
видимых пикселей. Новая генерация и правки игровых PNG не выполнялись.
Истоки направления: [цветовая проба](../defender-brighter-palette-20261017/README.md),
[внедрение для всех классов](../character-brighter-palette-20261017/README.md).
Их исходники и provider PNG сохранены как происхождение.

Повтор после импорта проекта: Godot `--path <project> --screen 0 --script <absolute>/render_reference.gd -- --output=<folder> --approved=<reference-folder>`.
Выбор эталона разрешён прямым поручением U; оценка всех анимаций/F5 остаётся открытой.
