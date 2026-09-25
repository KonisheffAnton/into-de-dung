extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session := _fixture()
	_check(session.units.size() >= 2, "armor fixture creates two units")
	_check(session.units[0].armor != null and session.units[1].armor != null, "armor capability is explicit")
	var target := session.units[1]
	var before := ItemSimulationSnapshot.capture(session.state, [])
	_check(before.code == ItemSnapshotResult.Code.OK, "initial armor snapshot")
	if before.code != ItemSnapshotResult.Code.OK or before.snapshot == null:
		printerr("BLOCKED ARMOR INTEGRATION: initial snapshot reason=" + String(before.reason))
		session.close()
		print("ARMOR INTEGRATION RESULTS: %d passed, %d failed" % [passed, failed + 1])
		quit(1)
		return
	var preview := session.preview_attack(target.id)
	if preview.status != ActionReceipt.APPLIED: printerr("BLOCKED ARMOR INTEGRATION: forecast reason=" + String(preview.reason))
	_check(preview.status == ActionReceipt.APPLIED, "armor forecast applies")
	_check(preview.snapshot_before != null and preview.snapshot_after != null, "forecast snapshots present")
	_check(preview.events.size() > 0, "forecast emits events")
	_check(preview.steps.size() > 0, "forecast emits steps")
	var live_before_rng := session.context.get_rng().to_dict()
	var live_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var repeated := session.preview_attack(target.id)
	_check(preview.events == repeated.events, "forecast events deterministic")
	_check(preview.steps == repeated.steps, "forecast steps deterministic")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == live_before, "forecast leaves armor live state unchanged")
	_check(session.context.get_rng().to_dict() == live_before_rng, "forecast leaves RNG unchanged")
	var receipt := session.attack_unit(target.id)
	_check(receipt.status == preview.status, "live and forecast status parity")
	_check(receipt.reason == preview.reason, "live and forecast reason parity")
	_check(receipt.get_events() == preview.events, "live and forecast event parity")
	_check(receipt.get_steps() == preview.steps, "live and forecast step parity")
	var after := ItemSimulationSnapshot.capture(session.state, [])
	_check(after.code == ItemSnapshotResult.Code.OK, "post-hit snapshot")
	_check(after.snapshot.to_dict() == preview.snapshot_after, "live and forecast snapshot parity")
	_check(target.armor != null and target.vitals != null, "target remains valid runtime")
	_check(session.context.get_rng().to_dict() == preview.rng_after, "live and forecast RNG parity")
	_check(session.context.simulation_counters() == preview.counters_after, "live and forecast counters parity")
	var rows: Array = []
	for unit: UnitState in session.units:
		_check(unit.armor.natural.has("physical"), "natural physical resistance retained")
		_check(unit.armor.natural.has("fire"), "natural fire resistance retained")
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values():
			_check(item.armor_origin_owner == unit.id, "armor origin owner retained")
			_check(item.armor_origin_item == item.get_item_instance_id(), "armor origin item retained")
			_check(item.armor_remaining >= 0 and item.armor_remaining <= item.get_definition().armor_max, "armor remains bounded")
			rows.append(item.armor_remaining)
	_check(rows.size() >= 4, "all armor items participate in snapshot")
	var isolated := preview.snapshot_after.duplicate(true)
	if isolated.has("board_snapshot"): isolated["board_snapshot"].clear()
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == after.snapshot.to_dict(), "forecast DTO mutation isolated")
	var invalid := session.preview_attack(999999)
	_check(invalid.status != ActionReceipt.APPLIED, "unknown target rejected")
	_check(session.context.get_rng().to_dict() == preview.rng_after, "rejection does not draw RNG")
	var legacy := DamageCalculator.calculate(session.units[0], session.units[1], session.units[0].cell, session.units[1].cell, 0.25, 0.0, session.board)
	_check(legacy.reason == &"armor/legacy_unsupported", "legacy calculator rejects armor capability")
	_check(session.units[1].armor != null, "armor capability survives legacy rejection")
	_test_math_contract()
	_test_checkpoint_faults()
	_test_voluntary_fall()
	_test_real_hit_boundaries()
	_test_rng_prefix_and_limits()
	_test_collision_fall()
	_test_last_enemy_expiry()
	_test_decimal_collision()
	_test_expiry_rng_fault()
	_test_sequential_move_admission()
	session.close()
	print("ARMOR INTEGRATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fixture() -> BattleArmorSession:
	var session := BattleArmorSession.new()
	for y in session.board.height:
		for x in session.board.width:
			session.board.set_height_steps(Vector2i(x, y), 0)
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	session.board.move_unit(session.units[0], Vector2i(3, 3))
	session.board.move_unit(session.units[1], Vector2i(4, 3))
	return session

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ARMOR INTEGRATION: " + label)

func _test_math_contract() -> void:
	var defenses := {"physical": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}, "fire": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 11000}}
	var physical: Array[Dictionary] = [{"type": &"physical", "policy": &"standard", "amount": ArmorFraction.make(100), "source": &"test"}]
	var fire: Array[Dictionary] = [{"type": &"fire", "policy": &"standard", "amount": ArmorFraction.make(10), "source": &"test"}]
	var armor_only := ArmorHitCalculation.calculate(physical, 50, 100, 100, 100, defenses)
	_check(armor_only.p_num == 0, "math p empty half")
	_check(armor_only.armor_spent == 50, "math armor spent")
	_check(armor_only.hp_after == 50, "math armor overflow HP")
	_check(armor_only.total_damage == 50, "math gross damage")
	var below := ArmorHitCalculation.calculate(physical, 40, 100, 100, 100, defenses)
	_check(below.hp_after == 40, "math below half armor absorbs")
	_check(below.armor_spent == 40, "math below half spends remainder")
	var overflow := ArmorHitCalculation.calculate(physical, 0, 100, 100, 100, defenses)
	_check(overflow.hp_after == 0, "math empty armor lethal")
	_check(overflow.total_damage == 100, "math empty armor damage")
	var healing_defense := defenses.duplicate(true)
	healing_defense["fire"]["natural"] = 11000
	var healing := ArmorHitCalculation.calculate(fire, 0, 0, 5, 10, healing_defense)
	_check(healing.total_healing == 1, "math 110 percent healing")
	_check(healing.total_damage == 0, "math net healing gross damage zero")
	_check(healing.hp_after == 6, "math healing clamps once")
	var vulnerable_defense := defenses.duplicate(true)
	vulnerable_defense["physical"]["natural"] = -2500
	var vulnerable := ArmorHitCalculation.calculate(physical, 0, 0, 100, 100, vulnerable_defense)
	_check(vulnerable.total_damage == 125, "math vulnerability")
	_check(vulnerable.hp_after == 0, "math vulnerability lethal clamp")
	var grouped: Array[Dictionary] = [{"type": &"physical", "policy": &"standard", "amount": ArmorFraction.make(3, 5), "source": &"a"}, {"type": &"physical", "policy": &"standard", "amount": ArmorFraction.make(3, 5), "source": &"b"}]
	var grouped_result := ArmorHitCalculation.calculate(grouped, 0, 0, 10, 10, defenses)
	_check(grouped_result.rows.size() == 1, "math groups provenance")
	_check(grouped_result.rows[0]["hp_damage"] == 1, "math floors after grouping")
	_check((grouped_result.rows[0]["sources"] as Array).size() == 2, "math preserves sources")
	var shares := ArmorHitCalculation.distribute(7, [5, 3, 2])
	_check(shares.size() == 3, "math distribution size")
	_check(shares[0] + shares[1] + shares[2] == 7, "math distribution total")
	_check(shares[0] >= shares[1] and shares[1] >= shares[2], "math distribution order")
	for i in range(1):
		var copy := grouped_result.get_rows()
		(copy[0]["sources"] as Array).append(&"mutation")
		_check(grouped_result.get_rows()[0]["sources"].size() == 2, "math deep copy iteration %d" % i)

