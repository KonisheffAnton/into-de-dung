extends SceneTree

var passed: int = 0
var failed: int = 0

class InternalAcidParent extends Command:
	var unit: UnitState
	var tick: bool
	var standing: bool
	func _init(p_unit: UnitState, p_tick: bool = false, p_standing: bool = false) -> void:
		unit = p_unit
		tick = p_tick
		standing = p_standing
	func get_kind() -> StringName: return &"acid_test_parent"
	func copy_for_queue() -> Command: return InternalAcidParent.new(unit, tick, standing)
	func validate(context: ActionContext) -> StringName: return AcidCommand.new(unit, tick, standing).validate(context)
	func execute(_context: ActionContext) -> CommandStepResult:
		var mandatory: Array[Command] = [AcidCommand.new(unit, tick, standing)]
		return CommandStepResult.applied([], mandatory)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_state_codec()
	_apply_and_tick()
	_armor_order_and_no_health_damage()
	_zero_armor_and_unrelated_statuses()
	_queue_simulation_parity()
	_overflow_and_invalid_runtime()
	_root_rejection()
	_signal_guard()
	print("ACID RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ACID: " + label)

func _fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_height_steps(Vector2i(x, y), 0)
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	session.state.abilities = null
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	session.state.environment.fires.clear()
	for unit: UnitState in session.units:
		unit.elemental.acid_ticks = 0
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
		if unit.is_alive():
			unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
			unit.vitals._hp = 100.0
	session.board.move_unit(session.units[1], Vector2i(2, 2))
	return session

func _submit(session: BattleCoreReactionsSession, unit: UnitState, tick: bool = false, standing: bool = false) -> ActionReceipt:
	return session._queue.submit(InternalAcidParent.new(unit, tick, standing), session.context)

func _fill_equipped_armor(session: BattleCoreReactionsSession, unit: UnitState) -> ItemInstance:
	var owner := session.state.get_owner(unit.id)
	var candidates: Array[ItemInstance] = []
	for id: int in owner._items:
		var item: ItemInstance = owner._items[id]
		if item._placement >= ItemOwnerState.EQUIPMENT_BASE and item.get_definition().armor_max > 0:
			item.armor_remaining = item.get_definition().armor_max
			candidates.append(item)
	candidates.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		return a.armor_origin_owner < b.armor_origin_owner or (a.armor_origin_owner == b.armor_origin_owner and a.armor_origin_item < b.armor_origin_item))
	return candidates[0] if not candidates.is_empty() else null

func _state_codec() -> void:
	var state := ElementalState.new()
	var schema_one := state.to_dict()
	_check(schema_one.size() == 7 and schema_one.schema_version == 1 and not schema_one.has("acid_ticks"), "zero acid preserves the exact schema 1 shape")
	var old_state := ElementalState.from_dict(schema_one)
	_check(old_state != null and old_state.to_dict() == schema_one, "legacy schema 1 round trips unchanged")
	state.acid_ticks = 2
	var schema_two := state.to_dict()
	_check(schema_two.size() == 8 and schema_two.schema_version == 2 and schema_two.acid_ticks == 2, "positive acid uses schema 2 with one new field")
	var restored := ElementalState.from_dict(schema_two)
	_check(restored != null and restored.to_dict() == schema_two, "schema 2 round trips without aliasing values")
	schema_two["acid_ticks"] = -1
	_check(not ElementalState.valid(schema_two), "negative serialized acid is malformed")
	schema_two["acid_ticks"] = 0
	_check(not ElementalState.valid(schema_two), "schema 2 cannot encode zero acid")
	schema_two["acid_ticks"] = "1"
	_check(not ElementalState.valid(schema_two), "schema 2 requires an integer acid duration")
	var extra := schema_one.duplicate(true)
	extra["acid_ticks"] = 1
	_check(not ElementalState.valid(extra), "schema 1 rejects extra fields")

