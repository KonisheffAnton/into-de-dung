# Модуль 3: Pathfinding ✅

## Файлы
- `scripts/core/pathfinding/grid_data_provider.gd` — `GridDataProvider` (RefCounted)
  - Конструктор: `_init(is_walkable: Callable, get_height: Callable, get_move_cost: Callable)`
  - Помощники с дефолтами: `cell_is_walkable(cell)`, `cell_height(cell)`, `cell_move_cost(cell)`
- `scripts/core/pathfinding/grid_pathfinder.gd` — `GridPathfinder` (RefCounted)
  - `configure(bounds: Rect2i, data_provider: GridDataProvider, max_height_step:=1)`
  - `find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]` — собственный Dijkstra
  - `get_reachable_cells(from: Vector2i, max_cost: float) -> Dictionary[Vector2i, float]` — flood-fill
  - `is_cell_reachable(from, to, max_cost) -> bool`
  - 4-connectivity только (без диагоналей)

## ВАЖНО: отклонение от изначального плана
`AStarGrid2D` НЕ используется. Причина: он запрещает/взвешивает только ТОЧКИ,
не РЁБРА, а правило высоты (`|height(a)-height(b)| > max_height_step` запрещает
переход) — это edge-правило. Чтобы `find_path` и `get_reachable_cells` были
СОГЛАСОВАНЫ, оба реализованы через собственный Dijkstra с общей
`_can_move_between(a, b)`. Если понадобится больше производительности на
больших картах — рассмотреть оптимизацию (напр. binary heap вместо
`Array.sort_custom` на каждой итерации), сейчас это O(n log n) на каждый pop,
приемлемо для тактических сеток (десятки-сотни клеток).

## Тестовые файлы
- `debug_grid_visualizer.gd` расширен: `wall_cells`, `unit_start_cell`,
  `unit_move_range`, `max_height_step` — рисует зону хода (зелёным); путь
  считается здесь (`get_current_path_screen_points()`), но рисуется ОТДЕЛЬНЫМ
  узлом (см. ниже) в слое UI_PREVIEW, чтобы не проваливаться под платформы.
- `debug_path_overlay.gd` (новый, слой `UIPreviewLayer` z=500) — читает точки
  пути через `grid_visualizer_path` (NodePath) и рисует белую линию поверх
  ВСЕГО, включая `ElevatedTileVisual`. Системная причина: путь — это чистый
  UI-превью элемент, не должен участвовать в occlusion с игровыми объектами
  (см. `RenderLayers.Layer.UI_PREVIEW`, `DECISIONS.md`).

## Статус проверки
Пользователь подтвердил: путь строится корректно. Известная особенность:
приподнятые тайлы визуально не могут "закрыть" юнита позади (см. Модуль 2 doc) —
не относится к самому pathfinding, чисто рендеринг.
