extends SceneTree

const EXPECTED_PATH := "res://tests/fixtures/battle_forecast_text_expected.json"
var passed: int = 0
var failed: int = 0
var actual: Array[Dictionary] = []
var demo: BattleDemo
var emit_path: String = ""
var actor_id: int
var target_id: int

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--emit-expected="):
			emit_path = argument.trim_prefix("--emit-expected=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE FORECAST TEXT: " + label)

func _run() -> void:
	# Эталон получен старым UI-адаптером, а не новым formatter.
	for core: bool in [false, true]:
		_open(core)
		var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()
		var rng := demo.session.context.get_rng().to_dict()
		_attack_cases(core)
		_reason_cases(core)
		if core:
			_move_cases()
			_guard_cases()
			_item_and_raise_cases()
			_spell_cases()
			_phase_cases()
		check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before, "text keeps full live state")
		check(demo.session.context.get_rng().to_dict() == rng, "text keeps live RNG")
		demo.session.close()
		demo.session = null
		demo._battle = null
		demo.free()
	if not emit_path.is_empty():
		var file := FileAccess.open(emit_path, FileAccess.WRITE)
		check(file != null, "baseline output writable")
		if file != null: file.store_string(JSON.stringify(actual, "\t") + "\n")
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		check(expected is Array and expected.size() == actual.size(), "baseline case count")
		if expected is Array and expected.size() == actual.size():
			for index: int in actual.size():
				check(actual[index] == expected[index], "baseline " + String(actual[index].label))
	print("BATTLE FORECAST TEXT RESULTS: %d passed, %d failed; %d cases" % [passed, failed, actual.size()])
	quit(0 if failed == 0 else 1)

func _open(core: bool) -> void:
	demo = BattleDemo.new()
	demo.session = BattleCoreReactionsSession.new() if core else BattleTacticalSession.new()
	demo._battle = demo.session as BattleTacticalSession
	actor_id = demo.session.units[0].id
	target_id = demo.session.units[1].id
	demo.board_view = BattleDemoBoard.new()
	demo._forecast_panel = RichTextLabel.new()
	demo._forecast_heading = Label.new()
	demo._log = RichTextLabel.new()
	demo._log_heading = Label.new()
	for node: Node in [demo.board_view, demo._forecast_panel, demo._forecast_heading, demo._log, demo._log_heading]:
		demo.add_child(node)

func _reset() -> void:
	demo._forecast = null
	demo._move_forecast = null
	demo._guard_forecast = null
	demo._item_forecast = null
	demo._raise_forecast = null
	demo._armor_forecast = null
	demo._elemental_forecast = null
	demo._turn_forecast = null
	demo._environment_forecast = null
	demo._attack_forecast_pending = false
	demo._move_forecast_pending = false
	demo._action_forecast_pending = false
	demo._turn_forecast_pending = false
	demo._environment_forecast_pending = false
	demo._action_forecast_kind = &""
	demo._forecast_panel.text = "unchanged"
	demo._forecast_panel.visible = false
	demo._forecast_heading.text = "unchanged heading"
	demo._forecast_heading.visible = false
	demo._log.visible = true
	demo._log_heading.visible = true

