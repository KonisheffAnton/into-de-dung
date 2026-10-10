extends SceneTree

class VariantSession extends BattleTacticalSession:
	var sources: Array[ItemDef] = []
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		var helper := definition.summon_definition
		helper.hp_max = 24.0
		helper.armor = 1.0
		helper.strength = 7.0
		helper.weapon_damage = 3.0
		helper.impact_power = 2.0
		helper.balance_max = 8.0
		helper.move_range = 6.0
		helper.main_actions_max = 2.0
		helper.bonus_actions_max = 3.0
		helper.attack_range = 2.0
		helper.name_prefix = "Страж · "
		sources.append(definition)
		return definition

class VariantEnvironment extends BattleEnvironmentSession:
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		definition.summon_definition.hp_max = 24.0
		return definition

class UnsupportedSummon extends SummonDefinition:
	pass

class ForgedSummon extends SummonDefinition:
	var calls: int = 0
	func validate() -> bool:
		calls += 1
		return true
	func to_dict() -> Dictionary:
		calls += 1
		return super.to_dict()

class ForeignItem extends ItemDef:
	var calls: int = 0
	func summon_definition_valid() -> bool:
		calls += 1
		return true

class VariantDemo extends BattleDemo:
	func _create_session() -> void:
		session = VariantSession.new()
		_battle = session as BattleTacticalSession

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL M1: " + label)

func snapshot(s: BattleTacticalSession) -> ItemSimulationSnapshot:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "capture: " + result.reason)
	return result.snapshot

func catalogue(s: BattleTacticalSession) -> Dictionary:
	var result: Dictionary = {}
	for owner in s.state.get_owners():
		for id: StringName in owner._definitions: result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _run() -> void:
	_test_current_envelopes()
	_test_definition_validation()
	_test_forged_definition()
	_test_legacy_raw_precedence()
	_test_spawn_isolation()
	_test_refusal_and_repeat()
	_test_snapshot()
	_test_forecast()
	_test_faults()
	_test_environment()
	await _test_ui()
	print("M1 RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_legacy_raw_precedence() -> void:
	var s := BattleTacticalSession.new()
	var definition := ForeignItem.new()
	definition.id = &"foreign_legacy"
	var owner := s.state.get_owner(s.selected_id)
	var item := owner.create_item(definition)
	check(item != null and s.state.get_inventory(s.selected_id).add_item(item), "legacy subtype fixture still constructible")
	definition.calls = 0
	definition.use_heal_amount = NAN
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "legacy malformed raw outranks unsupported subclass")
	definition.use_heal_amount = 0.0
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and result.reason.ends_with("/subclass") and definition.calls == 0, "legacy exact type checked after raw without virtual call")
	s.close()

func _test_forged_definition() -> void:
	var s := VariantSession.new()
	var seal := s.summoning_item()
	var forged := ForgedSummon.new()
	forged.hp_max = 24.0
	var definition := seal.get_definition()
	definition.summon_definition = forged
	var before := snapshot(s).canonical_bytes()
	var snap := snapshot(s)
	var defs := catalogue(s)
	defs[definition.id] = definition
	var owner := s.state.get_owner(s.selected_id)
	var next_item := owner._next_item_id
	var next_effect := owner._next_effect_id
	var global_id := UnitId.get_counter()
	check(not definition.summon_definition_valid() and not SummonDefinition.valid_definition(forged), "forged override denied statically")
	check(owner.create_item(definition) == null and owner._next_item_id == next_item and owner._next_effect_id == next_effect, "forged create denied before runtime allocation")
	check(snap.instantiate(defs).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "forged restore catalogue denied")
	check(UseSummoningItemCommand.make_helper(999, Faction.Type.PLAYER, Vector2i.ZERO, "owner", forged) == null, "forged direct factory denied")
	check(snapshot(s).canonical_bytes() == before and forged.calls == 0 and UnitId.get_counter() == global_id, "forged Resource never executes virtual code")
	var original := seal._definition.summon_definition
	seal._definition.summon_definition = forged
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "forged live capture denied")
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var receipt := s.use_summoning_item(Vector2i(0, 1))
	check(receipt.status == ActionReceipt.REJECTED and receipt.get_events().is_empty() and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and forged.calls == 0, "forged command denied before callbacks or payment")
	seal._definition.summon_definition = original
	check(snapshot(s).canonical_bytes() == before and UnitId.get_counter() == global_id, "forged rejection preserves full live state")
	s.close()

