extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL RETURN EFFECTS: " + label)

func _run() -> void:
	var unit := _fixture()
	var before: Dictionary = unit.to_snapshot_dict()
	if not UnitState.validate_snapshot_dict(before):
		_check(false, "base fixture snapshot validates")
		quit(1)
		return
	var input_copy: Dictionary = before.duplicate(true)
	var clean: Dictionary = ReturnEffects.cleared(before)
	if not UnitState.validate_snapshot_dict(clean):
		_check(false, "clean snapshot remains valid")
		quit(1)
		return
	_check(true, "clean snapshot remains valid")
	_check(before == input_copy, "snapshot input is not mutated")
	_check(ReturnEffects.cleared(clean) == clean, "snapshot clearing is idempotent")
	_check(clean["vitals"] == before["vitals"] and clean["stats"] == before["stats"] and clean["action_resources"] == before["action_resources"], "resources and stats are preserved")
	_check(clean["guard_stance"] == false, "guard stance cleared")
	_check(clean["elemental"]["burning_stacks"] == 0 and clean["elemental"]["burning_ticks"] == 0 and clean["elemental"]["burning_source"].is_empty(), "burning state cleared")
	_check(clean["elemental"]["poison_stacks"] == 0 and clean["elemental"]["poison_ticks"] == 0 and clean["elemental"]["poison_source"].is_empty() and clean["elemental"]["acid_ticks"] == 0, "poison and acid state cleared")
	_check(clean["elemental"]["burning_contributions"].is_empty() and clean["elemental"]["poison_contributions"].is_empty() and clean["elemental"]["freeze_immune"], "authorship and immunity survive elemental clear")
	_check(clean["bleeding"]["ticks_left"] == 0 and clean["bleeding"]["stacks"] == 0 and clean["bleeding"]["source"].is_empty() and clean["bleeding"]["hit_id"].is_empty() and clean["bleeding"]["stacked"] == before["bleeding"]["stacked"], "bleeding effect clears while capability flag survives")
	_check(clean["bleeding"]["immune"], "bleeding immunity survives clear")
	_check(clean["control"]["stunned_turns"] == 0 and clean["control"]["entangled_turns"] == 0, "control state cleared")
	_check(not clean["armor"].has("shield") and not clean["armor"]["raised_shield"]["active"] and clean["armor"]["raised_shield"]["ready_turn"] == 5, "shields clear while cooldown survives")
	_check(clean["armor"]["grants"].size() == 1 and clean["armor"]["grants"][0]["expires"] == "persistent" and clean["armor"]["natural"] == before["armor"]["natural"] and clean["armor"]["perks"] == before["armor"]["perks"], "temporary armor grant clears while permanent armor stays")
	_check(clean["combat_perks"]["mode"] == CombatPerksState.Mode.NONE and clean["combat_perks"]["cover_target_id"] == 0 and clean["combat_perks"]["reaction_left"] == 0 and not clean["combat_perks"]["movement_stopped"], "temporary combat perk state clears")
	_check(clean["combat_perks"]["definition"] == before["combat_perks"]["definition"], "perk definition survives")
	var warrior_unit := _fixture()
	warrior_unit.combat_perks.uses_bonus_actions = true
	warrior_unit.combat_perks.reaction_left = 0
	warrior_unit.combat_perks.warrior = WarriorKit.make()
	warrior_unit.combat_perks.warrior["ready_turn"] = 7
	var warrior_clean := ReturnEffects.cleared(warrior_unit.to_snapshot_dict())
	_check(warrior_clean["combat_perks"]["warrior"]["ready_turn"] == 7 and warrior_clean["combat_perks"]["definition"] == warrior_unit.to_snapshot_dict()["combat_perks"]["definition"], "warrior cooldown and perk definition survive")
	var wet_unit := _fixture()
	wet_unit.elemental.burning_stacks = 0
	wet_unit.elemental.burning_ticks = 0
	wet_unit.elemental.burning_source.clear()
	wet_unit.elemental.burning_contributions.clear()
	wet_unit.elemental.poison_stacks = 0
	wet_unit.elemental.poison_ticks = 0
	wet_unit.elemental.poison_source.clear()
	wet_unit.elemental.poison_contributions.clear()
	wet_unit.elemental.wet_turns = 2
	wet_unit.elemental.frozen_turns = 1
	var wet_snapshot: Dictionary = wet_unit.to_snapshot_dict()
	if not UnitState.validate_snapshot_dict(wet_snapshot):
		_check(false, "wet fixture snapshot validates")
		quit(1)
		return
	var wet_clean := ReturnEffects.cleared(wet_snapshot)
	if not UnitState.validate_snapshot_dict(wet_clean):
		_check(false, "wet cleaned snapshot validates")
		quit(1)
		return
	_check(true, "wet cleaned snapshot validates")
	_check(wet_clean["elemental"]["wet_turns"] == 0 and wet_clean["elemental"]["frozen_turns"] == 0, "wet and frozen state clears")
	var stacked_unit := _fixture()
	stacked_unit.elemental.burning_stacks = 0
	stacked_unit.elemental.burning_ticks = 0
	stacked_unit.elemental.burning_source.clear()
	stacked_unit.elemental.burning_contributions.clear()
	stacked_unit.elemental.poison_stacks = 0
	stacked_unit.elemental.poison_ticks = 0
	stacked_unit.elemental.poison_source.clear()
	stacked_unit.elemental.poison_contributions.clear()
	stacked_unit.bleeding.stacked = true
	stacked_unit.bleeding.stacks = 1
	stacked_unit.bleeding.authored = true
	stacked_unit.bleeding.ticks_left = 1
	stacked_unit.bleeding.hit_id = "hit.stack"
	stacked_unit.bleeding.source = DamageSource.new(&"attack", 0, stacked_unit.cell, stacked_unit.id, stacked_unit.id).to_dict()
	stacked_unit.bleeding.contributions.assign([StatusContributions.make(stacked_unit.bleeding.source)])
	var stacked_snapshot: Dictionary = stacked_unit.to_snapshot_dict()
	if not UnitState.validate_snapshot_dict(stacked_snapshot):
		_check(false, "stacked bleeding fixture snapshot validates")
		quit(1)
		return
	var stacked_clean := ReturnEffects.cleared(stacked_snapshot)
	if not UnitState.validate_snapshot_dict(stacked_clean):
		_check(false, "stacked bleeding cleaned snapshot validates")
		quit(1)
		return
	_check(true, "stacked bleeding cleaned snapshot validates")
	_check(stacked_clean["bleeding"]["stacked"] and stacked_clean["bleeding"]["stacks"] == 0 and stacked_clean["bleeding"]["contributions"].is_empty() and stacked_clean["bleeding"]["immune"], "stacked bleeding authorship clears while stacked capability and immunity survive")
	ReturnEffects.apply(stacked_unit)
	_check(stacked_unit.to_snapshot_dict() == stacked_clean, "stacked bleeding live state matches cleaned snapshot")
	var stats_ref: StatsBag = unit.stats
	var armor_ref: ArmorState = unit.armor
	var bleeding_ref: BleedingState = unit.bleeding
	var control_ref: ControlState = unit.control
	var elemental_ref: ElementalState = unit.elemental
	var perks_ref: CombatPerksState = unit.combat_perks
	var definition_ref: CombatPerksDefinition = unit.combat_perks.definition
	var resources_ref: ActionResources = unit.action_resources
	var raised_ref: Dictionary = unit.armor.raised_shield
	var grants_ref: Array[Dictionary] = unit.armor.grants
	var bleeding_source_ref: Dictionary = unit.bleeding.source
	var burning_source_ref: Dictionary = unit.elemental.burning_source
	ReturnEffects.apply(unit)
	_check(unit.to_snapshot_dict() == clean, "live state matches cleaned snapshot")
	_check(unit.stats == stats_ref and unit.armor == armor_ref and unit.bleeding == bleeding_ref and unit.control == control_ref and unit.elemental == elemental_ref and unit.combat_perks == perks_ref and unit.action_resources == resources_ref and unit.combat_perks.definition == definition_ref, "component and definition identities survive")
	raised_ref["probe"] = true
	grants_ref.append({"probe": true})
	bleeding_source_ref["probe"] = true
	burning_source_ref["probe"] = true
	_check(unit.armor.raised_shield.has("probe") and unit.armor.grants.back().has("probe") and unit.bleeding.source.has("probe") and unit.elemental.burning_source.has("probe"), "mutable field identities survive")
	print("RETURN EFFECTS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fixture() -> UnitState:
	# Настоящий session unit задаёт полный валидный snapshot-граф со всеми stats/component defaults.
	var session := BattleCoreReactionsSession.new()
	var unit: UnitState = session.units[0]
	unit.guard_stance = true
	unit.armor.in_battle = true
	unit.armor.fractional = true
	unit.armor.natural["physical"] = 2
	var battle_id: int = unit.armor.battle_id
	unit.armor.grants.assign([
		{"grant_id": 1, "source": "battle_spell", "remaining": 3, "expires": "battle", "battle_id": battle_id},
		{"grant_id": 2, "source": "permanent_armor", "remaining": 4, "expires": "persistent", "battle_id": battle_id},
	])
	unit.armor.next_grant_id = 3
	unit.armor.shield = SpellShield.make(&"mage.shield", 3, 2)
	unit.armor.raised_shield = {"active": true, "ready_turn": 5, "blocked_root": 0, "blocked_group": 0}
	unit.bleeding.immune = true
	# Элементальные поля требуют сохранённой возможности стека; нулевые ticks валидны без active bleeding.
	unit.bleeding.stacked = true
	unit.bleeding.authored = false
	unit.bleeding.contributions.clear()
	unit.elemental.freeze_immune = true
	var source: Dictionary = DamageSource.new(&"attack", 0, unit.cell, unit.id, unit.id).to_dict()
	unit.elemental.burning_stacks = 1
	unit.elemental.burning_ticks = 2
	unit.elemental.burning_source = source.duplicate(true)
	unit.elemental.burning_contributions.assign([StatusContributions.make(source)])
	unit.elemental.poison_stacks = 1
	unit.elemental.poison_ticks = 2
	unit.elemental.poison_source = source.duplicate(true)
	unit.elemental.poison_contributions.assign([StatusContributions.make(source)])
	unit.elemental.acid_ticks = 2
	unit.elemental.authored = true
	unit.control.stunned_turns = 1
	unit.control.entangled_turns = 1
	unit.combat_perks.definition.tank_reactions = true
	unit.combat_perks.definition.counterattack = true
	unit.combat_perks.mode = CombatPerksState.Mode.COVER
	unit.combat_perks.cover_target_id = session.units[1].id
	unit.combat_perks.uses_bonus_actions = false
	unit.combat_perks.reaction_left = 1
	unit.combat_perks.movement_stopped = true
	return unit
