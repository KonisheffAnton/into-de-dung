extends RefCounted
class_name SpatialRules

const MIN_STEPS: int = -4294967296
const MAX_STEPS: int = 4294967295

class EdgeCheck extends RefCounted:
	var reason: StringName = &""
	var cost: float = 0.0
	var drop_steps: int = 0

static func inspect_edge(provider: GridDataProvider, from: Vector2i, to: Vector2i) -> EdgeCheck:
	var result := EdgeCheck.new()
	if provider == null or not provider.has_spatial_heights():
		result.reason = &"move/height_units_unsupported"
		return result
	var from_steps := provider.cell_height_steps(from)
	var to_steps := provider.cell_height_steps(to)
	if from_steps < MIN_STEPS or from_steps > MAX_STEPS or to_steps < MIN_STEPS or to_steps > MAX_STEPS:
		result.reason = &"move/height_units_unsupported"
		return result
	if not provider.cell_is_walkable(to):
		result.reason = &"move/blocked"
		return result
	var rise := to_steps - from_steps
	# Падение требует места для приземления и последствий; союзник допускает лишь проход.
	if rise < -2 and not provider.cell_can_stop(to):
		result.reason = &"move/blocked"
		return result
	if rise > 2:
		result.reason = &"move/height_step"
		return result
	var terrain_cost := provider.cell_move_cost(to)
	if not is_finite(terrain_cost) or terrain_cost < 1.0:
		result.reason = &"move/invalid_cost"
		return result
	var cost := terrain_cost + floorf(float(maxi(0, rise)) / 2.0)
	if not is_finite(cost):
		result.reason = &"move/cost_overflow"
		return result
	result.cost = cost
	result.drop_steps = maxi(0, -rise)
	return result

static func height_multiplier(signed_steps: int) -> float:
	return maxf(0.0, 1.0 + float(signed_steps) * 0.1)

static func fall_amount(hp_max: float, armor: float, drop_steps: int, voluntary: bool) -> float:
	if drop_steps < 0 or drop_steps > MAX_STEPS - MIN_STEPS: return NAN
	if drop_steps < 2 or (voluntary and drop_steps <= 2): return 0.0
	if not is_finite(hp_max) or hp_max < 0.0 or not is_finite(armor): return NAN
	@warning_ignore("integer_division")
	var levels: int = drop_steps / 2
	var quarter := hp_max * 0.25
	var scaled := quarter * float(levels)
	var raw := scaled - armor
	if not is_finite(quarter) or not is_finite(scaled) or not is_finite(raw): return NAN
	return maxf(1.0, raw)

