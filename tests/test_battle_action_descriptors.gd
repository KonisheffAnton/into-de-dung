extends SceneTree

const EXPECTED_PATH := "res://tests/fixtures/battle_action_descriptors_expected.json"

class ProbeDemo:
	extends BattleDemo
	var force_pending: bool = false
	var reason_prefix: String = ""
	var formatted_reasons: Array[StringName] = []

	func _create_session() -> void:
		_battle = session as BattleTacticalSession

	func is_execution_pending() -> bool:
		return force_pending or super.is_execution_pending()

	func _reason_text(reason: StringName) -> String:
		if not reason_prefix.is_empty(): formatted_reasons.append(reason)
		return reason_prefix + super._reason_text(reason)

class CoverProbeSession:
	extends BattleCoreReactionsSession
	var accepted_id: int = -1
	var queries: Array[int] = []

	func reaction_reason(_mode: int, cover_id: int = 0) -> StringName:
		queries.append(cover_id)
		return &"" if cover_id == accepted_id else StringName("fixture/cover%d" % cover_id)

var passed: int = 0
var failed: int = 0
var actual: Array[Dictionary] = []
var emit_path: String = ""
var demo: ProbeDemo

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--emit-expected="): emit_path = argument.trim_prefix("--emit-expected=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE ACTION DESCRIPTORS: " + label)

func _run() -> void:
	var scripts: Array[Script] = [BattleTacticalSession, BattleArmorSession,
		BattleBleedingSession, BattleEnvironmentSession, BattleControlSession,
		BattleCoreCombinationSession, BattleCoreReactionsSession]
	for index: int in scripts.size():
		demo = ProbeDemo.new()
		demo.session = scripts[index].new() as BattleDemoSession
		demo.tactical_mode = true
		demo.armor_mode = demo.session is BattleArmorSession
		demo.bleeding_mode = demo.session is BattleBleedingSession
		demo.environment_mode = demo.session is BattleEnvironmentSession
		demo.control_mode = demo.session is BattleControlSession
		demo.core_combination_mode = demo.session is BattleCoreCombinationSession
		root.add_child(demo)
		demo.set_process(false)
		for unit: UnitState in demo.session.units:
			demo.session.selected_id = unit.id
			_record("mode%d/unit%d" % [index, demo.session.units.find(unit)])
		var actor := demo.session.units[0]
		demo.session.selected_id = actor.id
		for phase: BattleTacticalSession.Phase in [BattleTacticalSession.Phase.ENEMY_TURN,
				BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEPLOYMENT]:
			demo._battle.phase = phase
			_record("mode%d/phase%d" % [index, phase])
		demo._battle.phase = BattleTacticalSession.Phase.PLAYER_TURN
		if actor.control != null:
			actor.control.stunned_turns = 1
			_record("mode%d/stunned" % index)
			actor.control.stunned_turns = 0
			actor.control.entangled_turns = 1
			_record("mode%d/rooted" % index)
			actor.control.entangled_turns = 0
		var resources := actor.action_resources.to_snapshot_dict()
		actor.action_resources.try_spend_main(actor.action_resources.get_main_left())
		_record("mode%d/no-main" % index)
		actor.action_resources = ActionResources.from_snapshot_dict(resources, actor.id)
		demo.session.selected_id = UnitId.NONE
		_record("mode%d/no-selection" % index)
		demo.session.selected_id = actor.id
		if demo.session is BattleCoreReactionsSession: _reactions(actor)
		if index == scripts.size() - 1:
			demo.reason_prefix = "Причина оболочки: "
			_record("reactions/overridden-reason-formatter")
			actual.append({"label": "item/overridden-reason-formatter", "item":
				JSON.parse_string(JSON.stringify(demo._item_action_descriptor(
					demo._battle.healing_item(), &"healing_item", &"attack/insufficient_main")))})
			demo.reason_prefix = ""
		_items("mode%d" % index)
		var saved_session := demo.session
		var published := demo._action_bar._dynamic_descriptors.duplicate(true)
		demo.force_pending = true
		demo.session = null
		demo._refresh()
		check(demo._action_bar._dynamic_descriptors == published, "pending guard preserves publication with detached session")
		demo.session = saved_session
		demo.force_pending = false
		if index == scripts.size() - 1: _cover_queries()
		demo.queue_free()
		await process_frame
	if not emit_path.is_empty():
		var file := FileAccess.open(emit_path, FileAccess.WRITE)
		check(file != null, "baseline output writable")
		if file != null: file.store_string(JSON.stringify(actual, "\t") + "\n")
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		check(expected is Array and expected.size() == actual.size(), "base case count")
		if expected is Array and expected.size() == actual.size():
			for index: int in actual.size():
				check(actual[index] == expected[index], "base " + String(actual[index].label))
	print("BATTLE ACTION DESCRIPTORS RESULTS: %d passed, %d failed; %d cases" % [passed, failed, actual.size()])
	quit(0 if failed == 0 else 1)

