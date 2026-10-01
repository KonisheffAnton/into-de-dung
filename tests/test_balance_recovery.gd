extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
const Forecast = preload("res://scripts/demo/turn_forecast.gd")
var passed: int = 0
var failed: int = 0
var callback_session: BattleCoreReactionsSession
var callback_target_id: int = 0
var callback_rng: bool = false
var callback_item: ItemInstance

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BALANCE RECOVERY: " + label)

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return capture.snapshot.to_dict() if capture.code == ItemSnapshotResult.Code.OK else {}

func _malicious_recovery_callback(_old_value: float, _new_value: float) -> void:
	var target := callback_session.board.get_unit_by_id(callback_target_id)
	if callback_item != null:
		callback_item._charges_left = 0
	elif callback_rng:
		callback_session.context.get_rng().next_int(&"combat", 17)
	elif target != null:
		target.vitals.set_balance(6.0)

func _normal_enemy_turn_and_forecast() -> void:
	var session := PlayerTurnFixture.create()
	var first := session.board.get_unit_by_id(session.units[1].id)
	var second := session.board.get_unit_by_id(session.units[3].id)
	var dead := session.board.get_unit_by_id(session.units[5].id)
	first.vitals.set_balance(0.5)
	second.vitals.set_balance(18.0)
	dead.vitals.set_balance(3.25)
	var death := session._queue.submit(DeathCommand.new(dead.id, DamageSource.new(&"test", 0, dead.cell)), session.context)
	check(death.status == ActionReceipt.APPLIED and not dead.is_alive(), "dead enemy fixture uses the real death command")
	first.action_resources.try_spend_main(1)
	first.spend_move_points(1.0)
	var ally := session.board.get_unit_by_id(session.units[0].id)
	ally.vitals.set_balance(4.0)
	var other_ally := session.board.get_unit_by_id(session.units[2].id)
	other_ally.vitals.set_balance(0.0)
	var selection_changed := session.select_unit(other_ally.id)
	check(selection_changed and other_ally.vitals.get_balance() == 0.0 and ally.vitals.get_balance() == 4.0, "changing selection does not recover balance")
	var selected_before := session.selected_id
	var state_before := _snapshot(session)
	var counters_before := session.context.simulation_counters()
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var forecast := Forecast.build(session)
	check(forecast.status == ActionReceipt.APPLIED and forecast.phase_after == BattleTacticalSession.Phase.ENEMY_TURN, "TurnForecast previews the enemy turn transition")
	var environment_roots := 0
	for event: Dictionary in forecast.events:
		if event.get("kind", &"") == &"environment_turn": environment_roots += 1
	var rng_flow_ok := true
	if rng_before.has("draws"):
		rng_flow_ok = int(forecast.rng_after.get("draws", -1)) == int(rng_before["draws"]) + environment_roots
	check(rng_flow_ok and session.context.get_rng().to_dict() == rng_before, "recovery adds no RNG draws beyond existing boundary roots and forecast leaves live RNG untouched")
	check(_snapshot(session) == state_before and session.context.simulation_counters() == counters_before and session.selected_id == selected_before, "forecast leaves live units, selection, and counters untouched")
	check(session.end_player_turn() and session.phase == BattleTacticalSession.Phase.ENEMY_TURN, "player boundary refills the incoming enemy team")
	check(first.vitals.get_balance() == 0.0 and second.vitals.get_balance() == 17.0, "recovery subtracts one and clamps balance at zero")
	check(first.action_resources.get_main_left() == 1 and is_equal_approx(first.move_points_left, 5.0), "resource refill completes before balance recovery")
	check(ally.vitals.get_balance() == 4.0 and session.selected_id == UnitId.NONE, "enemy refill leaves the outgoing player unchanged")
	check(dead.vitals.get_balance() == 3.25, "dead enemy is excluded from recovery")
	check(forecast.snapshot_after == _snapshot(session) and forecast.rng_after == session.context.get_rng().to_dict(), "forecast values match live transition including recovery")
	session.close()

func _recovery_does_not_break() -> void:
	var session := PlayerTurnFixture.create()
	var target := session.board.get_unit_by_id(session.units[1].id)
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 12.0)
	target.vitals.set_balance(18.0)
	var broken := [0]
	target.vitals.balance_broken.connect(func() -> void: broken[0] += 1)
	var changed := [0]
	target.vitals.balance_changed.connect(func(_old: float, _new: float) -> void: changed[0] += 1)
	check(session.end_player_turn(), "normal transition accepts recovery above the reduced threshold")
	check(target.vitals.get_balance() == 17.0 and changed[0] == 1 and broken[0] == 0, "18 to 17 at threshold 12 emits a value change without break")
	session.close()

