extends SceneTree

var passed: int = 0
var failed: int = 0

class CursorRng extends ActionRngPort:
	var cursor: int = 17
	func clone() -> ActionRngPort:
		var copy := CursorRng.new()
		copy.cursor = cursor
		return copy
	func to_dict() -> Dictionary: return {"cursor": cursor}
	func next_int(_stream: StringName, upper: int) -> int:
		cursor += 1
		return cursor % upper

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

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL FORECAST: " + label)

func fixture() -> BattleDemoSession:
	var s := BattleDemoSession.new()
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0], Vector2i(3, 3))
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	s.context._rng = CursorRng.new()
	s.context._sink = CountingSink.new()
	# Ненулевые счётчики выявляют ложное создание контекста с начальными значениями.
	s.context._revision = 13
	s.context._next_root_id = 7
	s.context._next_command_seq = 31
	s.context._next_event_seq = 41
	return s

func snapshot(s: BattleDemoSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "fixture snapshot valid")
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func parity(s: BattleDemoSession, label: String, kinds: Array[StringName]) -> AttackForecast:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var next_id := UnitId.get_counter()
	var selected := s.selected_id
	var last := s.last_receipt
	var sink := s.context.get_sink() as CountingSink
	var forecast := s.preview_attack(s.units[1].id)
	check(forecast.status == ActionReceipt.APPLIED, label + " applied: " + String(forecast.reason))
	var again := s.preview_attack(s.units[1].id)
	check(forecast.snapshot_after == again.snapshot_after and forecast.events == again.events and forecast.steps == again.steps, label + " repeated deterministic")
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng, label + " live state/counters/RNG unchanged")
	check(UnitId.get_counter() == next_id and s.selected_id == selected and s.last_receipt == last and sink.calls == 0, label + " IDs selection receipt sink unchanged")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason, label + " actual status parity")
	check(snapshot(s) == forecast.snapshot_after, label + " whole item/board snapshot parity")
	check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, label + " whole receipt parity")
	check(s.context.simulation_counters() == forecast.counters_after and s.context.get_rng().to_dict() == forecast.rng_after, label + " counters RNG parity")
	check(sink.calls == receipt.get_events().size(), label + " only live execution publishes")
	for kind in kinds:
		check(forecast.events.any(func(event: Dictionary) -> bool: return event.get("kind") == kind), label + " includes " + String(kind))
	return forecast

