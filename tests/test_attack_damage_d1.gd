extends SceneTree

## Эталон снят с настоящего кода до D1; hash сравнивает float и типы Variant без JSON-округления.
const BASE_COMMIT: String = "f17b7d9bda9ccc5633bbca8650a57b564413fcb0"
const BASELINE_PATH: String = "res://tests/fixtures/attack_damage_d1_baseline.json"
const BASE_ATTACK_SHA256: String = "f76124bc55556277a6d3493d63447e0713aa23f84e86609c603c4554e0808e8d"
var passed: int = 0
var failed: int = 0
var observations: Dictionary = {}

class CursorRng extends ActionRngPort:
	var cursor: int = 17
	func clone() -> ActionRngPort:
		var result := CursorRng.new()
		result.cursor = cursor
		return result
	func to_dict() -> Dictionary: return {"cursor": cursor}
	func next_int(_stream: StringName, upper: int) -> int:
		cursor += 1
		return cursor % upper

class CountingSink extends ActionEventSink:
	var events: Array[Dictionary] = []
	func publish(event: Dictionary) -> void: events.append(event.duplicate(true))

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL D1: " + label)

func fixture(profile: StringName) -> BattleDemoSession:
	UnitId.reset_counter()
	var s := BattleDemoSession.new()
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0], Vector2i(3, 3))
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	var definition := AttackDefinition.new()
	definition.id = &"demo_strike"
	definition.profile = profile
	s.context._attack_rules = AttackRules.new([s.units[0].id], [{"actor_unit_id": s.units[0].id, "target_unit_id": s.units[1].id}], [definition])
	s.context._rng = CursorRng.new()
	s.context._sink = CountingSink.new()
	s.context._revision = 13
	s.context._next_root_id = 7
	s.context._next_command_seq = 31
	s.context._next_event_seq = 41
	return s

func snapshot(s: BattleDemoSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "snapshot capture")
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func live_values(s: BattleDemoSession) -> Dictionary:
	return {"snapshot": snapshot(s), "counters": s.context.simulation_counters(), "rng": s.context.get_rng().to_dict(), "unit_id": UnitId.get_counter(), "selected": s.selected_id, "sink": (s.context.get_sink() as CountingSink).events.duplicate(true), "context_fault": s.context.is_faulted(), "queue_fault": s._queue._faulted}

func forecast_values(f: AttackForecast) -> Dictionary:
	return {"status": f.status, "reason": f.reason, "units": f.units, "events": f.events, "steps": f.steps, "before": f.snapshot_before, "after": f.snapshot_after, "rng": f.rng_after, "counters": f.counters_after}

func receipt_values(r: ActionReceipt) -> Dictionary:
	return {"status": r.status, "reason": r.reason, "root_id": r.root_id, "revision_before": r.revision_before, "revision_after": r.revision_after, "events": r.get_events(), "steps": r.get_steps()}

func record(label: String, values: Dictionary) -> void:
	var bytes := var_to_bytes(values)
	observations[label] = bytes.hex_encode().sha256_text()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace-dir="):
			var path := argument.trim_prefix("--trace-dir=").path_join(label + ".bin")
			var file := FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "trace file " + label)
			if file != null: file.store_buffer(bytes)

func attack_case(profile: StringName, scenario: String) -> void:
	var s := fixture(profile)
	var actor := s.units[0]
	var target := s.units[1]
	match scenario:
		"fractional_height_guard":
			actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 2.25)
			actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 1.125)
			target.stats.set_base_value(StatTypes.StatType.ARMOR, 0.375)
			s.board.set_height_steps(actor.cell, 2)
			target.guard_stance = true
		"minimum":
			actor.stats.set_base_value(StatTypes.StatType.STRENGTH, -3.0)
			actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.25)
			target.guard_stance = true
		"negative_armor": target.stats.set_base_value(StatTypes.StatType.ARMOR, -2.75)
		"height_zero": s.board.set_height_steps(target.cell, 10)
		"wall": s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.WALL)
		"collision": s.board.move_unit(s.units[2], Vector2i(5, 3))
		"collision_fall":
			s.board.move_unit(s.units[2], Vector2i(5, 3))
			s.units[2].vitals.set_hp(1.0)
			s.board.set_height_steps(Vector2i(5, 3), -4)
		"fall": s.board.set_height_steps(Vector2i(5, 3), -4)
		"void": s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.VOID)
		"lethal": target.vitals.set_hp(1.0)
		"no_main": actor.action_resources.try_spend_main(1)
		"half_height": s.board.set_height_steps(actor.cell, 1)
		"sum_overflow":
			actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0e308)
			actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 1.0e308)
		"command_limit":
			actor.guard_stance = true
			s._queue = ActionQueue.new(1, 512, 32)
		"event_limit": s._queue = ActionQueue.new(256, 1, 32)
	var revision := s.context.get_revision() - 1 if scenario == "stale" else s.context.get_revision()
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", revision)
	var before := live_values(s)
	var last := s.last_receipt
	var validation := command.validate(s.context)
	var first := AttackForecast.build(s.context, s._queue, command)
	var second := AttackForecast.build(s.context, s._queue, command)
	var label := String(profile) + "_" + scenario
	check(forecast_values(first) == forecast_values(second), label + " repeated forecast")
	check(before == live_values(s) and s.last_receipt == last, label + " forecast/validate do not mutate live")
	var receipt := s._submit(command)
	var after := live_values(s)
	check(receipt.status == first.status and receipt.reason == first.reason, label + " status parity")
	check(receipt.get_events() == first.events and receipt.get_steps() == first.steps, label + " receipt parity")
	check(after["snapshot"] == first.snapshot_after and after["counters"] == first.counters_after and after["rng"] == first.rng_after, label + " snapshot/counters/RNG parity")
	if receipt.status == ActionReceipt.REJECTED: check(before == after, label + " rejection no mutation")
	record(label, {"before": before, "validate": validation, "forecast": forecast_values(first), "receipt": receipt_values(receipt), "after": after})
	s.close()

