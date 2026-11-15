extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL INTEGER BALANCE: " + label)

func _snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "valid integer snapshot: " + String(capture.reason))
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func _run() -> void:
	var stats := StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 28.0, StatTypes.StatType.BALANCE_MAX: 5.9})
	var unit := UnitState.create(Faction.Type.PLAYER, Vector2i.ZERO, stats, "Целые очки")
	var v := unit.vitals
	v.set_hp(17.25)
	v.set_balance(2.9)
	check(v.get_hp() == 17.25 and v.get_balance() == 2.0 and v.get_balance_max() == 5.0, "setter and effective threshold use whole points, HP keeps fraction")
	check(not v.add_impact(0.9) and v.get_balance() == 2.0, "sub-point impact does not accumulate")
	check(not v.add_impact(1.9) and v.get_balance() == 3.0, "one final floor per hit")
	check(not v.would_break(1.9) and v.would_break(2.1), "direct preview uses identical whole impact")
	check(v.add_impact(2.1) and v.get_balance() == 0.0, "whole threshold breaks and resets")
	v.set_balance(9.9)
	check(not v.would_break(0.5) and not v.add_impact(0.5) and v.get_balance() == 9.0, "zero rounded hit does not break an over-max imported value")
	v.set_balance(2.0)
	v.set_balance(NAN)
	v.set_balance(INF)
	check(not v.add_impact(NAN) and not v.would_break(INF) and v.get_balance() == 2.0, "nonfinite inputs cannot poison live balance")
	var dto := unit.to_snapshot_dict()
	var restored := UnitState.from_snapshot_dict(dto)
	check(restored != null and restored.to_snapshot_dict() == dto and typeof(dto.vitals.balance) == TYPE_FLOAT, "integer-valued float schema roundtrips exactly")
	var invalid := dto.duplicate(true)
	invalid.vitals.balance = 2.5
	check(UnitState.from_snapshot_dict(invalid) == null, "strict restore rejects fractional disruption without silent rounding")
	v._balance = 2.5
	check(unit.to_snapshot_dict().is_empty(), "capture rejects illegally injected fractional disruption")
	v._balance = 2.0
	var draft := {"kind": &"balance_changed", "actor_unit_id":1, "target_unit_id":2,
		"balance_before":0.0,"balance_after":1.0,"balance_max":5.0,"impact":1.0,"broke":false}
	check(ActionEventValidator.valid_draft(draft), "whole-point receipt remains valid")
	draft.balance_after = 1.5
	draft.impact = 1.5
	var original := draft.duplicate(true)
	check(not ActionEventValidator.valid_draft(draft) and draft == original, "fractional receipt rejected without rewriting it")
	var link := {"kind": &"chain_link", "actor_unit_id":1,"from_unit_id":2,"target_unit_id":3,"impulse":2.0,"broke":false}
	check(ActionEventValidator.valid_draft(link), "whole chain impulse remains valid")
	link.impulse = 2.5
	check(not ActionEventValidator.valid_draft(link), "fractional chain receipt rejected")
	stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1e9)
	v.set_balance(1e9 - 3.0)
	var changes: Array[int] = [0]
	v.balance_changed.connect(func(_old: float, _new: float) -> void: changes[0] += 1)
	v.add_impact(1.0)
	v.set_balance(v.get_balance() - 1.0)
	var spatial := v.add_spatial_impact(1.0, func(_stage: StringName) -> StringName: return &"")
	check(spatial.reason == &"" and changes[0] == 3 and v.get_balance() == 1e9 - 2.0, "every single point emits even at large integer balance")
	var sink := RecordingEventSink.new()
	var hit := DamageInfo.new()
	hit.target = unit
	hit.balance_added = 1.0
	DamageCalculator.apply(hit, sink)
	check(sink.count_of(&"unit_balance_changed") == 1, "legacy sink preserves a one-point change at large balance")
	for row: Dictionary in [
		{"impact":3.0,"height":0,"guard":true,"critical":false,"expected":1.0},
		{"impact":1.0,"height":0,"guard":true,"critical":false,"expected":0.0},
		{"impact":3.0,"height":1,"guard":false,"critical":false,"expected":3.0},
		{"impact":3.0,"height":1,"guard":false,"critical":true,"expected":6.0},
		{"impact":3.0,"height":1,"guard":true,"critical":true,"expected":4.0},
	]:
		_attack_case(row)
	print("INTEGER BALANCE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _attack_case(row: Dictionary) -> void:
	var s := PlayerTurnFixture.create()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in s.units.size():
		if not s.units[index].is_alive(): continue
		check(s.board.move_unit(s.units[index], Vector2i(index, 0)), "park fixture through board")
	var actor: UnitState = s.units[0]
	var target: UnitState = s.units[1]
	check(s.board.move_unit(actor, Vector2i(1, 3)) and s.board.move_unit(target, Vector2i(2, 3)), "front-facing adjacent fixture")
	s.board.set_height_steps(actor.cell, int(row.height))
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, float(row.impact))
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.9)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 500.0)
	target.vitals.set_hp(500.0)
	target.vitals.set_balance(0.0)
	target.guard_stance = bool(row.guard)
	target.control.stunned_turns = 1 if row.critical else 0
	var before := _snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var ids := UnitId.get_counter()
	var preview := s.preview_attack(target.id)
	check(_snapshot(s) == before and s.context.get_rng().to_dict() == rng and UnitId.get_counter() == ids, "preview keeps live state/RNG/IDs")
	var receipt := s.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "live receipt equals integer preview: " + String(receipt.reason))
	check(_snapshot(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after, "full state parity after integer hit")
	check(target.vitals.get_balance() == float(row.expected), "final impact rounded after height/critical/guard: " + str(row))
	for event: Dictionary in receipt.get_events():
		if event.get("kind", &"") not in [&"balance_changed", &"balance_broken"]: continue
		check(BalancePoints.valid(event.balance_before) and BalancePoints.valid(event.balance_after) and BalancePoints.valid(event.balance_max) and BalancePoints.valid(event.impact), "receipt contains only whole balance points")
	# Валидация capture и clone не должна подлечивать испорченный live-снимок.
	target.vitals._balance = 0.5
	check(ItemSimulationSnapshot.capture(s.state, []).code != ItemSnapshotResult.Code.OK, "item snapshot refuses fractional live balance")
	target.vitals._balance = 0.0
	s.close()
