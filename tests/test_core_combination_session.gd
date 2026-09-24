extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL K2 SESSION: " + label)

func _run() -> void:
	_start_and_restore()
	_attacks()
	_stacked_bleeding()
	_rejections_and_helper()
	_team_boundaries()
	_lethal_boundary(Faction.Type.ENEMY)
	_lethal_boundary(Faction.Type.PLAYER)
	_faults()
	print("CORE COMBINATION SESSION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _snapshot(s: BattleCoreCombinationSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "capture: " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func _seed_bleeding(unit: UnitState, source: UnitState) -> void:
	unit.bleeding.ticks_left = 2
	unit.bleeding.source = DamageSource.new(&"attack", 0, source.cell, source.id, source.id).to_dict()
	unit.bleeding.hit_id = "k2-start"

func _events(events: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event.get("kind") == kind)

func _start_and_restore() -> void:
	var s := BattleCoreCombinationSession.new()
	var positions: Array[Vector2i] = [Vector2i(0, 2), Vector2i(5, 1), Vector2i(4, 3), Vector2i(3, 3), Vector2i(5, 5), Vector2i(5, 4)]
	for i: int in 6:
		check(s.units[i].cell == positions[i] and s.units[i].control != null, "authored placement/control %d" % i)
	check(s.units.size() == 7 and not s.units[6].is_alive() and s.units[6].control == null, "original D5 body has no control")
	check(s.state.environment.corpses_at(Vector2i(0, 3)).size() == 1 and s.state.environment.fires.size() == 2 and not s.state.environment.fire_at(Vector2i(2, 3)).is_empty(), "body and spike geometry")
	check(s.units[1].control.stunned_turns == 1 and s.units[4].control.stunned_turns == 1 and s.units[3].control.entangled_turns == 1 and s.units[3].bleeding.immune, "authored durations and D3 immunity")
	var bor := s.units[2]
	var sword := s.state.get_equipment(bor.id).get_equipped(EquipmentState.EquipSlot.WEAPON)
	check(sword != null and sword.get_definition_id() == &"d4_piercing_sword" and sword.is_active(), "K7 Bor has one active catalog blade")
	check(bor.stats.get_base_value(StatTypes.StatType.WEAPON_DAMAGE) == 0.0 and bor.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4.0 and bor.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0, "K7 preserves damage and adds 50 percent piercing")
	check(s.state.get_equipment(bor.id).get_occupied_slots().count(EquipmentState.EquipSlot.WEAPON) == 1, "K7 weapon slot has one item")
	for i: int in s.units.size():
		if i == 2 or not s.units[i].is_alive(): continue
		check(s.units[i].get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4.0 and s.units[i].get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 0.0, "K7 other unit baseline %d" % i)
	for id: StringName in [&"demo_strike", &"blood_rune"]:
		var definition := s.context.get_attack_rules().get_definition(id)
		check(definition.backstab_bonus_percent == 50 and definition.critical_on_control and definition.bleeding_policy == (&"physical_hp" if id == &"demo_strike" else &"bypass_hp_gate"), "C1 data keeps D3 policy " + String(id))
	check(s.context.get_attack_rules().validate() == &"", "combined definitions valid")
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	var original := capture.snapshot.to_dict()
	var decoded := ItemSimulationSnapshot.from_dict(original)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_bytes() == capture.snapshot.canonical_bytes(), "canonical mixed-capability decode")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null, "restore with copied catalogue")
	if restored.state != null:
		check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == original, "restore no refill or mutation")
		var restored_bor := restored.state.get_board().get_unit_by_id(bor.id)
		var restored_sword := restored.state.get_equipment(bor.id).get_equipped(EquipmentState.EquipSlot.WEAPON)
		check(restored_sword != null and restored_sword.is_active() and restored_sword.get_definition_id() == &"d4_piercing_sword" and restored_bor.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4.0 and restored_bor.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0, "K7 canonical restore equips once with effective stats")
		var target := restored.state.get_board().get_unit_by_id(s.units[3].id)
		target.control.entangled_turns = 0
		target.bleeding.immune = false
		restored.state.environment.ignite(Vector2i(0, 0))
		target.action_resources.try_spend_main(1)
		for item: ItemInstance in restored.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
		check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() != original and _snapshot(s) == original and capture.snapshot.to_dict() == original, "restore isolates control bleeding environment items and resources")
		AttackForecast._close(restored.state)
	var copy := s.context.get_attack_rules().copy()
	copy._definitions[0].critical_on_control = false
	copy._definitions[0].damage_components[0]["numerator"] = 999
	check(s.context.get_attack_rules().get_definition(&"demo_strike").critical_on_control and s.context.get_attack_rules().get_definition(&"demo_strike").damage_components[0]["numerator"] == 10, "attack catalogue copies isolated")
	var second := BattleCoreCombinationSession.new()
	var other_sword := second.state.get_equipment(second.units[2].id).get_equipped(EquipmentState.EquipSlot.WEAPON)
	var original_effect := (sword.get_definition().effects[0] as StatModifierEffect).value
	var other_effect := (other_sword.get_definition().effects[0] as StatModifierEffect).value
	(other_sword.get_definition().effects[0] as StatModifierEffect).value = 25.0
	check(other_sword.get_definition() != sword.get_definition() and (sword.get_definition().effects[0] as StatModifierEffect).value == original_effect and s.units[2].get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0 and other_effect == 50.0, "K7 session nested catalog mutation isolated from source and active stats")
	var definition_count := s.state.get_owner(bor.id).get_item_count(&"d4_piercing_sword", ItemOwnerState.EQUIPMENT_BASE + int(EquipmentState.EquipSlot.WEAPON))
	s.reset()
	var reset_sword := s.state.get_equipment(s.units[2].id).get_equipped(EquipmentState.EquipSlot.WEAPON)
	check(definition_count == 1 and reset_sword != null and s.units[2].get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4.0 and s.units[2].get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0 and s.state.get_owner(s.units[2].id).get_item_count(&"d4_piercing_sword", ItemOwnerState.EQUIPMENT_BASE + int(EquipmentState.EquipSlot.WEAPON)) == 1, "K7 reset does not stack weapon effects")
	second.close()
	s.close()

