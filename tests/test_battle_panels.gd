extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport
var demo: BattleDemo

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL BATTLE PANELS: " + label)

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()

func player_session() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s._enemy_index = s._enemy_ids.size(); s.step_enemy()
	for unit: UnitState in s.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0); unit.vitals.set_hp(80.0)
		unit.control.stunned_turns = 0; unit.control.entangled_turns = 0
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	return s

func run() -> void:
	for spell: StringName in AbilityDefinition.TEST_EFFECTS:
		var s := player_session()
		var target := s.units[1]
		if spell == &"mage.test_freeze": target.elemental.wet_turns = 3
		var before := snapshot(s)
		var rng := s.context.get_rng().to_dict()
		var main_before := s.units[0].action_resources.get_main_left()
		var forecast := ForecastSimulation.run_prepared(s.prepare_mage_forecast(spell, target.id))
		check(forecast.status == ActionReceipt.APPLIED, "%s forecast applied: %s" % [spell, forecast.reason])
		check(snapshot(s) == before and s.context.get_rng().to_dict() == rng, "%s forecast isolates live" % spell)
		var worker := BattleExecutionWorker.new()
		check(worker.start(s, &"cast_mage_spell", [spell, target.id]), "%s transfers to worker" % spell)
		var completed := worker.take_finished(true)
		var receipt: ActionReceipt = completed.get("result")
		check(receipt != null and receipt.status == ActionReceipt.APPLIED, "%s live applied" % spell)
		if receipt != null:
			check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "%s preview/live parity" % spell)
		check(s.state.abilities.mana == 5 and s.state.abilities.ledger.is_empty() and s.units[0].action_resources.get_main_left() == main_before, "%s pays only mage mana" % spell)
		var entries := BattleStatusPresentation.entries({"elemental": target.elemental.to_dict(), "control": target.control.to_dict(), "bleeding": target.bleeding.to_dict()})
		check(not entries.is_empty(), "%s visible status" % spell)
		s.close()
	var s := player_session()
	var ally := s.units[0]
	var enemy := s.units[1]
	check(s.cast_mage_spell(&"mage.test_roots", ally.id).status == ActionReceipt.APPLIED and ally.control.entangled_turns == 1, "test spells can target allies")
	var immune := s.units[3]
	var before := snapshot(s)
	check(s.cast_mage_spell(&"mage.test_stun", immune.id).status == ActionReceipt.REJECTED and snapshot(s) == before, "stun immunity rejects before payment")
	check(s.cast_mage_spell(&"mage.test_bleeding", enemy.id).status == ActionReceipt.APPLIED, "bleeding first stack")
	check(s.cast_mage_spell(&"mage.test_bleeding", enemy.id).status == ActionReceipt.APPLIED and enemy.bleeding.stacks == 2 and enemy.bleeding.ticks_left == 3, "bleeding stack differs from duration")
	check(s.cast_mage_spell(&"mage.test_burning", enemy.id).status == ActionReceipt.APPLIED and enemy.bleeding.stacks == 0, "burn clears bleeding through guarded write")
	before = snapshot(s)
	check(s.cast_mage_spell(&"mage.test_bleeding", enemy.id).status == ActionReceipt.REJECTED and snapshot(s) == before, "burn blocks bleeding without payment")
	check(s.cast_mage_spell(&"mage.test_wet", enemy.id).status == ActionReceipt.APPLIED and enemy.elemental.burning_stacks == 0, "water extinguishes mage burn")
	s.close()
	s = player_session()
	# Каталог двух базовых заклинаний остаётся допустимым снимком без миграции.
	for index: int in range(s.state.abilities.catalog.size() - 1, -1, -1):
		if AbilityDefinition.TEST_EFFECTS.has(s.state.abilities.catalog[index].ability_id): s.state.abilities.catalog.remove_at(index)
	check(BattleAbilityState.valid(s.state.abilities.to_dict()), "old catalog remains valid")
	check(s.cast_mage_spell(&"mage.test_roots", s.units[1].id).reason == &"mage/unknown_spell", "optional catalog required")
	s.close()
	s = player_session()
	enemy = s.units[1]
	s.cast_mage_spell(&"mage.test_bleeding", enemy.id)
	var command := MageCastCommand.new(&"mage.test_burning", enemy.id, s.context.get_revision())
	enemy.elemental.changed.connect(func() -> void: command.target_id = s.units[0].id)
	var fault := command.execute(s.context)
	check(fault.status == &"FAULTED" and enemy.elemental.burning_stacks == 1 and enemy.bleeding.stacks == 1 and s.state.abilities.mana == 4, "callback seal fault stops before second status write, keeps paid prefix")
	s.close()
	await ui_and_areas()
	print("BATTLE PANELS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func area_for(id: int, rows: Array[Dictionary]) -> Dictionary:
	for area: Dictionary in rows:
		if area.owner_id == id: return area
	return {}

func ui_and_areas() -> void:
	viewport = SubViewport.new(); viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false; viewport.add_child(demo); demo.set_process(false)
	viewport.notify_mouse_entered()
	demo.session.close(); demo.session = player_session(); demo._battle = demo.session as BattleCoreReactionsSession; demo.board_view.session = demo.session
	var s := demo.session as BattleCoreReactionsSession
	var ally := s.units[0]; var enemy := s.units[1]
	s.selected_id = ally.id
	ally.guard_stance = true; enemy.guard_stance = true
	ally.combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST; enemy.combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
	ally.combat_perks.reaction_left = 1; enemy.combat_perks.reaction_left = 1
	demo._refresh(); await process_frame; await process_frame
	check(demo._action_bar._buttons.size() == 4 and demo._action_bar._page == 0, "main four slots no pages")
	check(demo._action_bar.get_global_rect().end.x <= demo.board_view.global_position.x, "character slots left of field")
	check(demo._action_bar._buttons[3].global_position.y > demo._action_bar._buttons[0].get_global_rect().end.y, "slots vertical")
	check(demo._mage_row.global_position.y >= demo.board_view.get_global_rect().end.y and demo._mage_buttons.size() == 8, "eight mage spells below field")
	check(demo._mage_row.get_global_rect().end.x <= viewport.size.x and demo._instructions.get_global_rect().end.y <= viewport.size.y, "panels fit 1280x850")
	check(demo.board_view.grid_config.tile_size == Vector2(128,64), "panels preserve fixed tiles")
	var areas := demo.board_view.action_areas
	check(area_for(ally.id, areas).ready and area_for(enemy.id, areas).ready, "both ready factions shown")
	check(area_for(ally.id, areas).faction == Faction.Type.PLAYER and area_for(enemy.id, areas).faction == Faction.Type.ENEMY and BattleDemoBoard.ALLY_AREA != BattleDemoBoard.ENEMY_AREA, "side colors separate")
	check(demo.board_view.area_details(enemy.cell).contains(enemy.debug_name), "area inspection names source")
	var saved := ActionPresentationState.capture(s.state)
	enemy.combat_perks.reaction_left = 0
	check(not area_for(enemy.id, ActionPresentationState.capture_action_areas(s.state)).ready, "spent reaction removes active zone")
	demo.board_view.show_presentation_state(saved)
	check(area_for(enemy.id, demo.board_view.action_areas).ready, "presentation uses copied readiness")
	enemy.combat_perks.reaction_left = 1; enemy.control.stunned_turns = 1
	check(area_for(enemy.id, ActionPresentationState.capture_action_areas(s.state)).is_empty(), "stun removes area")
	enemy.control.stunned_turns = 0; enemy.elemental.frozen_turns = 2
	check(area_for(enemy.id, ActionPresentationState.capture_action_areas(s.state)).is_empty(), "freeze removes area")
	enemy.elemental.frozen_turns = 0
	ally.guard_stance = false
	demo._refresh(); demo._action_bar_hovered(&"opportunity_guard")
	check(demo.board_view.area_preview_owner == ally.id and not area_for(ally.id, demo.board_view.action_areas).ready, "hover potential separate from ready reaction")
	demo._action_bar_hover_left(&"opportunity_guard")
	check(demo.board_view.area_preview_owner == UnitId.NONE, "preview clears on leave")
	ally.guard_stance = true
	demo._refresh(); demo.board_view.zoom_camera(0.75, demo.board_view.size * 0.5)
	await capture("panels-and-zones-75")
	for spell: StringName in AbilityDefinition.TEST_EFFECTS:
		s.state.abilities.mana = 6
		enemy.elemental = ElementalState.new(); enemy.control.stunned_turns = 0; enemy.control.entangled_turns = 0
		enemy.bleeding = BleedingState.new(); enemy.bleeding.stacked = true
		if spell == &"mage.test_freeze": enemy.elemental.wet_turns = 3
		demo._refresh()
		var button: Button = demo._mage_buttons[spell]
		await click(button.global_position + button.size * 0.5)
		check(s.elemental_selected == spell, "UI selects " + String(spell))
		await click(demo.board_view.global_position + demo.board_view.cell_center(enemy.cell))
		check(s.state.abilities.mana == 5 and not demo.board_view.displayed_unit_summary(enemy.id).is_empty(), "UI applies " + String(spell))
	await capture("test-bleeding-panel")
	demo.queue_free(); await process_frame; viewport.queue_free(); await process_frame

func click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position
	viewport.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true); event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