func _values(value: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	if value == null: return result
	for property: Dictionary in value.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[property.name] = value.get(property.name)
	return result.duplicate(true)

func _observe(label: String, method: StringName, value: RefCounted = null) -> void:
	var before := _values(value)
	demo.call(method)
	check(_values(value) == before, label + " preserves detached forecast")
	actual.append({"label": label, "text": demo._forecast_panel.text,
		"heading": demo._forecast_heading.text, "panel_visible": demo._forecast_panel.visible,
		"heading_visible": demo._forecast_heading.visible, "log_visible": demo._log.visible,
		"log_heading_visible": demo._log_heading.visible})

func _unit(id: int) -> Dictionary:
	return {"id": id, "name": "DTO #%d" % id, "alive": true, "hp": 12.0, "hp_max": 20.0,
		"cell": Vector2i(1, 2), "balance": 8.0, "balance_max": 12.0,
		"armor_current": 6, "armor_max": 10, "main": 2, "bonus": 2, "move": 4.5,
		"guard_stance": true, "owner_unit_id": actor_id, "pending": true,
		"bleeding": {"stacked": true, "stacks": 2, "ticks_left": 3},
		"elemental": {"burning_stacks": 1, "burning_ticks": 2, "wet_turns": 1},
		"control": {"stunned_turns": 0, "entangled_turns": 1},
		"combat_perks": {"uses_bonus_actions": true, "reaction_left": 1,
			"movement_stopped": true, "definition": {"passive_opportunist": false}}}

func _after(id: int) -> Dictionary:
	var row := _unit(id)
	row.merge({"hp": 0.0, "alive": false, "cell": Vector2i(2, 3), "balance": 0.0,
		"balance_max": 10.0, "armor_current": 3, "main": 1, "bonus": 1, "move": 2.0,
		"guard_stance": false, "pending": false,
		"bleeding": {"stacked": true, "stacks": 1, "ticks_left": 1},
		"elemental": {"wet_turns": 2, "frozen_turns": 1},
		"control": {"stunned_turns": 1, "entangled_turns": 0}}, true)
	row.combat_perks.reaction_left = 0
	row.combat_perks.movement_stopped = false
	return row

func _events() -> Array[Dictionary]:
	return [
		{"kind": &"chain_link", "actor_unit_id": actor_id, "target_unit_id": target_id,
			"from_unit_id": actor_id, "impulse": 4.5, "broke": false},
		{"kind": &"attacked", "actor_unit_id": actor_id, "target_unit_id": target_id,
			"modifiers": {"sneak_percent": 50, "threat_ids": [target_id, actor_id], "backstab_percent": 50, "critical": true}},
		{"kind": &"hit_resolved", "target_unit_id": target_id, "source": {"kind": &"cell", "origin_cell": Vector2i(4, 3)},
			"hit": {"armor_spent": 3, "p_num": 1, "p_den": 2, "total_damage": 8, "total_healing": 1,
				"hp_before": 12, "hp_after": 0, "rows": [
					{"type": &"physical", "policy": &"hp_only_natural", "D": 8, "armor_spent": 0, "hp_damage": 6, "healing": 0},
					{"type": &"fire", "policy": &"hp_only_unresisted", "D": 2, "armor_spent": 0, "hp_damage": 2, "healing": 1}],
				"bleeding": {"policy": &"bypass_hp_gate", "eligible": true}}},
		{"kind": &"environment_turn", "turn": 3, "marked": [Vector2i(4, 3)]},
		{"kind": &"support_collapsed", "cell": Vector2i(4, 3)},
	]

func _attack_cases(core: bool) -> void:
	_reset()
	demo._attack_forecast_actor = actor_id
	demo._forecast_target_id = target_id
	_observe("attack none %s" % core, &"_render_forecast_panel")
	demo._attack_forecast_pending = true
	_observe("attack pending %s" % core, &"_render_forecast_panel")
	demo._attack_forecast_pending = false
	var value := AttackForecast.new()
	demo._forecast = value
	value.reason = &"attack/out_of_range"
	_observe("attack rejected %s" % core, &"_render_forecast_panel", value)
	value.status = ActionReceipt.APPLIED
	value.units = {target_id: {"before": _unit(target_id), "after": _after(target_id)},
		actor_id: {"before": _unit(actor_id), "after": _after(actor_id)}}
	value.events = _events()
	value.steps = [
		{"kind": &"stun_apply", "status": &"APPLIED", "reason": &""},
		{"kind": &"stun_apply", "status": &"SKIPPED", "reason": &"control/stun_immune"},
		{"kind": &"entangle_apply", "status": &"APPLIED", "reason": &""},
		{"kind": &"entangle_apply", "status": &"SKIPPED", "reason": &"control/dead_target"},
		{"kind": &"bleeding_apply", "status": &"SKIPPED", "reason": &"bleeding/burning"}]
	_observe("attack applied %s" % core, &"_render_forecast_panel", value)
	var old_name: String = demo.session.units[0].debug_name
	demo.session.units[0].debug_name = "Свежий текст без revision"
	_observe("attack fresh name %s" % core, &"_render_forecast_panel", value)
	check(demo._forecast_panel.text.contains("Свежий текст без revision"), "name resolved fresh")
	demo.session.units[0].debug_name = old_name
	value.units[target_id].before.bleeding.stacked = false
	value.units[target_id].after.bleeding.stacked = false
	value.events.clear()
	_observe("attack legacy bleeding no events %s" % core, &"_render_forecast_panel", value)

func _move_cases() -> void:
	for retreat: bool in [false, true]:
		_reset()
		demo._move_forecast_retreat = retreat
		demo._move_forecast_cell = Vector2i(3, 4)
		demo._move_forecast_pending = true
		for has_path: bool in [false, true]:
			demo.board_view.pending_move_path.clear()
			if has_path: demo.board_view.pending_move_path.append(Vector2i(1, 2))
			_observe("move pending %s %s" % [retreat, has_path], &"_render_move_forecast_panel")
		demo._move_forecast_pending = false
		var value := MoveForecast.new()
		value.actor_id = actor_id
		value.units = {actor_id: {"before": _unit(actor_id), "after": _after(actor_id)},
			target_id: {"before": _unit(target_id), "after": _unit(target_id)}}
		value.events = _events()
		demo._move_forecast = value
		for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
			value.status = status
			value.reason = &"perks/opportunist_stopped"
			_observe("move %s %s" % [retreat, status], &"_render_move_forecast_panel", value)

func _guard_cases() -> void:
	for kind: StringName in [&"guard", &"raise_shields"]:
		_reset()
		demo._action_forecast_kind = kind
		demo._guard_forecast_actor = actor_id
		var value := GuardForecast.new()
		value.actor_id = actor_id
		value.reason = &"raise_shields/cooldown"
		value.units = {actor_id: {"before": _unit(actor_id), "after": _after(actor_id)}}
		demo._guard_forecast = value
		for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
			value.status = status
			_observe("guard %s %s" % [kind, status], &"_render_guard_forecast_panel", value)
	for mode: int in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]:
		demo._guard_forecast_mode = mode
		demo._guard_forecast_target = target_id
		for bonus: bool in [false, true]:
			for passive: bool in [false, true]:
				demo._guard_forecast.units[actor_id].after.combat_perks.uses_bonus_actions = bonus
				demo._guard_forecast.units[actor_id].after.combat_perks.definition.passive_opportunist = passive
				_observe("reaction %d %s %s" % [mode, bonus, passive], &"_render_reaction_guard_forecast", demo._guard_forecast)
		demo._guard_forecast.status = ActionReceipt.REJECTED
		_observe("reaction rejected %d" % mode, &"_render_reaction_guard_forecast", demo._guard_forecast)
		demo._guard_forecast.status = ActionReceipt.APPLIED

