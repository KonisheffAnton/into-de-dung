# Плита01 без выступающего торца — 2026-11-07

Base `f948431d9d2fe61ba6a1c053a93ce828937d3f6a`, main.
Пользователь указал на выступ после прежней подгонки размера:
[его снимок](../../../test_reports/fire29-flush-spikes-20261107/user-trap-lip.png).
Причина — часть нарисованного торца внутри внешнего ромба исходного блока.
Прежний тест проверял footprint на прозрачном фоне; совпадение размеров
не проверяло отсутствие этой фаски.

Теперь исходная внутренняя плоскость center(128,90), half(67,55) отображается
на полный тайл128×96. Все девять гнёзд сохранены; source PNG, маски металла,
три готовые позы и резкие40мс не изменены. Пустые наследованные overrides
старых FloorTrap/Panel и Rim удалены из каменного пресета: этих узлов больше нет.
Геометрия — [контракт сцен](../../BATTLE_VISUAL_SCENE_CONTRACT.md#выбранные-шипы-и-редкие-блики--2026-11-07).

Свежий isolated Godot import/startup PASS, environment_visual_contract56/0,
hazards_ui118/0. Три позы: GPU coverage1, mismatch0/65024, unallowed0.
Контроль с прежним внешним ромбом показывает1912 лишних пикселей торца.
[Лог](../../../test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7/environment_visual_contract.log).

В дополнительной сцене используются текущие dungeon terrain и environment,
соседние каменные клетки и полный игровой размер с увеличением2×:
[исправлено](../../../test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7/fire29-animation-screenshots/flush-spikes-0.png),
[прежний торец](../../../test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7/fire29-animation-screenshots/negative-old-trap-lip.png).
Это диагностическое сравнение, не интерактивный F5 и не художественная приёмка U.
Full/core, ручные движение/zoom/DPI/performance не запускались.