## Guard переносит ожидаемые фазы известными delta. Ни один checkpoint не снимает baseline.
class Guard extends RefCounted:
	var refs: Dictionary = {}
	var values: Dictionary = {}
	var _ref_seal: Dictionary = {}
	var _value_seal: Dictionary = {}
	var _validated_stats_snapshots: Dictionary = {}
	var _validated_stats_values: Dictionary = {}

	func copy() -> Guard:
		var result := Guard.new()
		result.refs = refs.duplicate(true)
		result.values = values.duplicate(true)
		result._ref_seal = _ref_seal.duplicate(true)
		result._value_seal = _value_seal.duplicate(true)
		result._validated_stats_snapshots = _validated_stats_snapshots.duplicate(true)
		result._validated_stats_values = _validated_stats_values.duplicate(true)
		return result

	func seal() -> void:
		_ref_seal = refs.duplicate(true)
		_value_seal = values.duplicate(true)

	func sealed() -> bool:
		return refs == _ref_seal and values == _value_seal

	func check(context: ActionContext) -> bool:
		if not sealed() or context == null or refs.get("context") != context: return false
		var state: ItemSimulationState = refs["state"]
		var board: BattleBoard = refs["board"]
		if context._state != state or state == null or state._board != board or board == null: return false
		if refs.has("armor_rng") and (context.get_rng() != refs["armor_rng"] or context.get_rng().to_dict() != values["armor_rng"]): return false
		if state._owners != refs["owners"] or state._inventories != refs["inventories"] or state._equipment != refs["equipment"]: return false
		if state.abilities != refs.get("abilities"): return false
		if state.abilities != null and (state.abilities.catalog != refs["ability_catalog"] or state.abilities.to_dict() != values["abilities"]): return false
		if state.artifacts != refs.get("artifacts"): return false
		if state.artifacts != null:
			if state.artifacts.get_script() != BattleArtifactState or not BattleArtifactState.valid(state.artifacts.to_dict()) or not state.artifacts.references_valid(board) or state.artifacts.to_dict() != values["artifacts"]: return false
			for hero_id: int in state.artifacts.heroes:
				if state.summon_owner_id(hero_id) != 0: return false
			for item: Dictionary in state.artifacts.equipped:
				if state.summon_owner_id(item["unit_id"]) != 0: return false
		if state.environment != refs.get("environment"): return false
		if state.environment != null and state.environment.to_dict() != values["environment"]: return false
		# Проверяем raw attachment до getters, которые обходят массив и вызывают методы.
		for record: Dictionary in refs["attachments"]:
			var attachment: RefCounted = record["object"]
			if attachment.get(record["field"]) != record["attached"] or attachment.get("_closed") != record["closed"]: return false
		if board.width != values["width"] or board.height != values["height"] or board.board_version != values["expected_board_version"]: return false
		var geometry: Dictionary = values["geometry"]
		for cell: Vector2i in geometry:
			var expected: Array = geometry[cell]
			if not board.is_in_bounds(cell) or board.get_height_steps(cell) != expected[0] or board.get_terrain(cell) != expected[1] or board._occupancy.get(cell, 0) != expected[2]: return false
		var participants: Dictionary = refs["participants"]
		for id: int in participants:
			var r: Dictionary = participants[id]
			var v: Dictionary = values["participants"][id]
			var unit: UnitState = r["unit"]
			var stats: StatsBag = r["stats"]
			var vitals: Vitals = r["vitals"]
			var owner: ItemOwnerState = r["owner"]
			var resources: ActionResources = r["resources"]
			if board._units.get(id) != unit or unit.id != id or unit.stats != stats or unit.vitals != vitals or unit.action_resources != resources or vitals._stats != stats: return false
			if owner._owner != unit or owner._closed or state.get_owner(id) != owner: return false
			if r.has("armor_refs"):
				if not ArmorRuntime.same_references(owner, r["armor_refs"]) or ArmorRuntime.capture(owner) != v["armor"]: return false
			elif unit.armor != null: return false
			if [owner._inventory_registered, owner._inventory_retired, owner._equipment_registered, owner._equipment_retired] != v["lifecycle"]: return false
			if state.get_inventory(id) != r["inventory"] or state.get_equipment(id) != r["equipment"]: return false
			if unit.cell != v["cell"] or unit.height != v["height"] or board.get_height_steps(unit.cell) != v["height_steps"]: return false
			if vitals._hp != v["hp"] or vitals._is_alive != v["alive"] or vitals._balance != v["balance"] or unit.move_points_left != v["move"]: return false
			if unit.guard_stance != v["guard_stance"]: return false
			if unit.bleeding != r["bleeding"]: return false
			if unit.bleeding != null and unit.bleeding.to_dict() != v["bleeding"]: return false
			if unit.elemental != r["elemental"]: return false
			if unit.elemental != null and (unit.elemental.get_script() != ElementalState or unit.elemental.to_dict() != v["elemental"]): return false
			if unit.control != r["control"]: return false
			if unit.control != null and (unit.control.get_script() != ControlState or unit.control.to_dict() != v["control"]): return false
			if unit.combat_perks != r["combat_perks"]: return false
			if unit.combat_perks != null and (unit.combat_perks.definition != r["perk_definition"] or unit.combat_perks.to_dict() != v["combat_perks"]): return false
			if resources != null and (resources.get_owner_unit_id() != id or resources.get_main_left() != v["main"] or resources.get_bonus_left() != v["bonus"]): return false
			var occupied: Array[Vector2i] = []
			for cell: Vector2i in board._occupancy:
				if board._occupancy[cell] == id: occupied.append(cell)
			if occupied != v["occupancy"]: return false
			var current_stats_snapshot := stats.to_snapshot_dict()
			# Быстрый путь допустим лишь пока обе части публичного baseline совпадают
			# с копией, сделанной при capture; новый seal не продвигает этот cache.
			if _validated_stats_snapshots.has(id) and _validated_stats_values.has(id):
				if current_stats_snapshot == _validated_stats_snapshots[id] and v["stats"] == _validated_stats_values[id]: continue
			var stats_copy := StatsBag.from_snapshot_dict(current_stats_snapshot)
			if stats_copy == null: return false
			for type: int in v["stats"]:
				if v["stats"][type] == null:
					if stats_copy.has_stat(type): return false
					continue
				if not stats_copy.has_stat(type) or stats_copy.get_value(type) != v["stats"][type]: return false
		return true

	func ability_phase(after: Dictionary) -> Guard:
		var result := copy()
		result.values["abilities"] = after.duplicate(true)
		result.seal()
		return result

	func artifacts_phase(after: Dictionary) -> Guard:
		var result := copy()
		result.values["artifacts"] = after.duplicate(true)
		result.seal()
		return result

	func debit(id: int, main_cost: int, move_cost: float) -> Guard:
		var result := copy()
		result.values["participants"][id]["main"] -= main_cost
		result.values["participants"][id]["move"] -= move_cost
		result.seal()
		return result

	func perks_phase(id: int, state: CombatPerksState, value: Dictionary) -> Guard:
		var result := copy()
		result.refs["participants"][id]["combat_perks"] = state
		result.refs["participants"][id]["perk_definition"] = state.definition if state != null else null
		result.values["participants"][id]["combat_perks"] = value.duplicate(true)
		result.seal()
		return result

	func stance(id: int, active: bool) -> Guard:
		var result := copy()
		result.values["participants"][id]["guard_stance"] = active
		result.seal()
		return result

	func moved(id: int, destination: Vector2i) -> Guard:
		var result := copy()
		var participant: Dictionary = result.values["participants"][id]
		var origin: Vector2i = participant["cell"]
		var steps: int = result.values["geometry"][destination][0]
		result.values["geometry"][origin][2] = 0
		result.values["geometry"][destination][2] = id
		participant["cell"] = destination
		participant["height_steps"] = steps
		participant["height"] = int(floor(float(steps) / 2.0))
		participant["occupancy"] = [destination]
		result.values["expected_board_version"] += 1
		result.seal()
		return result

	func hp_phase(id: int, amount: float, death_written: bool) -> Guard:
		var result := copy()
		var participant: Dictionary = result.values["participants"][id]
		if amount > 0.0: participant["hp"] = maxf(0.0, float(participant["hp"]) - amount)
		if death_written:
			participant["alive"] = false
			participant["occupancy"] = []
			result.values["geometry"][participant["cell"]][2] = 0
			result.values["expected_board_version"] += 1
		result.seal()
		return result

	func balance_phase(id: int, after: float) -> Guard:
		var result := copy()
		result.values["participants"][id]["balance"] = after
		result.seal()
		return result

	func armor_phase(id: int, view: Dictionary) -> Guard:
		var result := copy()
		result.values["participants"][id]["armor"] = view.duplicate(true)
		result.seal()
		return result

	func rng_phase(after: Dictionary) -> Guard:
		var result := copy()
		result.values["armor_rng"] = after.duplicate(true)
		result.seal()
		return result

	func bleeding_phase(id: int, after: Dictionary) -> Guard:
		var result := copy()
		result.values["participants"][id]["bleeding"] = after.duplicate(true)
		result.seal()
		return result

	func elemental_phase(id: int, after: Dictionary) -> Guard:
		var result := copy()
		result.values["participants"][id]["elemental"] = after.duplicate(true)
		result.seal()
		return result

	func control_phase(id: int, after: Dictionary) -> Guard:
		var result := copy()
		result.values["participants"][id]["control"] = after.duplicate(true)
		result.seal()
		return result

	func hit_hp_phase(id: int, after: float, death_written: bool) -> Guard:
		var result := hp_phase(id, 0.0, death_written)
		result.values["participants"][id]["hp"] = after
		result.seal()
		return result