func _test_checkpoint_faults() -> void:
	var extra_case := _fixture()
	var target := extra_case.units[1]
	target.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 50, "expires": "battle", "battle_id": target.armor.battle_id}]
	target.armor.next_grant_id = 2
	var changed: Dictionary = {"value": false}
	var mutate := func(kind: StringName, _key: int, _before: int, _after: int) -> void:
		if kind == &"extra":
			changed["value"] = true
			target.guard_stance = true
	target.armor.changed.connect(mutate)
	var before_hp := target.vitals.get_hp()
	var before_rng := extra_case.context.get_rng().to_dict()
	var fault := extra_case.attack_unit(target.id)
	if not changed["value"]: printerr("BLOCKED ARMOR FAULT SCENARIO: reason=" + String(fault.reason) + " events=" + str(fault.get_events()))
	_check(changed["value"], "extra callback invoked")
	_check(fault.status == &"FAULTED", "extra callback faults hit")
	_check(target.vitals.get_hp() == before_hp, "extra fault keeps HP")
	_check(extra_case.context.get_rng().to_dict() == before_rng, "extra fault keeps RNG")
	_check(fault.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"armor_changed"), "extra fault keeps armor event")
	_check(not fault.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved"), "extra fault has no complete hit")
	if target.armor.changed.is_connected(mutate): target.armor.changed.disconnect(mutate)
	extra_case.close()

	var hp_case := _fixture()
	var hp_target := hp_case.units[1]
	var hp_mutate := func(_old: float, _new: float) -> void: hp_target.guard_stance = true
	hp_target.vitals.hp_changed.connect(hp_mutate)
	var hp_fault := hp_case.attack_unit(hp_target.id)
	_check(hp_fault.status == &"FAULTED", "HP callback faults after write")
	_check(not hp_fault.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved"), "HP fault has no complete hit")
	if hp_target.vitals.hp_changed.is_connected(hp_mutate): hp_target.vitals.hp_changed.disconnect(hp_mutate)
	hp_case.close()

func _test_voluntary_fall() -> void:
	var fall_case := _fixture()
	var actor := fall_case.units[0]
	var destination := Vector2i(3, 2)
	fall_case.board.set_height_steps(actor.cell, 4)
	fall_case.board.set_height_steps(destination, 0)
	var before := ItemSimulationSnapshot.capture(fall_case.state, []).snapshot.to_dict()
	var command := MoveCommand.new(actor.id, [actor.cell, destination], fall_case.context.get_revision())
	var receipt := fall_case._queue.submit(command, fall_case.context)
	_check(receipt.status == &"APPLIED", "voluntary fall applies")
	_check(actor.cell == destination, "voluntary fall reaches destination")
	_check(receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"moved"), "voluntary fall emits moved")
	_check(receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"armor_changed"), "voluntary fall emits armor change")
	_check(receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved"), "voluntary fall resolves hit")
	_check(ItemSimulationSnapshot.capture(fall_case.state, []).snapshot.to_dict() != before, "voluntary fall changes snapshot")
	fall_case.close()

func _armor(s: BattleArmorSession, unit: UnitState) -> int:
	return ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(unit.id)))["current"]