func _parity(s: BattleCoreCombinationSession, target: UnitState, label: String) -> ActionReceipt:
	var before := _snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var revision := s.context.get_revision()
	var ids := UnitId.get_counter()
	var first := s.preview_attack(target.id)
	var second := s.preview_attack(target.id)
	check(first.status == ActionReceipt.APPLIED and second.status == ActionReceipt.APPLIED, label + " two previews apply")
	check(first.events == second.events and first.steps == second.steps and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after, label + " repeated prediction deterministic")
	check(_snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and s.context.get_revision() == revision and UnitId.get_counter() == ids, label + " preview isolates live/resources/RNG/IDs")
	var actor := s.selected_unit()
	var main := actor.action_resources.get_main_left()
	var receipt := s.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == first.events and receipt.get_steps() == first.steps, label + " live events/steps match")
	check(_snapshot(s) == first.snapshot_after and s.context.get_rng().to_dict() == first.rng_after and s.context.simulation_counters() == first.counters_after, label + " live snapshot/RNG/counters match")
	check(actor.action_resources.get_main_left() == main - 1, label + " costs one main")
	return receipt

func _attacks() -> void:
	for mode: String in ["ordinary", "rune", "piercing_bleed", "blocked", "direct_death", "spike_death"]:
		var s := BattleCoreCombinationSession.new()
		var target := s.units[3]
		check(s.select_unit(s.units[2].id), mode + " select Bor")
		if mode in ["rune", "piercing_bleed"]:
			target.bleeding.immune = false
			if mode == "rune": s.rune_selected = true
		if mode == "blocked": check(s.board.move_unit(s.units[5], Vector2i(2, 3)), "blocker placed through board")
		if mode in ["direct_death", "spike_death"]:
			for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
			if mode == "spike_death":
				target.stats.set_base_value(StatTypes.StatType.HP_MAX, 64)
				target.vitals.set_hp(54)
		var receipt := _parity(s, target, mode)
		var events := receipt.get_events()
		var attacks := _events(events, &"attacked")
		check(attacks.size() == 1 and attacks[0]["modifiers"] == {"backstab_percent": 50, "critical": true}, mode + " actual backstab/critical")
		if mode == "blocked":
			check(target.cell == Vector2i(3, 3) and target.control.entangled_turns == 1 and _events(events, &"control_changed").is_empty(), "block preserves root")
		elif mode == "direct_death":
			check(not target.is_alive() and target.cell == Vector2i(3, 3) and _events(events, &"moved").is_empty() and _events(events, &"bleeding_changed").is_empty(), "direct death stops spatial/status continuation")
		else:
			check(target.cell == Vector2i(2, 3) and target.control.entangled_turns == 0, mode + " push to spikes clears root")
		if mode.ends_with("death"):
			check(not target.is_alive() and not s.board.is_occupied(target.cell) and _events(events, &"died").size() == 1 and _events(events, &"corpse_created").size() == 1 and s.state.environment.corpses_at(target.cell).size() == 1, mode + " single death/body")
		elif mode == "rune": check(target.bleeding.ticks_left == 2, "rune applies through armour after root/spikes")
		elif mode == "piercing_bleed": check(target.bleeding.ticks_left == 2, "K7 piercing physical HP damage opens bleeding gate after spike push")
		else: check(target.bleeding.ticks_left == 0, mode + " immunity preserved")
		s.close()

