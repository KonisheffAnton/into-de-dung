extends RefCounted
class_name BiomeArtCatalog

# Шесть фиксированных участков; выбор рисунка не расходует игровой RNG.
const IDS: Array[String] = ["stone", "forest", "ice", "volcanic", "desert", "swamp"]
const FLOORS: Array[Texture2D] = [
	preload("res://assets/art_presets/trials/dungeon_room_v2/floor.png"),
	preload("res://assets/art_presets/trials/biomes_v1/forest/floor.png"),
	preload("res://assets/art_presets/trials/biomes_v1/ice/floor.png"),
	preload("res://assets/art_presets/trials/biomes_v1/volcanic/floor.png"),
	preload("res://assets/art_presets/trials/biomes_v1/desert/floor.png"),
	preload("res://assets/art_presets/trials/biomes_v1/swamp/floor.png"),
]
const SIDES: Array[Texture2D] = [
	preload("res://assets/art_presets/trials/dungeon_room_v2/masonry.png"),
	preload("res://assets/art_presets/trials/biomes_v1/forest/side.png"),
	preload("res://assets/art_presets/trials/biomes_v1/ice/side.png"),
	preload("res://assets/art_presets/trials/biomes_v1/volcanic/side.png"),
	preload("res://assets/art_presets/trials/biomes_v1/desert/side.png"),
	preload("res://assets/art_presets/trials/biomes_v1/swamp/side.png"),
]
const OBSTACLES: Array[Texture2D] = [
	preload("res://assets/art_presets/trials/dungeon_room_v2/column.png"),
	preload("res://assets/art_presets/trials/biomes_v1/forest/prop.png"),
	preload("res://assets/art_presets/trials/biomes_v1/ice/prop.png"),
	preload("res://assets/art_presets/trials/biomes_v1/volcanic/prop.png"),
	preload("res://assets/art_presets/trials/biomes_v1/desert/prop.png"),
	preload("res://assets/art_presets/trials/biomes_v1/swamp/prop.png"),
]
const REGIONS: Array[Rect2] = [Rect2(216, 374, 624, 780), Rect2(42, 139, 1041, 1147), Rect2(187, 86, 831, 1197), Rect2(205, 95, 787, 1160), Rect2(257, 118, 646, 1142), Rect2(197, 106, 884, 1165)]
const HEIGHTS: Array[float] = [90.0, 90.0, 94.0, 94.0, 100.0, 94.0]

static func index_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= 24 or cell.y >= 16: return 0
	return cell.x / 8 + (cell.y / 8) * 3

static func is_obstacle(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < 24 and cell.y < 16 and Vector2i(posmod(cell.x, 8), posmod(cell.y, 8)) == Vector2i(3, 0)
