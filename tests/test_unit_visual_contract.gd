extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/placeholder_unit.tscn")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL UNIT VISUAL CONTRACT: " + label)

func _values() -> Dictionary:
	var statuses: Array[Dictionary] = [{"id": "frozen", "title": "Заморожен", "stacks": 0,
		"remaining": 1, "duration_unit": "концов хода своей команды", "embodied": true}]
	return {
		"cell": Vector2i(2, 3), "half_steps": 3,
		"unit": {"id": 17, "faction": int(Faction.Type.PLAYER), "name": "Астра", "alive": true,
			"hp": 18.0, "hp_max": 24.0, "balance": 3.0, "balance_max": 5.0},
		"visual_class_id": &"warrior", "selected": true, "inspected": false, "hovered": false,
		"acting": false, "show_rear": true, "summon_pending": false,
		"forecast_entry": {"after": {"hp": 16.0}},
		"armor_values": {"current": 2.0, "maximum": 4.0},
		"shield_view": {"active": true, "hp": 4}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 1, "ready": true, "charge": 1},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0},
		"status_entries": statuses,
	}

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	root.add_child(viewport)
	var visual := UNIT_SCENE.instantiate() as BattleManagedUnitVisual
	check(visual != null, "placeholder scene creates the managed unit visual")
	if visual == null:
		viewport.queue_free()
		await process_frame
		quit(1)
		return
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.modulate = Color("d9c8b5")
	var authored_modulate := visual.modulate
	viewport.add_child(visual)
	await process_frame
	check(visual.get_node_or_null("StatusHud") != null, "unit role is set before add so ready creates StatusHud")
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 32.0
	config.origin_offset = Vector2(300.0, 240.0)
	var values := _values()
	var pristine_values: Dictionary = values.duplicate(true)
	check(visual.apply_view(values, config) and visual.view_apply_count == 1, "first value snapshot is applied")
	check(visual.unit != null and visual.unit.id == 17 and visual.unit.debug_name == "Астра" and visual.unit.hp == 18.0,
		"unit view is built from published scalar values")
	check(visual.status_text == "Заморожен" and visual.frozen and not visual.stunned and not visual.entangled,
		"status summary and control flags match the published entries")
	check(not visual.apply_view(pristine_values, config) and visual.view_apply_count == 1,
		"identical values and geometry skip scene art synchronization")
	values.forecast_entry.after.hp = 1.0
	values.armor_values.current = 0.0
	values.reaction_view.charge = 0
	values.action_resources_view.main = 0
	values.status_entries[0].title = "изменено снаружи"
	values.unit.hp = 0.0
	values.unit.name = "изменено снаружи"
	check(visual.forecast_entry.after.hp == 16.0 and visual.armor_values.current == 2.0
		and visual.reaction_view.charge == 1 and visual.action_resources_view.main == 1
		and visual.status_entries[0].title == "Заморожен" and visual.unit.hp == 18.0
		and visual.unit.debug_name == "Астра",
		"published dictionaries and arrays are detached from caller values")
	var count_before_repair := visual.view_apply_count
	visual.hovered = true
	visual.acting = true
	visual.unit.hp = 1.0
	visual.forecast_entry.after.hp = 0.0
	visual.reaction_view.charge = 0
	visual.action_resources_view.main = 0
	visual.grid_anchor = Vector2i(99, 99)
	visual.half_steps = 88
	visual.height_level = 7
	visual.position = Vector2(999.0, 999.0)
	visual.role = BattleDemoIsoVisual.Role.FLOOR
	check(visual.apply_view(pristine_values, config) and visual.view_apply_count == count_before_repair + 1,
		"apply repairs actual visual fields even when incoming snapshot matches the prior one")
	check(not visual.hovered and not visual.acting and visual.unit.hp == 18.0
		and visual.forecast_entry.after.hp == 16.0 and visual.reaction_view.charge == 1
		and visual.action_resources_view.main == 1,
		"apply restores changed scalar, status-related and value collections")
	var expected_position := IsoGridUtils.grid_to_screen(Vector2i(2, 3), config, 0)
	check(visual.role == BattleDemoIsoVisual.Role.UNIT and visual.half_steps == 3
		and visual.grid_anchor == Vector2i(2, 3) and visual.height_level == 0
		and visual.position == expected_position,
		"apply restores role and geometry after external pose changes")
	var count_before_values := visual.view_apply_count
	var changed_values: Dictionary = pristine_values.duplicate(true)
	changed_values.unit.hp = 15.0
	check(visual.apply_view(changed_values, config) and visual.view_apply_count == count_before_values + 1
		and visual.unit.hp == 15.0, "scalar unit change synchronizes scene art")
	var stunned_status: Array[Dictionary] = [{"id": "stunned", "title": "Оглушён", "stacks": 0,
		"remaining": 1, "duration_unit": "до конца ближайшего хода своей команды", "embodied": true}]
	changed_values.status_entries = stunned_status
	check(visual.apply_view(changed_values, config) and visual.stunned and not visual.frozen
		and visual.status_text == "Оглушён", "status change synchronizes summary and flags")
	changed_values.reaction_view.charge = 0
	changed_values.action_resources_view.bonus = 1
	check(visual.apply_view(changed_values, config) and visual.reaction_view.charge == 0
		and visual.action_resources_view.bonus == 1, "reaction and action-resource changes synchronize")
	var count_before_config := visual.view_apply_count
	config.tile_size = Vector2(144.0, 108.0)
	config.height_step = 40.0
	config.origin_offset = Vector2(320.0, 250.0)
	check(visual.apply_view(changed_values, config) and visual.view_apply_count == count_before_config + 1,
		"in-place grid configuration changes are detected by value")
	visual.action_offset = Vector2(5.0, -3.0)
	visual.presentation_lift = 8.0
	visual.presentation_offset = Vector2(2.0, 1.0)
	visual.fall_drop = 4.0
	visual.landing_compression = 0.2
	visual.death_progress = 0.4
	visual.transient_label = "временная подпись"
	visual.modulate = Color.RED
	visual.reset_view_pose()
	check(visual.action_offset == Vector2.ZERO and visual.presentation_lift == 0.0
		and visual.presentation_offset == Vector2.ZERO and visual.fall_drop == 0.0
		and visual.landing_compression == 0.0 and visual.death_progress == 0.0
		and visual.transient_label.is_empty() and visual.modulate == authored_modulate,
		"pose reset clears scene-owned animation and restores authored modulation")
	visual.role = BattleDemoIsoVisual.Role.PLATFORM
	visual.half_steps = -4
	visual.grid_anchor = Vector2i(9, 9)
	visual.height_level = 3
	visual.position = Vector2(-99.0, -99.0)
	var count_before_pose_repair := visual.view_apply_count
	check(visual.apply_view(changed_values, config) and visual.view_apply_count == count_before_pose_repair + 1
		and visual.half_steps == 3 and visual.grid_anchor == Vector2i(2, 3)
		and visual.height_level == 0 and visual.position == IsoGridUtils.grid_to_screen(Vector2i(2, 3), config, 0),
		"identical values resynchronize when pose geometry was changed")
	var count_before_identical := visual.view_apply_count
	check(not visual.apply_view(changed_values, config) and visual.view_apply_count == count_before_identical,
		"repaired visual again skips identical apply")
	visual.retire_view()
	check(visual.unit == null and visual.forecast_entry.is_empty() and visual.status_entries.is_empty()
		and not visual._view_initialized and is_instance_valid(visual) and visual.get_parent() == viewport,
		"retirement clears detached values without freeing the visual")
	viewport.queue_free()
	await process_frame
	print("UNIT VISUAL CONTRACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