func _stacked_bleeding() -> void:
	var s := BattleCoreCombinationSession.new()
	var actor := s.units[2]
	var target := s.units[3]
	check(s.select_unit(actor.id),"stack select Bor")
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
	target.bleeding.immune = false
	target.stats.set_base_value(StatTypes.StatType.HP_MAX,256.0)
	target.vitals.set_hp(256.0)
	target.armor.natural["physical"] = 0
	s.rune_selected = true
	_parity(s,target,"K2 first bleeding")
	actor.try_refill_turn_resources()
	_parity(s,target,"K2 repeated bleeding")
	check(target.bleeding.ticks_left == 4,"K2 repeat stacks duration to four")
	var hp := target.vitals.get_hp()
	var rng := s.context.get_rng().to_dict()
	check(s.end_player_turn() and target.bleeding.ticks_left == 3 and target.vitals.get_hp() == hp - 4,"K2 team boundary consumes one tick with fixed damage")
	check(s.context.get_rng().to_dict() == rng,"K2 stacked tick uses no RNG")
	s.close()

func _rejections_and_helper() -> void:
	var s := BattleCoreCombinationSession.new()
	var stunned := s.units[4]
	s.select_unit(stunned.id)
	var before := _snapshot(s)
	var revision := s.context.get_revision()
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var denied := s.attack_unit(s.units[5].id)
	check(denied.status == ActionReceipt.REJECTED and denied.reason == &"control/stunned", "stunned attack rejected")
	check(s.guard_selected().reason == &"control/stunned" and s.use_healing_item().reason == &"control/stunned", "stunned guard/item rejected")
	check(_snapshot(s) == before and s.context.get_revision() == revision and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "rejections preserve all resources and counters")
	var bor := s.units[2]
	s.select_unit(bor.id)
	var target := s.units[3]
	bor.action_resources.try_spend_main(1)
	before = _snapshot(s)
	revision = s.context.get_revision()
	rng = s.context.get_rng().to_dict()
	counters = s.context.simulation_counters()
	check(s.attack_unit(target.id).reason == &"attack/insufficient_main" and _snapshot(s) == before and s.context.get_revision() == revision and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "armed Bor rejects insufficient main without mutation")
	bor.try_refill_turn_resources()
	bor.control.stunned_turns = 1
	before = _snapshot(s)
	check(s.attack_unit(target.id).reason == &"control/stunned" and _snapshot(s) == before and bor.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0, "armed Bor stun rejects without mutation")
	var actor := s.units[0]
	s.select_unit(actor.id)
	actor.control.stunned_turns = 1
	before = _snapshot(s)
	check(s.raise_corpse(Vector2i(0, 3)).reason == &"control/stunned" and _snapshot(s) == before, "stunned raise consumes neither corpse nor main")
	actor.control.stunned_turns = 0
	check(s.raise_corpse(Vector2i(0, 3)).status == ActionReceipt.APPLIED, "raise through production session")
	var helper := s.state.active_summon(actor.id)
	check(helper != null, "helper registered")
	if helper != null:
		check(helper.control == null and helper.armor != null and helper.bleeding != null and helper.vitals.get_hp() == 16 and helper.action_resources.get_main_left() == 0 and helper.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 0.0 and s.state.is_summon_pending(helper.id), "D5/M1 default, no K7 piercing and pending resources")
		before = _snapshot(s)
		s.select_unit(helper.id)
		check(s.move_to(Vector2i(0, 4)).status == ActionReceipt.REJECTED and _snapshot(s) == before, "pending helper has no early action")
		s.select_unit(actor.id)
		check(s.end_player_turn(), "helper waits enemy turn")
		for _i: int in 40:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			s.step_enemy()
		check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and not s.state.is_summon_pending(helper.id) and helper.action_resources.get_main_left() == 1, "first team refill admits helper once")
		s.select_unit(helper.id)
		check(s.move_to(Vector2i(0, 4)).status == ActionReceipt.APPLIED, "default helper acts with nullable control")
		before = _snapshot(s)
		s.select_unit(actor.id); s.select_unit(helper.id)
		check(_snapshot(s) == before, "selection never refills helper")
	s.reset()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.round_number == 1 and s.state.environment.corpses.size() == 1 and s.units.size() == 7 and s.units[4].control.stunned_turns == 1 and not s.rune_selected and s.turn_events.is_empty(), "reset restores scenario and drops helper")
	s.close()

