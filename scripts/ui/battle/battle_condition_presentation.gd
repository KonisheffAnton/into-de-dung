class_name BattleConditionPresentation
extends RefCounted

## Иконки дополняют факты опубликованного кадра; состояния и правила здесь не вычисляются.
static func reaction_icon(view: Dictionary) -> StringName:
	match int(view.get("mode", 0)):
		CombatPerksState.Mode.OPPORTUNIST: return &"opportunist"
		CombatPerksState.Mode.COUNTERATTACK: return &"counterattack"
		CombatPerksState.Mode.COVER: return &"cover"
	return &""

static func cell_entries(terrain: int, values: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match terrain:
		TerrainType.Type.DEEP_ACID: result.append({"id": &"deep_acid", "title": "Глубокая кислота"})
		TerrainType.Type.VOID: result.append({"id": &"void", "title": "Провал"})
		TerrainType.Type.HAZARD: result.append({"id": &"hazard", "title": "Опасная поверхность"})
	# Среда на непроходимой/смертельной поверхности не рисуется и не обещается в осмотре.
	if terrain != TerrainType.Type.FLOOR: return result
	for pair: Array in [["burning", &"fire_on_tile", "Огонь"], ["acid", &"acid_pool", "Кислота"], ["spikes", &"spikes", "Кальтропы"], ["warning", &"collapse_warning", "Угроза обрушения"]]:
		if bool(values.get(pair[0], false)): result.append({"id": pair[1], "title": pair[2]})
	var corpses: Array = values.get("corpses", [])
	if not corpses.is_empty(): result.append({"id": &"corpse", "title": "Труп ×%d" % corpses.size()})
	for trap: Dictionary in values.get("traps", []):
		var floor_trap := String(trap.get("kind", "")) == "floor"
		var title := "Напольная ловушка" if floor_trap else "Настенная ловушка"
		var direction: Vector2i = trap.get("direction", Vector2i.ZERO)
		if floor_trap:
			title += " · взведена" if bool(trap.get("armed", false)) else " · не взведена"
		else:
			# У настенной ловушки нет командного таймера: -1 не означает безопасность.
			title += " " + _direction(direction) + " · при толчке в грань"
		result.append({"id": &"floor_trap" if floor_trap else &"wall_trap", "title": title})
	return result

static func _direction(direction: Vector2i) -> String:
	if direction == Vector2i.UP: return "↑"
	if direction == Vector2i.RIGHT: return "→"
	if direction == Vector2i.DOWN: return "↓"
	if direction == Vector2i.LEFT: return "←"
	return "(%d,%d)" % [direction.x, direction.y]