func _test_current_envelopes() -> void:
	for capability_fixture: int in range(3):
		var capability_session: BattleTacticalSession = BattleTacticalSession.new() if capability_fixture == 0 else (BattleArmorSession.new() if capability_fixture == 1 else BattleEnvironmentSession.new())
		var snap := snapshot(capability_session)
		var data := snap.to_dict()
		check(data["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and data["scope"] == ItemSimulationSnapshot.SCOPE, "capability fixture uses current schema eleven")
		check(data.has("environment") == (capability_session.state.environment != null), "environment capability presence follows runtime")
		for owner_data: Dictionary in data["owners"]:
			for descriptor: Dictionary in owner_data["definitions"]:
				for field: String in ["use_heal_amount", "max_charges", "use_summon", "armor_resistances", "summon_definition"]:
					check(descriptor.has(field), "summon fixture descriptor always includes " + field)
		var defs := catalogue(capability_session)
		var restored := snap.instantiate(defs)
		check(restored.code == ItemSnapshotResult.Code.OK, "current envelope restore")
		if restored.state != null:
			check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snap.canonical_bytes(), "current envelope canonical roundtrip")
			AttackForecast._close(restored.state)
		(defs[&"tactical_summoning_seal"] as ItemDef).summon_definition.hp_max = 25.0
		var counter := UnitId.get_counter()
		check(snap.instantiate(defs).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and UnitId.get_counter() == counter, "current envelope rejects changed catalogue before allocation")
		capability_session.close()

func _test_definition_validation() -> void:
	var definition := SummonDefinition.new()
	check(definition.validate() and definition.is_default() and definition.to_dict() == SummonDefinition.default_values(), "default definition")
	check(not UnsupportedSummon.new().validate(), "subclass denied")
	var wrong_key := definition.to_dict()
	wrong_key.erase("hp_max")
	wrong_key[&"hp_max"] = 16.0
	check(not SummonDefinition.valid_data(wrong_key), "StringName key rejected")
	var copied_default := SummonDefinition.default_values()
	copied_default["hp_max"] = 200.0
	check(definition.is_default(), "default values independent")
	definition.append_owner_name = false
	check(definition.name_valid("x".repeat(5000)) and definition.make_name("owner") == definition.name_prefix, "optional owner suffix")
	definition.append_owner_name = true
	var s := BattleTacticalSession.new()
	var owner := s.state.get_owner(s.selected_id)
	var before := snapshot(s).canonical_bytes()
	var next_item := owner._next_item_id
	var next_effect := owner._next_effect_id
	var global_id := UnitId.get_counter()
	for field: String in ["hp_max", "armor", "strength", "weapon_damage", "impact_power", "balance_max", "move_range", "main_actions_max", "bonus_actions_max", "attack_range"]:
		for value: Variant in [-1.0, 4097.0, INF, NAN, 1, true, "1"]:
			var raw := definition.to_dict()
			raw[field] = value
			check(not SummonDefinition.valid_data(raw), "strict numeric " + field + " " + str(value))
	for patch: Dictionary in [{"hp_max": 0.0}, {"balance_max": 0.0}, {"attack_range": 0.0}, {"main_actions_max": 1.5}, {"bonus_actions_max": 1.5}, {"name_prefix": ""}, {"name_prefix": "я".repeat(129)}, {"append_owner_name": 1}, {"schema_version": 2}, {"owner_id": 3}]:
		var raw := definition.to_dict().merged(patch, true)
		check(not SummonDefinition.valid_data(raw), "strict definition " + str(patch.keys()))
	var missing := definition.to_dict()
	missing.erase("strength")
	check(not SummonDefinition.valid_data(missing), "missing field")
	for invalid in [false, true]:
		var item := ItemDef.new()
		item.id = &"invalid_m1"
		item.use_summon = invalid
		item.max_charges = 2 if invalid else 0
		item.summon_definition = SummonDefinition.new()
		if invalid: item.summon_definition.hp_max = -1.0
		check(owner.create_item(item) == null, "invalid item refused before allocation")
	check(snapshot(s).canonical_bytes() == before and owner._next_item_id == next_item and owner._next_effect_id == next_effect and UnitId.get_counter() == global_id, "invalid definitions pure")
	check(UseSummoningItemCommand.make_helper(999, Faction.Type.PLAYER, Vector2i.ZERO, "a".repeat(4096)) == null, "oversize name no unit")
	check(UnitId.get_counter() == global_id, "factory does not allocate global id")
	s.close()

func _test_ui() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var demo := VariantDemo.new()
	demo.tactical_mode = true
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	check(demo._action_bar._buttons[3].tooltip_text.contains("24 HP"), "variant tooltip reads definition")
	check(demo._inspection_text(demo.session.selected_unit()).contains("24 HP"), "variant inspection reads definition")
	var press := InputEventKey.new()
	press.keycode = KEY_4
	press.pressed = true
	viewport.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	viewport.push_input(release, true)
	await process_frame
	check(demo.summoning_mode and demo._hint.text.contains("24 HP"), "variant real input targeting reads definition")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(argument.trim_prefix("--captures=").path_join("m1-variant-targeting.png")) == OK, "variant capture")
	viewport.queue_free()
	await process_frame
	await process_frame