func _team_boundaries() -> void:
	var s := BattleCoreCombinationSession.new()
	var ally := s.units[4]
	var target := s.units[3]
	s.units[5].control.stunned_turns = 1
	_seed_bleeding(target, s.units[2])
	_seed_bleeding(ally, target)
	ally.action_resources.try_spend_main(1)
	target.action_resources.try_spend_main(1)
	var before := _snapshot(s)
	s.select_unit(ally.id); s.select_unit(s.units[2].id)
	check(_snapshot(s) == before, "selection preserves status and spent actions")
	var observations: Array[Dictionary] = []
	var observe := func(_old: float, _new: float) -> void: observations.append({"stun": ally.control.stunned_turns, "main": target.action_resources.get_main_left()})
	target.vitals.hp_changed.connect(observe)
	var root: int = s.context.simulation_counters()["next_root_id"]
	check(s.end_player_turn(), "end player turn")
	target.vitals.hp_changed.disconnect(observe)
	check(observations == [{"stun": 0, "main": 0}] and target.bleeding.ticks_left == 1 and ally.bleeding.ticks_left == 2, "player expiry then enemy bleeding before refill")
	check(int(s.context.simulation_counters()["next_root_id"]) == root + 3 and target.action_resources.get_main_left() == 1 and ally.action_resources.get_main_left() == 0, "exactly three boundary roots; incoming-only refill")
	var player_observations: Array[Dictionary] = []
	var player_observe := func(_old: float, _new: float) -> void: player_observations.append({"root": target.control.entangled_turns, "main": ally.action_resources.get_main_left()})
	ally.vitals.hp_changed.connect(player_observe)
	var receipts: int = 0
	var attacks: Array[Dictionary] = []
	for _i: int in 40:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		var receipt := s.step_enemy()
		if receipt == null: continue
		receipts += 1
		check(receipt.status == ActionReceipt.APPLIED, "AI admitted " + String(receipt.reason))
		attacks.append_array(_events(receipt.get_events(), &"attacked"))
	ally.vitals.hp_changed.disconnect(player_observe)
	check(receipts == 1 and attacks.size() == 1 and attacks[0]["actor_unit_id"] == target.id, "real BT skips stunned enemies; rooted adjacent enemy attacks")
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.round_number == 2 and player_observations == [{"root": 0, "main": 0}], "enemy expiry then player tick before refill")
	check(ally.bleeding.ticks_left == 1 and target.bleeding.ticks_left == 1 and ally.action_resources.get_main_left() == 1 and target.action_resources.get_main_left() == 0, "one tick/refill per incoming team and paid AI")
	check(int(s.context.simulation_counters()["next_root_id"]) == root + 6 + receipts, "no duplicate transition roots")
	check(_events(s.turn_events, &"control_changed").size() == 4 and _events(s.turn_events, &"bleeding_changed").size() == 2, "each initial control expires and each incoming status ticks once")
	s.close()

func _lethal_boundary(incoming: Faction.Type) -> void:
	var s := BattleCoreCombinationSession.new()
	var target := s.units[3] if incoming == Faction.Type.ENEMY else s.units[4]
	var source := s.units[0] if incoming == Faction.Type.ENEMY else s.units[3]
	for unit: UnitState in s.units:
		if unit.is_alive() and unit.faction == incoming and unit != target:
			check(s._submit(DeathCommand.new(unit.id, DamageSource.new(&"test", 0, unit.cell))).status == ActionReceipt.APPLIED, "remove other incoming unit")
	target.vitals.set_hp(4)
	_seed_bleeding(target, source)
	target.action_resources.try_spend_main(1)
	if incoming == Faction.Type.PLAYER:
		check(s.end_player_turn(), "enter enemy turn for lethal player boundary")
		# Противники оглушены, чтобы проверить именно реальный переход после их WAIT.
		for id: int in s.living_ids(Faction.Type.ENEMY): s.board.get_unit_by_id(id).control.stunned_turns = 1
	var root: int = s.context.simulation_counters()["next_root_id"]
	if incoming == Faction.Type.ENEMY: check(not s.end_player_turn(), "lethal enemy tick prevents phase change")
	else:
		for _i: int in 20:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			s.step_enemy()
	var expected := BattleTacticalSession.Phase.VICTORY if incoming == Faction.Type.ENEMY else BattleTacticalSession.Phase.DEFEAT
	check(s.phase == expected and not target.is_alive() and target.action_resources.get_main_left() == 0 and s.round_number == 1, "lethal tick stops before refill/next round")
	check(int(s.context.simulation_counters()["next_root_id"]) == root + 2 and s.state.environment.corpses_at(target.cell).size() == 1 and not s.board.is_occupied(target.cell), "expiry/tick only, one corpse")
	var before := _snapshot(s)
	check(not s.end_player_turn() and s.step_enemy() == null and _snapshot(s) == before, "terminal cannot transition again")
	s.close()

