> **ИСТОРИЧЕСКАЯ КАРТОЧКА модуля.** Описывает ранний этап, может содержать
> заменённые API/правила и статусы. Не использовать как текущее ТЗ.
> Актуальное устройство — [ARCHITECTURE](../ARCHITECTURE.md),
> действующие контракты — [PROJECT_CONTEXT](../PROJECT_CONTEXT.md).

# Модуль 2: Y-Sorting & Z-Ordering ✅

## Файлы
- `scripts/core/rendering/render_layers.gd` — `RenderLayers` (static)
  - `enum Layer { GROUND_EFFECTS, TILES, ENTITIES, PROJECTILES, VFX_OVERLAY, UI_PREVIEW }`
  - `z_index_for(layer) -> int` (шаг 100 на слой)
- `scripts/core/rendering/y_sortable.gd` — `YSortable : Node2D`
  - `@export grid_anchor: Vector2i`, `@export height_level: int`, `@export grid_config: IsoGridConfig`
  - `_update_sort_position()` — `position = grid_to_screen(grid_anchor, config, height=0)` (высота ИГНОРИРУЕТСЯ для сортировки!)
  - `get_visual_offset() -> Vector2` — визуальный сдвиг для отрисовки (`-height_level * height_step`)
  - `set_grid_anchor(anchor, height)`

## Ключевое правило (см. DECISIONS.md)
- `TILES` (z=100) < `ENTITIES` (z=200) < `PROJECTILES` (z=300) — фиксированный порядок слоёв.
- Внутри `ENTITIES` — Godot `y_sort_enabled=true` на родительской ноде.
- Сортировочная позиция ВСЕГДА берётся при height=0. Визуальный подъём — отдельно
  через `get_visual_offset()`. Не путать эти два понятия при реализации будущих юнитов.
- **РЕШЕНО**: `ElevatedTileVisual : YSortable` (`scripts/core/rendering/elevated_tile_visual.gd`)
  реализует именно это — платформа с визуальным объёмом (верх + боковая
  грань), живёт в ENTITIES, корректно перекрывает/перекрывается юнитами по
  Y-sort. См. DECISIONS.md за подробностями.

## Тестовые файлы (не финальная архитектура)
- `scripts/test/debug_unit_placeholder.gd` (extends YSortable) — цветной круг + label
- `scripts/test/debug_projectile_placeholder.gd` — летает по синусоиде, свободные координаты

## Статус проверки
Подтверждено headless-прогоном + математической проверкой sort-key по скриншоту
пользователя. Визуальное "наложение" кругов на скрине — ожидаемый артефакт
плейсхолдера (круг вместо спрайта с нижним якорем), не баг сортировки.
