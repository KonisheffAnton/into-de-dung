extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport
var demo: BattleDemo

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL MAGE R14: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "snapshot capture: " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	var players := session.living_ids(Faction.Type.PLAYER)
	if not players.is_empty(): session.selected_id = players[0]
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.vitals.set_hp(80.0)
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.elemental.frozen_turns = 0
	return session

func adjacent_safe_cell(session: BattleCoreReactionsSession, owner: UnitState) -> Vector2i:
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell := owner.cell + direction
		if not session.board.is_in_bounds(cell) or session.board.is_occupied(cell): continue
		if not session.board.is_terrain_walkable(cell) or session.board.is_lethal(cell): continue
		if session.board.get_height_steps(cell) != session.board.get_height_steps(owner.cell): continue
		if not session.state.environment.fire_at(cell).is_empty(): continue
		return cell
	return Vector2i(-1, -1)

func _run() -> void:
	await _heal_preview_live()
	await _summon_preview_live_and_pending()
	await _raise_preview_live_and_corpse()
	await _production_factory_artifacts()
	_rejections_are_immutable()
	_fault_keeps_paid_spawn_prefix()
	_team_summons_codec_and_zone()
	_anchor_does_not_define_helper()
	await _page_two_ui()
	print("MAGE R14 RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _heal_preview_live() -> void:
	var session := fixture()
	var owner := session.board.get_unit_by_id(session.selected_id)
	owner.vitals.apply_damage(12.0)
	var hp_before := owner.vitals.get_hp()
	var main_before := owner.action_resources.get_main_left()
	var bonus_before := owner.action_resources.get_bonus_left()
	var move_before := owner.move_points_left
	var before := snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var admission_before := SummonAdmission.values(session.context)
	var prepared := session.prepare_mage_forecast(&"mage.test_heal", owner.id)
	var preview := ForecastSimulation.run_prepared(prepared)
	check(preview.status == ActionReceipt.APPLIED, "test heal forecast: " + String(preview.reason))
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng_before
		and session.context.simulation_counters() == counters_before and SummonAdmission.values(session.context) == admission_before,
		"heal preview leaves all live state isolated")
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"cast_mage_spell", [&"mage.test_heal", owner.id]), "heal transfers to execution worker")
	var completed := worker.take_finished(true)
	var receipt: ActionReceipt = completed.get("result")
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, "worker heal applies")
	if receipt != null:
		check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
			and snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after
			and session.context.simulation_counters() == preview.counters_after
			and SummonAdmission.values(session.context) == preview.admission_after,
			"heal worker/live matches preview snapshot, events, steps, RNG, counters and admission")
		var cast := find_event(receipt.get_events(), &"mage_cast")
		check(cast.get("source", {}).get("source_instance_id", 0) == 9, "test heal uses stable mage source 9")
	check(is_equal_approx(owner.vitals.get_hp(), hp_before + 4.0), "test heal restores exactly four HP")
	check(owner.action_resources.get_main_left() == main_before and owner.action_resources.get_bonus_left() == bonus_before
		and is_equal_approx(owner.move_points_left, move_before), "heal consumes no hero action resource")
	check(session.state.abilities.mana == int(before.get("abilities", {}).get("mana", 0)) - 1 and session.state.abilities.remaining(&"mage.test_heal") == 0,
		"heal spends one mana with no cooldown")
	check(snapshot(session).get("owners", []) == before.get("owners", []), "heal does not alter item owners or charges")
	session.close()