func _faults() -> void:
	var s := BattleCoreCombinationSession.new()
	var target := s.units[3]
	s.select_unit(s.units[2].id)
	var mutate := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == target: target.control.stunned_turns = 1
	s.board.unit_position_changed.connect(mutate)
	var receipt := s.attack_unit(target.id)
	s.board.unit_position_changed.disconnect(mutate)
	check(receipt.status == ActionReceipt.FAULTED and s.phase == BattleTacticalSession.Phase.FAULTED and s.context.is_faulted(), "callback fault reaches session")
	check(target.cell == Vector2i(2, 3) and target.control.entangled_turns == 1 and s.units[2].action_resources.get_main_left() == 0 and _events(receipt.get_events(), &"moved").size() == 1 and _events(receipt.get_events(), &"control_changed").is_empty(), "fault retains paid/direct hit/move prefix before root removal")
	var before := _snapshot(s)
	var counters := s.context.simulation_counters()
	check(not s.end_player_turn() and s.step_enemy() == null and _snapshot(s) == before and s.context.simulation_counters() == counters, "FAULTED prevents boundary")
	s.close()
	s = BattleCoreCombinationSession.new()
	var armed_actor := s.units[2]
	target = s.units[3]
	s.select_unit(armed_actor.id)
	var before_hp := target.vitals.get_hp()
	var mutate_piercing := func(_kind: StringName, _id: int, _before_value: int, _after_value: int) -> void:
		armed_actor.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 25.0)
	target.armor.changed.connect(mutate_piercing)
	var piercing_receipt := s.attack_unit(target.id)
	target.armor.changed.disconnect(mutate_piercing)
	check(piercing_receipt.status == ActionReceipt.FAULTED and s.phase == BattleTacticalSession.Phase.FAULTED, "K7 callback piercing mutation faults attack")
	check(armed_actor.action_resources.get_main_left() == 0 and target.vitals.get_hp() == before_hp and _events(piercing_receipt.get_events(), &"hit_resolved").is_empty(), "K7 fault keeps spent main and armor prefix before hit")
	s.close()
	s = BattleCoreCombinationSession.new()
	s.units[0].control.stunned_turns = 1
	_seed_bleeding(s.units[3], s.units[2])
	s.units[3].action_resources.try_spend_main(1)
	s._queue = ActionQueue.new(2)
	var root: int = s.context.simulation_counters()["next_root_id"]
	check(not s.end_player_turn() and s.phase == BattleTacticalSession.Phase.FAULTED, "fault during control expiry stops boundary")
	check(s.units[0].control.stunned_turns == 0 and s.units[4].control.stunned_turns == 1 and s.units[3].bleeding.ticks_left == 2 and s.units[3].action_resources.get_main_left() == 0 and int(s.context.simulation_counters()["next_root_id"]) == root + 1, "control fault keeps prefix without bleeding/refill")
	s.close()
	s = BattleCoreCombinationSession.new()
	target = s.units[3]
	_seed_bleeding(target, s.units[2])
	target.action_resources.try_spend_main(1)
	var hp_callback := func(_old: float, _new: float) -> void: target.control.stunned_turns = 1
	target.vitals.hp_changed.connect(hp_callback)
	root = s.context.simulation_counters()["next_root_id"]
	check(not s.end_player_turn() and s.phase == BattleTacticalSession.Phase.FAULTED, "callback fault during bleeding stops boundary")
	target.vitals.hp_changed.disconnect(hp_callback)
	check(s.units[4].control.stunned_turns == 0 and target.bleeding.ticks_left == 1 and target.vitals.get_hp() == 28 and target.action_resources.get_main_left() == 0 and int(s.context.simulation_counters()["next_root_id"]) == root + 2, "tick fault keeps expiry/tick/HP prefix without refill")
	s.close()