func _item_and_raise_cases() -> void:
	for kind: StringName in [&"healing", &"summon"]:
		_reset()
		demo._item_forecast_kind = kind
		demo._item_forecast_cell = Vector2i(3, 4)
		var value := ItemUseForecast.new()
		value.reason = &"item/no_charges"
		value.units = {actor_id: {"before": _unit(actor_id), "after": _after(actor_id)},
			999: {"before": null, "after": _unit(999)}}
		value.items = {2: {"actor_id": target_id, "before": {"charges": 3}, "after": {"charges": 2}},
			1: {"actor_id": actor_id, "before": {"charges": 1}, "after": {"charges": 0}}}
		demo._item_forecast = value
		for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
			value.status = status
			_observe("item %s %s" % [kind, status], &"_render_item_forecast_panel", value)
	_reset()
	var raise_value := RaiseCorpseForecast.new()
	raise_value.actor_id = actor_id
	raise_value.reason = &"raise/no_corpse"
	raise_value.corpses = {42: {"before": {"cell": Vector2i(2, 3)}, "after": null}}
	raise_value.units = {999: {"before": null, "after": _unit(999)},
		actor_id: {"before": _unit(actor_id), "after": _after(actor_id)}}
	demo._raise_forecast = raise_value
	demo._raise_forecast_cell = Vector2i(2, 3)
	for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
		raise_value.status = status
		_observe("raise %s" % status, &"_render_raise_forecast_panel", raise_value)
	_reset()
	var armor := ForecastSimulation.new()
	armor.units_before = {actor_id: _unit(actor_id)}
	armor.units_after = {actor_id: _after(actor_id)}
	armor.events = [{"kind": &"armor_changed", "items": [{"id": 7, "before": 2, "after": 5}], "grants": [{"before": 0, "after": 4}]}]
	demo._armor_forecast = armor
	demo._armor_forecast_actor = actor_id
	for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
		armor.status = status
		_observe("armor %s" % status, &"_render_armor_forecast_panel", armor)

