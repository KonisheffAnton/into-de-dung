extends SceneTree

var passed: int = 0
var failed: int = 0

class CursorRng extends ActionRngPort:
	var cursor: int = 29
	func clone() -> ActionRngPort:
		var copy := CursorRng.new()
		copy.cursor = cursor
		return copy
	func to_dict() -> Dictionary: return {"cursor": cursor}

class NoCloneRng extends ActionRngPort:
	func to_dict() -> Dictionary: return {"cursor": 4}

class AliasRng extends ActionRngPort:
	func clone() -> ActionRngPort: return self

class WrongRng extends CursorRng:
	func clone() -> ActionRngPort:
		var copy := WrongRng.new()
		copy.cursor = 0
		return copy

class CountingSink extends ActionEventSink:
	var calls: int = 0
	func publish(_event: Dictionary) -> void: calls += 1

class UnknownCommand extends UseHealingItemCommand:
	func validate(_context: ActionContext) -> StringName:
		push_error("Unsupported command must never run")
		return &""

class CustomSession extends BattleTacticalSession:
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		definition.summon_definition.hp_max = 21.0
		definition.summon_definition.main_actions_max = 2.0
		definition.summon_definition.name_prefix = "Спутник · "
		return definition

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ITEM FORECAST: " + label)

func fixture(s: BattleTacticalSession = null) -> BattleTacticalSession:
	if s == null: s = BattleTacticalSession.new()
	s.context._rng = CursorRng.new()
	s.context._sink = CountingSink.new()
	s.context._revision = 13
	s.context._next_root_id = 7
	s.context._next_command_seq = 31
	s.context._next_event_seq = 41
	return s

func snapshot(s: BattleTacticalSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "valid fixture snapshot: " + capture.reason)
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func command(s: BattleTacticalSession, summon: bool = false) -> Command:
	var item := s.summoning_item() if summon else s.healing_item()
	return s.item_command(s.selected_id, item.get_item_instance_id(), Vector2i(0, 1))

func parity(s: BattleTacticalSession, cmd: Command, label: String, expected: StringName = ActionReceipt.APPLIED) -> ItemUseForecast:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var admission := SummonAdmission.values(s.context)
	var next_id := UnitId.get_counter()
	var selected := s.selected_id
	var phase := s.phase
	var last := s.last_receipt
	var sink := s.context.get_sink() as CountingSink
	var sink_before := sink.calls
	var signals: Array[int] = []
	var actor := s.board.get_unit_by_id(s.selected_id)
	var callback := func(_before: float, _after: float) -> void: signals.append(1)
	var board_callback := func() -> void: signals.append(2)
	actor.vitals.hp_changed.connect(callback)
	s.board.board_changed.connect(board_callback)
	var first := ItemUseForecast.build(s.context, s._queue, cmd)
	var second := ItemUseForecast.build(s.context, s._queue, cmd)
	check(first.status == expected, label + " expected status: " + String(first.reason))
	check(first.snapshot_before == before and first.admission_before == admission, label + " complete before")
	check(first.status == second.status and first.reason == second.reason and first.events == second.events and first.steps == second.steps and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after and first.admission_after == second.admission_after and first.units == second.units and first.items == second.items, label + " identical previews")
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and SummonAdmission.values(s.context) == admission, label + " live snapshot/counters/RNG/admission isolated")
	check(UnitId.get_counter() == next_id and s.selected_id == selected and s.phase == phase and s.last_receipt == last and sink.calls == sink_before and signals.is_empty() and not s.context.is_faulted(), label + " allocator/session/signals/sink isolated")
	var receipt := s._queue.submit(cmd, s.context)
	actor.vitals.hp_changed.disconnect(callback)
	s.board.board_changed.disconnect(board_callback)
	check(receipt.status == first.status and receipt.reason == first.reason and receipt.get_events() == first.events and receipt.get_steps() == first.steps, label + " complete receipt parity")
	check(snapshot(s) == first.snapshot_after and s.context.simulation_counters() == first.counters_after and s.context.get_rng().to_dict() == first.rng_after and SummonAdmission.values(s.context) == first.admission_after, label + " complete after parity")
	check(sink.calls - sink_before == receipt.get_events().size(), label + " only live publishes")
	if expected != ActionReceipt.APPLIED: check(first.units.is_empty() and first.items.is_empty(), label + " no ready result on failure")
	return first

func refuse(s: BattleTacticalSession, cmd: Command, reason: StringName) -> void:
	var f := parity(s, cmd, "refusal " + String(reason), ActionReceipt.REJECTED)
	check(f.reason == reason, "exact refusal: " + String(f.reason))

