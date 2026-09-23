extends SceneTree

var passed: int = 0
var failed: int = 0
const PIERCING: int = StatTypes.StatType.PHYSICAL_PIERCING_PERCENT

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL PIERCING: " + label)

func _run() -> void:
	_ids_and_legacy()
	_equipment_and_save()
	_live_and_preview()
	_rejections()
	_fault_prefix()
	_control_interaction()
	print("ARMOR PIERCING RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _ids_and_legacy() -> void:
	check(PIERCING == 11 and StatTypes.StatType.ATTACK_RANGE == 10, "append only IDs")
	for bad: Variant in [-1, 12, 11.0, "11", true, null]:
		check(not StatTypes.is_valid_id(bad), "strict raw stat ID " + str(bad))
	var old := D4RunState.new().to_dict()
	(old["items"] as Array).pop_back()
	old["next_item_id"] = 13
	var restored := D4RunState.from_dict(old)
	check(restored != null and restored.to_dict() == old, "old profile retains 12 items; no automatic grant")
	var bag := StatsBag.from_base_values({PIERCING: 50.0})
	var raw := bag.to_snapshot_dict()
	check(StatsBag.from_snapshot_dict(raw).get_value(PIERCING) == 50.0, "new ID in existing stats schema")
	for bad: Variant in [12, 11.0, "11", true]:
		var invalid := raw.duplicate(true)
		invalid["stats"][0]["stat_type"] = bad
		check(not StatsBag.validate_snapshot_dict(invalid), "raw stats reject invalid ID " + str(bad))

func _equipment_and_save() -> void:
	var run := D4RunState.new()
	check(run.item(13).kind == "piercing_sword" and run.item(13).place == "warehouse", "one demo weapon on new profile")
	check(run.equip(13, 1), "equip demo weapon")
	var path := "user://piercing-%d.save" % Time.get_ticks_usec()
	check(D4RunStore.write_run(path, run).is_empty(), "disk save")
	var restored: D4RunState = D4RunStore.read_run(path).run
	check(restored != null and restored.to_dict() == run.to_dict(), "disk restore exact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if restored == null: return
	check(restored.start_run(), "restored checkpoint starts battle")
	var s := D4BattleSession.new()
	check(s.configure(restored), "saved weapon projects")
	var actor: UnitState = s.hero_units[1]
	check(actor.get_stat(PIERCING) == 50.0 and actor.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4.0, "equipped effect supplies percent and weapon damage")
	check((s.hero_units[2] as UnitState).get_stat(PIERCING) == 0.0, "other hero has no piercing")
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "weapon snapshot supported")
	if captured.snapshot != null:
		var definitions: Dictionary = {}
		for owner: ItemOwnerState in s.state.get_owners():
			for key: StringName in owner._definitions:
				definitions[key] = (owner._definitions[key] as ItemDef).duplicate(true)
		var instance := captured.snapshot.instantiate(definitions)
		check(instance.code == ItemSnapshotResult.Code.OK, "weapon snapshot restores")
		if instance.state != null:
			check(instance.state.get_board().get_unit_by_id(actor.id).get_stat(PIERCING) == 50.0, "restore does not double modifier")
			check(ItemSimulationSnapshot.capture(instance.state, []).snapshot.to_dict() == captured.snapshot.to_dict(), "snapshot canonical roundtrip")
			AttackForecast._close(instance.state)
		var changed: ItemDef = definitions[&"d4_piercing_sword"]
		(changed.effects[0] as StatModifierEffect).value = 25.0
		check(captured.snapshot.instantiate(definitions).code != ItemSnapshotResult.Code.OK, "catalogue mismatch rejected")
		for bad: Variant in [12, 11.0, "11", true]:
			var invalid := captured.snapshot.to_dict()
			for owner: Dictionary in invalid["owners"]:
				for definition: Dictionary in owner["definitions"]:
					if definition["id"] == "d4_piercing_sword": definition["effects"][0]["stat_type"] = bad
			check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK, "item raw effect rejects " + str(bad))
	s.close()
	check(run.unequip(13) and run.start_run() and s.configure(run), "unequipped weapon projection")
	check((s.hero_units[1] as UnitState).get_stat(PIERCING) == 0.0, "warehouse effect inactive")
	s.close()
	var backpack := D4RunState.new()
	backpack.items[12].place = "backpack"
	backpack.items[12].hero = 1
	check(backpack.start_run() and s.configure(backpack), "backpack projection")
	check((s.hero_units[1] as UnitState).get_stat(PIERCING) == 0.0, "backpack effect inactive")
	s.close()

func _fixture(equipped: bool = true) -> D4BattleSession:
	var run := D4RunState.new()
	if equipped: run.equip(13, 1)
	run.start_run()
	var s := D4BattleSession.new()
	check(s.configure(run), "fixture configures")
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	s.board.move_unit(s.hero_units[1], Vector2i(3, 3))
	s.board.move_unit(s.units[3], Vector2i(4, 3))
	(s.hero_units[1] as UnitState).stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0)
	s.select_unit((s.hero_units[1] as UnitState).id)
	return s

