# Пробные воины

Поручение 2026-10-06: союзным воинам назначен вариант Retro Diffusion,
вражеским — PixelLab. Оригиналы 64×64 RGBA скопированы без преобразований:

| Файл | Провайдер | SHA-256 |
|---|---|---|
| warrior_ally_retro_v1.png | Retro Diffusion, RD Pro default | 267e93cc22d39cdf05e611342314c44c4d09d441e4c15ca3cdefa6bf95e7caae |
| warrior_enemy_pixellab_v1.png | PixelLab, Pixflux | be2f36099b4932f13a95ac91c9780fdf6a0d5bf778f0e9aaaa6cc8255e3eeac2 |

Описание и usage пробы — `docs/GRAPHICS_WORKFLOW.md`. Это статичные рисунки
одного ракурса, не набор направлений или финальная приёмка арта/анимации.
Масштаб, положение стоп и фильтрация задаются Sprite2D в
`scenes/demo/visuals/placeholder_unit.tscn`. Правила выбора и границы показа —
`docs/BATTLE_PRESENTATION_REWORK.md`; ядро и save-схема от рисунков не зависят.
