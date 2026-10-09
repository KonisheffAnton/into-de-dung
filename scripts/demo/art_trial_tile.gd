extends BattleDemoIsoVisual

# Пустые клетки оставляют поля тишины вокруг небольших сгруппированных куртин.
const VARIANT_GRID: Array[int] = [
	0, 0, 0, 3, 0, 0, 0, 0,
	0, 0, 1, 2, 0, 0, 0, 0,
	0, 0, 4, 0, 0, 0, 2, 3,
	0, 0, 0, 0, 0, 0, 1, 4,
	2, 3, 0, 0, 0, 0, 0, 0,
	4, 1, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 3, 0, 0, 0,
	0, 0, 0, 1, 4, 0, 0, 0,
]

func sync_scene_art() -> void:
	super.sync_scene_art()
	var table_index: int = posmod(grid_anchor.y, 8) * 8 + posmod(grid_anchor.x, 8)
	var selected_index: int = VARIANT_GRID[table_index]
	for index: int in range(5):
		var variant := get_node_or_null("ArtRoot/GroundSurface/Grass%d" % index) as Node2D
		if variant != null:
			# Постоянная таблица сохраняет группы и не расходует игровой RNG.
			variant.visible = index == selected_index and _uses_ground_art()
