extends "res://tests/test_counterattack.gd"

func run() -> void:
	codec_and_readiness()
	print("PASSIVE OPPORTUNIST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func codec_and_readiness() -> void:
	var legacy := CombatPerksState.new().to_dict()
	check(legacy == {"schema_version": 1, "definition": {"sneak_attack": false, "tank_reactions": false}, "mode": 0, "cover_target_id": 0, "reaction_left": 0, "movement_stopped": false}, "legacy schema one exact form")
	var old := CombatPerksState.new()
	old.uses_bonus_actions = true
	old.definition.counterattack = true
	var packed_v5 := old.to_dict()
	var restored_v5 := CombatPerksState.from_dict(packed_v5)
	check(packed_v5.schema_version == 5 and restored_v5 != null and restored_v5.to_dict() == packed_v5, "schema five roundtrip remains unchanged")
	var state := CombatPerksState.new()
	state.uses_bonus_actions = true
	state.definition.passive_opportunist = true
	state.mode = CombatPerksState.Mode.OPPORTUNIST
	var packed := state.to_dict()
	check(packed.schema_version == 6 and CombatPerksState.valid(packed), "passive perk uses schema six")
	var restored := CombatPerksState.from_dict(packed)
	check(restored != null and restored.copy().definition.passive_opportunist, "schema six roundtrip and copy")
	var false_flag := packed.duplicate(true)
	false_flag.definition.passive_opportunist = false
	check(not CombatPerksState.valid(false_flag), "schema six rejects false flag")
	var mixed_reserve := packed.duplicate(true)
	mixed_reserve.reaction_left = 0
	check(not CombatPerksState.valid(mixed_reserve), "schema six rejects legacy reserve field")
	var wrong_type := packed.duplicate(true)
	wrong_type.definition.passive_opportunist = 1
	check(not CombatPerksState.valid(wrong_type), "schema six rejects wrong flag type")
	var v5_extra := old.to_dict()
	v5_extra.definition.passive_opportunist = false
	check(not CombatPerksState.valid(v5_extra), "schema five rejects added flag")

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
