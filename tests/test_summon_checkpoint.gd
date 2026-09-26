extends SceneTree

class CustomEnvironment extends BattleEnvironmentSession:
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		definition.summon_definition.hp_max = 24.0
		return definition

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SUMMON CHECKPOINT: " + label)

func _run() -> void:
	for session: BattleTacticalSession in [BattleTacticalSession.new(), BattleBleedingSession.new(), BattleEnvironmentSession.new(), CustomEnvironment.new()]:
		_projection_parity(session, false)
	for session: BattleTacticalSession in [BattleEnvironmentSession.new(), CustomEnvironment.new()]:
		_projection_parity(session, true)
	for raise_body: bool in [false, true]:
		for mutation: String in ["observe", "other_unit", "helper", "admission", "counter", "environment"]:
			_callback_guard(raise_body, mutation)
	print("SUMMON CHECKPOINT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _projection_parity(s: BattleTacticalSession, raise_body: bool) -> void:
	var actor := s.selected_unit()
	var cell := Vector2i(0, 3) if raise_body else Vector2i(0, 1)
	# Ненулевая высота проверяет именно запись BattleBoard при создании помощника.
	s.board.set_height_steps(actor.cell, 4)
	s.board.set_height_steps(cell, 4)
	var before := ItemSimulationSnapshot.capture(s.state, [])
	check(before.code == ItemSnapshotResult.Code.OK, "fixture capture")
	var source_values := before.snapshot.to_dict()
	var id := UseSummoningItemCommand.next_id(s.board)
	var admission := SummonAdmission.extend(s.context.get_move_rules(), s.context.get_attack_rules(), id, actor.id, false)
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for key: StringName in owner._definitions: definitions[key] = (owner._definitions[key] as ItemDef).duplicate(true)
	var legacy := before.snapshot.instantiate(definitions)
	check(legacy.code == ItemSnapshotResult.Code.OK, "legacy full clone")
	var copy_context := ActionContext.new(legacy.state, ActionRngPort.new(), ActionEventSink.new(), [], s.context.get_move_rules(), s.context.get_attack_rules())
	var projected: ItemSnapshotResult
	var allocator_before := UnitId.get_counter()
	if raise_body:
		var corpse: Dictionary = s.state.environment.corpses_at(cell)[0]
		var command := RaiseCorpseCommand.new(actor.id, corpse["id"], s.context.get_revision())
		check(command.validate(s.context) == &"", "raise admitted")
		var helper := command._new_helper(s.context, id, corpse)
		projected = SummonMutationProjection.expected(before.snapshot, helper, actor.id, s.board.get_height(cell), 1, 0, 0, corpse["id"])
		command._apply(copy_context, command._new_helper(copy_context, id, corpse), admission)
	else:
		var item := s.summoning_item()
		var action := item.get_use_action()
		var command := UseSummoningItemCommand.new(actor.id, item.get_item_instance_id(), cell, s.context.get_revision())
		check(command.validate(s.context) == &"", "summon admitted")
		var helper := command._new_helper(s.context, id)
		projected = SummonMutationProjection.expected(before.snapshot, helper, actor.id, s.board.get_height(cell), action.get_main_cost(), item.get_item_instance_id(), action.get_charge_cost())
		command._apply(copy_context, command._new_helper(copy_context, id), admission)
	var expected := ItemSimulationSnapshot.capture(legacy.state, [])
	check(projected.code == ItemSnapshotResult.Code.OK and expected.code == ItemSnapshotResult.Code.OK, "both checkpoints valid")
	if projected.snapshot != null and expected.snapshot != null:
		check(projected.snapshot.canonical_bytes() == expected.snapshot.canonical_bytes(), "projection equals full clone checkpoint")
	check(before.snapshot.to_dict() == source_values and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == source_values and UnitId.get_counter() == allocator_before, "projection leaves source/live/allocator intact")
	AttackForecast._close(legacy.state)
	s.close()

func _callback_guard(raise_body: bool, mutation: String) -> void:
	var s := BattleEnvironmentSession.new()
	var actor := s.selected_unit()
	var seen: Array[bool] = []
	var callback := func() -> void:
		var helper := s.state.active_summon(actor.id)
		seen.append(helper != null and actor.action_resources.get_main_left() == 0 and s.state.get_owner(helper.id).get_owner() == helper)
		match mutation:
			"other_unit": s.units[1].debug_name += "!"
			"helper": helper.debug_name += "!"
			"admission": s.context._move_rules._admitted_unit_ids.clear()
			"counter": s.context._next_root_id += 1
			"environment": s.state.environment.next_fire_id += 1
	s.board.board_changed.connect(callback)
	var receipt := s.raise_corpse(Vector2i(0, 3)) if raise_body else s.use_summoning_item(Vector2i(0, 1))
	s.board.board_changed.disconnect(callback)
	check(seen == [true], "callback sees committed spawn/payment " + mutation)
	if mutation == "observe":
		check(receipt.status == ActionReceipt.APPLIED, "read-only callback allowed")
	else:
		var reason: StringName = &"environment/invalid_mutation" if raise_body else &"summon/invalid_mutation"
		check(receipt.status == ActionReceipt.FAULTED and receipt.reason == reason and s.context.is_faulted(), "foreign mutation faults " + mutation)
		check(s.state.active_summon(actor.id) != null and actor.action_resources.get_main_left() == 0 and receipt.get_events().size() == (1 if raise_body else 2), "fault preserves completed prefix " + mutation)
	s.close()
