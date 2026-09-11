# Модуль 1: Universal Input & Grid System ✅

## Файлы
- `scripts/core/grid/iso_grid_config.gd` — `IsoGridConfig : Resource`
  - `tile_size: Vector2` (default 128x64)
  - `height_step: float` (default 32) — сдвиг по Y на 1 уровень высоты
  - `origin_offset: Vector2`
- `scripts/core/grid/iso_grid_utils.gd` — `IsoGridUtils` (static, RefCounted)
  - `grid_to_screen(grid_pos: Vector2i, config, height_level:=0) -> Vector2`
  - `screen_to_grid_flat(world_pos: Vector2, config, height_level:=0) -> Vector2i`
  - `resolve_grid_with_height(world_pos, config, height_query: Callable, max_iterations:=3) -> Vector2i`
    — `height_query(cell) -> int`, итеративно корректирует клетку под реальную высоту
- `scripts/core/input/input_manager.gd` — Autoload `InputManager`
  - Сигналы (все в **viewport координатах**): `primary_action(pos)`, `secondary_action(pos)`,
    `long_press(pos)`, `pointer_moved(pos)`, `camera_pan(delta)`, `camera_zoom(factor, center)`
  - Обрабатывает: мышь (ЛКМ/ПКМ/колесо), touch (тап/drag/pinch), trackpad gestures
  - Настройки: `tap_max_distance`, `tap_max_time`, `long_press_time`, `mouse_wheel_zoom_step`
- `scripts/gameplay/camera/iso_camera_controller.gd` — `IsoCameraController : Camera2D`
  - Подписывается на `InputManager.camera_pan/camera_zoom`
  - Инерция пана (`pan_friction`, `pan_velocity_smoothing`), плавный зум (`zoom_smoothing_speed`, `zoom_min/max`)
- `resources/grid/default_grid_config.tres` — дефолтный `IsoGridConfig`

## Ключевое правило
Все координаты из `InputManager` — viewport-space. Перед вызовом `IsoGridUtils`
переводить в world-space через `get_viewport().get_canvas_transform().affine_inverse() * screen_pos`.

## Статус проверки
Пользователь подтвердил визуально: hover/select/pan/zoom/height всё работает корректно.