func _run() -> void:
	_healing()
	_summoning()
	_refusals()
	_gates_and_capabilities()
	_limits()
	_restore_and_cleanup()
	print("ITEM FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _healing() -> void:
	for deficit: float in [5.0, 20.0]:
		var s := fixture()
		var actor := s.selected_unit()
		actor.vitals.apply_damage(deficit)
		actor.guard_stance = true
		var f := parity(s, command(s), "heal deficit " + str(deficit))
		check(f.units[actor.id]["after"]["hp"] == minf(32.0, 32.0 - deficit + 12.0), "heal clamps to deficit")
		check(f.units[actor.id]["after"]["main"] == 0 and f.units[actor.id]["after"]["bonus"] == 1 and f.units[actor.id]["after"]["guard_stance"], "main only and stance preserved")
		check(f.items[s.healing_item().get_item_instance_id()] == {"actor_id": actor.id, "before": {"charges": 2}, "after": {"charges": 1}}, "affected item charges")
		s.close()
	var custom := fixture()
	var actor := custom.selected_unit()
	actor.vitals.apply_damage(20.0)
	var definition := ItemDef.new()
	definition.id = &"k3_custom_flask"
	definition.use_heal_amount = 7.5
	definition.max_charges = 3
	var item := custom.state.get_owner(actor.id).create_item(definition)
	custom.state.get_inventory(actor.id).add_item(item)
	var f := parity(custom, custom.item_command(actor.id, item.get_item_instance_id()), "custom healing")
	check(f.units[actor.id]["after"]["hp"] == 19.5 and f.items[item.get_item_instance_id()]["after"]["charges"] == 2, "custom values from live definition")
	custom.close()
	var k2 := fixture(BattleCoreCombinationSession.new())
	k2.selected_unit().vitals.apply_damage(20.0)
	var preview := k2.preview_healing_item()
	f = parity(k2, command(k2), "K2 heal with armor/environment/control")
	check(preview.snapshot_after == f.snapshot_after and preview.events == f.events, "session healing matches direct execution")
	k2.close()

func _summoning() -> void:
	for custom: bool in [false, true]:
		var s := fixture(CustomSession.new() if custom else BattleTacticalSession.new())
		var actor := s.selected_unit()
		actor.guard_stance = true
		var preview := s.preview_summoning_item(Vector2i(0, 1))
		var id := UseSummoningItemCommand.next_id(s.board)
		var f := parity(s, command(s, true), "custom summon" if custom else "default summon")
		check(preview.snapshot_after == f.snapshot_after and preview.admission_after == f.admission_after, "session summoning parity")
		check(f.units.has(id), "new helper included")
		if f.units.has(id):
			var after: Dictionary = f.units[id]["after"]
			check(f.units[id]["before"] == null and after["id"] == id and after["cell"] == Vector2i(0, 1) and after["owner_unit_id"] == actor.id and after["pending"], "new helper identity and absent before")
			check(after["hp"] == (21.0 if custom else 16.0) and after["main"] == 0 and after["bonus"] == 0 and after["move"] == 0.0, "helper template without refill")
			check(s.board.occupant_at(Vector2i(0, 1)).id == id and not s.context.get_move_rules().allows(id) and not s.context.get_attack_rules()._actors.has(id), "pending occupancy and inactive admission")
			check(s.context.get_attack_rules().allows(s.units[1].id, id), "pending immediately targetable")
		check(f.units[actor.id]["after"]["guard_stance"] and f.units[actor.id]["after"]["bonus"] == f.units[actor.id]["before"]["bonus"] and f.units[actor.id]["after"]["move"] == f.units[actor.id]["before"]["move"], "summon preserves unrelated resources")
		actor.try_refill_turn_resources()
		refuse(s, command(s, true), &"summon/active_helper")
		s.close()

func _refusals() -> void:
	for summon: bool in [false, true]:
		for mode: String in ["main", "charges", "inactive", "missing", "kind", "stale", "dead", "admission"]:
			var s := fixture()
			var actor := s.selected_unit()
			var item := s.summoning_item() if summon else s.healing_item()
			actor.vitals.apply_damage(5.0)
			var cmd := command(s, summon)
			var reason: StringName
			match mode:
				"main":
					actor.action_resources.try_spend_main(1)
					check(actor.action_resources.get_bonus_left() == 1, "bonus available for no-main refusal")
					reason = &"item/insufficient_main"
				"charges":
					item._charges_left = 0
					reason = &"item/no_charges"
				"inactive":
					s.state.get_inventory(actor.id).remove_item(item)
					reason = &"item/inactive"
				"missing":
					cmd = UseSummoningItemCommand.new(actor.id, 999, Vector2i(0, 1), 13) if summon else UseHealingItemCommand.new(actor.id, 999, 13)
					reason = &"item/not_owned"
				"kind":
					cmd = UseSummoningItemCommand.new(actor.id, s.healing_item().get_item_instance_id(), Vector2i(0, 1), 13) if summon else UseHealingItemCommand.new(actor.id, s.summoning_item().get_item_instance_id(), 13)
					reason = &"item/not_usable"
				"stale":
					s.context._revision += 1
					reason = &"item/stale_revision"
				"dead":
					actor.vitals.apply_damage(100.0)
					reason = &"item/no_selected_unit"
				"admission":
					s.context._move_rules = MoveRules.new([])
					reason = &"item/not_admitted"
			refuse(s, cmd, reason)
			s.close()
	for hp: float in [32.0, 40.0]:
		var s := fixture()
		s.selected_unit().vitals.set_hp(hp)
		refuse(s, command(s), &"item/full_hp")
		s.close()
	for mode: int in 6:
		var s := fixture()
		var cell := Vector2i(0, 1)
		match mode:
			0: cell = Vector2i(-1, 1)
			1: cell = s.selected_unit().cell
			2: s.board.set_height_steps(cell, 1)
			3: s.board.set_terrain(cell, TerrainType.Type.HAZARD)
			4: s.board.set_terrain(cell, TerrainType.Type.WALL)
			5: s.board.move_unit(s.units[2], cell)
		refuse(s, s.item_command(s.selected_id, s.summoning_item().get_item_instance_id(), cell), &"summon/invalid_cell")
		s.close()
	var k2 := fixture(BattleCoreCombinationSession.new())
	refuse(k2, command(k2, true), &"armor/summon_unsupported")
	k2.select_unit(k2.units[4].id)
	k2.selected_unit().vitals.apply_damage(5.0)
	refuse(k2, command(k2), &"control/stunned")
	refuse(k2, command(k2, true), &"control/stunned")
	k2.close()
	var helper_session := fixture()
	helper_session.use_summoning_item(Vector2i(0, 1))
	var helper := helper_session.state.active_summon(helper_session.selected_id)
	var admission := SummonAdmission.extend(helper_session.context.get_move_rules(), helper_session.context.get_attack_rules(), helper.id, helper_session.selected_id, true)
	helper_session.context._move_rules = admission["move"]
	helper_session.context._attack_rules = admission["attack"]
	helper_session.select_unit(helper.id)
	refuse(helper_session, UseSummoningItemCommand.new(helper.id, 999, Vector2i(0, 0), helper_session.context.get_revision()), &"summon/helper_cannot_summon")
	helper_session.close()

func _gates_and_capabilities() -> void:
	var s := fixture()
	s.selected_unit().vitals.apply_damage(5.0)
	var cmd := command(s)
	var before := snapshot(s)
	var last := s.last_receipt
	for mode: int in 5:
		match mode:
			0: s.phase = BattleTacticalSession.Phase.ENEMY_TURN
			1: s._transitioning = true
			2: s.context._busy = true
			3: s.context._faulted = true
			4: s.selected_id = s.units[1].id
		check(s.preview_healing_item().status == ActionReceipt.REJECTED and s.preview_summoning_item(Vector2i(0, 1)).status == ActionReceipt.REJECTED, "session gates " + str(mode))
		check(snapshot(s) == before and s.last_receipt == last, "session gate pure")
		s.phase = BattleTacticalSession.Phase.PLAYER_TURN
		s._transitioning = false
		s.context._busy = false
		s.context._faulted = false
		s.selected_id = s.units[0].id
	for mode: int in 4:
		match mode:
			0: s.context._busy = true
			1: s._queue._busy = true
			2: s.context._faulted = true
			3: s._queue._faulted = true
		check(ItemUseForecast.build(s.context, s._queue, cmd).reason == (&"BUSY" if mode < 2 else &"CONTEXT_FAULTED"), "direct queue/context gate")
		s.context._busy = false
		s._queue._busy = false
		s.context._faulted = false
		s._queue._faulted = false
	for unsupported: Command in [UnknownCommand.new(), AttackCommand.new(), RaiseCorpseCommand.new(), null]:
		check(ItemUseForecast.build(s.context, s._queue, unsupported).reason == &"preview/unsupported_command", "narrow command capability")
	s.context._unsupported_runtime_ids = [&"unknown/status"]
	check(ItemUseForecast.build(s.context, s._queue, cmd).status == ActionReceipt.REJECTED, "unknown runtime refused")
	s.context._unsupported_runtime_ids.clear()
	for rng: ActionRngPort in [NoCloneRng.new(), AliasRng.new(), WrongRng.new()]:
		s.context._rng = rng
		check(ItemUseForecast.build(s.context, s._queue, cmd).reason in [&"preview/rng_not_cloneable", &"preview/rng_state_mismatch"], "RNG fails closed")
	s.context._rng = ActionRngPort.new()
	check(ItemUseForecast.build(s.context, s._queue, cmd).status == ActionReceipt.APPLIED, "base RNG port")
	check(snapshot(s) == before and s.last_receipt == last, "capability refusals pure")
	s.close()
	check(s.preview_healing_item().reason == &"battle/input_locked" and s.preview_summoning_item(Vector2i.ZERO).reason == &"battle/input_locked", "closed session gate")
	check(ItemUseForecast.build(null, null, cmd).reason == &"session/closed", "closed direct gate")

func _limits() -> void:
	for summon: bool in [false, true]:
		for mode: int in 5:
			var s := fixture()
			s.selected_unit().vitals.apply_damage(5.0)
			var status := ActionReceipt.REJECTED
			match mode:
				0:
					s._queue = ActionQueue.new(1, 1, 1)
					status = ActionReceipt.FAULTED
				1: s._queue = ActionQueue.new(0, 512, 32)
				2: s.context._next_root_id = ActionContext.MAX_ID
				3: s.context._next_command_seq = ActionContext.MAX_ID
				4:
					s.context._next_event_seq = ActionContext.MAX_ID - 1
			var f := parity(s, command(s, summon), "limit %d summon %s" % [mode, summon], status)
			if mode == 0: check(f.events.size() == 2 and f.steps.size() == 1 and f.snapshot_after != f.snapshot_before, "fault retains full atomic prefix")
			s.close()

func _restore_and_cleanup() -> void:
	var s := fixture(CustomSession.new())
	var original := snapshot(s)
	var first := s.preview_summoning_item(Vector2i(0, 1))
	var expected := first.snapshot_after.duplicate(true)
	var restored := ItemSimulationSnapshot.from_dict(first.snapshot_after)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.snapshot.to_dict() == expected, "forecast snapshot decodes")
	var definitions: Dictionary = {}
	for owner in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var instance := restored.snapshot.instantiate(definitions)
	check(instance.code == ItemSnapshotResult.Code.OK, "forecast restores independently")
	if instance.state != null:
		var helper := instance.state.active_summon(s.selected_id)
		helper.vitals.set_hp(1.0)
		instance.state.get_owner(s.selected_id)._items[s.summoning_item().get_item_instance_id()]._charges_left = 0
		check(snapshot(s) == original and first.snapshot_after == expected, "restored runtime independent of live/DTO")
		AttackForecast._close(instance.state)
	first.snapshot_before.clear()
	first.snapshot_after["board_snapshot"]["board"]["units"][0]["vitals"]["hp"] = -100.0
	first.units[s.selected_id]["after"]["hp"] = -100.0
	first.items[s.summoning_item().get_item_instance_id()]["after"]["charges"] = -100
	check(s.preview_summoning_item(Vector2i(0, 1)).snapshot_after == expected and snapshot(s) == original, "nested DTO values independent")
	first.snapshot_after.clear()
	first.events.clear()
	first.steps.clear()
	first.admission_after.clear()
	first.items.clear()
	first.units.clear()
	check(s.preview_summoning_item(Vector2i(0, 1)).snapshot_after == expected and snapshot(s) == original, "mutated DTO cannot alter next prediction")
	# Повторение успеха, отказа и fault ловит удержание копий/подписок при завершении runner.
	for index: int in 12:
		s._queue = ActionQueue.new(1, 1 if index % 3 == 2 else 512, 32)
		var cell := Vector2i(0, 1) if index % 3 != 1 else Vector2i(-1, -1)
		var f := ItemUseForecast.build(s.context, s._queue, s.item_command(s.selected_id, s.summoning_item().get_item_instance_id(), cell))
		check(f.status == [ActionReceipt.APPLIED, ActionReceipt.REJECTED, ActionReceipt.FAULTED][index % 3], "cleanup path " + str(index))
	check(snapshot(s) == original and s.state.get_summons().is_empty(), "all preview paths leave live reusable")
	s.close()
