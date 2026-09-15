extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HEALING: " + label)

func snapshot(s: BattleDemoSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "capture " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func catalogue(s: BattleDemoSession) -> Dictionary:
	var definitions: Dictionary = {}
	for owner in s.state.get_owners():
		for id: StringName in owner._definitions:
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return definitions

func command(s: BattleTacticalSession) -> UseHealingItemCommand:
	return UseHealingItemCommand.new(s.selected_id, s.healing_item().get_item_instance_id(), s.context.get_revision())

func refuse(s: BattleTacticalSession, cmd: Command, reason: StringName) -> void:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var revision := s.context.get_revision()
	var rng := s.context.get_rng().to_dict()
	var receipt := s._queue.submit(cmd, s.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == reason, "refuse " + String(reason) + ": " + String(receipt.reason))
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_revision() == revision and s.context.get_rng().to_dict() == rng and not s.context.is_faulted(), "refusal no mutation")

func _run() -> void:
	_test_use()
	_test_refusals()
	_test_snapshots()
	_test_forecast()
	_test_faults()
	print("HEALING RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_use() -> void:
	var s := BattleTacticalSession.new()
	var actor := s.selected_unit()
	var item := s.healing_item()
	check(item != null and item.get_charges_left() == 2 and item.get_definition().use_heal_amount == 12.0, "initial flask")
	var before := snapshot(s)
	var last := s.last_receipt
	check(s.healing_reason() == &"item/full_hp" and snapshot(s) == before and s.last_receipt == last, "availability pure/full hp")
	actor.vitals.apply_damage(20.0)
	actor.guard_stance = true
	var bonus := actor.action_resources.get_bonus_left()
	var move := actor.move_points_left
	var rng := s.context.get_rng().to_dict()
	var stale := command(s)
	var seen: Array[bool] = []
	var callback := func(_before: float, _after: float) -> void:
		seen.append(actor.action_resources.get_main_left() == 0 and item.get_charges_left() == 1)
	actor.vitals.hp_changed.connect(callback)
	var receipt := s.use_healing_item()
	actor.vitals.hp_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.APPLIED and actor.vitals.get_hp() == 24.0, "heal12 applied " + String(receipt.reason))
	check(item.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0 and seen == [true], "charge and main before signal")
	check(actor.guard_stance and actor.move_points_left == move and actor.action_resources.get_bonus_left() == bonus and not actor.has_attacked, "unrelated resources/stance preserved")
	check(receipt.get_steps().size() == 1 and receipt.get_events().size() == 2 and receipt.revision_after == receipt.revision_before + 1 and s.context.get_rng().to_dict() == rng, "atomic revision/event/RNG")
	var events := receipt.get_events()
	check(events[0]["kind"] == &"item_used" and events[0]["charges_after"] == 1 and events[1]["source"]["source_instance_id"] == item.get_item_instance_id() and events[1]["source"]["kind"] == &"item", "item journal source")
	refuse(s, stale, &"item/stale_revision")
	refuse(s, command(s), &"item/insufficient_main")
	check(s.select_unit(s.units[2].id) and s.healing_item().get_charges_left() == 2, "other owner separate charges")
	check(s.select_unit(actor.id) and s.healing_item() == item and item.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0, "selection preserves resources")
	actor.try_refill_turn_resources()
	receipt = s.use_healing_item()
	check(receipt.status == ActionReceipt.APPLIED and actor.vitals.get_hp() == 32.0 and receipt.get_events()[1]["amount"] == 8.0 and item.get_charges_left() == 0, "second charge clamps to missing8")
	actor.try_refill_turn_resources()
	refuse(s, command(s), &"item/no_charges")
	var inv := s.state.get_inventories()[0]
	check(inv.remove_item(item) and inv.add_item(item) and item.get_charges_left() == 0, "detach/reactivate no refill")
	check(s.end_player_turn(), "end turn")
	for _i in 20:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and item.get_charges_left() == 0, "team turn no charge refill")
	s.reset()
	check(s.healing_item().get_charges_left() == 2 and s.selected_unit().vitals.get_hp() == 32.0, "reset fresh items")
	s.close()