func _test_refusal_and_repeat() -> void:
	var s := VariantSession.new()
	var owner := s.state.get_owner(s.selected_id)
	var seal := s.summoning_item()
	var copy := seal.get_definition()
	var second := owner.create_item(copy)
	check(second != null and second._definition == seal._definition and second.get_charges_left() == 2, "repeat same ID uses frozen definition")
	var before := snapshot(s).canonical_bytes()
	copy.summon_definition.hp_max += 1.0
	check(owner.create_item(copy) == null and snapshot(s).canonical_bytes() == before, "conflicting repeat rejected without allocation")
	var actor := s.selected_unit()
	actor.debug_name = "x".repeat(4096)
	before = snapshot(s).canonical_bytes()
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var receipt := s.use_summoning_item(Vector2i(0, 1))
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"item/invalid_definition" and snapshot(s).canonical_bytes() == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng, "oversize derived name rejected without payment")
	actor.debug_name = "owner"
	seal._definition.summon_definition.hp_max = -1.0
	var version := s.board.board_version
	var global_id := UnitId.get_counter()
	receipt = s.use_summoning_item(Vector2i(0, 1))
	check(receipt.status == ActionReceipt.REJECTED and receipt.get_events().is_empty() and seal.get_charges_left() == 2 and actor.action_resources.get_main_left() == 1 and s.state.get_summons().is_empty() and s.board.board_version == version and s.context.simulation_counters() == counters and UnitId.get_counter() == global_id, "invalid live definition pure refusal")
	s.close()