func _run() -> void:
	var s := fixture()
	var f := parity(s, "flat push healing", [&"attacked", &"damaged", &"balance_broken", &"moved", &"healed"])
	check(f.units[s.units[1].id]["after"]["hp"] == s.units[1].vitals.get_hp(), "final HP includes heal")
	check(f.units[s.units[0].id]["after"]["main"] == 0 and f.units[s.units[0].id]["after"]["bonus"] == 1, "forecast spends main only")
	# Возвращённые значения не разделяются с live или следующим результатом.
	f.units[s.units[1].id]["after"]["hp"] = -100.0
	f.snapshot_before.clear()
	check(s.units[1].vitals.get_hp() > 0, "DTO mutation isolated")
	s.close()
	s = fixture()
	var protection := ItemDef.new()
	protection.id = &"forecast_balance"
	var modifier := StatModifierEffect.new()
	modifier.stat_type = StatTypes.StatType.BALANCE_MAX
	modifier.value = 20.0
	protection.effects.append(modifier)
	var protection_item := s.state.get_owner(s.units[1].id).create_item(protection)
	check(s.state.get_inventory(s.units[1].id).add_item(protection_item), "activate item stat modifier")
	f = parity(s, "item protects balance", [&"balance_changed", &"healed"])
	check(f.units[s.units[1].id]["after"]["cell"] == f.units[s.units[1].id]["before"]["cell"], "item modifier prevents push")
	s.close()
	s = fixture()
	s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.WALL)
	parity(s, "wall", [&"push_blocked", &"healed"])
	s.close()
	s = fixture()
	s.board.move_unit(s.units[2], Vector2i(5, 3))
	f = parity(s, "allied collateral", [&"collision", &"damaged"])
	check(f.units[s.units[2].id]["after"]["hp"] < f.units[s.units[2].id]["before"]["hp"], "ally collateral in result")
	s.close()
	s = fixture()
	s.board.set_height_steps(Vector2i(5, 3), -5)
	parity(s, "half height fall", [&"moved", &"damaged", &"healed"])
	s.close()
	s = fixture()
	s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.VOID)
	f = parity(s, "void lethal", [&"died"])
	check(not f.units[s.units[1].id]["after"]["alive"] and f.units[s.units[1].id]["after"]["hp"] == 0.0, "void expected death")
	check(not f.events.any(func(e: Dictionary) -> bool: return e.get("kind") == &"healed"), "no healing after lethal cascade")
	s.close()
	s = fixture()
	s.units[1].vitals.set_hp(1.0)
	parity(s, "direct lethal", [&"died"])
	s.close()
	s = fixture()
	s.units[1].vitals.set_hp(40.0)
	var definition := ItemDef.new()
	definition.id = &"forecast_healing"
	var heal := HealOnDamageEffect.new()
	heal.heal_amount = 30.0
	definition.effects.append(heal)
	var item := s.state.get_owner(s.units[1].id).create_item(definition)
	s.state.get_inventory(s.units[1].id).add_item(item)
	f = parity(s, "net healing", [&"healed"])
	check(f.units[s.units[1].id]["after"]["hp"] > 40.0, "final HP can increase")
	s.close()
	_test_rejections()
	_test_limits()
	print("FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_rejections() -> void:
	var s := fixture()
	var target := s.units[1]
	var before := snapshot(s)
	s.context._busy = true
	check(s.preview_attack(target.id).reason == &"BUSY", "busy context rejected")
	s.context._busy = false
	s._queue._busy = true
	check(s.preview_attack(target.id).reason == &"BUSY", "busy queue rejected")
	s._queue._busy = false
	s.context._faulted = true
	check(s.preview_attack(target.id).reason == &"CONTEXT_FAULTED", "fault context rejected")
	s.context._faulted = false
	s.context._unsupported_runtime_ids = [&"unknown/status"]
	check(s.preview_attack(target.id).status != ActionReceipt.APPLIED, "unknown runtime rejected")
	s.context._unsupported_runtime_ids.clear()
	for rng: ActionRngPort in [NoCloneRng.new(), AliasRng.new(), WrongRng.new()]:
		s.context._rng = rng
		check(s.preview_attack(target.id).reason in [&"preview/rng_not_cloneable", &"preview/rng_state_mismatch"], "unsupported RNG fail closed")
	s.context._rng = ActionRngPort.new()
	check(s.preview_attack(target.id).status == ActionReceipt.APPLIED, "no draw base port supported")
	check(snapshot(s) == before, "rejections and RNG checks pure")
	var command := AttackCommand.new(s.selected_id, target.id, s.units[0].cell, target.cell, &"demo_strike", 0)
	check(AttackForecast.build(s.context, s._queue, command).reason == &"attack/stale_revision", "stale command kept stale")
	s.units[0].action_resources.try_spend_main(1)
	check(s.preview_attack(target.id).reason == &"attack/insufficient_main", "no main reason")
	s.close()
	s = fixture()
	s.board.move_unit(target_for(s), Vector2i(7, 0))
	check(s.preview_attack(s.units[1].id).reason == &"attack/not_aligned", "geometry reason")
	s.close()
	var battle := BattleTacticalSession.new()
	var last := battle.last_receipt
	check(battle.preview_attack(battle.units[2].id).reason == &"battle/friendly_target", "friendly gate")
	battle.end_player_turn()
	last = battle.last_receipt
	check(battle.preview_attack(battle.units[1].id).reason == &"battle/input_locked" and battle.last_receipt == last, "phase gate does not write receipt")
	battle.close()

func target_for(s: BattleDemoSession) -> UnitState: return s.units[1]

func _test_limits() -> void:
	for mode: int in 4:
		var s := fixture()
		match mode:
			0: s._queue = ActionQueue.new(1, 512, 32)
			1: s._queue = ActionQueue.new(256, 1, 32)
			2: s.context._next_event_seq = ActionContext.MAX_ID - 1
			3: s.context._next_root_id = ActionContext.MAX_ID
		var before := snapshot(s)
		var counters := s.context.simulation_counters()
		var forecast := s.preview_attack(s.units[1].id)
		check(forecast.status != ActionReceipt.APPLIED and forecast.units.is_empty(), "limited/faulted result has no HP promises")
		check(snapshot(s) == before and s.context.simulation_counters() == counters and not s.context.is_faulted(), "limited simulation leaves live usable")
		var receipt := s.attack_unit(s.units[1].id)
		check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "limits preserve exact prefix/status")
		check(snapshot(s) == forecast.snapshot_after and s.context.simulation_counters() == forecast.counters_after, "limits snapshot/counters parity")
		s.close()