func _fill(s: BattleArmorSession, unit: UnitState, full: bool) -> void:
	for item: ItemInstance in s.state.get_owner(unit.id)._items.values():
		item.armor_remaining = item.get_definition().armor_max if full else 0

func _kinds(events: Array[Dictionary]) -> Array[StringName]:
	var result: Array[StringName] = []
	for event: Dictionary in events: result.append(event["kind"])
	return result

func _parity(s: BattleArmorSession, label: String) -> AttackForecast:
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var forecast := s.preview_attack(s.units[1].id)
	_check(forecast.status == &"APPLIED", label + " forecast " + String(forecast.reason))
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng, label + " all live unchanged")
	var repeated := s.preview_attack(s.units[1].id)
	_check(repeated.events == forecast.events and repeated.snapshot_after == forecast.snapshot_after, label + " repeated")
	var receipt := s.attack_unit(s.units[1].id)
	_check(receipt.status == forecast.status and receipt.reason == forecast.reason, label + " status")
	_check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, label + " receipt parity")
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	_check(capture.code == ItemSnapshotResult.Code.OK and capture.snapshot.to_dict() == forecast.snapshot_after, label + " snapshot parity")
	_check(s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, label + " RNG/counters parity")
	return forecast

func _test_real_hit_boundaries() -> void:
	for mode: String in ["armor_only", "below_half", "zero_guard", "net_zero", "net_heal", "lethal", "E_only", "single_item"]:
		var s := _fixture()
		var actor := s.units[0]
		var target := s.units[1]
		actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		if mode in ["armor_only", "zero_guard", "E_only", "single_item"]: _fill(s, target, true)
		if mode == "zero_guard":
			actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0)
			actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
			s.context._attack_rules._definitions[0].damage_components.clear()
			target.guard_stance = true
		if mode in ["net_zero", "net_heal", "lethal"]:
			_fill(s, target, false)
			target.vitals.set_hp(16.0 if mode != "lethal" else 1.0)
		if mode in ["net_zero", "net_heal"]:
			target.armor.natural["fire"] = 11000
			target.armor.perks = [{"id": "limit15", "type": "fire", "branch": "both", "bonus": 1500}, {"id": "limit20", "type": "fire", "branch": "both", "bonus": 2000}]
			s.context._attack_rules._definitions[0].damage_components[0]["numerator"] = 100 if mode == "net_zero" else 200
		if mode == "E_only":
			target.armor.next_grant_id = 2
			target.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 30, "expires": "battle", "battle_id": 1}]
		if mode == "single_item":
			for item: ItemInstance in s.state.get_owner(target.id)._items.values():
				if item.get_definition().armor_max == 40: item.armor_remaining = 0
		var rng_before := s.context.get_rng().to_dict()
		var f := _parity(s, mode)
		var kinds := _kinds(f.events)
		match mode:
			"armor_only": _check(_armor(s, target) == 80 and target.vitals.get_hp() == 32.0 and &"damaged" not in kinds and &"healed" not in kinds, "armor-only does not trigger heal")
			"below_half": _check(_armor(s, target) == 15 and target.vitals.get_hp() == 24.0 and &"healed" in kinds, "split 10armor 10HP then actual item heal2")
			"zero_guard": _check(_armor(s, target) == 100 and target.vitals.get_hp() == 32 and &"armor_changed" not in kinds and &"hit_resolved" in kinds, "guard1 floors0 no minimum")
			"net_zero", "net_heal":
				_check(target.vitals.get_hp() == (16.0 if mode == "net_zero" else 26.0), mode + " exact HP")
				_check(&"damaged" not in kinds and kinds.count(&"healed") == (0 if mode == "net_zero" else 1), mode + " net event only")
				for event: Dictionary in f.events:
					if event["kind"] == &"hit_resolved": _check(event["hit"]["total_damage"] == 10 and event["hit"]["rows"][0]["hp_damage"] == 10, "gross physical admission preserved before healing")
			"lethal": _check(not target.is_alive() and target.vitals.get_hp() == 0.0 and kinds.count(&"died") == 1 and s.board.occupant_at(target.cell) == null, "one death after net result")
			"E_only": _check(target.armor.grants[0]["remaining"] == 10 and _armor(s, target) == 110 and s.context.get_rng().to_dict() == rng_before, "E first protects items and RNG")
			"single_item": _check(_armor(s, target) == 40 and s.context.get_rng().to_dict() == rng_before, "single candidate no draws")
		s.close()

