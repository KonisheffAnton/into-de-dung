extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL COMBAT PERKS STATE: " + label)

func _unit(id: int) -> UnitState:
	var stats := StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 12.0, StatTypes.StatType.BALANCE_MAX: 4.0, StatTypes.StatType.MOVE_RANGE: 3.0, StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0, StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0, StatTypes.StatType.WEAPON_DAMAGE: 2.0, StatTypes.StatType.ATTACK_RANGE: 1.0})
	var unit := UnitState.new()
	unit.id = id
	unit.faction = Faction.Type.PLAYER
	unit.stats = stats
	unit.vitals = Vitals.new(stats, true)
	return unit

func _run() -> void:
	_test_state_codec()
	_test_counterattack_codec()
	_test_unit_schema_and_board()
	print("COMBAT PERKS STATE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_state_codec() -> void:
	var state := CombatPerksState.new()
	check(CombatPerksState.valid(state.to_dict()), "empty state valid")
	state.movement_stopped = true
	var clone := state.copy()
	check(clone != null and clone.movement_stopped, "movement stop cloned")
	state.definition.sneak_attack = true
	state.definition.tank_reactions = true
	state.mode = CombatPerksState.Mode.COVER
	state.cover_target_id = 21
	state.reaction_left = 1
	clone = state.copy()
	check(clone != null and clone.definition != state.definition and clone.definition.tank_reactions, "definition independently copied")
	clone.definition.sneak_attack = false
	clone.reaction_left = 0
	check(state.definition.sneak_attack and state.reaction_left == 1, "runtime and definition isolation")
	var tank_only := CombatPerksState.new()
	tank_only.definition.tank_reactions = true
	tank_only.mode = CombatPerksState.Mode.OPPORTUNIST
	tank_only.reaction_left = 1
	check(CombatPerksState.valid(tank_only.to_dict()), "tank only state")
	var data := state.to_dict()
	for field: String in ["schema_version", "mode", "cover_target_id", "reaction_left", "movement_stopped"]:
		var bad := data.duplicate(true)
		bad[field] = "bad"
		check(not CombatPerksState.valid(bad), "reject wrong type " + field)
	var bad_extra := data.duplicate(true)
	bad_extra["extra"] = true
	check(not CombatPerksState.valid(bad_extra), "reject unknown key")
	for invalid_id: int in [-1, CombatPerksState.MAX_ID]:
		var bad_id := data.duplicate(true)
		bad_id["cover_target_id"] = invalid_id
		check(not CombatPerksState.valid(bad_id), "reject cover id bound")
	var bad_subclass := _PerksStateSubclass.new()
	check(bad_subclass.to_dict().is_empty(), "reject subclass instance")
	var bad_self := _unit(30)
	bad_self.enable_action_resources()
	bad_self.combat_perks = state.copy()
	bad_self.combat_perks.cover_target_id = bad_self.id
	check(bad_self.to_snapshot_dict().is_empty(), "reject self cover target")

func _test_counterattack_codec() -> void:
	var old := {"schema_version": 1, "definition": {"sneak_attack": false, "tank_reactions": false}, "mode": 0, "cover_target_id": 0, "reaction_left": 0, "movement_stopped": false}
	check(not CombatPerksState.valid(old), "old perk schema is refused")
	var canonical := CombatPerksState.new().to_dict()
	check(canonical.schema_version == 7 and canonical.definition.size() == 8 and CombatPerksState.valid(canonical), "all-false definitions use the current complete shape")
	check(CombatPerksState.from_dict(canonical).to_dict() == canonical, "current empty definition roundtrips")
	var v2_state := CombatPerksState.new()
	v2_state.definition.stun_immune = true
	var v2 := v2_state.to_dict()
	check(v2.schema_version == 7 and v2.definition.size() == 8 and CombatPerksState.valid(v2), "current definition includes every perk flag")
	check(CombatPerksState.from_dict(v2).to_dict() == v2, "current definition roundtrips")
	var bad_legacy_mode := canonical.duplicate(true)
	bad_legacy_mode["mode"] = CombatPerksState.Mode.COUNTERATTACK
	check(not CombatPerksState.valid(bad_legacy_mode), "counterattack mode requires counterattack perk")
	var bad_v2 := v2.duplicate(true)
	bad_v2["definition"]["counterattack"] = true
	check(CombatPerksState.valid(bad_v2), "counterattack is a known current definition flag")
	var counter := CombatPerksState.new()
	counter.definition.counterattack = true
	counter.mode = CombatPerksState.Mode.COUNTERATTACK
	counter.reaction_left = 1
	var v3 := counter.to_dict()
	check(v3["schema_version"] == 7 and v3["definition"].size() == 8 and CombatPerksState.valid(v3), "schema seven counterattack roundtrip shape")
	var restored := CombatPerksState.from_dict(v3)
	check(restored != null and restored.definition.counterattack and restored.mode == CombatPerksState.Mode.COUNTERATTACK and restored.reaction_left == 1, "counterattack state restored")
	var cloned := counter.copy()
	cloned.definition.counterattack = false
	cloned.reaction_left = 0
	check(counter.definition.counterattack and counter.reaction_left == 1, "counterattack definition and charge isolated")
	var bad_type := v3.duplicate(true)
	bad_type["definition"]["counterattack"] = 1
	check(not CombatPerksState.valid(bad_type), "schema seven rejects wrong counterattack type")
	var bad_flag_type := v3.duplicate(true)
	bad_flag_type["definition"]["stunning_strike"] = 1
	check(not CombatPerksState.valid(bad_flag_type), "schema seven rejects wrong perk flag type")
	var bad_key := v3.duplicate(true)
	bad_key["definition"]["unknown"] = false
	check(not CombatPerksState.valid(bad_key), "schema seven rejects unknown definition key")
	var downgraded := v3.duplicate(true)
	downgraded["schema_version"] = 6
	check(not CombatPerksState.valid(downgraded), "old perk schema is rejected")
	var fake_v3 := v3.duplicate(true)
	fake_v3["definition"]["counterattack"] = false
	check(not CombatPerksState.valid(fake_v3), "counterattack mode requires counterattack flag")
	var counter_only_charge := CombatPerksState.new()
	counter_only_charge.definition.counterattack = true
	counter_only_charge.reaction_left = 1
	check(CombatPerksState.valid(counter_only_charge.to_dict()), "counterattack perk shares reaction charge")
	var no_tank_opportunist := counter_only_charge.copy()
	no_tank_opportunist.mode = CombatPerksState.Mode.OPPORTUNIST
	check(no_tank_opportunist.to_dict().is_empty(), "opportunist still requires tank perk")
	var no_tank_cover := counter_only_charge.copy()
	no_tank_cover.mode = CombatPerksState.Mode.COVER
	no_tank_cover.cover_target_id = 5
	check(no_tank_cover.to_dict().is_empty(), "cover still requires tank perk")
	var no_counter_mode := CombatPerksState.new()
	no_counter_mode.mode = CombatPerksState.Mode.COUNTERATTACK
	check(no_counter_mode.to_dict().is_empty(), "counterattack mode requires counterattack perk")

func _test_unit_schema_and_board() -> void:
	var unit := _unit(20)
	check(unit.to_snapshot_dict()["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION, "canonical unit schema is current")
	unit.enable_action_resources()
	unit.combat_perks = CombatPerksState.new()
	unit.combat_perks.definition.sneak_attack = true
	var packed := unit.to_snapshot_dict()
	check(packed.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and UnitState.validate_snapshot_dict(packed), "current schema with sneak perk")
	var restored := UnitState.from_snapshot_dict(packed)
	check(restored != null and restored.combat_perks.definition.sneak_attack, "current schema roundtrip")
	unit.combat_perks.definition.counterattack = true
	unit.combat_perks.reaction_left = 1
	packed = unit.to_snapshot_dict()
	check(packed.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and packed["combat_perks"]["schema_version"] == 7, "counterattack uses nested perk schema seven")
	var counter_restored := UnitState.from_snapshot_dict(packed)
	check(counter_restored != null and counter_restored.combat_perks.definition.counterattack and counter_restored.combat_perks.reaction_left == 1, "current unit schema restores counterattack and shared charge")
	var missing := packed.duplicate(true)
	missing.erase("action_resources")
	check(not UnitState.validate_snapshot_dict(missing), "combat perks require action resources")
	var high_id := CombatPerksState.new()
	high_id.definition.tank_reactions = true
	high_id.mode = CombatPerksState.Mode.COVER
	high_id.cover_target_id = 2147483648
	check(not high_id.to_dict().is_empty() and CombatPerksState.from_dict(high_id.to_dict()).cover_target_id == high_id.cover_target_id, "cover ID uses full existing ID range")
	restored.combat_perks.definition.sneak_attack = false
	check(unit.combat_perks.definition.sneak_attack, "unit definition isolated")
	var armored := _unit(22)
	armored.enable_action_resources()
	armored.guard_stance = true
	armored.armor = ArmorState.new()
	armored.bleeding = BleedingState.new()
	armored.combat_perks = CombatPerksState.new()
	armored.combat_perks.definition.tank_reactions = true
	var armored_data := armored.to_snapshot_dict()
	check(armored_data.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and armored_data.has("guard_stance") and not armored_data.has("control"), "current schema armor and bleeding without control")
	check(UnitState.from_snapshot_dict(armored_data) != null, "current schema armor and bleeding restore")
	var controlled := _unit(23)
	controlled.enable_action_resources()
	controlled.control = ControlState.new()
	controlled.control.entangled_turns = 1
	controlled.combat_perks = CombatPerksState.new()
	var controlled_copy := UnitState.from_snapshot_dict(controlled.to_snapshot_dict())
	check(controlled_copy != null and controlled_copy.control.entangled_turns == 1 and controlled_copy.armor == null and not controlled_copy.to_snapshot_dict().has("armor"), "current schema preserves control without armor")
	for version: int in range(1, 7):
		var legacy := _unit(30 + version)
		if version >= 2: legacy.enable_action_resources()
		if version >= 3: legacy.guard_stance = true
		if version >= 4: legacy.armor = ArmorState.new()
		if version >= 5: legacy.bleeding = BleedingState.new()
		if version >= 6: legacy.control = ControlState.new()
		var current_data := legacy.to_snapshot_dict()
		var has_actions: bool = legacy.action_resources != null
		check(current_data.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and current_data.has("guard_stance") and current_data.has("action_resources") == has_actions and not current_data.has("combat_perks"), "current optional fields for fixture %d" % version)
		var current_copy := UnitState.from_snapshot_dict(current_data)
		check(current_copy != null and current_copy.to_snapshot_dict() == current_data, "current optional fixture roundtrip %d" % version)
	var bad := packed.duplicate(true)
	bad["combat_perks"]["mode"] = 1
	check(not UnitState.validate_snapshot_dict(bad), "reject opportunist without tank perk")
	var board := BattleBoard.new(1, 1)
	unit.cell = Vector2i.ZERO
	check(board.add_unit(unit), "board fixture")
	var snapshot := SimulationSnapshot.capture_board(board, [])
	check(snapshot.code == BoardSnapshotResult.Code.OK, "board captures combat perks")
	var board_copy := snapshot.snapshot.instantiate_board()
	check(board_copy != null and board_copy.get_unit_by_id(20).combat_perks != unit.combat_perks, "board restores independent state")
	var malformed := snapshot.snapshot.to_dict()
	malformed["board"]["units"][0]["combat_perks"]["unknown"] = 1
	check(SimulationSnapshot.from_dict(malformed).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "snapshot rejects malformed perk")

class _PerksStateSubclass extends CombatPerksState:
	pass