func _test_refusals() -> void:
	var s := BattleTacticalSession.new()
	refuse(s, command(s), &"item/full_hp")
	s.selected_unit().vitals._hp = 40.0
	refuse(s, command(s), &"item/full_hp")
	s.selected_unit().vitals._hp = 10.0
	refuse(s, UseHealingItemCommand.new(s.selected_id, 999, s.context.get_revision()), &"item/not_owned")
	refuse(s, UseHealingItemCommand.new(s.units[1].id, s.healing_item().get_item_instance_id(), s.context.get_revision()), &"item/not_usable")
	var item := s.healing_item()
	var cmd := command(s)
	s.state.get_inventories()[0].remove_item(item)
	refuse(s, cmd, &"item/inactive")
	s.state.get_inventories()[0].add_item(item)
	s.context._busy = true
	check(s._queue.submit(cmd, s.context).reason == &"BUSY" and s.healing_reason() == &"battle/input_locked", "busy")
	s.context._busy = false
	s.context._faulted = true
	check(s._queue.submit(cmd, s.context).reason == &"CONTEXT_FAULTED", "faulted")
	s.context._faulted = false
	s.selected_unit().vitals.apply_damage(100.0)
	refuse(s, cmd, &"item/no_selected_unit")
	s.reset()
	cmd = command(s)
	s.close()
	check(cmd.validate(s.context) == &"item/invalid_runtime", "closed")
	s = BattleTacticalSession.new()
	s.selected_unit().vitals.apply_damage(10.0)
	s.context._move_rules = MoveRules.new([s.units[1].id], 1, &"spatial_move_v1")
	refuse(s, command(s), &"item/not_admitted")
	s.close()

func _test_snapshots() -> void:
	var legacy := BattleDemoSession.new()
	var old := ItemSimulationSnapshot.capture(legacy.state, []).snapshot
	check(old.to_dict()["schema_version"] == 1 and old.canonical_bytes()[4] == 1, "legacy v1")
	var definitions := catalogue(legacy)
	var forged: ItemDef = definitions.values()[0]
	forged.use_heal_amount = 1.0
	forged.max_charges = 1
	check(old.instantiate(definitions).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "v1 refuses injected usable catalogue")
	legacy.close()
	var s := BattleTacticalSession.new()
	s.healing_item()._charges_left = 0
	var data := snapshot(s)
	var saved := ItemSimulationSnapshot.from_dict(data).snapshot
	check(data["schema_version"] == 2 and data["scope"] == ItemSimulationSnapshot.SCOPE_V2 and saved.canonical_bytes()[4] == 2, "v2 envelope")
	var restored := saved.instantiate(catalogue(s))
	check(restored.code == ItemSnapshotResult.Code.OK, "restore")
	check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.fingerprint() == saved.fingerprint(), "canonical roundtrip")
	var restored_item: ItemInstance = restored.state.get_owner(s.selected_id)._items[s.healing_item().get_item_instance_id()]
	check(restored_item.get_charges_left() == 0 and restored_item != s.healing_item() and restored_item.get_definition() != s.healing_item().get_definition(), "zero charges and independent runtime/def")
	restored_item._charges_left = 1
	check(s.healing_item().get_charges_left() == 0, "clone charges isolated")
	AttackForecast._close(restored.state)
	var first: Dictionary = data["owners"][0]
	check(first["items"][0]["charges_left"] == 0, "stored zero")
	for value: Variant in [-1, 3, 4097, 1.5, true, "1", null]:
		var bad := data.duplicate(true)
		bad["owners"][0]["items"][0]["charges_left"] = value
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "bad charge " + str(value))
	for field: String in ["charges_left"]:
		var bad := data.duplicate(true)
		bad["owners"][0]["items"][0].erase(field)
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "missing charge")
	for field: String in ["max_charges", "use_heal_amount"]:
		var bad := data.duplicate(true)
		bad["owners"][0]["definitions"][0].erase(field)
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "missing definition " + field)
	for value: Variant in [-1.0, NAN, INF, 0.0, 12, "12"]:
		var bad := data.duplicate(true)
		bad["owners"][0]["definitions"][0]["use_heal_amount"] = value
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "invalid amount " + str(value))
	for value: Variant in [-1, 0, 4097, 2.0, true]:
		var bad := data.duplicate(true)
		bad["owners"][0]["definitions"][0]["max_charges"] = value
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "invalid capacity " + str(value))
	var unknown := data.duplicate(true)
	unknown["schema_version"] = 99
	check(ItemSimulationSnapshot.from_dict(unknown).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unknown v2-shaped envelope")
	var changed := catalogue(s)
	(changed[&"tactical_healing_flask"] as ItemDef).use_heal_amount = 13.0
	check(saved.instantiate(changed).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "catalogue mismatch")
	s.healing_item()._charges_left = 3
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "live charge overflow")
	s.healing_item()._charges_left = 0
	var def := s.healing_item().get_definition()
	def.use_heal_amount = NAN
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "live NaN")
	def.use_heal_amount = 12.0
	var owner := s.state.get_owner(s.selected_id)
	var bad_def := ItemDef.new()
	bad_def.id = &"bad_flask"
	bad_def.max_charges = 2
	check(owner.create_item(bad_def) == null, "create rejects incomplete pair")
	s.close()

