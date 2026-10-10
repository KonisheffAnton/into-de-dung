extends "res://tests/test_counterattack.gd"

func run() -> void:
	codec_and_readiness()
	print("PASSIVE OPPORTUNIST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func codec_and_readiness() -> void:
	var old := {"schema_version": 1, "definition": {"sneak_attack": false, "tank_reactions": false}, "mode": 0, "cover_target_id": 0, "reaction_left": 0, "movement_stopped": false}
	check(not CombatPerksState.valid(old), "old minimal perk schema is refused")
	var empty := CombatPerksState.new().to_dict()
	check(empty.schema_version == 7 and empty.definition.size() == 8 and CombatPerksState.from_dict(empty).to_dict() == empty, "current all-false definition roundtrips")
	var old_runtime := CombatPerksState.new()
	old_runtime.uses_bonus_actions = true
	old_runtime.definition.counterattack = true
	var packed_counter := old_runtime.to_dict()
	var restored_counter := CombatPerksState.from_dict(packed_counter)
	check(packed_counter.schema_version == 7 and packed_counter.reaction_left == 0 and packed_counter.definition.size() == 8 and restored_counter != null and restored_counter.to_dict() == packed_counter, "current bonus mode preserves all flags and zero legacy reserve")
	var state := CombatPerksState.new()
	state.uses_bonus_actions = true
	state.definition.passive_opportunist = true
	state.mode = CombatPerksState.Mode.OPPORTUNIST
	var packed := state.to_dict()
	check(packed.schema_version == 7 and packed.reaction_left == 0 and CombatPerksState.valid(packed), "passive perk uses schema seven")
	var restored := CombatPerksState.from_dict(packed)
	check(restored != null and restored.copy().definition.passive_opportunist, "schema seven roundtrip and copy")
	var false_flag := packed.duplicate(true)
	false_flag.definition.passive_opportunist = false
	check(not CombatPerksState.valid(false_flag), "opportunist mode requires the passive flag")
	var mixed_reserve := packed.duplicate(true)
	mixed_reserve.reaction_left = 1
	check(not CombatPerksState.valid(mixed_reserve), "bonus mode requires zero legacy reserve")
	var wrong_type := packed.duplicate(true)
	wrong_type.definition.passive_opportunist = 1
	check(not CombatPerksState.valid(wrong_type), "schema seven rejects wrong flag type")
	var previous_schema := packed.duplicate(true); previous_schema.schema_version = 6
	check(not CombatPerksState.valid(previous_schema), "previous perk schema is refused")

	var s := fixture()
	var opportunist := s.units[2]
	opportunist.guard_stance = false
	opportunist.combat_perks = state.copy()
	opportunist.action_resources._set_for_refill(0, 1)
	check(MeleeThreat.has_passive_opportunist(opportunist) and MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.OPPORTUNIST), "passive opportunist ready without stance")
	opportunist.action_resources._set_for_refill(0, 0)
	check(not MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.OPPORTUNIST), "no bonus means not ready")
	opportunist.action_resources._set_for_refill(0, 1)
	opportunist.control.stunned_turns = 1
	check(not MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.OPPORTUNIST), "control prevents passive reaction")
	opportunist.control.stunned_turns = 0
	var pending := UnitState.from_snapshot_dict(s.units[5].to_snapshot_dict())
	check(pending != null, "pending unit fixture copies cleanly")
	if pending == null:
		s.close()
		return
	pending.id = 1000
	pending.action_resources = ActionResources.new(1000, 1, 1)
	pending.combat_perks = state.copy()
	s.state.register_mage_summon(pending)
	check(not MeleeThreat.reaction_ready_state(s.state, pending, CombatPerksState.Mode.OPPORTUNIST), "pending summon cannot react")
	var tank := CombatPerksState.new()
	tank.definition.tank_reactions = true
	tank.mode = CombatPerksState.Mode.OPPORTUNIST
	tank.reaction_left = 1
	opportunist.combat_perks = tank
	check(not MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.OPPORTUNIST), "legacy tank still requires stance")
	opportunist.combat_perks = state.copy()
	opportunist.action_resources._set_for_refill(0, 1)
	check(not MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.COVER) and not MeleeThreat.reaction_ready_state(s.state, opportunist, CombatPerksState.Mode.COUNTERATTACK), "passive perk grants neither cover nor counterattack")
	check(not MeleeThreat.has_tank(opportunist), "passive perk does not grant tank ownership")
	s.close()
