extends SceneTree

const Worker = preload("res://scripts/demo/action_forecast_worker.gd")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

class UnsupportedRng extends ActionRngPort:
	func clone() -> ActionRngPort: return UnsupportedRng.new()
	func to_dict() -> Dictionary: return {"unsupported": true}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ACTION FORECAST WORKER: " + label)

func snapshot(s: BattleDemoSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()

func take(worker: Object) -> ForecastSimulation:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var result: ForecastSimulation = worker.take_finished()
		if result != null: return result
		await create_timer(0.002).timeout
	worker.close()
	check(false, "worker deadline")
	return ForecastSimulation.rejected(&"timeout")

func parity(kind: String) -> void:
	var s := PlayerTurnFixture.create()
	var actor := s.selected_unit()
	var command: Command
	var prepared: ForecastSimulation.Prepared
	match kind:
		"guard", "opportunity", "cover":
			var mode := CombatPerksState.Mode.NONE
			var target := 0
			if kind == "opportunity": mode = CombatPerksState.Mode.OPPORTUNIST
			if kind == "cover":
				mode = CombatPerksState.Mode.COVER
				s.board.move_unit(s.units[2], Vector2i(1, 2))
				target = s.units[2].id
			command = GuardCommand.new(actor.id, s.context.get_revision(), -1 if mode == CombatPerksState.Mode.NONE else mode, target)
			prepared = s.prepare_guard_forecast(mode, target)
		"heal":
			actor.vitals.set_hp(10.0)
			command = s.item_command(actor.id, s.healing_item().get_item_instance_id())
			prepared = s.prepare_item_forecast(ItemUseAction.Kind.HEAL_SELF)
		"summon":
			command = s.item_command(actor.id, s.summoning_item().get_item_instance_id(), Vector2i(0, 1))
			prepared = s.prepare_item_forecast(ItemUseAction.Kind.SUMMON_ADJACENT, Vector2i(0, 1))
		"raise":
			command = s._raise_command(Vector2i(0, 3))
			prepared = s.prepare_raise_corpse_forecast(Vector2i(0, 3))
		"armor":
			for item: ItemInstance in s.state.get_owner(actor.id)._items.values():
				if item.get_definition().armor_max > 0: item.armor_remaining = 0
			command = RestoreArmorCommand.new(actor.id, 20, s.context.get_revision())
			prepared = s.prepare_restore_armor_forecast()
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var allocator := UnitId.get_counter()
	var expected := ForecastSimulation.run(s.context, s._queue, command)
	var worker := Worker.new()
	worker.start(prepared)
	var result := await take(worker)
	check(result.status == ActionReceipt.APPLIED, kind + " applied fixture")
	check(result.status == expected.status and result.reason == expected.reason and result.events == expected.events and result.steps == expected.steps, kind + " sync receipt parity")
	check(result.snapshot_before == expected.snapshot_before and result.snapshot_after == expected.snapshot_after and result.units_before == expected.units_before and result.units_after == expected.units_after and result.items == expected.items and result.corpses_after == expected.corpses_after, kind + " complete values parity")
	check(result.admission_after == expected.admission_after and result.rng_after == expected.rng_after and result.counters_after == expected.counters_after, kind + " admission RNG counters parity")
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and UnitId.get_counter() == allocator, kind + " live isolation")
	check(worker.take_finished() == null and ForecastSimulation.run_prepared(prepared).reason == &"preview/request_consumed", kind + " one-shot")
	var live := s._queue.submit(command, s.context)
	check(result.events == live.get_events() and result.steps == live.get_steps() and result.snapshot_after == snapshot(s) and result.rng_after == s.context.get_rng().to_dict() and result.counters_after == s.context.simulation_counters(), kind + " live parity")
	worker.close()
	s.close()

func run() -> void:
	for kind: String in ["guard", "opportunity", "cover", "heal", "summon", "raise", "armor"]: await parity(kind)
	var s := PlayerTurnFixture.create()
	s.selected_unit().vitals.set_hp(10.0)
	check(s.healing_hint_reason() == s.healing_reason() and s.summoning_hint_reason() == s.summoning_reason() and s.raise_hint_cells() == s.raise_cells(), "valid hints match strict checks")
	var before := snapshot(s)
	s.context._unsupported_runtime_ids.append(&"test_unknown")
	check(s.healing_hint_reason() == &"" and s.summoning_hint_reason() == &"" and s.raise_hint_reason() == &"", "hints do not certify full runtime")
	check(s.healing_reason() == &"item/invalid_runtime" and s.summoning_reason() == &"item/invalid_runtime", "strict validation still inspects full runtime")
	check(s.use_healing_item().status == ActionReceipt.REJECTED and s.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.REJECTED and s.raise_corpse(Vector2i(0, 3)).status == ActionReceipt.REJECTED, "fresh commands refuse despite valid hints")
	s.context._unsupported_runtime_ids.clear()
	check(snapshot(s) == before, "refused hints spend nothing")
	var worker := Worker.new()
	worker.start(null)
	check(worker.take_finished().reason == &"preview/request_consumed", "null request")
	var prepared := s.prepare_guard_forecast()
	prepared.context._rng = UnsupportedRng.new()
	worker.start(prepared)
	check(worker._thread == null and worker.take_finished().reason == &"preview/unsupported_worker_rng", "unknown RNG never starts thread")
	worker.start(s.prepare_attack_forecast(s.units[3].id))
	check(worker.take_finished().reason == &"preview/unsupported_command", "different command rejected")
	worker.start(s.prepare_guard_forecast())
	worker.close()
	check(not worker.is_started(), "close joins pending calculation")
	s.close()
	print("ACTION FORECAST WORKER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