func _summon_preview_live_and_pending() -> void:
	var session := fixture()
	var owner := session.board.get_unit_by_id(session.selected_id)
	owner.control.stunned_turns = 1
	owner.elemental.frozen_turns = 2
	owner.action_resources._set_for_refill(0, 0)
	owner.move_points_left = 0.0
	var action_before := owner.action_resources.to_snapshot_dict()
	var move_before := owner.move_points_left
	var cell := adjacent_safe_cell(session, owner)
	check(cell != Vector2i(-1, -1), "summon fixture finds safe adjacent cell")
	var before := snapshot(session)
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(&"mage.test_summon", cell))
	check(preview.status == ActionReceipt.APPLIED, "summon allowed for controlled owner without hero actions: " + String(preview.reason))
	check(snapshot(session) == before, "summon preview leaves live state untouched")
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"cast_mage_cell", [&"mage.test_summon", cell]), "summon transfers to execution worker")
	var completed := worker.take_finished(true)
	var receipt: ActionReceipt = completed.get("result")
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, "worker summon applies")
	var summoned := find_event(receipt.get_events() if receipt != null else [], &"mage_summoned")
	if receipt != null:
		check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
			and snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after
			and session.context.simulation_counters() == preview.counters_after
			and SummonAdmission.values(session.context) == preview.admission_after,
			"summon worker/live matches preview snapshot, events, steps, RNG, counters and admission")
		check(find_event(receipt.get_events(), &"mage_cast").get("source", {}).get("source_instance_id", 0) == 10,
			"test summon uses stable mage source 10")
	check(summoned.get("owner_unit_id", -1) == 0 and summoned.get("anchor_unit_id", 0) > 0 and summoned.get("actor_unit_id", -1) == 0
		and summoned.get("corpse_id", -1) == 0 and summoned.get("cell", Vector2i(-1, -1)) == cell,
		"summon event binds allied anchor and destination without owner")
	var helper := session.board.get_unit_by_id(int(summoned.get("target_unit_id", 0)))
	check(helper != null and session.state.is_summon_pending(helper.id), "summoned helper is pending until next own turn")
	check(owner.action_resources.to_snapshot_dict() == action_before and is_equal_approx(owner.move_points_left, move_before),
		"summon does not spend main, bonus, movement or other hero actions")
	check(session.state.abilities.mana == int(before.get("abilities", {}).get("mana", 0)) - 1 and session.state.abilities.remaining(&"mage.test_summon") == 0,
		"summon spends one mana and has no cooldown")
	if helper != null:
		var player_ids := session.living_ids(Faction.Type.PLAYER)
		if player_ids.size() > 1: check(session.select_unit(player_ids[1]), "select another original for next turn boundary")
	check(session.end_player_turn(), "end player turn after summon")
	for _step: int in range(80):
		if session.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and helper != null
		and not session.state.is_summon_pending(helper.id), "summon activates on next player turn")
	session.close()

func _raise_preview_live_and_corpse() -> void:
	var session := fixture()
	var owner := session.board.get_unit_by_id(session.selected_id)
	var fallen := session.units[1]
	var corpse_cell := adjacent_safe_cell(session, owner)
	check(corpse_cell != Vector2i(-1, -1), "raise fixture finds safe adjacent cell")
	check(session.board.move_unit(fallen, corpse_cell), "place future corpse beside owner")
	var death := session._queue.submit(DeathCommand.new(fallen.id, DamageSource.new(&"test", 0, corpse_cell)), session.context)
	check(death.status == ActionReceipt.APPLIED, "create humanoid corpse through death command")
	owner.action_resources._set_for_refill(0, 0)
	owner.control.stunned_turns = 1
	var action_before := owner.action_resources.to_snapshot_dict()
	var cell := corpse_cell
	var before := snapshot(session)
	var found_corpses := session.state.environment.corpses_at(cell)
	if found_corpses.is_empty():
		check(false, "death command leaves a humanoid corpse on the expected cell")
		session.close()
		return
	var corpse_id: int = found_corpses[0].id
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(&"mage.test_raise", cell))
	check(preview.status == ActionReceipt.APPLIED, "raise forecast applies: " + String(preview.reason))
	check(snapshot(session) == before, "raise preview leaves live corpse and state untouched")
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"cast_mage_cell", [&"mage.test_raise", cell]), "raise transfers to execution worker")
	var completed := worker.take_finished(true)
	var receipt: ActionReceipt = completed.get("result")
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, "worker raise applies")
	var raised := find_event(receipt.get_events() if receipt != null else [], &"mage_summoned")
	if receipt != null:
		check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
			and snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after
			and session.context.simulation_counters() == preview.counters_after
			and SummonAdmission.values(session.context) == preview.admission_after,
			"raise worker/live matches preview snapshot, events, steps, RNG, counters and admission")
		check(find_event(receipt.get_events(), &"mage_cast").get("source", {}).get("source_instance_id", 0) == 11,
			"test raise uses stable mage source 11")
	check(raised.get("corpse_id", 0) == corpse_id and raised.get("owner_unit_id", -1) == 0 and raised.get("anchor_unit_id", 0) > 0
		and raised.get("cell", Vector2i(-1, -1)) == cell, "raise event consumes selected body without owner")
	check(session.state.environment.corpses_at(cell).is_empty() and not session.state.get_summons().is_empty(),
		"raise consumes one body and installs the active helper")
	check(owner.action_resources.to_snapshot_dict() == action_before, "raise spends no hero resources despite disabled actor")
	session.close()