func _test_spawn_isolation() -> void:
	var s := VariantSession.new()
	var before := snapshot(s).canonical_bytes()
	var authored := s.sources[0]
	authored.summon_definition.hp_max = 400.0
	authored.max_charges = 9
	var seal := s.summoning_item()
	var exposed := seal.get_definition()
	exposed.summon_definition.strength = 400.0
	exposed.max_charges = 10
	var helper_copy := seal.get_definition().get_summon_definition()
	helper_copy.hp_max = 300.0
	check(snapshot(s).canonical_bytes() == before, "source and getters cannot mutate battle")
	var actor := s.selected_unit()
	var global_id := UnitId.get_counter()
	var stale := UseSummoningItemCommand.new(actor.id, seal.get_item_instance_id(), Vector2i(0, 1), s.context.get_revision())
	check(s.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "variant spawn through real command")
	var helper := s.state.active_summon(actor.id)
	if helper == null:
		s.close()
		return
	for stat: int in helper_copy.base_values():
		check(helper.get_stat(stat as StatTypes.StatType) == seal.get_definition().get_summon_definition().base_values()[stat], "variant stat " + str(stat))
	check(helper.debug_name == "Страж · " + actor.debug_name and helper.vitals.get_hp() == 24.0 and helper.armor == null, "variant name HP legacy capability")
	check(helper.action_resources.get_main_left() == 0 and helper.action_resources.get_bonus_left() == 0 and helper.move_points_left == 0.0 and s.state.is_summon_pending(helper.id), "variant pending")
	before = snapshot(s).canonical_bytes()
	var counters := s.context.simulation_counters()
	check(s._queue.submit(stale, s.context).reason == &"item/stale_revision" and snapshot(s).canonical_bytes() == before and s.context.simulation_counters() == counters, "variant stale pure")
	check(s.select_unit(s.units[2].id) and s.use_summoning_item(Vector2i(2, 4)).status == ActionReceipt.APPLIED, "second variant owner")
	var other := s.state.active_summon(s.selected_id)
	helper.vitals.apply_damage(100.0)
	check(other.vitals.get_hp() == 24.0 and other.stats != helper.stats and other.vitals != helper.vitals and other.action_resources != helper.action_resources, "runtime ownership isolated")
	actor.try_refill_turn_resources()
	s.select_unit(actor.id)
	check(s.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "variant replacement")
	var replacement := s.state.active_summon(actor.id)
	check(replacement.id != helper.id and replacement.vitals.get_hp() == 24.0 and UnitId.get_counter() == global_id, "replacement independent no global ID")
	check(s._refill(Faction.Type.PLAYER) and replacement.action_resources.get_main_left() == 2 and replacement.action_resources.get_bonus_left() == 3 and replacement.move_points_left == 6.0 and not s.state.is_summon_pending(replacement.id), "variant admission refill")
	s.close()

func _test_snapshot() -> void:
	var s := VariantSession.new()
	var snap := snapshot(s)
	check(snap.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and snap.to_dict()["scope"] == ItemSimulationSnapshot.SCOPE and not snap.to_dict().has("environment"), "current schema omits absent environment capability")
	for ready in [false, true]:
		if not ready: s.use_summoning_item(Vector2i(0, 1))
		else: s._refill(Faction.Type.PLAYER)
		snap = snapshot(s)
		var defs := catalogue(s)
		var restored := ItemSimulationSnapshot.from_dict(snap.to_dict()).snapshot.instantiate(defs)
		check(restored.code == ItemSnapshotResult.Code.OK, "current schema restore")
		if restored.state != null:
			check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snap.canonical_bytes(), "current pending/ready no refill")
			(defs[&"tactical_summoning_seal"] as ItemDef).summon_definition.hp_max = 300.0
			check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snap.canonical_bytes(), "restore catalogue isolated")
			AttackForecast._close(restored.state)
	var data := snap.to_dict()
	var index := -1
	for i in data["owners"][0]["definitions"].size():
		if data["owners"][0]["definitions"][i]["use_summon"]: index = i
	check(index >= 0, "find descriptor")
	if index >= 0:
		for patch: Dictionary in [{"hp_max": -1.0}, {"hp_max": 24}, {"strength": INF}, {"schema_version": 99}, {"pending": true}, {"name_prefix": "x".repeat(257)}]:
			var bad := data.duplicate(true)
			bad["owners"][0]["definitions"][index]["summon_definition"].merge(patch, true)
			var global_id := UnitId.get_counter()
			check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and UnitId.get_counter() == global_id, "current raw rejection " + str(patch.keys()))
		var defs := catalogue(s)
		(defs[&"tactical_summoning_seal"] as ItemDef).summon_definition.name_prefix = "Другой · "
		check(snap.instantiate(defs).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "catalogue full name mismatch")
		defs.erase(&"tactical_summoning_seal")
		check(snap.instantiate(defs).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "missing catalogue")
		var conflict := data.duplicate(true)
		conflict["owners"][0]["definitions"][index]["summon_definition"]["hp_max"] = 25.0
		check(ItemSimulationSnapshot.from_dict(conflict).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "conflicting owner definitions")
	var unknown := data.duplicate(true)
	unknown["scope"] = "unknown"
	check(ItemSimulationSnapshot.from_dict(unknown).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unknown scope")
	check(snapshot(s).canonical_bytes() == snap.canonical_bytes(), "malformed decode does not mutate live")
	s.close()

func _parity(s: BattleTacticalSession, cmd: AttackCommand) -> void:
	var before := snapshot(s).canonical_bytes()
	var counters := s.context.simulation_counters()
	var rules := SummonAdmission.values(s.context)
	var rng := s.context.get_rng().to_dict()
	var global_id := UnitId.get_counter()
	var forecast := AttackForecast.build(s.context, s._queue, cmd)
	var again := AttackForecast.build(s.context, s._queue, cmd)
	check(forecast.status == ActionReceipt.APPLIED and again.snapshot_after == forecast.snapshot_after, "variant forecast repeated " + String(forecast.reason))
	check(snapshot(s).canonical_bytes() == before and s.context.simulation_counters() == counters and SummonAdmission.values(s.context) == rules and s.context.get_rng().to_dict() == rng and UnitId.get_counter() == global_id, "variant forecast isolation")
	var receipt := s._submit(cmd)
	check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(s).to_dict() == forecast.snapshot_after and s.context.simulation_counters() == forecast.counters_after and s.context.get_rng().to_dict() == forecast.rng_after, "variant full live parity")

