extends RefCounted
class_name BiomeShowcaseLayout

const SIZE: Vector2i = Vector2i(24, 16)
const CHUNK_SIZE: Vector2i = Vector2i(8, 8)
const CHUNK_ORIGINS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(8, 0), Vector2i(16, 0),
	Vector2i(0, 8), Vector2i(8, 8), Vector2i(16, 8),
]

## Повторяется только геометрия: ловушки и огонь не должны неожиданно умножать игровой риск.
static func apply(board: BattleBoard, has_authored_opening: bool) -> void:
	if board == null or board.width != SIZE.x or board.height != SIZE.y:
		return
	var terrain: Array[Dictionary] = []
	var heights: Array[Dictionary] = []
	if has_authored_opening:
		for tile: Dictionary in ExpeditionOpening.values().terrain:
			if tile.type == TerrainType.Type.WALL:
				terrain.append(tile)
		for tile: Dictionary in ExpeditionOpening.values().heights:
			heights.append(tile)
	else:
		# Для старой записи добавляем образцы только за пределами исходного участка.
		terrain.append({"cell": [3, 0], "type": TerrainType.Type.WALL})
		heights.append_array([
			{"cell": [3, 3], "steps": 1},
			{"cell": [4, 3], "steps": 2},
		])
	for chunk_index: int in range(CHUNK_ORIGINS.size()):
		if chunk_index == 0:
			continue
		var origin: Vector2i = CHUNK_ORIGINS[chunk_index]
		for tile: Dictionary in terrain:
			var cell := origin + ExpeditionOpening.cell(tile.cell)
			if board.is_in_bounds(cell):
				board.set_terrain(cell, int(tile.type) as TerrainType.Type)
		for tile: Dictionary in heights:
			var cell := origin + ExpeditionOpening.cell(tile.cell)
			if board.is_in_bounds(cell):
				board.set_height_steps(cell, int(tile.steps))