func _spell_cases() -> void:
	for effect: StringName in [&"burning", &"mage.fire", &"mage.test_summon"]:
		_reset()
		var value := ForecastSimulation.new()
		value.reason = &"mage/cooldown"
		value.units_before = {actor_id: _unit(actor_id), target_id: _unit(target_id)}
		value.units_after = {actor_id: _after(actor_id), target_id: _after(target_id)}
		value.events = _events()
		value.snapshot_before = {"abilities": demo.session.state.abilities.to_dict()}
		value.snapshot_after = value.snapshot_before.duplicate(true)
		demo._elemental_forecast = value
		demo._action_forecast_effect = effect
		demo._action_forecast_actor = actor_id
		demo._action_forecast_target_id = target_id
		demo._action_forecast_cell = Vector2i(2, 3)
		for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
			value.status = status
			_observe("elemental %s %s" % [effect, status], &"_render_elemental_forecast_panel", value)
		value.snapshot_after = {}
		_observe("elemental damaged abilities %s" % effect, &"_render_elemental_forecast_panel", value)
	for effect: StringName in [&"card.fire", &"card.summon", &"card.raise", &"unknown"]:
		demo._action_forecast_kind = &"mage_card"
		demo._action_forecast_effect = effect
		demo._action_forecast_card_id = 17
		for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
			demo._elemental_forecast.status = status
			demo._elemental_forecast.snapshot_after = demo._elemental_forecast.snapshot_before.duplicate(true)
			_observe("card %s %s" % [effect, status], &"_render_elemental_forecast_panel", demo._elemental_forecast)
		demo._elemental_forecast.snapshot_after = {}
		_observe("card damaged abilities %s" % effect, &"_render_elemental_forecast_panel", demo._elemental_forecast)

func _phase_cases() -> void:
	_reset()
	demo._environment_forecast_pending = true
	_observe("environment pending", &"_render_environment_forecast")
	demo._environment_forecast_pending = false
	var environment := ForecastSimulation.new()
	environment.units_before = {target_id: _unit(target_id), actor_id: _unit(actor_id)}
	environment.units_after = {target_id: _after(target_id), actor_id: _after(actor_id)}
	environment.events = _events()
	demo._environment_forecast = environment
	for status: StringName in [ActionReceipt.REJECTED, ActionReceipt.APPLIED]:
		environment.status = status
		_observe("environment %s" % status, &"_render_environment_forecast", environment)
	_reset()
	demo._turn_forecast_pending = true
	_observe("turn pending", &"_render_turn_forecast")
	demo._turn_forecast_pending = false
	var turn := TurnForecast.new()
	turn.units_before = environment.units_before.duplicate(true)
	turn.units_after = environment.units_after.duplicate(true)
	# Отсутствующее имя проверяет прежний live fallback; другой ID хранит DTO-имя.
	turn.units_before[actor_id].erase("name")
	turn.events = _events()
	demo._turn_forecast = turn
	_observe("turn rejected", &"_render_turn_forecast", turn)
	turn.status = ActionReceipt.APPLIED
	for phase: int in [-1, BattleTacticalSession.Phase.ENEMY_TURN, BattleTacticalSession.Phase.VICTORY,
		BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]:
		turn.phase_after = phase
		_observe("turn phase %d" % phase, &"_render_turn_forecast", turn)