func _apply_and_tick() -> void:
	var session := _fixture()
	var unit := session.units[1]
	unit.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 30, "expires": "battle", "battle_id": unit.armor.battle_id}]
	unit.armor.next_grant_id = 2
	var hp_before: float = unit.vitals.get_hp()
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var first := _submit(session, unit)
	_check(first.status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 1, "entry applies one acid tick while fully armored")
	_check(unit.vitals.get_hp() == hp_before and unit.armor.grants[0]["remaining"] == 30, "entry deals no immediate armor or HP damage")
	var copied := AcidCommand.new(unit, true, true).copy_for_queue() as AcidCommand
	_check(copied != null and copied.get_kind() == &"acid_tick", "queued copy preserves tick command")
	var standing := _submit(session, unit, true, true)
	_check(standing.status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 2, "standing in acid accumulates duration at own turn start")
	_check(unit.armor.grants[0]["remaining"] == 20 and unit.vitals.get_hp() == hp_before, "standing tick deals exactly ten armor and no HP damage")
	_check(session.context.get_rng().to_dict() == rng_before, "acid application and damage consume no RNG")
	var outside := _submit(session, unit, true, false)
	_check(outside.status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 1 and unit.armor.grants[0]["remaining"] == 10, "outside tick consumes one duration and deals ten armor")
	outside = _submit(session, unit, true, false)
	_check(outside.status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 0 and unit.elemental.to_dict().schema_version == 1, "final outside tick expires acid to exact schema 1")
	_check(unit.vitals.get_hp() == hp_before and unit.armor.grants[0]["remaining"] == 0, "fixed damage remains armor-only through expiration")
	session.close()

func _armor_order_and_no_health_damage() -> void:
	var session := _fixture()
	var unit := session.units[1]
	var equipped := _fill_equipped_armor(session, unit)
	var equipped_before: int = equipped.armor_remaining if equipped != null else 0
	var owner := session.state.get_owner(unit.id)
	unit.armor.grants = [
		{"grant_id": 1, "source": "persistent", "remaining": 2, "expires": "persistent", "battle_id": unit.armor.battle_id},
		{"grant_id": 2, "source": "battle", "remaining": 5, "expires": "battle", "battle_id": unit.armor.battle_id}
	]
	unit.armor.next_grant_id = 3
	var reserve: ItemInstance
	for id: int in owner._items:
		var item: ItemInstance = owner._items[id]
		if item._placement == ItemOwnerState.INVENTORY_PLACEMENT and item.get_definition().armor_max > 0:
			reserve = item
			item.armor_remaining = item.get_definition().armor_max
			break
	var total_before: int = int(ArmorRuntime.totals(ArmorRuntime.capture(owner))["current"])
	var equipment_before: Dictionary = {}
	for item: ItemInstance in owner._items.values():
		if item._placement >= ItemOwnerState.EQUIPMENT_BASE and item.get_definition().armor_max > 0: equipment_before[item.get_item_instance_id()] = item.armor_remaining
	var hp_before: float = unit.vitals.get_hp()
	_check(_submit(session, unit).status == ActionReceipt.APPLIED, "acid fixture accepts entry before damage tick")
	var receipt := _submit(session, unit, true, false)
	_check(receipt.status == ActionReceipt.APPLIED, "acid tick applies across grants and equipment")
	_check(unit.armor.grants[1]["remaining"] == 0 and unit.armor.grants[0]["remaining"] == 0, "battle grant is consumed before persistent grant")
	_check(equipped != null and equipped.armor_remaining == equipped_before - 3, "remaining acid damage consumes the first canonical equipped item after grants")
	var later_equipment_unchanged: bool = true
	for item: ItemInstance in owner._items.values():
		if item._placement >= ItemOwnerState.EQUIPMENT_BASE and item.get_definition().armor_max > 0 and item != equipped:
			later_equipment_unchanged = later_equipment_unchanged and item.armor_remaining == equipment_before[item.get_item_instance_id()]
	_check(later_equipment_unchanged, "later equipped items remain untouched after canonical armor item")
	_check(reserve == null or reserve.armor_remaining == reserve.get_definition().armor_max, "inventory reserve armor is never consumed")
	var total_after: int = int(ArmorRuntime.totals(ArmorRuntime.capture(owner))["current"])
	_check(total_before >= 10 and total_after == total_before - 10 and unit.vitals.get_hp() == hp_before, "damage is exactly ten armor with HP unchanged")
	var armor_events: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"armor_changed": armor_events.append(event)
	_check(armor_events.size() == 1 and armor_events[0]["actor_unit_id"] == 0 and armor_events[0]["source"]["kind"] == &"status", "armor change emits one status-source event")
	session.close()