class NoCloneRng extends ActionRngPort:
	func to_dict() -> Dictionary: return {"seed": 7}

class OneDrawRng extends ActionRngPort:
	var draws: int = 0
	var limit: int = 1
	func next_int(_stream: StringName, _upper: int) -> int:
		if draws >= limit: return -1
		draws += 1
		return 0
	func to_dict() -> Dictionary: return {"draws": draws, "limit": limit}
	func from_dict(data: Dictionary) -> bool:
		draws = data["draws"]
		limit = data["limit"]
		return true
	func clone() -> ActionRngPort:
		var result := OneDrawRng.new()
		result.draws = draws
		result.limit = limit
		return result

func _test_rng_prefix_and_limits() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var target := s.units[1]
	_fill(s, target, true)
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	s.context._rng = NoCloneRng.new()
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var refusal := s.attack_unit(target.id)
	_check(refusal.status == &"REJECTED" and refusal.reason == &"armor/rng_not_cloneable", "missing clone explicitly rejects")
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before, "RNG refusal no debit or armor mutation")
	s.close()
	for fault_at: String in ["extra", "item", "replace", "defense"]:
		s = _fixture(); actor = s.units[0]; target = s.units[1]
		_fill(s, target, true)
		actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 200.0 if fault_at != "extra" else 20.0)
		actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		s.context._attack_rules._definitions[0].damage_components.clear()
		if fault_at == "extra":
			target.armor.next_grant_id = 2
			target.armor.grants = [{"grant_id": 1, "source": "test", "remaining": 5, "expires": "battle", "battle_id": 1}]
		var original := target.armor
		var callbacks: Array[int] = [0]
		var callback := func(kind: StringName, _id: int, _before: int, _after: int) -> void:
			if (fault_at == "extra" and kind != &"extra") or (fault_at != "extra" and kind != &"item"): return
			callbacks[0] += 1
			if fault_at == "replace": target.armor = ArmorState.from_dict(original.to_dict())
			elif fault_at == "defense": target.armor.natural["fire"] = 2500
			else: target.guard_stance = true
		original.changed.connect(callback)
		var rng_before := s.context.get_rng().to_dict()
		var receipt := s.attack_unit(target.id)
		_check(receipt.status == &"FAULTED" and callbacks[0] == 1, fault_at + " faults immediately")
		_check(target.vitals.get_hp() == 32 and &"hit_resolved" not in _kinds(receipt.get_events()), fault_at + " no HP or fictitious full hit")
		if fault_at == "extra":
			_check(original.grants[0]["remaining"] == 0 and _armor(s, target) == 100 and s.context.get_rng().to_dict() == rng_before, "E5 prefix before RNG and items")
		else:
			_check(s.context.get_rng().to_dict()["draws"] > rng_before["draws"] and _armor(s, target) == 40, fault_at + " RNG and first60item prefix retained")
		original.changed.disconnect(callback)
		s.close()
	for limit: String in ["commands", "events"]:
		s = _fixture(); target = s.units[1]
		s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		_fill(s, target, true)
		s._queue = ActionQueue.new(1 if limit == "commands" else 256, 1 if limit == "events" else 512, 32)
		var receipt := s.attack_unit(target.id)
		_check(receipt.status == &"FAULTED" and receipt.reason == (&"command_limit" if limit == "commands" else &"event_limit"), limit + " limit")
		_check(s.units[0].action_resources.get_main_left() == 0 and _armor(s, target) == (100 if limit == "commands" else 80), limit + " actual debit/armor prefix")
		s.close()

