extends RefCounted
class_name ActionPresentationState

static func capture(state: ItemSimulationState) -> Dictionary:
	if state == null or state.get_board() == null:
		return {}
	var board := state.get_board()
	var heights := PackedInt32Array()
	var terrain := PackedByteArray()
	heights.resize(board.width * board.height)
	terrain.resize(board.width * board.height)
	for y: int in board.height:
		for x: int in board.width:
			var index := y * board.width + x
			heights[index] = board.get_height_steps(Vector2i(x, y))
			terrain[index] = board.get_terrain(Vector2i(x, y))
	var units: Dictionary = {}
	for unit: UnitState in board.get_all_units():
		if unit == null:
			continue
		# Производные значения читаем из копии, чтобы кадр не прогревал live cache.
		var stats_copy := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict()) if unit.stats != null else null
		var hp_max := stats_copy.get_value(StatTypes.StatType.HP_MAX) if stats_copy != null else 0.0
		var balance_max := stats_copy.get_value(StatTypes.StatType.BALANCE_MAX) if stats_copy != null else 0.0
		balance_max = ControlRules.balance_maximum(unit, balance_max)
		var armor: Dictionary = {}
		if unit.armor != null:
			armor = ArmorRuntime.totals(ArmorRuntime.capture(state.get_owner(unit.id)))
		var actions := unit.action_resources
		var bleeding: Dictionary = unit.bleeding.to_dict().duplicate(true) if unit.bleeding != null else {}
		var elemental: Dictionary = unit.elemental.to_dict().duplicate(true) if unit.elemental != null else {}
		var control: Dictionary = unit.control.to_dict().duplicate(true) if unit.control != null else {}
		units[unit.id] = {
			"id": unit.id, "name": unit.debug_name, "faction": int(unit.faction),
			"cell": unit.cell, "alive": unit.is_alive(),
			"hp": unit.vitals.get_hp() if unit.vitals != null else 0.0,
			"hp_max": hp_max,
			"attack_range": stats_copy.get_value(StatTypes.StatType.ATTACK_RANGE) if stats_copy != null else 1.0,
			"balance": unit.vitals.get_balance() if unit.vitals != null else 0.0,
			"balance_max": balance_max, "armor": armor.duplicate(true),
			"bleeding": bleeding, "elemental": elemental, "control": control,
			"main": actions.get_main_left() if actions != null else 0,
			"bonus": actions.get_bonus_left() if actions != null else 0,
			"move": unit.move_points_left, "guard": unit.guard_stance,
			"reaction": unit.combat_perks.reaction_left if unit.combat_perks != null else 0,
		}
	var environment := state.environment
	var abilities: Dictionary = state.abilities.to_dict().duplicate(true) if state.abilities != null else {}
	return {
		"width": board.width, "height": board.height,
		"heights": heights, "terrain": terrain, "units": units,
		"fires": environment.fires.duplicate(true) if environment != null else [],
		"corpses": environment.corpses.duplicate(true) if environment != null else [],
		"collapse": environment.collapse.duplicate(true) if environment != null else {},
		"abilities": abilities,
	}
