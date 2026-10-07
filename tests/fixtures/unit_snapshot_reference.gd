extends RefCounted
## Замороженная копия прежней сериализации нужна для проверки, что новый
## лёгкий reference DTO не меняет данные сохранённого полного снимка.
static func capture(unit: UnitState) -> Dictionary:
	if unit.get_script() != UnitState or unit.stats == null or unit.vitals == null or unit.stats.get_script() != StatsBag or unit.vitals.get_script() != Vitals or unit.ai_profile != null:
		return {}
	if unit.bleeding != null and (unit.action_resources == null or unit.armor == null):
		return {}
	if unit.bleeding != null and unit.bleeding.get_script() != BleedingState:
		return {}
	if unit.elemental != null and (unit.elemental.get_script() != ElementalState or not ElementalState.valid(unit.elemental.to_dict())):
		return {}
	if unit.control != null and (unit.control.get_script() != ControlState or unit.action_resources == null or not ControlState.valid(unit.control.to_dict())):
		return {}
	if unit.vitals._stats != unit.stats or unit.id < UnitId.FIRST or int(unit.faction) < 0 or int(unit.faction) > 2 or not is_finite(unit.move_points_left) or unit.move_points_left < 0.0:
		return {}
	var bag := unit.stats.to_snapshot_dict()
	if bag.is_empty():
		return {}
	var vital_data := unit.vitals.to_dict()
	if typeof(vital_data["hp"]) != TYPE_FLOAT or typeof(vital_data["balance"]) != TYPE_FLOAT or typeof(vital_data["is_alive"]) != TYPE_BOOL or not is_finite(vital_data["hp"]) or not is_finite(vital_data["balance"]) or vital_data["hp"] < 0.0 or vital_data["balance"] < 0.0:
		return {}
	var schema := 1
	var result := {"schema_version": schema, "id": unit.id, "faction": int(unit.faction),
		"cell_x": unit.cell.x, "cell_y": unit.cell.y, "height": unit.height,
		"debug_name": unit.debug_name, "ai_profile_path": "",
		"move_points_left": unit.move_points_left, "has_attacked": unit.has_attacked,
		"stats": bag, "vitals": vital_data}
	if unit.action_resources != null:
		if unit.action_resources.get_script() != ActionResources or unit.action_resources.validate(unit.id) != &"": return {}
		result["schema_version"] = 2
		result["action_resources"] = unit.action_resources.to_snapshot_dict()
	if unit.guard_stance:
		if unit.action_resources == null: return {}
		result["schema_version"] = 3
		result["guard_stance"] = unit.guard_stance
	if unit.armor != null:
		if unit.armor.get_script() != ArmorState or unit.action_resources == null or not ArmorState.valid(unit.armor.to_dict()): return {}
		result["schema_version"] = 4
		result["guard_stance"] = unit.guard_stance
		result["armor"] = unit.armor.to_dict()
		if unit.bleeding != null:
			if not BleedingState.valid(unit.bleeding.to_dict()): return {}
			result["schema_version"] = 5
			result["bleeding"] = unit.bleeding.to_dict()
	if unit.control != null:
		result["schema_version"] = 6
		result["control"] = unit.control.to_dict()
	if unit.combat_perks != null:
		if unit.action_resources == null or unit.combat_perks.get_script() != CombatPerksState:
			return {}
		var perks_data := unit.combat_perks.to_dict()
		if perks_data.is_empty() or (unit.combat_perks.mode == CombatPerksState.Mode.COVER and unit.combat_perks.cover_target_id == unit.id): return {}
		result["schema_version"] = 7
		result["combat_perks"] = perks_data
	if unit.elemental != null:
		if unit.action_resources == null or unit.armor == null or unit.bleeding == null or not unit.bleeding.stacked or unit.bleeding.to_dict().get("schema_version") != 3 or not BleedingState.valid(unit.bleeding.to_dict()): return {}
		result["schema_version"] = 8
		result["guard_stance"] = unit.guard_stance
		result["armor"] = unit.armor.to_dict()
		result["bleeding"] = unit.bleeding.to_dict()
		result["elemental"] = unit.elemental.to_dict()
	if unit.armor != null or unit.control != null or unit.combat_perks != null:
		# Сохраняем прежний полный валидатор, чтобы эталон учитывал итоговые комбинации.
		if not UnitState.validate_snapshot_dict(result): return {}
	return result