func _test_collision_fall() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var target := s.units[1]
	var blocker := s.units[3]
	s.board.move_unit(actor, Vector2i(2, 3))
	s.board.move_unit(target, Vector2i(3, 3))
	s.board.move_unit(blocker, Vector2i(4, 3))
	s.board.set_height_steps(actor.cell, 4)
	s.board.set_height_steps(target.cell, 4)
	s.board.set_height_steps(blocker.cell, 0)
	_fill(s, target, true); _fill(s, blocker, false)
	blocker.vitals.set_hp(10.0)
	var f := _parity(s, "collision then fall")
	_check(not blocker.is_alive() and target.cell == Vector2i(4, 3), "blocker dies then target enters")
	_check(_armor(s, target) == 54 and target.vitals.get_hp() == 32, "direct20 collision10 fall16 use successive armor")
	var hits: Array[Dictionary] = []
	for event: Dictionary in f.events:
		if event["kind"] == &"hit_resolved": hits.append(event)
	_check(hits.size() == 4, "direct target blocker fall four distinct hits")
	if hits.size() == 4:
		_check(hits[0]["hit"]["armor_spent"] == 20 and hits[1]["hit"]["armor_spent"] == 10 and hits[2]["hit"]["hp_after"] == 0 and hits[3]["hit"]["armor_spent"] == 16, "ordered per-hit explanation")
	s.close()

func _test_last_enemy_expiry() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var target := s.units[1]
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
	_fill(s,target,false)
	target.vitals.set_hp(1.0)
	actor.armor.next_grant_id = 3
	actor.armor.grants = [{"grant_id":1,"source":"spell","remaining":10,"expires":"battle","battle_id":1},{"grant_id":2,"source":"perk","remaining":5,"expires":"persistent","battle_id":1}]
	for enemy: UnitState in s.units:
		if enemy.faction == Faction.Type.ENEMY and enemy != target:
			s._queue.submit(DeathCommand.new(enemy.id,DamageSource.new(&"test",0,enemy.cell)),s.context)
	var forecast := _parity(s,"last enemy expiry")
	_check(not actor.armor.in_battle and actor.armor.grants.size() == 1 and actor.armor.grants[0]["remaining"] == 5,"expiry preserves persistent grant")
	_check(s.phase == BattleTacticalSession.Phase.VICTORY and forecast.counters_after == s.context.simulation_counters(),"terminal cleanup belongs to real forecast queue")
	s.close()