func _reason_cases(tactical: bool) -> void:
	demo.tactical_mode = tactical
	for reason: StringName in [
		&"raise_shields/cooldown", &"raise_shields/already_active", &"raise_shields/insufficient_main", &"raise_shields/not_owned",
		&"mage/cooldown", &"mage/insufficient_mana", &"mage/full_hp", &"mage/invalid_target",
		&"mage/invalid_summon_owner", &"mage/window_closed", &"mage/terminal", &"perks/stunning_strike_required",
		&"perks/not_owned", &"guard/already_active", &"guard/insufficient_main", &"control/stun_immune",
		&"control/entangle_immune", &"control/stunned", &"control/frozen", &"status/insufficient_main",
		&"status/dead_target", &"status/not_admitted", &"status/stale_revision", &"status/capability_required",
		&"control/entangled", &"control/capability_required", &"armor/summon_unsupported", &"armor/zero_restore",
		&"armor/full", &"attack/insufficient_main", &"battle/input_locked", &"battle/friendly_target",
		&"move/insufficient_move", &"move/insufficient_main", &"move/actor_dead", &"move/actor_displaced",
		&"move/path_blocked", &"move/budget_exhausted", &"attack/out_of_reach", &"attack/not_aligned",
		&"move/unreachable", &"move/no_selected_unit", &"attack/no_selected_unit", &"attack/self_target",
		&"attack/line_blocked", &"attack/terrain_shape_unsupported", &"attack/stale_revision", &"attack/missing_target",
		&"attack/invalid_target", &"attack/dead_target", &"BUSY", &"CONTEXT_FAULTED",
		&"summon/active_helper", &"summon/invalid_cell", &"environment/no_corpse", &"environment/invalid_raise_cell",
		&"summon/helper_cannot_summon", &"item/full_hp", &"item/no_charges", &"item/insufficient_main",
		&"item/not_owned", &"item/inactive", &"item/not_usable", &"item/no_selected_unit",
		&"item/not_admitted", &"item/stale_revision", &"item/invalid_runtime", &"item/invalid_mutation",
		&"guard/no_selected_unit", &"guard/not_admitted", &"guard/stale_revision", &"guard/invalid_runtime",
		&"attack/no_reachable_position", &"perks/invalid_cover_target", &"perks/movement_stopped", &"perks/opportunist_stopped",
		&"perks/invalid_mode", &"preview/rng_not_cloneable", &"preview/rng_state_mismatch", &"preview/unsupported_worker_rng",
		&"preview/unsupported_rng", &"turn/unsupported_session", &"turn/unsupported_runtime", &"turn/unsupported_phase",
		&"turn/not_transitioned", &"turn/faulted", &"preview/worker_unavailable", &"command_limit",
		&"event_limit", &"depth_limit", &"sequence_exhausted", &"unlisted/reason",
	]:
		actual.append({"label": "_reason_text %s %s" % [tactical, reason], "text": demo._reason_text(reason)})
	for reason: StringName in [
		&"control/dead_target", &"control/stun_immune", &"control/entangle_immune", &"unlisted/reason",
	]:
		actual.append({"label": "_control_skip_text %s %s" % [tactical, reason], "text": demo._control_skip_text(reason)})
	for reason: StringName in [
		&"bleeding/immune", &"bleeding/dead_target", &"bleeding/burning", &"unlisted/reason",
	]:
		actual.append({"label": "_bleeding_skip_text %s %s" % [tactical, reason], "text": demo._bleeding_skip_text(reason)})
	demo.tactical_mode = false
