extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CONTROL PERKS CODEC: " + label)

func _unit(id: int) -> UnitState:
	var stats := StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 12.0, StatTypes.StatType.BALANCE_MAX: 4.0, StatTypes.StatType.MOVE_RANGE: 3.0, StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0, StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0, StatTypes.StatType.WEAPON_DAMAGE: 2.0, StatTypes.StatType.ATTACK_RANGE: 1.0})
	var unit := UnitState.new()
	unit.id = id
	unit.faction = Faction.Type.PLAYER
	unit.stats = stats
	unit.vitals = Vitals.new(stats, true)
	unit.enable_action_resources()
	return unit

func _run() -> void:
	_test_combinations_and_codec()
	_test_unit_and_board_roundtrip()
	print("CONTROL PERKS CODEC RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_combinations_and_codec() -> void:
	for mask: int in range(8):
		var state := CombatPerksState.new()
		state.definition.stunning_strike = (mask & 1) != 0
		state.definition.stun_immune = (mask & 2) != 0
		state.definition.entangle_immune = (mask & 4) != 0
		var raw := state.to_dict()
		check(raw["schema_version"] == 7, "canonical current version for flag mask %d" % mask)
		check(raw["definition"].size() == 8, "all perk fields are explicit for mask %d" % mask)
		check(CombatPerksState.valid(raw), "valid flag mask %d" % mask)
		var restored := CombatPerksState.from_dict(raw)
		check(restored != null and restored.to_dict() == raw, "roundtrip flag mask %d" % mask)
		if restored != null:
			check(restored.definition != state.definition, "definition resource copied for mask %d" % mask)
			state.definition.stunning_strike = not state.definition.stunning_strike
			check(restored.definition.stunning_strike == ((mask & 1) != 0), "restored resource isolated for mask %d" % mask)
	var old := {"schema_version": 1, "definition": {"sneak_attack": false, "tank_reactions": false}, "mode": CombatPerksState.Mode.NONE, "cover_target_id": 0, "reaction_left": 0, "movement_stopped": false}
	check(not CombatPerksState.valid(old), "old minimal perk format is refused")
	var current := CombatPerksState.new().to_dict()
	var restored_current := CombatPerksState.from_dict(current)
	check(restored_current != null and restored_current.to_dict() == current and var_to_bytes(restored_current.to_dict()) == var_to_bytes(current), "current all-false DTO exact roundtrip")
	var bad := current.duplicate(true)
	bad["schema_version"] = 6
	check(not CombatPerksState.valid(bad), "reject previous perk schema")
	var canonical_v2 := CombatPerksState.new()
	canonical_v2.definition.stun_immune = true
	var v2 := canonical_v2.to_dict()
	for key: String in ["schema_version", "mode", "cover_target_id", "reaction_left", "movement_stopped"]:
		var invalid := v2.duplicate(true)
		invalid[key] = "bad"
		check(not CombatPerksState.valid(invalid), "reject wrong type %s" % key)
	for key: String in ["sneak_attack", "tank_reactions", "stunning_strike", "stun_immune", "entangle_immune", "counterattack", "burning_bypass_hp_gate", "passive_opportunist"]:
		var missing := v2.duplicate(true)
		missing["definition"].erase(key)
		check(not CombatPerksState.valid(missing), "reject missing definition field %s" % key)
		var wrong_type := v2.duplicate(true)
		wrong_type["definition"][key] = 1
		check(not CombatPerksState.valid(wrong_type), "reject nonbool definition field %s" % key)
	var extra := v2.duplicate(true)
	extra["definition"]["other"] = true
	check(not CombatPerksState.valid(extra), "reject extra definition field")
	var downgrade := v2.duplicate(true)
	downgrade["schema_version"] = 6
	check(not CombatPerksState.valid(downgrade), "reject current fields downgraded to old schema")
	var state_subclass := _PerksStateSubclass.new()
	check(state_subclass.to_dict().is_empty(), "reject runtime subclass")
	var definition_subclass := CombatPerksState.new()
	definition_subclass.definition = _PerksDefinitionSubclass.new()
	check(definition_subclass.to_dict().is_empty(), "reject definition subclass")

func _test_unit_and_board_roundtrip() -> void:
	var unit := _unit(41)
	unit.combat_perks = CombatPerksState.new()
	unit.combat_perks.definition.stunning_strike = true
	unit.combat_perks.definition.stun_immune = true
	var raw := unit.to_snapshot_dict()
	check(raw["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION and raw["combat_perks"]["schema_version"] == 7 and UnitState.validate_snapshot_dict(raw), "unit schema carries perks v7")
	var restored := UnitState.from_snapshot_dict(raw)
	check(restored != null and restored.to_snapshot_dict() == raw, "unit v7 exact restore")
	var malformed := raw.duplicate(true)
	malformed["combat_perks"]["definition"]["entangle_immune"] = "yes"
	check(not UnitState.validate_snapshot_dict(malformed), "unit rejects malformed nested current perks")
	var board := BattleBoard.new(1, 1)
	unit.cell = Vector2i.ZERO
	check(board.add_unit(unit), "board accepts codec unit")
	var snapshot := SimulationSnapshot.capture_board(board, [])
	check(snapshot.code == BoardSnapshotResult.Code.OK, "board captures perks v7")
	if snapshot.code != BoardSnapshotResult.Code.OK or snapshot.snapshot == null: return
	var packed := snapshot.snapshot.to_dict()
	var board_copy := SimulationSnapshot.from_dict(packed)
	check(board_copy.code == BoardSnapshotResult.Code.OK, "board snapshot validates perks v7")
	var instance := board_copy.snapshot.instantiate_board()
	check(instance != null and instance.get_unit_by_id(41).combat_perks.to_dict() == unit.combat_perks.to_dict(), "board restores exact perks v7")
	var malformed_board := packed.duplicate(true)
	malformed_board["board"]["units"][0]["combat_perks"]["schema_version"] = 2
	malformed_board["board"]["units"][0]["combat_perks"]["definition"] = {"sneak_attack": false, "tank_reactions": false, "stunning_strike": false, "stun_immune": false, "entangle_immune": false}
	check(SimulationSnapshot.from_dict(malformed_board).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "board rejects old nested perk schema")

class _PerksStateSubclass extends CombatPerksState:
	pass

class _PerksDefinitionSubclass extends CombatPerksDefinition:
	pass