func _test_decimal_collision() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var target := s.units[1]
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 0.1)
	actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.2)
	s.board.set_terrain(target.cell + Vector2i.RIGHT, TerrainType.Type.WALL)
	var result := _parity(s, "exact decimal collision")
	var hits: Array[Dictionary] = []
	for event: Dictionary in result.events:
		if event["kind"] == &"hit_resolved": hits.append(event)
	_check(hits.size() == 2 and hits[1]["hit"]["armor_spent"] == 0, "decimal collision accepts exact0.3 and floors once")
	var summon := UseSummoningItemCommand.new(actor.id, 0, actor.cell + Vector2i.UP, s.context.get_revision())
	_check(summon.validate(s.context) == &"item/not_owned", "unowned seal still refuses before cost or creation with armor")
	s.close()

func _test_expiry_rng_fault() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var target := s.units[1]
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	_fill(s, target, false)
	target.vitals.set_hp(1.0)
	actor.armor.next_grant_id = 2
	actor.armor.grants = [{"grant_id":1,"source":"spell","remaining":10,"expires":"battle","battle_id":1}]
	for enemy: UnitState in s.units:
		if enemy.faction == Faction.Type.ENEMY and enemy != target:
			s._queue.submit(DeathCommand.new(enemy.id,DamageSource.new(&"test",0,enemy.cell)),s.context)
	var tamper := func(_kind: StringName, _id: int, _before: int, _after: int) -> void:
		s.context.get_rng().next_int(&"combat", 2)
	actor.armor.changed.connect(tamper)
	var receipt := s.attack_unit(target.id)
	_check(receipt.status == &"FAULTED" and receipt.reason == &"armor/invalid_expiry", "expiry catches RNG callback mutation: " + String(receipt.status) + "/" + String(receipt.reason))
	_check(not actor.armor.in_battle and actor.armor.grants.is_empty(), "expiry fault retains actual removal prefix")
	actor.armor.changed.disconnect(tamper)
	s.close()

func _test_sequential_move_admission() -> void:
	for mode: String in ["second_draw", "after_extra", "after_healing", "success"]:
		var s := _fixture()
		var actor := s.units[0]
		var path: Array[Vector2i] = [actor.cell, actor.cell + Vector2i.UP, actor.cell + Vector2i.UP * 2]
		s.board.set_height_steps(path[0], 8)
		s.board.set_height_steps(path[1], 4)
		s.board.set_height_steps(path[2], 0)
		if mode == "after_healing":
			path.append(actor.cell + Vector2i.UP * 3)
			for index: int in path.size(): s.board.set_height_steps(path[index], 12 - index * 4)
			var rng := OneDrawRng.new()
			rng.limit = 2
			s.context._rng = rng
			for item: ItemInstance in s.state.get_owner(actor.id)._items.values():
				if item.get_definition().armor_max > 0: item.armor_remaining = item.get_definition().armor_max / 4
			actor.vitals.set_hp(16.0)
			var definition := ItemDef.new()
			definition.id = &"fall_healer"
			var effect := HealOnDamageEffect.new()
			effect.heal_amount = 4.0
			definition.effects.append(effect)
			s.state.get_inventory(actor.id).add_item(s.state.get_owner(actor.id).create_item(definition))
		elif mode == "second_draw": s.context._rng = OneDrawRng.new()
		else:
			actor.armor.next_grant_id = 2
			actor.armor.grants = [{"grant_id":1,"source":"spell","remaining":16,"expires":"battle","battle_id":1}]
			if mode == "after_extra": s.context._rng = NoCloneRng.new()
		var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
		var rng_before := s.context.get_rng().to_dict()
		var counters_before := s.context.simulation_counters()
		var receipt := s._queue.submit(MoveCommand.new(actor.id, path, s.context.get_revision()), s.context)
		if mode == "success":
			_check(receipt.status == &"APPLIED" and actor.cell == path[2] and _armor(s,actor) == 84 and actor.armor.grants[0]["remaining"] == 0, "sequential falls propagate E then items")
			_check(s.context.get_rng().to_dict()["draws"] == rng_before["draws"] + 1 and actor.vitals.get_hp() == 32, "sequential falls draw only after E")
		else:
			_check(receipt.status == &"REJECTED" and receipt.reason == (&"armor/rng_failure" if mode in ["second_draw", "after_healing"] else &"armor/rng_not_cloneable"), mode + " root rejects later fall failure: " + String(receipt.reason))
			_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.get_rng().to_dict() == rng_before and s.context.simulation_counters() == counters_before, mode + " refuses before movement or debit")
		s.close()