func _zero_armor_and_unrelated_statuses() -> void:
	var session := _fixture()
	var unit := session.units[1]
	unit.elemental.wet_turns = 2
	unit.elemental.frozen_turns = 1
	unit.bleeding.stacked = true
	unit.bleeding.ticks_left = 2
	unit.bleeding.stacks = 1
	unit.bleeding.source = DamageSource.new(&"attack", 0, session.units[0].cell, session.units[0].id, session.units[0].id).to_dict()
	unit.bleeding.hit_id = "acid-independence"
	var before_status := unit.elemental.to_dict()
	var hp_before: float = unit.vitals.get_hp()
	_check(_submit(session, unit).status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 1, "zero-armor unit acquires acid")
	var tick := _submit(session, unit, true, false)
	_check(tick.status == ActionReceipt.APPLIED and unit.elemental.acid_ticks == 0, "zero-armor acid duration still expires")
	var after_status := unit.elemental.to_dict()
	_check(after_status["wet_turns"] == before_status["wet_turns"] and after_status["frozen_turns"] == before_status["frozen_turns"] and after_status["burning_ticks"] == before_status["burning_ticks"], "acid does not react with wet, freeze, or fire")
	_check(unit.bleeding.to_dict()["ticks_left"] == 2 and unit.vitals.get_hp() == hp_before, "acid has no bleed or health side effect")
	var fire_session := _fixture()
	var burning_unit := fire_session.units[1]
	var fire_source := DamageSource.new(&"attack", 0, fire_session.units[0].cell, fire_session.units[0].id, fire_session.units[0].id)
	burning_unit.elemental.burning_stacks = 1
	burning_unit.elemental.burning_ticks = 2
	burning_unit.elemental.burning_source = fire_source.to_dict()
	_check(_submit(fire_session, burning_unit).status == ActionReceipt.APPLIED and burning_unit.elemental.burning_stacks == 1 and burning_unit.elemental.burning_ticks == 2 and burning_unit.elemental.acid_ticks == 1, "acid does not extinguish or extend fire")
	fire_session.close()
	var pending := session.units[2]
	session.state._summons.append({"unit_id": pending.id, "owner_unit_id": session.units[0].id, "pending": true})
	var pending_result := AcidCommand.new(pending).execute(session.context)
	_check(pending_result.status == CommandStepResult.SKIPPED and pending_result.reason == &"summon/pending", "pending unit does not acquire acid")
	var dead := session.units[2]
	dead.vitals._hp = 0.0
	dead.vitals._is_alive = false
	var dead_result := AcidCommand.new(dead).execute(session.context)
	_check(dead_result.status == CommandStepResult.SKIPPED and dead_result.reason == &"status/dead_target", "dead target command is safely skipped")
	_check(dead.elemental.acid_ticks == 0, "dead target does not acquire acid")
	session.close()

func _overflow_and_invalid_runtime() -> void:
	var session := _fixture()
	var unit := session.units[1]
	unit.elemental.acid_ticks = ElementalState.MAX_VALUE
	var before_state := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var overflow := _submit(session, unit)
	_check(overflow.status == ActionReceipt.REJECTED and overflow.reason == &"status/duration_exhausted", "acid overflow rejects before any mutation")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before_state, "overflow leaves the full state unchanged")
	unit.elemental.acid_ticks = -1
	_check(not ElementalRules.valid_unit(unit), "negative runtime acid is not silently normalized")
	var invalid := _submit(session, unit)
	_check(invalid.status == ActionReceipt.REJECTED, "invalid runtime acid refuses command")
	session.close()

