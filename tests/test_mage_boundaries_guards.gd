extends SceneTree
var passed: int = 0
var failed: int = 0
class BoundarySink extends ActionEventSink:
	var session: BattleCoreReactionsSession
	var observed: bool = false
	var closed: bool = true
	var corrupt: bool = false
	func publish(_event: Dictionary) -> void:
		if session == null: return
		observed = true
		closed = closed and session._transitioning and not session.state.abilities.mage_allowed
		if corrupt: session.state.abilities.mana -= 1; corrupt = false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL MAGE GUARDS: " + label)
func player() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s._enemy_index = s._enemy_ids.size(); s.step_enemy()
	return s
func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	return result.snapshot.to_dict() if result.snapshot != null else {}
func bare(s: BattleCoreReactionsSession, u: UnitState) -> void:
	u.armor.natural = {"physical": 0, "fire": 0}
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = 0
func run() -> void:
	var s := player()
	var target := s.units[1]
	bare(s, target)
	var fired := s.cast_mage_spell(&"mage.fire", target.id)
	check(fired.status == ActionReceipt.APPLIED, "cast before end")
	var sink := BoundarySink.new(); sink.session = s; s.context._sink = sink
	check(s.end_player_turn() and sink.observed and sink.closed, "entire outgoing boundary including environment closes window")
	check(s.state.abilities.remaining(&"mage.fire") == 2 and not s.state.abilities.ledger[0].skip_current_end, "cast end retains two full future turns")
	sink.session = null; s.close()
	s = player(); target = s.units[1]; bare(s, target)
	var ability := s.state.abilities
	var callback := func(_old: float, _new: float) -> void: ability.mana -= 1
	target.vitals.hp_changed.connect(callback)
	var actor := s.units[0]
	actor.control.stunned_turns = 0
	s.board.move_unit(target, Vector2i(1, 2))
	var hit := s._submit(AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision()))
	check(hit.status == ActionReceipt.FAULTED and ability.mana == 5, "old hero attack detects direct mage mutation without revision")
	target.vitals.hp_changed.disconnect(callback); s.close()
	s = player(); target = s.units[1]; bare(s, target)
	ability = s.state.abilities
	var original := ability.definition(&"mage.fire")
	var replace_definition := func(_old: float, _new: float) -> void:
		for i: int in ability.catalog.size():
			if ability.catalog[i] == original: ability.catalog[i] = original.copy()
	target.vitals.hp_changed.connect(replace_definition)
	check(s.cast_mage_spell(&"mage.fire", target.id).status == ActionReceipt.FAULTED, "equal-value descriptor identity swap faults after payment")
	target.vitals.hp_changed.disconnect(replace_definition); s.close()
	s = player(); sink = BoundarySink.new(); sink.session = s; sink.corrupt = true; s.context._sink = sink
	var serial := s.state.abilities.serials.duplicate()
	check(not s.end_player_turn() and s.phase == BattleTacticalSession.Phase.FAULTED, "callback mutation stops transition")
	check(s.state.abilities.stage == "closing" and s.state.abilities.serials == serial and not s.state.abilities.mage_allowed, "failed control root has no later tick/refill/open")
	check(not s.end_player_turn() and s.state.abilities.serials == serial, "retry cannot process end twice")
	sink.session = null; s.close()
	for modifier: int in [0, 1, 2, 3]:
		s = player(); target = s.units[1]; bare(s, target)
		target.vitals.set_hp(12.0)
		target.guard_stance = modifier == 1
		if modifier == 2: target.elemental.frozen_turns = 1
		if modifier == 3:
			target.armor.natural["fire"] = 20000
			target.armor.perks.append({"id": "heal_fire", "type": "fire", "branch": "natural", "bonus": 15000})
		var preview := ForecastSimulation.run_prepared(s.prepare_mage_forecast(&"mage.fire", target.id))
		var receipt := s.cast_mage_spell(&"mage.fire", target.id)
		check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and snapshot(s) == preview.snapshot_after, "armor/guard/freeze/healing fire parity %d" % modifier)
		check(s.state.abilities.mana == 4 and s.state.abilities.remaining(&"mage.fire") == 2, "zero/healing/critical hit pays same price %d" % modifier)
		if modifier == 2: check(not target.is_alive() and s.state.environment.corpses_at(target.cell).size() == 1, "frozen critical shatters and creates body")
		if modifier == 3: check(target.vitals.get_hp() > 12.0, "over100 fire resistance heals through shared formula")
		s.close()
	s = player(); target = s.units[1]
	s.selected_id = 0
	var before := snapshot(s)
	check(s.cast_mage_spell(&"mage.heal", target.id).status == ActionReceipt.REJECTED and snapshot(s) == before, "wrong team rejected without selected hero or payment")
	s.state.abilities.mana = 1; before = snapshot(s)
	check(s.cast_mage_spell(&"mage.fire", target.id).status == ActionReceipt.REJECTED and snapshot(s) == before, "insufficient mana preserves state")
	s.close()
	s = player()
	var ids_before := s.context.simulation_counters()
	for i: int in range(s.state.abilities.catalog.size() - 1, -1, -1):
		if s.state.abilities.catalog[i].ability_id == &"guard:default": s.state.abilities.catalog.remove_at(i)
	s.units[0].control.stunned_turns = 0
	check(s.guard_selected().status == ActionReceipt.REJECTED and s.context.simulation_counters() == ids_before, "old action requires registry entry rather than inventing zero")
	s.close()
	s = player(); s.units[0].control.stunned_turns = 0
	s.selected_id = s.units[0].id
	var cells := s.summoning_cells()
	check(not cells.is_empty(), "helper placement available")
	var summon := s.use_summoning_item(cells[0])
	var helper := s.state.active_summon(s.units[0].id)
	check(summon.status == ActionReceipt.APPLIED and helper != null and snapshot(s).schema_version == ItemSimulationSnapshot.SCHEMA_VERSION, "summon projection supports current schema")
	if helper != null:
		helper.vitals.apply_damage(2.0)
		var mana_before := s.state.abilities.mana
		check(s.cast_mage_spell(&"mage.heal", helper.id).status == ActionReceipt.REJECTED and s.state.abilities.mana == mana_before, "pending helper cannot be mage target")
		s.end_player_turn(); s._enemy_index = s._enemy_ids.size(); s.step_enemy()
		check(not s.state.is_summon_pending(helper.id), "helper enters on next player refill")
		var preview := ForecastSimulation.run_prepared(s.prepare_mage_forecast(&"mage.heal", helper.id))
		var healed := s.cast_mage_spell(&"mage.heal", helper.id)
		check(healed.status == ActionReceipt.APPLIED and healed.get_events() == preview.events and snapshot(s) == preview.snapshot_after, "active helper receives capped mage heal with full preview parity")
	s.close()
	var source := DamageSource.new(&"mage", 1, Vector2i(-1, -1), 0, 0)
	s = player()
	check(source.validate(s.context) == &"", "mage source without fictitious UnitId")
	source.instigator_unit_id = s.units[0].id
	check(source.validate(s.context) != &"", "mage source forbids hero attribution")
	s.close()
	print("MAGE GUARDS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
