extends SceneTree

const EXPECTED_PATH := "res://tests/fixtures/battle_inspection_text_expected.json"
var passed: int = 0
var failed: int = 0
var actual: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE INSPECTION TEXT: " + label)

func _run() -> void:
	for script: Script in [BattleDemoSession, BattleTacticalSession, BattleArmorSession,
			BattleBleedingSession, BattleControlSession, BattleCoreReactionsSession]:
		var demo := BattleDemo.new()
		demo.session = script.new() as BattleDemoSession
		demo._battle = demo.session as BattleTacticalSession
		var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()
		var rng := demo.session.context.get_rng().to_dict()
		for control: bool in [false, true]:
			demo.control_mode = control
			for unit: UnitState in demo.session.units:
				actual.append(demo._inspection_text(unit))
		check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before, "real inspection preserves full snapshot")
		check(demo.session.context.get_rng().to_dict() == rng, "inspection preserves RNG")
		var actor := demo.session.units[0]
		var original := demo._inspection_text(actor)
		actor.debug_name = "Имя изменено без revision"
		check(demo._inspection_text(actor) != original and demo._inspection_text(actor).begins_with(actor.debug_name), "fresh name without revision")
		if demo.session is BattleCoreReactionsSession:
			_variants(demo)
		demo.session.close()
		demo.session = null
		demo._battle = null
		demo.free()
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
	check(expected is Array and expected.size() == actual.size(), "base output count")
	if expected is Array and expected.size() == actual.size():
		for index: int in actual.size():
			check(actual[index] == expected[index], "base inspection %d" % index)
	print("BATTLE INSPECTION TEXT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _variants(demo: BattleDemo) -> void:
	var actor := demo.session.units[0]
	# Отдельные значения проверяют текстовые ветви, не исполняют игровые эффекты.
	actor.guard_stance = true
	actor.control.stunned_turns = 1
	actor.control.entangled_turns = 1
	actor.bleeding.stacks = 3
	actor.bleeding.ticks_left = 2
	actor.bleeding.immune = true
	actor.elemental.burning_stacks = 2
	actor.elemental.burning_ticks = 3
	actor.elemental.wet_turns = 1
	actor.elemental.frozen_turns = 2
	actor.elemental.freeze_immune = true
	actor.armor.shield = {"hp": 6, "hits_left": 2}
	actor.armor.raised_shield = {"active": true}
	var perks := CombatPerksState.new()
	actor.combat_perks = perks
	for field: StringName in [&"sneak_attack", &"tank_reactions", &"stunning_strike",
			&"stun_immune", &"entangle_immune", &"counterattack", &"burning_bypass_hp_gate"]:
		perks.definition.set(field, true)
	perks.movement_stopped = true
	for bonus: bool in [false, true]:
		perks.uses_bonus_actions = bonus
		perks.reaction_left = 0 if bonus else 1
		perks.definition.passive_opportunist = bonus
		for mode: int in [CombatPerksState.Mode.NONE, CombatPerksState.Mode.OPPORTUNIST,
				CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]:
			perks.mode = mode
			perks.cover_target_id = demo.session.units[2].id if mode == CombatPerksState.Mode.COVER else 0
			actual.append(demo._inspection_text(actor))
	actor.armor.raised_shield.active = false
	actual.append(demo._inspection_text(actor))
	actor.bleeding.stacked = false
	actual.append(demo._inspection_text(actor))
	for mage: bool in [false, true]:
		for pending: bool in [false, true]:
			var record := {"unit_id": actor.id, "owner_unit_id": demo.session.units[2].id, "pending": pending}
			if mage: record.source_kind = "mage"
			demo.session.state._summons = [record]
			var before := demo.session.state.get_summons()
			actual.append(demo._inspection_text(actor))
			check(demo.session.state.get_summons() == before, "inspection preserves summon metadata")
	demo.session.state._summons.clear()
	for stat: int in range(13):
		actual.append(demo._stat_name(stat as StatTypes.StatType))
	actual.append(demo._item_cost_text(null))
	actual.append(demo._summon_hp_text(null))