func _test_forecast() -> void:
	var s := BattleTacticalSession.new()
	s.select_unit(s.units[2].id)
	var item := s.healing_item()
	item._charges_left = 1
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var last := s.last_receipt
	var rng := s.context.get_rng().to_dict()
	var forecast := s.preview_attack(s.units[3].id)
	var repeated := s.preview_attack(s.units[3].id)
	check(forecast.status == ActionReceipt.APPLIED and forecast.snapshot_after == repeated.snapshot_after, "forecast v2 repeat " + String(forecast.reason))
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.last_receipt == last and s.context.get_rng().to_dict() == rng, "forecast v2 no mutation")
	var receipt := s.attack_unit(s.units[3].id)
	check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(s) == forecast.snapshot_after, "forecast full v2 parity")
	check(s.context.simulation_counters() == forecast.counters_after and item.get_charges_left() == 1, "forecast counters/charge parity")
	s.close()

func _test_faults() -> void:
	var s := BattleTacticalSession.new()
	s.selected_unit().vitals.apply_damage(20.0)
	s._queue = ActionQueue.new(1, 1, 1)
	var receipt := s.use_healing_item()
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"event_limit" and receipt.get_events().size() == 2 and s.units[0].vitals.get_hp() == 24.0 and s.units[0].action_resources.get_main_left() == 0, "event limit keeps atomic prefix")
	s.close()
	s = BattleTacticalSession.new()
	s.selected_unit().vitals.apply_damage(20.0)
	var actor := s.selected_unit()
	var item := s.healing_item()
	var callback := func(_a: float, _b: float) -> void: item._charges_left += 1
	actor.vitals.hp_changed.connect(callback)
	receipt = s.use_healing_item()
	actor.vitals.hp_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"item/invalid_mutation" and receipt.get_events()[0]["charges_after"] == 1 and actor.vitals.get_hp() == 24.0, "callback charge mutation faults own prefix")
	s.close()
	s = BattleTacticalSession.new()
	s.selected_unit().vitals.apply_damage(20.0)
	actor = s.selected_unit()
	var nested: Array[StringName] = []
	var cmd := command(s)
	callback = func(_a: float, _b: float) -> void: nested.append(s._queue.submit(cmd, s.context).reason)
	actor.vitals.hp_changed.connect(callback)
	receipt = s.use_healing_item()
	actor.vitals.hp_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.APPLIED and nested == [&"BUSY"], "nested submit refused")
	var event: Dictionary = receipt.get_events()[0]
	for field: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: event.erase(field)
	check(ActionQueue._valid_draft(event), "strict item event valid")
	event["charges_after"] = 99
	check(not ActionQueue._valid_draft(event), "strict item event bad debit")
	s.close()