func _production_factory_artifacts() -> void:
	var profile := HeroHubState.create(338)
	profile.party = [4, 2, 3]
	profile = ExpeditionTransitions.apply(profile, "start").profile
	profile = ExpeditionTransitions.apply(profile, "choose", {"node": 1}).profile
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "production expedition factory supplies H1/U14 fixture")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	check(session.start_battle(), "production expedition session starts")
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	var owner_id: int = bundle.hero_units[4]
	var owner := session.board.get_unit_by_id(owner_id)
	check(owner != null and owner.faction == Faction.Type.PLAYER and session.state.artifacts != null,
		"real production mage and artifacts exist")
	if owner == null or session.state.artifacts == null:
		session.close()
		return
	session.selected_id = owner_id
	var target_cell := adjacent_safe_cell(session, owner)
	check(target_cell != Vector2i(-1, -1), "production mage has a safe adjacent cell")
	if target_cell == Vector2i(-1, -1):
		session.close()
		return
	var before := snapshot(session)
	check(before.get("artifacts", {}).size() > 0, "production snapshot carries artifacts")
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(&"mage.test_summon", target_cell))
	check(preview.status == ActionReceipt.APPLIED, "artifacts snapshot accepts mage summon preview: " + String(preview.reason))
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"cast_mage_cell", [&"mage.test_summon", target_cell]), "production artifact session transfers to worker")
	var completed := worker.take_finished(true)
	var receipt: ActionReceipt = completed.get("result")
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, "production artifact session summons successfully")
	if receipt != null:
		check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
			and snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after
			and session.context.simulation_counters() == preview.counters_after
			and SummonAdmission.values(session.context) == preview.admission_after,
			"H1/U14 artifact worker/live matches complete mage preview")
	session.close()

func _rejections_are_immutable() -> void:
	var session := fixture()
	var owner := session.board.get_unit_by_id(session.selected_id)
	owner.vitals.set_hp(owner.get_stat(StatTypes.StatType.HP_MAX))
	var full_before := snapshot(session)
	var full := session.cast_mage_spell(&"mage.test_heal", owner.id)
	check(full.status == ActionReceipt.REJECTED and snapshot(session) == full_before, "full HP heal rejects without mutation")
	owner.vitals.set_hp(80.0)
	var safe_cell := adjacent_safe_cell(session, owner)
	var invalid_cell := Vector2i(-1, 2)
	_rejected_cell(session, &"mage.test_summon", invalid_cell, "out-of-bounds summon cell")
	_rejected_cell(session, &"mage.test_raise", safe_cell, "raise without a corpse")
	var enemy_id: int = session.living_ids(Faction.Type.ENEMY)[0]
	var enemy := session.board.get_unit_by_id(enemy_id)
	var original_selected := session.selected_id
	session.selected_id = enemy.id
	_rejected_cell(session, &"mage.test_summon", adjacent_safe_cell(session, enemy), "cell outside allied zone")
	session.selected_id = original_selected
	var before := snapshot(session)
	var counters := session.context.simulation_counters()
	var rng := session.context.get_rng().to_dict()
	var admission := SummonAdmission.values(session.context)
	session.state.abilities.mana = 0
	before = snapshot(session)
	counters = session.context.simulation_counters()
	rng = session.context.get_rng().to_dict()
	admission = SummonAdmission.values(session.context)
	var no_mana := session.cast_mage_cell(&"mage.test_summon", safe_cell)
	check(no_mana.status == ActionReceipt.REJECTED and _unchanged(session, before, counters, rng, admission), "no mana rejects without mutation")
	var serial := session.state.abilities.serials[Faction.Type.PLAYER]
	var closed_values := session.state.abilities.boundary(&"close", Faction.Type.PLAYER, serial)
	check(not closed_values.is_empty(), "close current mage window through ability boundary")
	session.state.abilities.apply_values(closed_values)
	before = snapshot(session)
	counters = session.context.simulation_counters()
	rng = session.context.get_rng().to_dict()
	admission = SummonAdmission.values(session.context)
	var closed := session.cast_mage_cell(&"mage.test_summon", safe_cell)
	check(closed.status == ActionReceipt.REJECTED and _unchanged(session, before, counters, rng, admission), "closed mage window rejects without mutation")
	session.close()
	session = fixture()
	owner = session.board.get_unit_by_id(session.selected_id)
	safe_cell = adjacent_safe_cell(session, owner)
	var active_receipt := session.cast_mage_cell(&"mage.test_summon", safe_cell)
	check(active_receipt.status == ActionReceipt.APPLIED, "active helper rejection fixture")
	var second_cell := adjacent_safe_cell(session, owner)
	before = snapshot(session)
	counters = session.context.simulation_counters()
	rng = session.context.get_rng().to_dict()
	admission = SummonAdmission.values(session.context)
	var active := session.cast_mage_cell(&"mage.test_summon", second_cell)
	check(active.status == ActionReceipt.APPLIED and session.state.get_summons().size() == 2 and session.state.active_summon(owner.id) == null, "two supreme mage summons have no owner limit")
	var revision := session.context.get_revision()
	var stale := MageCastCommand.new(&"mage.test_summon", owner.id, revision - 1, second_cell)
	before = snapshot(session)
	counters = session.context.simulation_counters()
	rng = session.context.get_rng().to_dict()
	admission = SummonAdmission.values(session.context)
	var stale_receipt := session._queue.submit(stale, session.context)
	check(stale_receipt.status == ActionReceipt.REJECTED and _unchanged(session, before, counters, rng, admission), "stale cell cast rejects without mutation")
	session.close()