func callback_case(profile: StringName) -> void:
	var s := fixture(profile)
	var target := s.units[1]
	target.guard_stance = true
	var callback := func(_old: float, _new: float) -> void: target.guard_stance = false
	target.vitals.hp_changed.connect(callback)
	var before := live_values(s)
	var receipt := s.attack_unit(target.id)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"attack/invalid_hit", "callback preserves fault contract")
	record(String(profile) + "_hostile_callback", {"before": before, "receipt": receipt_values(receipt), "after": live_values(s)})
	target.vitals.hp_changed.disconnect(callback)
	s.close()

func separate_paths() -> void:
	for mode: StringName in [&"flat", &"bypass"]:
		var s := fixture(AttackRules.SPATIAL_PROFILE)
		s.units[1].guard_stance = true
		var before := live_values(s)
		var source := DamageSource.new(&"test", 0, Vector2i.ZERO, 0, 0)
		var receipt := s._submit(DamageCommand.new(DamageRequest.new(s.units[1].id, 2.25, &"physical", mode, source)))
		record("direct_" + String(mode), {"before": before, "receipt": receipt_values(receipt), "after": live_values(s)})
		s.close()
	var s := fixture(AttackRules.PROFILE)
	s.units[1].guard_stance = true
	var before := live_values(s)
	var info := DamageCalculator.calculate(s.units[0], s.units[1], s.units[0].cell, s.units[1].cell, 0.25, 0.0, s.board)
	check(before == live_values(s), "legacy calculate pure")
	DamageCalculator.apply(info)
	record("legacy_calculator", {"before": before, "damage": info.final_damage, "after": live_values(s)})
	s.close()

func _run() -> void:
	for profile: StringName in [AttackRules.PROFILE, AttackRules.BALANCE_PROFILE, AttackRules.SPATIAL_PROFILE]:
		for scenario: String in ["normal", "fractional_height_guard", "minimum", "negative_armor", "height_zero", "wall", "collision", "collision_fall", "fall", "void", "lethal", "no_main", "half_height", "sum_overflow", "command_limit", "event_limit", "stale"]:
			attack_case(profile, scenario)
		callback_case(profile)
	separate_paths()
	var record_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--record-baseline="): record_path = argument.trim_prefix("--record-baseline=")
	if record_path != "":
		# Новый код не вправе незаметно объявить своё поведение старым эталоном.
		var source := FileAccess.get_file_as_string("res://scripts/core/actions/attack_command.gd").replace("\r\n", "\n")
		check(source.sha256_text() == BASE_ATTACK_SHA256, "record only pre-D1 AttackCommand")
		if failed == 0:
			var file := FileAccess.open(record_path, FileAccess.WRITE)
			check(file != null, "baseline writable")
			if file != null: file.store_string(JSON.stringify({"base_commit": BASE_COMMIT, "observations": observations}, "\t", true) + "\n")
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
		check(parsed is Dictionary, "baseline dictionary")
		if parsed is Dictionary:
			var baseline: Dictionary = parsed
			check(baseline.get("base_commit") == BASE_COMMIT, "baseline commit")
			var expected: Dictionary = baseline.get("observations", {})
			check(expected.size() == observations.size(), "baseline scenario count")
			for label: String in observations: check(expected.get(label) == observations[label], "pre-D1 exact trace " + label)
	print("D1 INTEGRATION RESULTS: %d passed, %d failed; %d baseline scenarios" % [passed, failed, observations.size()])
	quit(0 if failed == 0 else 1)