static func capture_guard(context: ActionContext, units: Array[UnitState], cells: Array[Vector2i], stat_types: Dictionary) -> Guard:
	if context == null or context.get_script() != ActionContext or context._state == null or context._state.get_script() != ItemSimulationState: return null
	var state := context._state
	var board := state._board
	if board == null or board.get_script() != BattleBoard or board.board_version < 0: return null
	var guard := Guard.new()
	guard.refs = {"context": context, "state": state, "board": board, "owners": state._owners.duplicate(), "inventories": state._inventories.duplicate(), "equipment": state._equipment.duplicate(), "attachments": [], "participants": {}}
	guard.values = {"board_origin_version": board.board_version, "expected_board_version": board.board_version, "width": board.width, "height": board.height, "geometry": {}, "participants": {}}
	guard.refs["abilities"] = state.abilities
	if state.abilities != null:
		if state.abilities.get_script() != BattleAbilityState or not BattleAbilityState.valid(state.abilities.to_dict()): return null
		guard.refs["ability_catalog"] = state.abilities.catalog.duplicate()
		guard.values["abilities"] = state.abilities.to_dict()
	guard.refs["artifacts"] = state.artifacts
	if state.artifacts != null:
		if state.artifacts.get_script() != BattleArtifactState or not BattleArtifactState.valid(state.artifacts.to_dict()) or not state.artifacts.references_valid(board): return null
		for hero_id: int in state.artifacts.heroes:
			if state.summon_owner_id(hero_id) != 0: return null
		for item: Dictionary in state.artifacts.equipped:
			if state.summon_owner_id(item["unit_id"]) != 0: return null
		guard.values["artifacts"] = state.artifacts.to_dict()
	guard.refs["environment"] = state.environment
	if state.environment != null: guard.values["environment"] = state.environment.to_dict()
	for owner: ItemOwnerState in state._owners:
		if owner == null or owner.get_script() != ItemOwnerState or owner._owner == null or owner._closed: return null
		guard.refs["attachments"].append({"object": owner, "field": "_owner", "attached": owner._owner, "closed": false})
	for facades: Array in [state._inventories, state._equipment]:
		for facade: RefCounted in facades:
			if facade == null or facade.get_script() not in [InventoryState, EquipmentState] or facade.get("_state") == null or facade.get("_closed"): return null
			guard.refs["attachments"].append({"object": facade, "field": "_state", "attached": facade.get("_state"), "closed": false})
	for cell: Vector2i in cells:
		if not board.is_in_bounds(cell): continue
		guard.values["geometry"][cell] = [board.get_height_steps(cell), board.get_terrain(cell), board._occupancy.get(cell, 0)]
	for unit: UnitState in units:
		if unit == null or unit.get_script() != UnitState or not board.is_in_bounds(unit.cell) or board._units.get(unit.id) != unit or board._occupancy.get(unit.cell, 0) != unit.id: return null
		var stats := unit.stats
		var vitals := unit.vitals
		var resources := unit.action_resources
		if stats == null or stats.get_script() != StatsBag or vitals == null or vitals.get_script() != Vitals or vitals._stats != stats: return null
		if not vitals._is_alive or not is_finite(vitals._hp) or vitals._hp < 0.0 or not is_finite(vitals._balance) or vitals._balance < 0.0 or not is_finite(unit.move_points_left) or unit.move_points_left < 0.0: return null
		if resources != null and (resources.get_script() != ActionResources or resources.validate(unit.id) != &""): return null
		var owner := state.get_owner(unit.id)
		if owner == null or owner._owner != unit or state._owners.count(owner) != 1: return null
		var inventory: InventoryState = null
		var equipment: EquipmentState = null
		var lifecycle := [owner._inventory_registered, owner._inventory_retired, owner._equipment_registered, owner._equipment_retired]
		if (lifecycle[0] and lifecycle[1]) or (lifecycle[2] and lifecycle[3]): return null
		var inventory_count := 0
		for facade: InventoryState in state._inventories:
			if facade._state == owner:
				inventory_count += 1
				inventory = facade
		var equipment_count := 0
		for facade: EquipmentState in state._equipment:
			if facade._state == owner:
				equipment_count += 1
				equipment = facade
		if inventory_count != (1 if lifecycle[0] else 0) or equipment_count != (1 if lifecycle[2] else 0): return null
		var stats_snapshot := stats.to_snapshot_dict()
		var stats_copy := StatsBag.from_snapshot_dict(stats_snapshot)
		if stats_copy == null: return null
		var stats_values: Dictionary = {}
		for type: int in stat_types.get(unit.id, []):
			# Старые юниты не объявляют пробивание: фиксируем отсутствие, чтобы callback
			# не мог добавить его между оплатой и попаданием незамеченным.
			if type == StatTypes.StatType.PHYSICAL_PIERCING_PERCENT and not stats_copy.has_stat(type):
				stats_values[type] = null
				continue
			if not stats_copy.has_stat(type): return null
			var value := stats_copy.get_value(type)
			if not is_finite(value): return null
			stats_values[type] = value
		guard.refs["participants"][unit.id] = {"unit": unit, "stats": stats, "vitals": vitals, "owner": owner, "resources": resources, "inventory": inventory, "equipment": equipment}
		guard.values["participants"][unit.id] = {"cell": unit.cell, "height": unit.height, "height_steps": board.get_height_steps(unit.cell), "hp": vitals._hp, "alive": vitals._is_alive, "balance": vitals._balance, "move": unit.move_points_left, "main": resources.get_main_left() if resources != null else 0, "bonus": resources.get_bonus_left() if resources != null else 0, "occupancy": [unit.cell], "lifecycle": lifecycle, "stats": stats_values}
		guard._validated_stats_snapshots[unit.id] = stats_snapshot.duplicate(true)
		guard._validated_stats_values[unit.id] = stats_values.duplicate(true)
		guard.values["geometry"][unit.cell] = [board.get_height_steps(unit.cell), board.get_terrain(unit.cell), unit.id]
		guard.values["participants"][unit.id]["guard_stance"] = unit.guard_stance
		guard.refs["participants"][unit.id]["bleeding"] = unit.bleeding
		guard.values["participants"][unit.id]["bleeding"] = unit.bleeding.to_dict() if unit.bleeding != null else {}
		if unit.bleeding != null and (unit.bleeding.get_script() != BleedingState or not BleedingState.valid(unit.bleeding.to_dict())): return null
		guard.refs["participants"][unit.id]["elemental"] = unit.elemental
		guard.values["participants"][unit.id]["elemental"] = unit.elemental.to_dict() if unit.elemental != null else {}
		if unit.elemental != null and not ElementalRules.valid_unit(unit): return null
		guard.refs["participants"][unit.id]["control"] = unit.control
		guard.refs["participants"][unit.id]["combat_perks"] = unit.combat_perks
		guard.refs["participants"][unit.id]["perk_definition"] = unit.combat_perks.definition if unit.combat_perks != null else null
		guard.values["participants"][unit.id]["combat_perks"] = unit.combat_perks.to_dict() if unit.combat_perks != null else {}
		if unit.combat_perks != null and guard.values["participants"][unit.id]["combat_perks"].is_empty(): return null
		guard.values["participants"][unit.id]["control"] = unit.control.to_dict() if unit.control != null else {}
		if unit.control != null and (unit.control.get_script() != ControlState or not ControlState.valid(unit.control.to_dict())): return null
		if unit.armor != null:
			var armor_view := ArmorRuntime.capture(owner)
			if armor_view.is_empty() or ArmorRuntime.totals(armor_view).is_empty() or context.get_rng() == null: return null
			guard.refs["participants"][unit.id]["armor_refs"] = ArmorRuntime.references(owner)
			guard.values["participants"][unit.id]["armor"] = armor_view
			guard.refs["armor_rng"] = context.get_rng()
			guard.values["armor_rng"] = context.get_rng().to_dict().duplicate(true)
	guard.seal()
	return guard if guard.check(context) else null