func _rejected_cell(session: BattleCoreReactionsSession, spell: StringName, cell: Vector2i, label: String) -> void:
	var before := snapshot(session)
	var counters := session.context.simulation_counters()
	var rng := session.context.get_rng().to_dict()
	var admission := SummonAdmission.values(session.context)
	var receipt := session.cast_mage_cell(spell, cell)
	check(receipt.status == ActionReceipt.REJECTED and _unchanged(session, before, counters, rng, admission), label + " rejection is immutable")

func _unchanged(session: BattleCoreReactionsSession, before: Dictionary, counters: Dictionary, rng: Dictionary, admission: Dictionary) -> bool:
	return (snapshot(session) == before and session.context.simulation_counters() == counters
		and session.context.get_rng().to_dict() == rng and SummonAdmission.values(session.context) == admission)

func _fault_keeps_paid_spawn_prefix() -> void:
	var session := fixture()
	var owner := session.board.get_unit_by_id(session.selected_id)
	var callback := func() -> void: owner.move_points_left -= 1.0
	session.board.board_changed.connect(callback)
	var receipt := session.cast_mage_cell(&"mage.test_summon", adjacent_safe_cell(session, owner))
	session.board.board_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.FAULTED and receipt.get_events().size() >= 1,
		"board callback faults after summon begins")
	check(session.state.abilities.mana == 5 and not session.state.get_summons().is_empty(),
		"fault keeps mana payment and already-written helper prefix")
	session.close()

