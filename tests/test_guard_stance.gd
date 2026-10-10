extends SceneTree

var passed: int = 0
var failed: int = 0

class CursorRng extends ActionRngPort:
	var cursor: int = 19
	func clone() -> ActionRngPort:
		var result := CursorRng.new()
		result.cursor = cursor
		return result
	func to_dict() -> Dictionary: return {"cursor": cursor}

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL GUARD: " + label)

func snapshot(s: BattleDemoSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "snapshot capture")
	return result.snapshot.to_dict() if result.snapshot != null else {}

func fixture() -> BattleDemoSession:
	var s := BattleDemoSession.new()
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0], Vector2i(3, 3))
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	s.context._rng = CursorRng.new()
	s.context._revision = 9
	s.context._next_root_id = 5
	s.context._next_command_seq = 13
	s.context._next_event_seq = 21
	return s

func guard(s: BattleDemoSession, actor: UnitState) -> ActionReceipt:
	return s._submit(GuardCommand.new(actor.id, s.context.get_revision()))

func parity(s: BattleDemoSession, label: String) -> AttackForecast:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var next_id := UnitId.get_counter()
	var last := s.last_receipt
	var selected := s.selected_id
	var f := s.preview_attack(s.units[1].id)
	check(f.status == ActionReceipt.APPLIED, label + " forecast " + String(f.reason))
	var repeated := s.preview_attack(s.units[1].id)
	check(f.events == repeated.events and f.snapshot_after == repeated.snapshot_after, label + " repeat")
	check(before == snapshot(s) and counters == s.context.simulation_counters() and rng == s.context.get_rng().to_dict(), label + " no mutation")
	check(last == s.last_receipt and selected == s.selected_id and next_id == UnitId.get_counter(), label + " no receipt/selection/id mutation")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == f.status and receipt.reason == f.reason, label + " status parity")
	check(snapshot(s) == f.snapshot_after and f.events == receipt.get_events() and f.steps == receipt.get_steps(), label + " snapshot/event/step parity")
	check(f.counters_after == s.context.simulation_counters() and f.rng_after == s.context.get_rng().to_dict(), label + " counters/RNG parity")
	return f

func _run() -> void:
	_test_command_and_flow()
	_test_snapshots()
	_test_combat()
	_test_callbacks_and_limits()
	print("GUARD RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_command_and_flow() -> void:
	var s := BattleTacticalSession.new()
	var actor := s.selected_unit()
	var before := snapshot(s)
	var last := s.last_receipt
	check(s.guard_reason() == &"" and snapshot(s) == before and last == s.last_receipt, "availability pure")
	var stale := GuardCommand.new(actor.id, s.context.get_revision())
	var receipt := s.guard_selected()
	check(receipt.status == ActionReceipt.APPLIED and actor.guard_stance, "guard applied")
	check(actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 1 and actor.move_points_left == 5.0 and not actor.has_attacked, "guard main only")
	check(receipt.get_events().size() == 1 and receipt.get_events()[0]["kind"] == &"guarded" and receipt.revision_after == receipt.revision_before + 1, "receipt/revision")
	before = snapshot(s)
	check(s.guard_selected().reason == &"guard/already_active" and snapshot(s) == before, "repeat no debit")
	check(stale.validate(s.context) == &"guard/stale_revision", "stale")
	check(s.select_unit(s.units[2].id) and s.select_unit(actor.id) and snapshot(s) == before, "switch preserves stance and resources")
	check(s.move_to(Vector2i(7, 7)).status == ActionReceipt.REJECTED and actor.guard_stance, "rejected move preserves")
	check(s.attack_unit(s.units[1].id).status == ActionReceipt.REJECTED and actor.guard_stance, "rejected attack preserves")
	check(s.move_to(Vector2i(1, 2)).status == ActionReceipt.APPLIED and not actor.guard_stance, "voluntary move cancels")
	before = snapshot(s)
	check(s.guard_selected().reason == &"guard/insufficient_main" and snapshot(s) == before and actor.action_resources.get_bonus_left() == 1, "no bonus fallback")
	s.select_unit(s.units[2].id)
	var second := s.selected_unit()
	check(s.guard_selected().status == ActionReceipt.APPLIED, "second guard")
	check(s.end_player_turn() and second.guard_stance, "outgoing stance retained")
	check(s.guard_selected().reason == &"battle/input_locked", "input locked")
	for _step in 20:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and not second.guard_stance and second.action_resources.get_main_left() == 1, "own next turn expires/refills")
	s.reset()
	actor = s.selected_unit()
	check(not actor.guard_stance and actor.action_resources.get_main_left() == 1, "reset")
	s.context._busy = true
	check(s.guard_selected().reason == &"battle/input_locked" and not actor.guard_stance, "busy session")
	check(s._queue.submit(GuardCommand.new(actor.id, 0), s.context).reason == &"BUSY", "busy queue")
	s.context._busy = false
	s.context._faulted = true
	check(s.guard_selected().reason == &"battle/input_locked" and not actor.guard_stance, "faulted session")
	s.context._faulted = false
	s.close()
	check(s.guard_selected().reason == &"battle/input_locked", "closed session")
	check(GuardCommand.new().validate(null) == &"guard/invalid_runtime", "closed command")
	s = BattleTacticalSession.new()
	actor = s.selected_unit()
	actor.vitals.apply_damage(100.0)
	check(GuardCommand.new(actor.id, 0).validate(s.context) == &"guard/no_selected_unit", "dead guard rejected")
	s.close()
	s = BattleTacticalSession.new()
	actor = s.selected_unit()
	guard(s, actor)
	s.units[2].stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 0.5)
	before = snapshot(s)
	var refill := s._submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER))
	check(refill.status == ActionReceipt.REJECTED and actor.guard_stance and snapshot(s) == before, "failed team preflight retains stance")
	s.close()

