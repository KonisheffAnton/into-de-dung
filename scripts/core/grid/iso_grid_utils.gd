extends RefCounted
class_name IsoGridUtils

## Чистые (без состояния) функции конвертации координат для изометрической сетки.
## Ничего не знает о сценах/нодах — только математика. Легко покрывается тестами.

## Логическая клетка -> позиция в мировых координатах (центр тайла).
static func grid_to_screen(grid_pos: Vector2i, config: IsoGridConfig, height_level: int = 0) -> Vector2:
	var half_w := config.tile_size.x * 0.5
	var half_h := config.tile_size.y * 0.5
	var x := float(grid_pos.x - grid_pos.y) * half_w
	var y := float(grid_pos.x + grid_pos.y) * half_h - float(height_level) * config.height_step
	return config.origin_offset + Vector2(x, y)

## Позиция в мировых координатах -> логическая клетка, БЕЗ учёта реальной высоты
## тайла под точкой (предполагается заданный height_level, по умолчанию 0).
static func screen_to_grid_flat(world_pos: Vector2, config: IsoGridConfig, height_level: int = 0) -> Vector2i:
	var half_w := config.tile_size.x * 0.5
	var half_h := config.tile_size.y * 0.5
	if half_w == 0.0 or half_h == 0.0:
		return Vector2i.ZERO

	var local := world_pos - config.origin_offset
	local.y += float(height_level) * config.height_step

	var gx := (local.x / half_w + local.y / half_h) * 0.5
	var gy := (local.y / half_h - local.x / half_w) * 0.5
	return Vector2i(roundi(gx), roundi(gy))

## Итеративное разрешение клетки с учётом реальной высоты тайлов:
## height_query(grid_pos: Vector2i) -> int должен вернуть высоту клетки под gpuess.
## Нужно, т.к. на изометрии клик может лежать в области клетки другой высоты,
## чем предполагалось изначально (height_level=0).
static func resolve_grid_with_height(
	world_pos: Vector2,
	config: IsoGridConfig,
	height_query: Callable,
	max_iterations: int = 3
) -> Vector2i:
	var height_level := 0
	var grid_pos := screen_to_grid_flat(world_pos, config, height_level)

	for _i in range(max_iterations):
		var queried_height: int = height_query.call(grid_pos)
		if queried_height == height_level:
			break
		height_level = queried_height
		var new_grid_pos := screen_to_grid_flat(world_pos, config, height_level)
		if new_grid_pos == grid_pos:
			break
		grid_pos = new_grid_pos

	return grid_pos