func find_event(events: Array[Dictionary], kind: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind: return event
	return {}

func _page_two_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	viewport.notify_mouse_entered()
	var session := demo.session as BattleCoreReactionsSession
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.vitals.set_hp(80.0)
	session.selected_id = session.units[0].id
	demo._refresh()
	await process_frame
	await process_frame
	var bar := demo._mage_row as BattleMageBar
	check(bar != null and bar.get_page_count() == 2 and bar.get_page() == 0, "real mage UI exposes two pages")
	if bar == null:
		demo.queue_free(); await process_frame
		viewport.queue_free(); await process_frame
		return
	await click(bar._next_button.global_position + bar._next_button.size * 0.5)
	check(bar.get_page() == 1 and session.elemental_selected == &"", "page click changes page and clears chosen spell")
	for spell: StringName in [&"mage.test_heal", &"mage.test_summon", &"mage.test_raise", &"mage.shield"]:
		check(demo._mage_buttons.has(spell) and demo._mage_buttons[spell].visible, "%s is visible on second page" % String(spell))
	if not captures.is_empty(): await capture("mage-r14-page-2")
	var heal: Button = demo._mage_buttons.get(&"mage.test_heal")
	await click(heal.global_position + heal.size * 0.5)
	check(session.elemental_selected == &"mage.test_heal", "second-page heal button selects spell without casting")
	var ally := session.units[0]
	await click(demo.board_view.global_position + demo.board_view.cell_center(ally.cell))
	check(is_equal_approx(ally.vitals.get_hp(), 84.0) and session.state.abilities.mana == 5, "second-page heal button applies on target click")
	var shield: Button = demo._mage_buttons.get(&"mage.shield")
	await click(shield.global_position + shield.size * 0.5)
	await click(demo.board_view.global_position + demo.board_view.cell_center(ally.cell))
	check(ally.armor.shield == SpellShield.make(&"mage.shield", 6, 1) and session.state.abilities.mana == 4, "supreme mage shield button applies six HP for one mana")
	check(demo.board_view._presentation_visual(ally.id).shield_view == ally.armor.shield, "shield is published on the figure after casting")
	if not captures.is_empty(): await capture("mage-shield-applied")
	# Отказ тоже обязан описывать клеточную цель, а не старую дальность героя.
	var invalid_cell := Vector2i(session.board.width - 1, session.board.height - 1)
	demo._action_forecast_actor = ally.id
	demo._action_forecast_target_id = UnitId.NONE
	demo._action_forecast_cell = invalid_cell
	for spell: StringName in [&"mage.test_summon", &"mage.test_raise"]:
		demo._action_forecast_effect = spell
		demo._elemental_forecast = ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(spell, invalid_cell))
		demo._render_elemental_forecast_panel()
		check(demo._elemental_forecast.status == ActionReceipt.REJECTED and demo._forecast_panel.text.contains(demo._cell_name(invalid_cell)) and demo._forecast_panel.text.contains("в зоне союзников") and not demo._forecast_panel.text.contains("дальность 3"), "rejected cell spell forecast names cell and adjacency: " + String(spell))
	demo._clear_forecast()
	# Отделённый оплаченный prefix без результата проверяет только представление:
	# кольцо нельзя переносить с неизвестной клетки появления на владельца.
	var cast := {"kind": &"mage_cast", "spell_id": "mage.test_summon", "actor_unit_id": 0, "target_unit_id": ally.id,
		"root_id": 99, "command_seq": 99, "source": DamageSource.new(&"mage", 10, Vector2i(-1, -1), 0, 0).to_dict()}
	var tween := demo.board_view.animate_presentation_frame([cast], {"kind": &"mage_cast", "command_seq": 99})
	check(demo.board_view._mage_effect != null and not demo.board_view._mage_effect.show_target, "cast-only cell prefix does not mark owner as destination")
	tween.kill()
	demo.board_view.clear_presentation_effects()
	for index: int in range(session.state.abilities.catalog.size() - 1, -1, -1):
		var id := session.state.abilities.catalog[index].ability_id
		if AbilityDefinition.TEST_EFFECTS.has(id) or AbilityDefinition.TEST_SUPPORT_EFFECTS.has(id): session.state.abilities.catalog.remove_at(index)
	check(BattleAbilityState.valid(session.state.abilities.to_dict()), "true base-only catalog remains valid")
	demo._refresh()
	check(bar.get_page_count() == 1 and bar.get_page() == 0 and demo._mage_fire.visible and demo._mage_heal.visible, "base-only catalog clamps pager and keeps base spells")
	for spell: StringName in AbilityDefinition.TEST_EFFECTS.keys() + AbilityDefinition.TEST_SUPPORT_EFFECTS.keys():
		check(not demo._mage_buttons[spell].visible, "old catalog hides optional " + String(spell))
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame

func click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)