func _test_forecast() -> void:
	for mode in [0, 1, 2]:
		var s := VariantSession.new()
		if mode == 0:
			_parity(s, AttackCommand.new(s.units[2].id, s.units[3].id, s.units[2].cell, s.units[3].cell, &"demo_strike", s.context.get_revision()))
		else:
			s.use_summoning_item(Vector2i(0, 1))
			var helper := s.state.active_summon(s.selected_id)
			var enemy := s.units[1]
			s.board.move_unit(enemy, Vector2i(1, 1))
			if mode == 2: s._refill(Faction.Type.PLAYER)
			var actor := enemy if mode == 1 else helper
			var target := helper if mode == 1 else enemy
			target.vitals.apply_damage(target.vitals.get_hp() - 1.0)
			_parity(s, AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision()))
			check(not target.is_alive(), "variant lethal helper target/actor")
		s.close()

func _test_faults() -> void:
	for mutation in [false, true]:
		var s := VariantSession.new()
		var seal := s.summoning_item()
		var cb := func() -> void: seal._definition.summon_definition.hp_max += 1.0
		if mutation: s.board.board_changed.connect(cb)
		else: s._queue = ActionQueue.new(1, 1, 1)
		var receipt := s.use_summoning_item(Vector2i(0, 1))
		if mutation: s.board.board_changed.disconnect(cb)
		check(receipt.status == ActionReceipt.FAULTED and receipt.reason == (&"summon/invalid_mutation" if mutation else &"event_limit"), "variant callback/limit fault")
		check(s.state.active_summon(s.units[0].id) != null and seal.get_charges_left() == 1 and s.units[0].action_resources.get_main_left() == 0 and receipt.get_events().size() == 2, "variant completed prefix preserved")
		s.close()

func _test_environment() -> void:
	var s := VariantEnvironment.new()
	var snap := snapshot(s)
	check(snap.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and snap.to_dict()["scope"] == ItemSimulationSnapshot.SCOPE and snap.to_dict().has("environment"), "current schema carries present environment capability")
	check(s.raise_corpse(Vector2i(0, 3)).status == ActionReceipt.APPLIED, "D5 raise with custom unused seal")
	var helper := s.state.active_summon(s.units[0].id)
	check(helper != null and helper.vitals.get_hp() == 16.0 and helper.armor != null and helper.bleeding != null, "D5 keeps fixed default and capabilities")
	var restored := snapshot(s).instantiate(catalogue(s))
	check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snapshot(s).canonical_bytes(), "current environment restore")
	if restored.state != null: AttackForecast._close(restored.state)
	var cmd := UseSummoningItemCommand.new(s.units[0].id, s.summoning_item().get_item_instance_id(), Vector2i(0, 1), s.context.get_revision())
	check(cmd.validate(s.context) == &"item/insufficient_main", "raise spent the main action also required by the seal")
	var corpse_count := s.state.environment.corpses.size()
	var receipt := s._queue.submit(DeathCommand.new(helper.id, DamageSource.new(&"cell", 0, helper.cell)), s.context)
	check(receipt.status == ActionReceipt.APPLIED and s.state.environment.corpses.size() == corpse_count and s.board.occupant_at(helper.cell) == null, "raised helper death leaves no corpse")
	s.close()
