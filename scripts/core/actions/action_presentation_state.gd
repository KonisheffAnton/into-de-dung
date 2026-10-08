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
			"shield": unit.armor.shield.duplicate(true) if unit.armor != null else {}, "pending": state.is_summon_pending(unit.id),
			"raised_shield": unit.armor.raised_shield.duplicate(true) if unit.armor != null else {},
			"bleeding": bleeding, "elemental": elemental, "control": control,
			"main": actions.get_main_left() if actions != null else 0,
			"bonus": actions.get_bonus_left() if actions != null else 0,
			"move": unit.move_points_left, "guard": unit.guard_stance,
			"reaction": MeleeThreat.reaction_points(unit),
			"reaction_view": capture_reaction_view(state, unit),
		}
	var environment := state.environment
	var abilities: Dictionary = state.abilities.to_dict().duplicate(true) if state.abilities != null else {}
	var result := {
		"width": board.width, "height": board.height,
		"heights": heights, "terrain": terrain, "units": units,
		"fires": environment.fires.duplicate(true) if environment != null else [],
		"corpses": environment.corpses.duplicate(true) if environment != null else [],
		"collapse": environment.collapse.duplicate(true) if environment != null else {},
		"abilities": abilities,
		"action_areas": capture_action_areas(state),
	}
	if state.deck != null:
		result["deck"] = state.deck.to_dict(); result["card_effects"] = state.card_effects.to_dict()
	if environment != null and not environment.hazards.is_empty(): result["hazards"] = BattleHazards.canonical(environment.hazards)
	return result

## Только значения для показа: выбранный режим переживает снятие стойки.
## Готовность режима не обещает допустимость конкретного будущего удара.
static func capture_reaction_view(state: ItemSimulationState, unit: UnitState) -> Dictionary:
	var perks := unit.combat_perks
	var mode := perks.mode if perks != null else CombatPerksState.Mode.NONE
	if MeleeThreat.has_passive_opportunist(unit): mode = CombatPerksState.Mode.OPPORTUNIST
	var target_id := perks.cover_target_id if perks != null else UnitId.NONE
	var ready := mode != CombatPerksState.Mode.NONE and MeleeThreat.reaction_ready_state(state, unit, mode)
	var cover_valid := false
	if mode == CombatPerksState.Mode.COVER:
		var board := state.get_board()
		var ally := board.get_unit_by_id(target_id)
		cover_valid = ally != null and ally != unit and unit.is_alive() and ally.is_alive() and unit.is_friendly_to(ally) and board.occupant_at(unit.cell) == unit and board.occupant_at(ally.cell) == ally and absi(unit.cell.x - ally.cell.x) + absi(unit.cell.y - ally.cell.y) == 1 and MeleeThreat.reaches(board, unit, ally.cell)
		ready = ready and cover_valid
	var result := {"guard": unit.guard_stance, "mode": mode, "charge": MeleeThreat.reaction_points(unit),
		"uses_bonus": perks != null and perks.uses_bonus_actions,
		"owned": MeleeThreat.has_reactions(unit), "ready": ready, "cover_target_id": target_id, "cover_valid": cover_valid}
	if MeleeThreat.has_passive_opportunist(unit): result["passive_opportunist"] = true
	return result

## Область — геометрия действия, не обещание попадания по любой цели внутри неё.
static func capture_action_areas(state: ItemSimulationState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or (state.abilities != null and state.abilities.stage in ["setup", "terminal"]): return result
	var board := state.get_board()
	for unit: UnitState in board.get_all_units():
		if not unit.is_alive() or state.is_summon_pending(unit.id) or ControlRules.action_reason(unit) != &"": continue
		var stats := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict()) if unit.stats != null else null
		if stats == null: continue
		var reach := stats.get_value(StatTypes.StatType.ATTACK_RANGE)
		var cells: Array[Vector2i] = []
		for y: int in board.height:
			for x: int in board.width:
				var cell := Vector2i(x, y)
				if cell != unit.cell and board.is_terrain_walkable(cell) and AttackReachCheck.inspect_spatial_cells(board, unit.cell, unit.faction, cell, reach) == &"": cells.append(cell)
		var mode := unit.combat_perks.mode if unit.combat_perks != null else CombatPerksState.Mode.NONE
		if MeleeThreat.has_passive_opportunist(unit): mode = CombatPerksState.Mode.OPPORTUNIST
		var ready := mode in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COUNTERATTACK] and MeleeThreat.reaction_ready_state(state, unit, mode)
		result.append({"owner_id": unit.id, "name": unit.debug_name, "faction": int(unit.faction), "origin": unit.cell, "cells": cells, "mode": mode, "ready": ready})
	return result