func _team_summons_codec_and_zone() -> void:
	var session := fixture()
	var original := session.selected_unit()
	var first_cell := adjacent_safe_cell(session, original)
	session.selected_id = UnitId.NONE
	var receipt := session.cast_mage_cell(&"mage.test_summon", first_cell)
	check(receipt.status == ActionReceipt.APPLIED, "supreme mage summon does not need a selected hero")
	var event := find_event(receipt.get_events(), &"mage_summoned")
	var helper := session.board.get_unit_by_id(int(event.get("target_unit_id", 0)))
	if helper == null:
		session.close(); return
	var only_helper_cell := Vector2i(-1, -1)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell := helper.cell + direction
		if not UseSummoningItemCommand.valid_cell(session.board, helper.cell, cell) or not session.state.environment.fire_at(cell).is_empty(): continue
		var original_reaches := false
		for ally: UnitState in session.board.get_all_units():
			if ally.is_alive() and ally.faction == Faction.Type.PLAYER and not session.state.is_summon(ally.id) and UseSummoningItemCommand.valid_cell(session.board, ally.cell, cell): original_reaches = true
		if not original_reaches: only_helper_cell = cell; break
	check(only_helper_cell.x >= 0, "fixture finds cell covered only by pending helper")
	if only_helper_cell.x >= 0:
		var preview := ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(&"mage.test_summon", only_helper_cell))
		receipt = session.cast_mage_cell(&"mage.test_summon", only_helper_cell)
		check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and snapshot(session) == preview.snapshot_after, "pending helper expands zone with complete preview parity")
	var saved := snapshot(session)
	check(saved.schema_version == 9 and saved.scope == ItemSimulationSnapshot.SCOPE_V9, "team summons use distinct v9 envelope")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for key: StringName in owner._definitions: definitions[key] = owner._definitions[key].duplicate(true)
	var parsed := ItemSimulationSnapshot.from_dict(saved)
	var restored := parsed.snapshot.instantiate(definitions) if parsed.snapshot != null else parsed
	check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == saved, "v9 restore preserves source pending and complete snapshot")
	if restored.state != null:
		for owner: ItemOwnerState in restored.state.get_owners(): owner.close()
	var legacy := saved.duplicate(true)
	legacy.schema_version = 7; legacy.scope = ItemSimulationSnapshot.SCOPE_V7
	check(ItemSimulationSnapshot.from_dict(legacy).code != ItemSnapshotResult.Code.OK, "legacy envelope refuses ownerless source record")
	var corrupted := saved.duplicate(true)
	corrupted.summons[0].source_kind = "unknown"
	check(ItemSimulationSnapshot.from_dict(corrupted).code != ItemSnapshotResult.Code.OK, "unknown summon source refused")
	corrupted = saved.duplicate(true); corrupted.summons[0].owner_unit_id = original.id
	check(ItemSimulationSnapshot.from_dict(corrupted).code != ItemSnapshotResult.Code.OK, "mage record cannot acquire character owner")
	var owned := MageSummonEffect.prepare_owned(session.context, helper.id, adjacent_safe_cell(session, helper), &"mage.test_summon", session.state.abilities.paid(&"mage.test_summon"))
	check(owned.reason == &"summon/helper_cannot_summon", "old owned spell still refuses a helper as owner")
	var cell_before := helper.cell
	receipt = session._queue.submit(DeathCommand.new(helper.id, DamageSource.new(&"test", 0, cell_before)), session.context)
	check(receipt.status == ActionReceipt.APPLIED and session.state.environment.corpses_at(cell_before).is_empty(), "mage helper death leaves no humanoid corpse")
	check(session.state.is_mage_summon(helper.id) and session.state.get_summons().size() >= 1, "dead team helper retains metadata for restore")
	session.close()

func _anchor_does_not_define_helper() -> void:
	for has_elemental: bool in [false, true]:
		var session := fixture()
		var cell := adjacent_safe_cell(session, session.selected_unit())
		var anchor := MageSummonEffect.zone_anchor(session.state, cell)
		check(anchor != null, "mixed-capability fixture has a zone anchor")
		if anchor == null:
			session.close(); continue
		# Среда v3 требует elemental у всех. Здесь проверяется допустимый
		# смешанный граф без этой возможности, а не повреждённая среда.
		session.state.environment = null
		anchor.elemental = ElementalState.new() if has_elemental else null
		anchor.bleeding.stacked = has_elemental
		var owned := MageSummonEffect.prepare_owned(session.context, anchor.id, cell, &"mage.test_summon", session.state.abilities.paid(&"mage.test_summon"))
		check(owned.reason == &"" and (owned.helper.elemental != null) == has_elemental, "preserved owned variant retains its original capability rule: " + String(owned.reason))
		var preview := ForecastSimulation.run_prepared(session.prepare_mage_cell_forecast(&"mage.test_summon", cell))
		var receipt := session.cast_mage_cell(&"mage.test_summon", cell)
		check(receipt.status == ActionReceipt.APPLIED and preview.status == receipt.status and receipt.get_events() == preview.events and snapshot(session) == preview.snapshot_after, "mixed-capability anchor preserves summon preview/live parity: " + String(receipt.reason) + "/" + String(preview.reason))
		var event := find_event(receipt.get_events(), &"mage_summoned")
		var helper := session.board.get_unit_by_id(int(event.get("target_unit_id", 0)))
		check(helper != null and helper.elemental != null and helper.bleeding.stacked, "supreme helper has fixed statuses regardless of anchor capabilities")
		session.close()
