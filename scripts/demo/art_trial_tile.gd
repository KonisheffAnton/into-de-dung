extends BattleDemoIsoVisual

# Таблица закрепляет рисунок за клеткой, чтобы пробный набор не менялся между боями.
const VARIANT_GRID: Array[int] = [
	0, 2, 1, 0, 1, 2,
	1, 0, 2, 1, 2, 0,
	2, 1, 0, 2, 0, 1,
	0, 1, 2, 0, 2, 1,
	2, 0, 1, 2, 1, 0,
	1, 2, 0, 1, 0, 2,
]

func sync_scene_art() -> void:
	super.sync_scene_art()
	var table_index: int = posmod(grid_anchor.y, 6) * 6 + posmod(grid_anchor.x, 6)
	var selected_index: int = VARIANT_GRID[table_index]
	for index: int in range(3):
		var variant := get_node_or_null("ArtRoot/GroundSurface/Grass%d" % index) as Polygon2D
		if variant != null:
			variant.visible = index == selected_index and _uses_ground_art()