func _pending_helper_refill() -> void:
	var session := PlayerTurnFixture.create()
	var owner := session.selected_unit()
	check(session.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "pending helper fixture is summoned")
	var helper := session.state.active_summon(owner.id)
	if helper == null:
		check(false, "summoned helper is present")
		session.close()
		return
	helper.vitals.set_balance(2.5)
	var player := session.board.get_unit_by_id(owner.id)
	player.vitals.set_balance(1.0)
	var dead_player := session.board.get_unit_by_id(session.units[2].id)
	dead_player.vitals.set_balance(3.0)
	var death := session._queue.submit(DeathCommand.new(dead_player.id, DamageSource.new(&"test", 0, dead_player.cell)), session.context)
	check(death.status == ActionReceipt.APPLIED and not dead_player.is_alive(), "dead player fixture uses the real death command")
	var receipt := session._queue.submit(BattleTurnRefill.new(session.living_ids(Faction.Type.PLAYER), session.context.get_revision(), Faction.Type.PLAYER), session.context)
	check(receipt.status == ActionReceipt.APPLIED, "player refill admits pending helper")
	check(not session.state.is_summon_pending(helper.id) and helper.vitals.get_balance() == 1.5, "helper recovers as a living player unit when its team refills")
	check(player.vitals.get_balance() == 0.0, "player unit recovery applies at same boundary")
	check(dead_player.vitals.get_balance() == 3.0, "dead player is excluded from its team refill")
	session.close()

func _preflight_is_atomic() -> void:
	var session := PlayerTurnFixture.create()
	var first := session.board.get_unit_by_id(session.units[1].id)
	var invalid := session.board.get_unit_by_id(session.units[3].id)
	first.action_resources.try_spend_main(1)
	first.move_points_left = 1.25
	first.vitals.set_balance(4.0)
	invalid.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, -1.0)
	var revision := session.context.get_revision()
	var receipt := session._queue.submit(BattleTurnRefill.new([first.id, invalid.id], revision, Faction.Type.ENEMY), session.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"resources/invalid_maximum", "invalid later participant rejects preflight")
	check(first.action_resources.get_main_left() == 0 and first.move_points_left == 1.25 and first.vitals.get_balance() == 4.0, "preflight refusal does not partially refill an earlier unit")
	session.close()

func _callback_corruption(mutate_rng: bool) -> void:
	var expected_draws := -1
	if mutate_rng:
		var baseline := PlayerTurnFixture.create()
		baseline.context._rng = CombatRng.new(99)
		baseline.board.get_unit_by_id(baseline.units[1].id).vitals.set_balance(3.0)
		baseline.board.get_unit_by_id(baseline.units[3].id).vitals.set_balance(3.0)
		var expected := Forecast.build(baseline)
		expected_draws = int(expected.rng_after.get("draws", 0)) + 1
		baseline.close()
	var session := PlayerTurnFixture.create()
	var first := session.board.get_unit_by_id(session.units[1].id)
	var second := session.board.get_unit_by_id(session.units[3].id)
	first.vitals.set_balance(3.0)
	second.vitals.set_balance(3.0)
	if mutate_rng: session.context._rng = CombatRng.new(99)
	callback_session = session
	callback_target_id = second.id
	callback_rng = mutate_rng
	var callback := Callable(self, "_malicious_recovery_callback")
	first.vitals.balance_changed.connect(callback)
	var applied := session.end_player_turn()
	first.vitals.balance_changed.disconnect(callback)
	check(not applied and session.phase == BattleTacticalSession.Phase.FAULTED, "balance callback corruption faults the turn")
	check(session.last_receipt.status == ActionReceipt.FAULTED and session.last_receipt.reason == &"turn/invalid_recovery", "callback mutation reports invalid recovery")
	var expected_second := 3.0 if mutate_rng else 6.0
	check(first.vitals.get_balance() == 2.0 and second.vitals.get_balance() == expected_second, "actual recovery prefix is retained and later targets are not refilled")
	if mutate_rng:
		check(int(session.context.get_rng().to_dict().get("draws", -1)) == expected_draws, "malicious RNG callback adds exactly one draw beyond the normal turn forecast")
	callback_session = null
	callback_target_id = 0
	callback_rng = false
	session.close()

func _callback_item_corruption() -> void:
	var session := PlayerTurnFixture.create()
	var first := session.units[1]
	var second := session.units[3]
	first.vitals.set_balance(3.0)
	second.vitals.set_balance(3.0)
	callback_session = session
	callback_item = session.healing_item()
	check(callback_item != null and callback_item.get_charges_left() > 0 and callback_item.get_owner_unit_id() != first.id, "callback fixture owns a charged item on another team")
	var callback := Callable(self, "_malicious_recovery_callback")
	first.vitals.balance_changed.connect(callback)
	check(not session.end_player_turn() and session.last_receipt.status == ActionReceipt.FAULTED and session.last_receipt.reason == &"turn/invalid_recovery", "item charge mutation in recovery callback faults instead of silently applying")
	check(first.vitals.get_balance() == 2.0 and second.vitals.get_balance() == 3.0 and callback_item.get_charges_left() == 0, "item corruption preserves actual prefix and stops later recovery")
	check(not session.last_receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"item_used"), "recovery does not fabricate an item-use receipt for corruption")
	first.vitals.balance_changed.disconnect(callback)
	callback_item = null
	callback_session = null
	session.close()

func run() -> void:
	_normal_enemy_turn_and_forecast()
	_recovery_does_not_break()
	_pending_helper_refill()
	_preflight_is_atomic()
	_callback_corruption(false)
	_callback_corruption(true)
	_callback_item_corruption()
	print("BALANCE RECOVERY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