func _record(label: String) -> void:
	var capture := ItemSimulationSnapshot.capture(demo.session.state, [])
	check(capture.snapshot != null, label + " valid fixture snapshot")
	if capture.snapshot == null: return
	var before := capture.snapshot.to_dict()
	var rng := demo.session.context.get_rng().to_dict()
	var selected: int = demo.session.selected_id
	demo.formatted_reasons.clear()
	demo._refresh()
	var projection := {
		"label": label,
		"descriptors": demo._action_bar._dynamic_descriptors.duplicate(true),
		"fixed": demo._action_bar._slot_states.duplicate(true),
	}
	if not demo.reason_prefix.is_empty(): projection["formatted_reasons"] = demo.formatted_reasons.duplicate()
	# JSON нормализует StringName так же, как сохранённый эталон из исходного Demo.
	actual.append(JSON.parse_string(JSON.stringify(projection)))
	check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before, label + " preserves snapshot")
	check(demo.session.context.get_rng().to_dict() == rng and demo.session.selected_id == selected, label + " preserves RNG and selection")
	if not demo._action_bar._dynamic_descriptors.is_empty():
		demo._action_bar._dynamic_descriptors[0]["label"] = "Повреждённая публикация"
		demo._refresh()
		check(demo._action_bar._dynamic_descriptors == projection.descriptors, label + " publishes fresh descriptors")

func _reactions(actor: UnitState) -> void:
	var session := demo.session as BattleCoreReactionsSession
	actor.combat_perks.definition = actor.combat_perks.definition.duplicate(true)
	actor.combat_perks.definition.tank_reactions = true
	actor.combat_perks.definition.counterattack = true
	actor.combat_perks.definition.stunning_strike = true
	actor.combat_perks.definition.burning_bypass_hp_gate = true
	actor.armor.raised_shield = RaisedShield.make()
	_record("reactions/all-perks-shield")
	actor.armor.raised_shield.active = true
	_record("reactions/shield-active")
	actor.armor.raised_shield.active = false
	actor.armor.raised_shield.ready_turn = 400
	_record("reactions/shield-cooldown")
	demo._action_bar.compact_vertical = true
	_record("reactions/compact-default")
	session.action_slot_overrides[actor.id] = [&"elemental_freeze", &"healing_item"]
	_record("reactions/compact-override")
	session.action_slot_overrides[actor.id] = [&"missing", &"missing"]
	_record("reactions/compact-missing")
	session.action_slot_overrides.erase(actor.id)
	demo._action_bar.compact_vertical = false
	for class_id: StringName in [&"archer", &"mage", &"shieldbearer"]:
		session.actor_loadouts[actor.id] = {"class_id": class_id, "attack_id": &"attack"}
		_record("reactions/loadout-" + String(class_id))
	session.actor_loadouts.clear()

func _items(label: String) -> void:
	var candidates: Array[ItemInstance] = [null, demo._battle.healing_item(), demo._battle.summoning_item()]
	var definition := ItemDef.new()
	definition.id = &"descriptor_inert"
	definition.display_name = "Предмет без действия"
	var owner := ItemOwnerState.new(demo.session.units[0])
	candidates.append(owner.create_item(definition))
	for index: int in candidates.size():
		for tactical: bool in [false, true]:
			demo.tactical_mode = tactical
			for reason: StringName in [&"", &"item/no_charges", &"battle/input_locked", &"descriptor/unknown"]:
				actual.append({"label": "%s/item%d/%s/%s" % [label, index, tactical, reason],
					"item": JSON.parse_string(JSON.stringify(demo._item_action_descriptor(candidates[index], &"fixture_item", reason)))})
	demo.tactical_mode = true

func _cover_queries() -> void:
	var probe := CoverProbeSession.new()
	for accepted: int in [-1, 17, 29]:
		probe.accepted_id = accepted
		probe.queries.clear()
		var targets: Array[int] = [17, 29, 41]
		var reason := demo._cover_choice_reason(probe, targets)
		actual.append(JSON.parse_string(JSON.stringify({"label": "cover/accepted%d" % accepted,
			"reason": String(reason), "queries": probe.queries.duplicate()})))
	probe.close()
