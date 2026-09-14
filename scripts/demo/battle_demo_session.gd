extends RefCounted
class_name BattleDemoSession

## Runtime-композиция демо: UI получает один объект и не знает о связке core.

var board: BattleBoard
var state: ItemSimulationState
var context: ActionContext
var units: Array[UnitState] = []
var selected_id: int = UnitId.NONE
var last_receipt: ActionReceipt

var _queue: ActionQueue

func _init() -> void:
	reset()

func reset() -> void:
	close()
	board = BattleBoard.new(8, 8)
	_configure_map()
	var stats_list: Array[StatsBag] = []
	for _i in 6:
		stats_list.append(_demo_stats())
	units = [
		UnitState.create(Faction.Type.PLAYER, Vector2i(0, 2), stats_list[0], "Астра"),
		UnitState.create(Faction.Type.ENEMY, Vector2i(4, 2), stats_list[1], "Страж"),
		UnitState.create(Faction.Type.PLAYER, Vector2i(2, 5), stats_list[2], "Бор"),
		UnitState.create(Faction.Type.PLAYER, Vector2i(3, 5), stats_list[3], "Щит"),
		UnitState.create(Faction.Type.PLAYER, Vector2i(5, 6), stats_list[4], "Рей"),
		UnitState.create(Faction.Type.ENEMY, Vector2i(6, 6), stats_list[5], "Мишень"),
	]
	# В демо ресурсы включаются только после полной сборки определения юнита.
	for unit in units:
		unit.enable_action_resources()
		unit.try_refill_turn_resources()
		board.add_unit(unit)
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	for unit in units:
		var owner := ItemOwnerState.new(unit)
		owners.append(owner)
		inventories.append(InventoryState.new(owner))
		equipment.append(EquipmentState.new(owner))
		if unit == units[1]:
			var amulet := ItemDef.new()
			amulet.id = &"demo_guard_amulet"
			amulet.display_name = "Амулет Стража"
			var heal := HealOnDamageEffect.new()
			heal.heal_amount = 2.0
			amulet.effects.append(heal)
			var item := owner.create_item(amulet)
			if item != null:
				inventories[inventories.size() - 1].add_item(item)
	state = ItemSimulationState.new(board, owners, inventories, equipment)
	var move_rules := MoveRules.new(_unit_ids(), 1, &"spatial_move_v1")
	var definition := AttackDefinition.new()
	definition.id = &"demo_strike"
	definition.profile = AttackRules.SPATIAL_PROFILE
	var pairs: Array[Dictionary] = []
	for actor in units:
		for target in units:
			if actor.id != target.id:
				pairs.append({"actor_unit_id": actor.id, "target_unit_id": target.id})
	var attack_rules := AttackRules.new(_unit_ids(), pairs, [definition])
	# Базовый RNG намеренно не выдаёт случайных значений: команды демо не бросают кубики.
	context = ActionContext.new(state, ActionRngPort.new(), ActionEventSink.new(), [], move_rules, attack_rules)
	_queue = ActionQueue.new()
	selected_id = units[0].id
	last_receipt = null

func close() -> void:
	if state != null:
		for inventory in state.get_inventories():
			if inventory != null:
				inventory.close()
		for equipment in state.get_equipment_facades():
			if equipment != null:
				equipment.close()
		for owner in state.get_owners():
			if owner != null:
				owner.close()
	if board != null:
		board.resize(0, 0)
	state = null
	context = null
	_queue = null
	units.clear()
	selected_id = UnitId.NONE
	last_receipt = null
	board = null

func select_unit(id: int) -> bool:
	var unit: UnitState = board.get_unit_by_id(id) if board != null else null
	if unit == null or not unit.is_alive():
		return false
	selected_id = id
	return true

func selected_unit() -> UnitState:
	if board == null:
		return null
	var unit := board.get_unit_by_id(selected_id)
	return unit if unit != null and unit.is_alive() else null

func path_to(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var unit := selected_unit()
	if unit == null or board == null:
		return result
	var finder := GridPathfinder.new()
	finder.configure(board.get_bounds(), board.make_spatial_data_provider(unit), 1, &"spatial_move_v1")
	return finder.find_path(unit.cell, cell)

func reachable_cells() -> Dictionary:
	var unit := selected_unit()
	if unit == null or board == null:
		return {}
	var finder := GridPathfinder.new()
	finder.configure(board.get_bounds(), board.make_spatial_data_provider(unit), 1, &"spatial_move_v1")
	return finder.get_reachable_cells(unit.cell, unit.move_points_left)

func move_to(cell: Vector2i) -> ActionReceipt:
	var unit := selected_unit()
	if unit == null:
		return _reject(&"move/no_selected_unit")
	var path := path_to(cell)
	if path.size() < 2:
		return _reject(&"move/unreachable")
	var command := MoveCommand.new(unit.id, path, context.get_revision())
	return _submit(command)

func attack_unit(id: int) -> ActionReceipt:
	var actor := selected_unit()
	var target: UnitState = board.get_unit_by_id(id) if board != null else null
	if actor == null:
		return _reject(&"attack/no_selected_unit")
	if target == null or not target.is_alive():
		return _reject(&"attack/invalid_target")
	if actor.id == target.id:
		return _reject(&"attack/self_target")
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", context.get_revision())
	return _submit(command)

func _submit(command: Command) -> ActionReceipt:
	if _queue == null or context == null:
		return _reject(&"session/closed")
	last_receipt = _queue.submit(command, context)
	return last_receipt

func _reject(reason: StringName) -> ActionReceipt:
	var receipt := ActionReceipt.new()
	receipt.status = ActionReceipt.REJECTED
	receipt.reason = reason
	if context != null:
		receipt.revision_before = context.get_revision()
		receipt.revision_after = context.get_revision()
	last_receipt = receipt
	return receipt

func _unit_ids() -> Array[int]:
	var result: Array[int] = []
	for unit in units:
		result.append(unit.id)
	return result

func _demo_stats() -> StatsBag:
	return StatsBag.from_base_values({
		StatTypes.StatType.HP_MAX: 80.0,
		StatTypes.StatType.ARMOR: 2.0,
		StatTypes.StatType.STRENGTH: 6.0,
		StatTypes.StatType.WEAPON_DAMAGE: 4.0,
		StatTypes.StatType.IMPACT_POWER: 5.0,
		StatTypes.StatType.BALANCE_MAX: 5.0,
		StatTypes.StatType.MOVE_RANGE: 8.0,
		StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0,
		StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0,
		StatTypes.StatType.ATTACK_RANGE: 1.0,
	})

func _configure_map() -> void:
	board.set_height_steps(Vector2i(1, 2), 1)
	board.set_height_steps(Vector2i(2, 2), 2)
	board.set_height_steps(Vector2i(3, 2), 3)
	board.set_height_steps(Vector2i(4, 2), 2)
	board.set_height_steps(Vector2i(5, 2), -1)
	board.set_terrain(Vector2i(4, 5), TerrainType.Type.WALL)
	board.set_terrain(Vector2i(6, 2), TerrainType.Type.VOID)
	board.set_terrain(Vector2i(7, 2), TerrainType.Type.VOID)
	board.set_terrain(Vector2i(6, 3), TerrainType.Type.VOID)
	board.set_terrain(Vector2i(7, 3), TerrainType.Type.VOID)
	# Пара у края позволяет увидеть летальный толчок без предварительной расстановки.
	for y in range(4, 8):
		board.set_terrain(Vector2i(7, y), TerrainType.Type.VOID)