func _root_rejection() -> void:
	var session := _fixture()
	var unit := session.units[1]
	var snapshot_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters().duplicate(true)
	var receipt := session._queue.submit(AcidCommand.new(unit), session.context)
	_check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"hazard/internal_command",
		"direct root AcidCommand is rejected as an internal hazard command")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == snapshot_before
		and session.context.get_rng().to_dict() == rng_before
		and session.context.simulation_counters() == counters_before,
		"root rejection preserves snapshot, RNG, and simulation counters")
	session.close()

func _queue_simulation_parity() -> void:
	var session := _fixture()
	var unit := session.units[1]
	unit.elemental.acid_ticks = 2
	unit.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 20, "expires": "battle", "battle_id": unit.armor.battle_id}]
	unit.armor.next_grant_id = 2
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	_check(capture.code == ItemSnapshotResult.Code.OK, "acid parity captures live state")
	if capture.code != ItemSnapshotResult.Code.OK:
		session.close()
		return
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for definition_id: StringName in owner._definitions:
			definitions[definition_id] = (owner._definitions[definition_id] as ItemDef).duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	_check(restored.code == ItemSnapshotResult.Code.OK, "acid parity instantiates isolated state")
	if restored.code != ItemSnapshotResult.Code.OK:
		session.close()
		return
	var rng_copy := session.context.get_rng().clone()
	var context_copy := session.context.copy_for_simulation(ItemSimulationState.new(null, [], [], []), rng_copy)
	var queue_copy := session._queue.copy_for_simulation()
	_check(context_copy != null and queue_copy != null, "acid parity copies command context and queue")
	if context_copy == null or queue_copy == null:
		session.close()
		return
	context_copy._state = restored.state
	var isolated_unit := restored.state.get_board().get_unit_by_id(unit.id)
	var isolated_receipt := queue_copy.submit(InternalAcidParent.new(isolated_unit, true, true), context_copy)
	var live_receipt := _submit(session, unit, true, true)
	var isolated_after := ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict()
	var live_after := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	_check(isolated_receipt.status == live_receipt.status and isolated_receipt.get_events() == live_receipt.get_events(), "acid preview and live queue match events")
	_check(isolated_after == live_after and context_copy.get_rng().to_dict() == session.context.get_rng().to_dict(), "acid preview and live queue match snapshots and RNG")
	_check(isolated_unit.elemental.acid_ticks == 3 and unit.elemental.acid_ticks == 3, "standing acid accumulates in both isolated and live execution")
	ForecastSimulation.close(restored.state)
	session.close()

func _signal_guard() -> void:
	var session := _fixture()
	var unit := session.units[1]
	unit.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 15, "expires": "battle", "battle_id": unit.armor.battle_id}]
	unit.armor.next_grant_id = 2
	_check(_submit(session, unit).status == ActionReceipt.APPLIED, "signal guard fixture applies acid")
	var corrupt := func(_kind: StringName, _id: int, _before: int, _after: int) -> void: unit.vitals._hp -= 1.0
	unit.armor.changed.connect(corrupt)
	var receipt := _submit(session, unit, true, false)
	_check(receipt.status == ActionReceipt.FAULTED, "armor signal mutation faults the acid command")
	_check(unit.armor.grants[0]["remaining"] == 5 and unit.vitals.get_hp() == 99.0, "guard preserves committed armor prefix and callback mutation")
	_check(unit.elemental.acid_ticks == 0, "fault retains already committed duration tick")
	var found_event: bool = false
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"armor_changed": found_event = true
	_check(found_event, "fault receipt retains armor mutation event prefix")
	unit.armor.changed.disconnect(corrupt)
	session.close()
