# Выбранный огонь29 в текущем бою — 2026-11-07

Base `f948431d9d2fe61ba6a1c053a93ce828937d3f6a`, main.
U посмотрел усиленную анимацию прямо в чате и разрешил внедрение.
[Выбранная сборка](../fire29-readable-20261106/README.md) остаётся неизменной:
26 групп,145 raw PixelLab,96 слотов по80мс,7,68с. Новых генераций нет.

`tools/art/build_fire29_animation.py --check` проверяет pinned manifest SHA,
source/raw, native snapshots0/24/48/72/96, endpoint96=0 и actual95!=0.
Экспорт для игры: crop(288,233,966,746), LANCZOS256×194 RGBA без фона,
6 атласов4×4. Все96 ячеек равны экспортированным кадрам. Это изменение
разрешения показа, новые позы/деформации не создаются.
Рабочий пакет — assets/art_presets/approved/fire29_selected_v1/.
Общие атласы занимают19,070,976 байт RGBA; расход не умножается на число клеток.

Текущий Hub выбирает dungeon_comparison_tile с selected_fire=true.
Огонь заполняет верх128×96 без нарисованной боковины; камень под огнём взят
из выбранного рисунка, боковины — из сцены. Lifecycle и точная геометрия:
[контракт](../../BATTLE_VISUAL_SCENE_CONTRACT.md#выбранный-огонь29--2026-11-07).
Механика burning, core/preview/queue/RNG/save и каталоги1–3 не меняются.

## Свежие проверки

Первый isolated Godot4.7.2/D3D12:
[report](../../../test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7/timing.json).
Import/startup PASS, fire29_animation165/0, environment_visual_contract56/0,
hazards_ui118/0, acid_tile_animation247/0, visual_scene_contract106/0.
DUNGEON1982/1 обнаружил устаревшее ожидание статичного BurningSprite.
После обновления проверки выбранного ресурса и lifecycle:
[повтор](../../../test_reports/demo-30d91f2cd58e4e44b203f82c436f24b8/timing.json),
import/startup PASS, dungeon_room_comparison1983/0.

[Огонь в текущем Hub](../../../test_reports/demo-30d91f2cd58e4e44b203f82c436f24b8/dungeon-room-comparison-screenshots/biome-01.png),
[увеличенный кадр24](../../../test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7/fire29-animation-screenshots/fire29-24.png).
Ведущий осмотрел оба снимка. Ревью — техническое APPROVE;
[сохранность/документы](../../../test_reports/fire29-flush-spikes-20261107/validation.json),
[ревью](../../../test_reports/fire29-flush-spikes-20261107/review.json).
Выбор анимации U подтверждён; посадка/читаемость в игре ещё требуют отзыва U.
Full/core и ручные F5/движение/zoom/DPI/performance не запускались.
