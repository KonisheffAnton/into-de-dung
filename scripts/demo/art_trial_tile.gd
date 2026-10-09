extends BattleDemoIsoVisual

# Разнообразная постоянная раскладка держит эталонные пучки вне игрового RNG.
const VARIANT_GRID: Array[int] = [
	2, 0, 2, 2, 0, 2, 2, 1,
	2, 3, 2, 1, 2, 0, 2, 1,
	2, 0, 2, 3, 1, 2, 0, 2,
	3, 2, 3, 2, 1, 2, 0, 2,
	2, 0, 2, 1, 3, 2, 0, 2,
	2, 3, 1, 2, 0, 2, 1, 2,
	2, 1, 2, 3, 2, 1, 0, 2,
	1, 2, 3, 2, 0, 2, 1, 0,
]

func sync_scene_art() -> void:
	super.sync_scene_art()
	var table_index: int = posmod(grid_anchor.y, 8) * 8 + posmod(grid_anchor.x, 8)
	var selected_index: int = VARIANT_GRID[table_index]
	for index: int in range(4):
		var variant := get_node_or_null("ArtRoot/GroundSurface/Grass%d" % index) as Polygon2D
		if variant != null:
			# Сетка привязывает рисунок к клетке и не меняет состояние боя.
			variant.visible = index == selected_index and _uses_ground_art()
