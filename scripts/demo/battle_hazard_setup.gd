extends RefCounted
class_name BattleHazardSetup

## Новый слой стартового боя; persisted catalog/план экспедиции не переписывается.
static func opening(session: BattleCoreReactionsSession) -> void:
	var environment := session.state.environment
	environment.hazards = BattleHazards.empty()
	for cell: Vector2i in [Vector2i(2, 4), Vector2i(4, 2)]:
		if _free_floor(session, cell): BattleHazards.add_trap(environment.hazards, cell)
	var acid := Vector2i(2, 6)
	if _free_floor(session, acid): environment.hazards.acid.append(acid)
	# Лицевая клетка находится южнее существующей стены; высота уступа E4
	# на один тайл выше пластины E3 и позволяет проверить падение на неё.
	var face := Vector2i(3, 1)
	if _free_floor(session, face) and session.board.get_terrain(face + Vector2i.UP) == TerrainType.Type.WALL:
		BattleHazards.add_trap(environment.hazards, face, "wall", Vector2i.UP)

static func _free_floor(session: BattleCoreReactionsSession, cell: Vector2i) -> bool:
	return session.board.is_in_bounds(cell) and session.board.get_terrain(cell) == TerrainType.Type.FLOOR and session.board.occupant_at(cell) == null and session.state.environment.fire_at(cell).is_empty()