func _test_snapshots() -> void:
	var s := fixture()
	var unit := s.units[0]
	var current := unit.to_snapshot_dict()
	check(current["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION and current["guard_stance"] == false, "current schema includes inactive stance")
	check(UnitState.from_snapshot_dict(current).to_snapshot_dict() == current, "current inactive stance roundtrip")
	guard(s, unit)
	var active := unit.to_snapshot_dict()
	check(active["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION and active["guard_stance"] == true, "current schema records active stance")
	check(UnitState.from_snapshot_dict(active).to_snapshot_dict() == active, "current active stance roundtrip")
	var data := snapshot(s)
	var parsed := ItemSimulationSnapshot.from_dict(data)
	var restored := parsed.snapshot.instantiate(s.state.get_owner(s.units[1].id)._definitions)
	check(restored.code == ItemSnapshotResult.Code.OK, "full item instantiate")
	if restored.state != null:
		check(restored.state.get_board().get_unit_by_id(unit.id).guard_stance, "full item retains stance")
		check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == data, "full roundtrip")
		AttackForecast._close(restored.state)
	for bad: Variant in [1, "true", null, 1.0]:
		var broken := active.duplicate(true)
		broken["guard_stance"] = bad
		check(not UnitState.validate_snapshot_dict(broken), "strict stance bool")
		var broken_items := data.duplicate(true)
		broken_items["board_snapshot"]["board"]["units"][0] = broken
		check(ItemSimulationSnapshot.from_dict(broken_items).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "item envelope rejects corrupt stance")
	var missing := active.duplicate(true)
	missing.erase("guard_stance")
	check(not UnitState.validate_snapshot_dict(missing), "required stance")
	missing = active.duplicate(true)
	missing.erase("action_resources")
	check(not UnitState.validate_snapshot_dict(missing), "active guard requires resources")
	for old_version: int in range(1, UnitState.SNAPSHOT_SCHEMA_VERSION):
		var old_snapshot := active.duplicate(true)
		old_snapshot["schema_version"] = old_version
		check(not UnitState.validate_snapshot_dict(old_snapshot), "old unit schema rejected " + str(old_version))
	var future := data.duplicate(true)
	future["board_snapshot"]["board"]["units"][0]["schema_version"] = 99
	check(ItemSimulationSnapshot.from_dict(future).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unknown version unsupported")
	s.close()

func _test_combat() -> void:
	var s := fixture()
	guard(s, s.units[1])
	var f := parity(s, "guarded target")
	check(is_equal_approx(s.units[1].vitals.get_hp(), 76.4), "8 direct reduced to5.6 then item heals2")
	check(is_equal_approx(s.units[1].vitals.get_balance(), 2.5) and s.units[1].cell == Vector2i(4, 3), "5impact reduced2.5 prevents push")
	check(s.units[1].guard_stance and f.units[s.units[1].id]["after"]["guard_stance"], "hit preserves stance/DTO")
	s.close()
	s = fixture()
	guard(s, s.units[0])
	s.units[0].action_resources._set_for_refill(1, 1)
	f = parity(s, "guarded attacker")
	check(not s.units[0].guard_stance and not f.units[s.units[0].id]["after"]["guard_stance"], "voluntary attack cancels in live and preview")
	s.close()
	for terrain in [TerrainType.Type.FLOOR, TerrainType.Type.WALL, TerrainType.Type.VOID]:
		s = fixture()
		guard(s, s.units[1])
		s.units[1].vitals.set_balance(3.0)
		s.board.set_terrain(Vector2i(5, 3), terrain)
		f = parity(s, "guarded cascade " + str(terrain))
		check(s.units[1].guard_stance, "forced consequences preserve stance")
		if terrain == TerrainType.Type.FLOOR: check(s.units[1].cell == Vector2i(5, 3), "forced push still moves")
		elif terrain == TerrainType.Type.WALL: check(is_equal_approx(s.units[1].vitals.get_hp(), 70.4), "collision full8 with two item heals")
		else: check(not s.units[1].is_alive(), "guard cannot prevent void death")
		s.close()
	s = fixture()
	guard(s, s.units[1])
	s.units[1].vitals.set_balance(3.0)
	s.board.set_height_steps(Vector2i(5, 3), -4)
	parity(s, "guarded fall")
	check(is_equal_approx(s.units[1].vitals.get_hp(), 40.4), "fall full38 with two item heals")
	s.close()
	s = fixture()
	guard(s, s.units[1])
	s.units[1].stats.set_base_value(StatTypes.StatType.ARMOR, 100.0)
	parity(s, "minimum hit")
	check(s.units[1].vitals.get_hp() == 80.0, "minimum1 then heal cap")
	s.close()
	s = fixture()
	guard(s, s.units[1])
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	parity(s, "zero impact")
	check(s.units[1].vitals.get_balance() == 0.0, "zero remains zero")
	s.close()
	s = fixture()
	guard(s, s.units[1])
	var direct := s._submit(DamageCommand.new(DamageRequest.new(s.units[1].id, 10.0, &"physical", &"bypass", DamageSource.new(&"test", 0, Vector2i.ZERO, 0, 0))))
	check(direct.status == ActionReceipt.APPLIED and s.units[1].vitals.get_hp() == 72.0, "generic damage unaffected; item heal remains")
	s.close()
	for profile in [AttackRules.PROFILE, AttackRules.BALANCE_PROFILE]:
		s = fixture()
		var definition := AttackDefinition.new()
		definition.id = &"demo_strike"
		definition.profile = profile
		s.context._attack_rules = AttackRules.new([s.units[0].id], [{"actor_unit_id": s.units[0].id, "target_unit_id": s.units[1].id}], [definition])
		guard(s, s.units[1])
		parity(s, "legacy guard " + String(profile))
		check(is_equal_approx(s.units[1].vitals.get_hp(), 76.4), "legacy guarded hit")
		s.close()
	s = fixture()
	guard(s, s.units[1])
	s.board.set_height_steps(s.units[0].cell, 1)
	parity(s, "height then guard")
	check(is_equal_approx(s.units[1].vitals.get_hp(), 75.7) and is_equal_approx(s.units[1].vitals.get_balance(), 2.75), "height modifier precedes guard")
	s.close()
	s = fixture()
	guard(s, s.units[1])
	s.units[1].vitals.set_balance(3.0)
	s.board.move_unit(s.units[2], Vector2i(5, 3))
	guard(s, s.units[2])
	parity(s, "guarded collateral")
	check(s.units[2].vitals.get_hp() == 72.0 and s.units[2].guard_stance, "collateral full8 even on guarded ally")
	s.close()

func _test_callbacks_and_limits() -> void:
	var s := fixture()
	guard(s, s.units[0])
	s.units[0].action_resources._set_for_refill(1, 1)
	s._queue = ActionQueue.new(1, 512, 32)
	var before := snapshot(s)
	var f := s.preview_attack(s.units[1].id)
	check(f.status == ActionReceipt.FAULTED and f.units.is_empty() and snapshot(s) == before, "partial forecast with stance no promise/mutation")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == ActionReceipt.FAULTED and not s.units[0].guard_stance and s.units[0].action_resources.get_main_left() == 0 and s.units[1].vitals.get_hp() == 80.0, "paid attack prefix clears stance before child limit")
	s.close()
	s = fixture()
	guard(s, s.units[1])
	var target := s.units[1]
	var callback := func(_old: float, _new: float) -> void: target.guard_stance = false
	target.vitals.hp_changed.connect(callback)
	receipt = s.attack_unit(target.id)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"attack/invalid_hit", "callback stance mutation detected")
	target.vitals.hp_changed.disconnect(callback)
	s.close()
	s = fixture()
	var actor := s.units[0]
	guard(s, actor)
	var movement_callback := func() -> void: actor.guard_stance = true
	s.board.board_changed.connect(movement_callback)
	receipt = s.move_to(Vector2i(3, 4))
	check(receipt.status == ActionReceipt.FAULTED and actor.cell == Vector2i(3, 4), "movement checkpoint detects stance callback with moved prefix")
	s.board.board_changed.disconnect(movement_callback)
	s.close()
	for profile in [AttackRules.PROFILE, AttackRules.BALANCE_PROFILE]:
		for change_target in [false, true]:
			s = fixture()
			actor = s.units[0]
			target = s.units[1]
			guard(s, actor)
			actor.action_resources._set_for_refill(1, 1)
			guard(s, target)
			var definition := AttackDefinition.new()
			definition.id = &"demo_strike"
			definition.profile = profile
			s.context._attack_rules = AttackRules.new([actor.id], [{"actor_unit_id": actor.id, "target_unit_id": target.id}], [definition])
			var changed := target if change_target else actor
			var mutation := func(_old: float, _new: float) -> void: changed.guard_stance = not change_target
			target.vitals.hp_changed.connect(mutation)
			receipt = s.attack_unit(target.id)
			check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"attack/invalid_hit", "legacy hit catches stance callback " + String(profile) + str(change_target))
			check(is_equal_approx(target.vitals.get_hp(), 74.4) and actor.action_resources.get_main_left() == 0 and receipt.get_events().size() == 2 and target.vitals.get_balance() == 0.0, "legacy paid HP prefix retained; no balance/heal after fault")
			target.vitals.hp_changed.disconnect(mutation)
			s.close()
	s = fixture()
	actor = s.units[0]
	guard(s, actor)
	s.context._move_rules = MoveRules.new(s._unit_ids(), 1)
	var legacy_movement_callback := func() -> void: actor.guard_stance = true
	s.board.board_changed.connect(legacy_movement_callback)
	receipt = s.move_to(Vector2i(3, 4))
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"move/invalid_runtime" and actor.cell == Vector2i(3, 4) and actor.move_points_left == 7.0 and receipt.get_events().size() == 1, "legacy movement catches stance callback and retains paid move event")
	s.board.board_changed.disconnect(legacy_movement_callback)
	s.close()
	for stage in ["balance", "push", "collision", "fall", "heal"]:
		s = fixture()
		actor = s.units[0]
		target = s.units[1]
		guard(s, actor)
		actor.action_resources._set_for_refill(1, 1)
		var definition := AttackDefinition.new()
		definition.id = &"demo_strike"
		definition.profile = AttackRules.BALANCE_PROFILE
		s.context._attack_rules = AttackRules.new([actor.id], [{"actor_unit_id": actor.id, "target_unit_id": target.id}], [definition])
		if stage in ["balance", "heal"]: target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 20.0)
		if stage == "collision": s.board.move_unit(s.units[2], Vector2i(5, 3))
		if stage == "fall": s.board.set_height_steps(Vector2i(5, 3), -4)
		var emitter: Signal
		var mutation: Callable
		if stage == "balance":
			emitter = target.vitals.balance_changed
			mutation = func(_old: float, _new: float) -> void: actor.guard_stance = true
		elif stage == "push":
			emitter = s.board.board_changed
			mutation = func() -> void: actor.guard_stance = true
		else:
			emitter = target.vitals.hp_changed
			mutation = func(old: float, current: float) -> void:
				if (stage == "heal" and current > old) or (stage != "heal" and old < 80.0): actor.guard_stance = true
		emitter.connect(mutation)
		receipt = s.attack_unit(target.id)
		check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"attack/invalid_stance", "legacy attack lifetime catches " + stage)
		check(actor.action_resources.get_main_left() == 0 and s._queue._attack_stances.is_empty(), "fault retains price and releases refs " + stage)
		if stage == "balance": check(target.vitals.get_hp() == 72.0 and target.vitals.get_balance() == 5.0 and receipt.get_events().size() == 3, "balance prefix before heal")
		if stage == "push": check(target.cell == Vector2i(5, 3) and target.vitals.get_hp() == 72.0, "forced move prefix before reactions")
		emitter.disconnect(mutation)
		s.close()
