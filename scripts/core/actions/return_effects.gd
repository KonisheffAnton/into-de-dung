extends RefCounted
class_name ReturnEffects

## Возвращение очищает только временные эффекты боя, сохраняя компоненты владельца.
static func cleared(unit_data: Dictionary) -> Dictionary:
	if not UnitState.validate_snapshot_dict(unit_data): return {}
	var result: Dictionary = unit_data.duplicate(true)
	result["guard_stance"] = false
	if result.has("elemental"):
		var elemental: Dictionary = result["elemental"]
		for key: String in ["burning_stacks", "burning_ticks", "poison_stacks", "poison_ticks", "wet_turns", "frozen_turns", "acid_ticks"]:
			elemental[key] = 0
		for key: String in ["burning_source", "poison_source"]:
			elemental[key] = {}
		if elemental.has("burning_contributions"):
			elemental["burning_contributions"] = []
			elemental["poison_contributions"] = []
	if result.has("bleeding"):
		var bleeding: Dictionary = result["bleeding"]
		bleeding["ticks_left"] = 0
		bleeding["source"] = {}
		bleeding["hit_id"] = ""
		bleeding["stacks"] = 0
		if bleeding.has("contributions"): bleeding["contributions"] = []
	if result.has("control"):
		result["control"]["stunned_turns"] = 0
		result["control"]["entangled_turns"] = 0
	if result.has("armor"):
		var armor: Dictionary = result["armor"]
		armor.erase("shield")
		if armor.has("raised_shield"):
			var raised: Dictionary = armor["raised_shield"]
			raised["active"] = false
			raised["blocked_root"] = 0
			raised["blocked_group"] = 0
		var lasting_grants: Array[Dictionary] = []
		for grant: Dictionary in armor["grants"]:
			if grant["expires"] == "persistent": lasting_grants.append(grant.duplicate(true))
		armor["grants"] = lasting_grants
	if result.has("combat_perks"):
		var perks: Dictionary = result["combat_perks"]
		perks["mode"] = CombatPerksState.Mode.NONE
		perks["cover_target_id"] = 0
		perks["reaction_left"] = 0
		perks["movement_stopped"] = false
	return result if UnitState.validate_snapshot_dict(result) else {}

## Обновляем поля на месте, чтобы доска и экипировка продолжали видеть те же runtime-объекты.
static func apply(unit: UnitState) -> void:
	if unit == null: return
	var clean: Dictionary = cleared(unit.to_snapshot_dict())
	if clean.is_empty(): return
	unit.guard_stance = clean["guard_stance"]
	if unit.elemental != null:
		var elemental: Dictionary = clean["elemental"]
		unit.elemental.burning_stacks = elemental["burning_stacks"]
		unit.elemental.burning_ticks = elemental["burning_ticks"]
		unit.elemental.burning_source.clear()
		unit.elemental.poison_stacks = elemental["poison_stacks"]
		unit.elemental.poison_ticks = elemental["poison_ticks"]
		unit.elemental.poison_source.clear()
		unit.elemental.wet_turns = elemental["wet_turns"]
		unit.elemental.frozen_turns = elemental["frozen_turns"]
		unit.elemental.acid_ticks = elemental["acid_ticks"]
		unit.elemental.burning_contributions.clear()
		unit.elemental.poison_contributions.clear()
	if unit.bleeding != null:
		unit.bleeding.ticks_left = 0
		unit.bleeding.source.clear()
		unit.bleeding.hit_id = ""
		unit.bleeding.stacks = 0
		unit.bleeding.contributions.clear()
	if unit.control != null:
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
	if unit.armor != null:
		unit.armor.shield.clear()
		if not unit.armor.raised_shield.is_empty():
			unit.armor.raised_shield["active"] = false
			unit.armor.raised_shield["blocked_root"] = 0
			unit.armor.raised_shield["blocked_group"] = 0
		var persistent_grants: Array[Dictionary] = []
		for grant: Dictionary in unit.armor.grants:
			if grant["expires"] == "persistent": persistent_grants.append(grant)
		unit.armor.grants.clear()
		unit.armor.grants.append_array(persistent_grants)
	if unit.combat_perks != null:
		unit.combat_perks.mode = CombatPerksState.Mode.NONE
		unit.combat_perks.cover_target_id = 0
		unit.combat_perks.reaction_left = 0
		unit.combat_perks.movement_stopped = false
