extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CURRENT SCHEMA: " + label)

func codec(raw: Dictionary, version: int, valid: Callable, restore: Callable, label: String) -> void:
	var before := var_to_bytes(raw)
	check(valid.call(raw) and restore.call(raw) != null, label + " current accepted")
	for old: int in range(1, version):
		var changed := raw.duplicate(true)
		changed.schema_version = old
		check(not valid.call(changed) and restore.call(changed) == null, label + " rejects old " + str(old))
	for unknown: Variant in [version + 1, 0, true, float(version), str(version)]:
		var changed := raw.duplicate(true)
		changed.schema_version = unknown
		check(not valid.call(changed) and restore.call(changed) == null, label + " rejects unknown/type " + str(unknown))
	check(var_to_bytes(raw) == before, label + " validation does not mutate source")

func run() -> void:
	codec(ArmorState.new().to_dict(), 4, ArmorState.valid, ArmorState.from_dict, "armor")
	codec(BleedingState.new().to_dict(), 4, BleedingState.valid, BleedingState.from_dict, "bleeding")
	codec(ElementalState.new().to_dict(), 3, ElementalState.valid, ElementalState.from_dict, "elemental")
	codec(CombatPerksState.new().to_dict(), 7, CombatPerksState.valid, CombatPerksState.from_dict, "perks")
	codec(CombatEnvironmentState.new().to_dict(), 5, CombatEnvironmentState.valid, CombatEnvironmentState.from_dict, "environment")
	codec(BattleAbilityState.create(AbilityCatalog.defaults()).to_dict(), 3, BattleAbilityState.valid, BattleAbilityState.from_dict, "abilities")
	var board := BattleBoard.new(2, 1)
	codec(board.to_snapshot_dict(), 2, BattleBoard.validate_snapshot_dict, BattleBoard.from_snapshot_dict, "board")
	var old_board := board.to_snapshot_dict()
	old_board.schema_version = 1; old_board.erase("height_half_steps")
	check(BattleBoard.from_snapshot_dict(old_board) == null, "former board1 shape refused")
	var bad := board.to_snapshot_dict()
	bad.schema_version = 99; bad.height_half_steps[0] = true
	check(SimulationSnapshot.from_dict({"schema_version": 1, "scope": SimulationSnapshot.SCOPE, "board": bad}).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "unknown version cannot hide malformed half bits")
	for bonus: bool in [false, true]:
		for mask: int in range(256):
			var perks := CombatPerksState.new()
			perks.uses_bonus_actions = bonus
			var flags: Array[String] = ["sneak_attack", "tank_reactions", "stunning_strike", "stun_immune", "entangle_immune", "counterattack", "burning_bypass_hp_gate", "passive_opportunist"]
			for i: int in flags.size(): perks.definition.set(flags[i], (mask & (1 << i)) != 0)
			var raw := perks.to_dict()
			if not bonus and perks.definition.passive_opportunist:
				check(raw.is_empty(), "passive perk cannot use legacy charge " + str(mask))
			else:
				var restored := CombatPerksState.from_dict(raw)
				check(restored != null and restored.to_dict() == raw and restored.definition != perks.definition, "perks mask roundtrip/ownership " + str(mask))
	var modern := CombatPerksState.new()
	modern.uses_bonus_actions = true; modern.definition.counterattack = true
	var mixed := modern.to_dict(); mixed.reaction_left = 1
	check(not CombatPerksState.valid(mixed), "bonus mode cannot introduce second reserve")
	var ability := BattleAbilityState.create_deck(AbilityCatalog.defaults(), 0)
	var ability_data := ability.to_dict(); ability_data.ruleset_id = ""
	check(not BattleAbilityState.valid(ability_data), "mode substitution cannot reinterpret mana/turn clock")
	var environment := CombatEnvironmentState.new().to_dict()
	environment.status_effects = true
	check(not CombatEnvironmentState.valid(environment), "status mode requires collapse capability")
	var bleeding := BleedingState.new().to_dict(); bleeding.stacks = 1
	check(not BleedingState.valid(bleeding), "unstacked mode cannot hide stacks")
	print("CURRENT SCHEMA BOUNDARY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