func _live_and_preview() -> void:
	var s := _fixture()
	var actor: UnitState = s.hero_units[1]
	var target: UnitState = s.units[3]
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var preview := s.preview_attack(target.id)
	check(preview.status == ActionReceipt.APPLIED, "real piercing forecast applies")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "preview isolates state RNG IDs resources")
	var rows := _attack_rows(preview.events)
	check(rows.size() == 3, "physical two policies plus fire")
	if rows.size() == 3:
		check(rows[0].D == 5 and rows[0].armor_spent == 5 and rows[0].hp_damage == 0, "ordinary half into full armor")
		check(rows[1].policy == &"hp_only_natural" and rows[1].D == 5 and rows[1].armor_spent == 0 and rows[1].hp_damage == 5, "piercing half into HP")
		check(rows[2].type == &"fire" and rows[2].D == 10 and rows[2].armor_spent == 10, "fire component unchanged")
	var receipt := s.attack_unit(target.id)
	check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "live forecast events steps parity")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after and s.context.simulation_counters() == preview.counters_after, "live forecast full state RNG counters parity")
	check(actor.action_resources.get_main_left() == 0 and target.vitals.get_hp() == 27, "one main and five HP")
	check(target.bleeding.ticks_left > 0, "existing physical HP bleeding gate sees piercing")
	check(s.attack_unit(target.id).status != ActionReceipt.APPLIED, "no second free attack")
	s.close()

func _rejections() -> void:
	var extras: Array[Dictionary] = []
	for index: int in 127:
		extras.append({"type":"fire", "policy":"standard", "numerator":1, "denominator":1, "source":"extra%d" % index, "factor_num":1, "factor_den":1})
	check(ArmorAttack.components(6, 4, 0, false, extras).size() == 128, "old component budget retained")
	check(ArmorAttack.components(6, 4, 0, false, extras, 0, 1, 50).is_empty(), "split refuses component overflow")
	var changed := _fixture()
	var changed_actor: UnitState = changed.hero_units[1]
	var changed_target := changed.units[3]
	var stale := AttackCommand.new(changed_actor.id, changed_target.id, changed_actor.cell, changed_target.cell, &"demo_strike", changed.context.get_revision())
	check(stale.validate(changed.context) == &"", "valid admission before runtime change")
	changed_actor.stats.set_base_value(PIERCING, 51)
	check(stale.execute(changed.context).status == ActionReceipt.FAULTED and changed_actor.action_resources.get_main_left() == 1 and changed_target.vitals.get_hp() == 32, "execute rechecks percentage before paying")
	changed.close()
	for value: float in [-51.0, 51.0, 0.5, INF, NAN]:
		var s := _fixture()
		var actor: UnitState = s.hero_units[1]
		actor.stats.set_base_value(PIERCING, value)
		var rng := s.context.get_rng().to_dict()
		var counters := s.context.simulation_counters()
		var target := s.units[3]
		var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision())
		check(command.validate(s.context) != &"", "invalid final percent rejected " + str(value))
		check(actor.action_resources.get_main_left() == 1 and target.vitals.get_hp() == 32 and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "invalid admission does not mutate")
		s.close()
	var legacy := BattleTacticalSession.new()
	var actor := legacy.units[0]
	actor.stats.set_base_value(PIERCING, 50)
	var target := legacy.units[1]
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", legacy.context.get_revision())
	check(command.validate(legacy.context) == &"attack/piercing_requires_armor", "legacy refuses unsupported piercing")
	legacy.close()

func _fault_prefix() -> void:
	for equipped: bool in [true, false]:
		var s := _fixture(equipped)
		var actor: UnitState = s.hero_units[1]
		var target := s.units[3]
		var before := ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(target.id)))
		var tamper := func(_kind: StringName, _id: int, _before: int, _after: int) -> void: actor.stats.set_base_value(PIERCING, 25)
		target.armor.changed.connect(tamper)
		var receipt := s.attack_unit(target.id)
		check(receipt.status == ActionReceipt.FAULTED, "changing present/absent piercing faults")
		check(actor.action_resources.get_main_left() == 0 and target.vitals.get_hp() == 32, "fault keeps cost and stops before HP")
		check(ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(target.id))).current < before.current, "fault retains armor prefix")
		check(not receipt.get_events().any(func(event: Dictionary) -> bool: return event.kind == &"hit_resolved"), "fault has no complete hit")
		target.armor.changed.disconnect(tamper)
		s.close()

func _control_interaction() -> void:
	var s := BattleControlSession.new()
	var actor := s.units[0]
	var target := s.units[1]
	actor.stats.set_base_value(PIERCING, 50)
	var preview := s.preview_attack(target.id)
	var receipt := s.attack_unit(target.id)
	check(preview.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "C1 critical plus piercing live preview parity")
	var rows := _attack_rows(receipt.get_events())
	check(rows.size() == 3 and rows[0].D == rows[1].D and rows[1].policy == &"hp_only_natural", "C1 critical physical base splits")
	s.close()

func _attack_rows(events: Array[Dictionary]) -> Array:
	for event: Dictionary in events:
		if event.kind == &"hit_resolved" and event.get("source", {}).get("kind") == &"attack": return event.hit.rows
	return []
