extends SceneTree

class CountingEnvironment extends BattleManagedEnvironmentVisual:
	var draw_calls: int = 0

	func _draw() -> void:
		draw_calls += 1
		super._draw()

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ENVIRONMENT VISUAL CONTRACT: " + label)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var overlay_scene: PackedScene = preload("res://scenes/demo/visuals/environment_overlay.tscn")
	var overlay := overlay_scene.instantiate() as BattleManagedEnvironmentVisual
	viewport.add_child(overlay)
	var corpse: Dictionary = {"faction": 1, "nested": {"tags": ["source"]}}
	var corpses: Array[Dictionary] = [corpse]
	var values := _view_values(corpses)
	check(overlay.apply_view(values), "first apply configures the persistent scene")
	check(overlay.view_apply_count == 1, "successful apply increments the count")
	check(not overlay.apply_view(values) and overlay.view_apply_count == 1,
		"unchanged apply skips configuration and drawing")
	corpse.nested.tags[0] = "changed"
	corpses.append({"faction": 0})
	check(overlay.corpse_records.size() == 1 and overlay.corpse_records[0].nested.tags[0] == "source",
		"nested corpse values are deep copied")
	check((overlay.get_node("AcidPool") as Node2D).visible
		and (overlay.get_node("FloorTrap") as Node2D).visible
		and (overlay.get_node("WallTrapLeft") as Node2D).visible
		and not (overlay.get_node("WallTrapUp") as Node2D).visible,
		"acid, floor trap and selected wall trap follow applied values")
	check((overlay.get_node("FloorTrap/ArmedRim") as Line2D).visible,
		"armed floor trap shows its authored rim")
	check(overlay.has_spikes and overlay.has_burning_fallback and overlay.is_warning,
		"base visual flags are configured")

	var changed := _view_values(corpses)
	changed.acid = false
	changed.floor_trap = false
	changed.wall_direction = Vector2i.UP
	changed.armed = false
	changed.spikes = false
	changed.warning = false
	changed.burning = false
	check(overlay.apply_view(changed) and overlay.view_apply_count == 2,
		"changed input updates all base values")
	check(not (overlay.get_node("AcidPool") as Node2D).visible
		and not (overlay.get_node("FloorTrap") as Node2D).visible
		and (overlay.get_node("WallTrapUp") as Node2D).visible
		and not (overlay.get_node("WallTrapLeft") as Node2D).visible
		and not (overlay.get_node("FloorTrap/ArmedRim") as Line2D).visible,
		"authored children reflect changed hazard configuration")

	# Изменение свойства напрямую должно обнаруживаться по актуальному состоянию, даже без ревизии.
	overlay.acid_pool = true
	check(overlay.apply_view(changed) and not overlay.acid_pool
		and not (overlay.get_node("AcidPool") as Node2D).visible,
		"apply repairs direct base-property changes without a revision token")
	overlay.collapse_progress = 0.6
	overlay.hazard_progress = 0.4
	overlay.trap_progress = 0.8
	overlay.reset_view_pose()
	check(overlay.collapse_progress == -1.0 and overlay.hazard_progress == -1.0
		and overlay.trap_progress == -1.0 and not overlay.is_warning,
		"pose reset clears transient samples and preserves configured flags")
	var caller_copy := changed.duplicate(true)
	overlay.retire_view()
	check(overlay.corpse_records.is_empty() and changed == caller_copy,
		"retire clears owned corpse state without mutating caller values")
	check(overlay.apply_view(changed) and overlay.view_apply_count == 4,
		"retired visual initializes again on its next apply")
	overlay.sync_view_transform()
	check(true, "transform sync is safe for editor-authored overlay geometry")

	var counting := CountingEnvironment.new()
	check(counting is BattleManagedEnvironmentVisual,
		"managed lifecycle can be extended by a custom fixture")
	counting.free()
	await _test_warning_phase_optimization(overlay, viewport, corpses)
	_test_environment_index()
	viewport.queue_free()
	await process_frame
	print("ENVIRONMENT VISUAL CONTRACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_warning_phase_optimization(overlay: BattleManagedEnvironmentVisual, viewport: SubViewport,
	corpses: Array[Dictionary]) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay.position = viewport.size * 0.5
	check(overlay.phase_updates_only_standard_effects,
		"authored standard environment overlay opts into phase-only preset updates")
	var animated_values := {"spikes": false, "burning": true, "warning": true, "corpses": corpses,
		"acid": false, "floor_trap": true, "wall_direction": Vector2i.ZERO, "armed": true}
	overlay.apply_view(animated_values)
	overlay.warning_phase = 0.0
	var rim := overlay.get_node("FloorTrap/ArmedRim") as Line2D
	var animated_draws: Array[int] = [0]
	overlay.draw.connect(func() -> void: animated_draws[0] += 1)
	await process_frame
	await process_frame
	var before_draw_count := animated_draws[0]
	var before_image := viewport.get_texture().get_image()
	overlay.warning_phase = PI * 0.5
	await process_frame
	await process_frame
	var after_image := viewport.get_texture().get_image()
	check(animated_draws[0] > before_draw_count,
		"warning and burning overlays request redraw when their phase changes")
	check(is_equal_approx(rim.modulate.a, 0.96), "armed floor rim alpha follows warning phase")
	check(_images_differ(before_image, after_image), "warning and fire pixels visibly follow the phase")

	var static_values := {"spikes": true, "burning": false, "warning": false, "corpses": corpses,
		"acid": true, "floor_trap": true, "wall_direction": Vector2i.ZERO, "armed": false}
	overlay.apply_view(static_values)
	await process_frame
	await process_frame
	var static_draw_count := animated_draws[0]
	overlay.warning_phase = PI
	await process_frame
	await process_frame
	check(animated_draws[0] == static_draw_count,
		"static spikes, corpses, acid and an unarmed trap do not redraw with phase")
	check(is_equal_approx(rim.modulate.a, 0.66),
		"hidden armed rim retains the phase-derived alpha for later visibility")

	var legacy := CountingEnvironment.new()
	legacy.position = Vector2(24, 24)
	viewport.add_child(legacy)
	check(not legacy.phase_updates_only_standard_effects,
		"custom environment drawing keeps the compatibility default")
	legacy.configure(true, true, true, corpses, true, true, Vector2i.LEFT, true)
	await process_frame
	await process_frame
	var legacy_draw_count := legacy.draw_calls
	legacy.warning_phase = 0.75
	await process_frame
	await process_frame
	check(legacy.draw_calls > legacy_draw_count,
		"default custom drawing receives the legacy phase redraw callback")
	legacy.queue_free()
	await process_frame


func _images_differ(first: Image, second: Image) -> bool:
	if first == null or second == null or first.is_empty() or second.is_empty(): return false
	return first.get_data() != second.get_data()


func _test_environment_index() -> void:
	var board := BattleDemoBoard.new()
	board._view_width = 24
	board._view_height = 16
	var same_cell := Vector2i(4, 5)
	var duplicate_corpse_cell := Vector2i(7, 8)
	var duplicate_trap_cell := Vector2i(9, 10)
	var source := {
		"fires": [
			{"cell": Vector2i(2, 2), "effect": "burning"},
			{"cell": Vector2i(4, 5)}, # Старый lookup считает отсутствующий effect шипами.
			{"cell": Vector2i(4, 5), "effect": "burning"},
			{"cell": Vector2i(-1, -1), "effect": "burning"},
			{"cell": Vector2i(24, 16), "effect": "spark"},
		],
		"corpses": [
			{"id": 11, "cell": duplicate_corpse_cell, "tags": ["first"]},
			{"id": 12, "cell": duplicate_corpse_cell, "tags": ["second"]},
			{"id": 15, "cell": duplicate_corpse_cell, "tags": ["third"]},
			{"id": 16, "cell": duplicate_corpse_cell, "tags": ["fourth"]},
			{"id": 13, "cell": Vector2i(-1, -1), "tags": []},
		],
		"collapse": [same_cell, Vector2i(-1, -1)],
		"hazards": {
			"acid": [same_cell, Vector2i(-1, -1), Vector2i(24, 16)],
			"traps": [
				{"cell": same_cell, "kind": "floor", "direction": Vector2i.ZERO, "armed_team": -1},
				{"cell": same_cell, "kind": "wall", "direction": Vector2i.LEFT, "armed_team": Faction.Type.ENEMY},
				{"cell": duplicate_trap_cell, "kind": "floor", "direction": Vector2i.ZERO, "armed_team": Faction.Type.PLAYER},
				{"cell": Vector2i(-1, -1), "kind": "floor", "direction": Vector2i.ZERO, "armed_team": -1},
			],
		},
	}
	var source_oracle: Dictionary = source.duplicate(true)
	board._view_fires.assign(source.fires.duplicate(true))
	board._view_corpses.assign(source.corpses.duplicate(true))
	board._view_collapse.assign(source.collapse.duplicate(true))
	board._view_hazards = source.hazards.duplicate(true)
	var initial_index := board._index_environment_view()
	var initial_mismatch := _environment_index_mismatch(board, initial_index)
	check(initial_mismatch.is_empty(), "fresh environment index matches linear lookup across 24x16: %s" % str(initial_mismatch))
	check(initial_index.has(Vector2i(-1, -1)) and initial_index.has(Vector2i(24, 16)),
		"out-of-board environment records remain indexed without affecting board cells")
	check(initial_index.get(same_cell, {}).get("trap", {}) == {"kind": "floor", "direction": Vector2i.ZERO, "armed": false},
		"duplicate trap lookup preserves first-record-wins order")
	var duplicated_corpses: Array = initial_index.get(duplicate_corpse_cell, {}).get("corpses", [])
	check(duplicated_corpses.size() == 4 and duplicated_corpses[0].id == 11 and duplicated_corpses[1].id == 12
		and duplicated_corpses[2].id == 15 and duplicated_corpses[3].id == 16,
		"same-cell corpse records retain input order")
	check(source == source_oracle, "building the transient index leaves source DTO values unchanged")

	# Индекс создаётся заново на публикацию, потому что DTO-поля могут меняться на месте без revision.
	var prior_cell := Vector2i(2, 2)
	var prior_index := initial_index
	board._view_fires[0].effect = "bleeding"
	board._view_corpses.append({"id": 14, "cell": duplicate_corpse_cell, "tags": ["third"]})
	board._view_collapse.append(duplicate_corpse_cell)
	var acid_cells: Array = board._view_hazards["acid"]
	acid_cells.append(duplicate_corpse_cell)
	var traps: Array = board._view_hazards["traps"]
	traps.append({"cell": duplicate_corpse_cell, "kind": "floor",
		"direction": Vector2i.ZERO, "armed_team": Faction.Type.PLAYER})
	var changed_index := board._index_environment_view()
	var prior_values: Dictionary = prior_index.get(prior_cell, {})
	var changed_values: Dictionary = changed_index.get(prior_cell, {})
	check(prior_values.get("burning", false) and not prior_values.get("spikes", false)
		and not changed_values.get("burning", false) and changed_values.get("spikes", false),
		"new transient index sees in-place fire edits while prior index remains a snapshot of flags")
	check(_environment_index_mismatch(board, changed_index).is_empty(),
		"rebuilt index matches linear lookup after in-place collection changes")
	var changed_corpses: Array = changed_index.get(duplicate_corpse_cell, {}).get("corpses", [])
	check(changed_corpses.size() == 5 and changed_index.get(duplicate_corpse_cell, {}).get("warning", false)
		and changed_index.get(duplicate_corpse_cell, {}).get("acid", false),
		"rebuilt index includes appended corpse, warning and acid on the same cell")
	check(source == source_oracle, "in-place board DTO edits do not alter source values")
	board.free()


func _environment_index_mismatch(board: BattleDemoBoard, index: Dictionary) -> Dictionary:
	for y: int in board._view_height:
		for x: int in board._view_width:
			var cell := Vector2i(x, y)
			var expected := _linear_environment_values(board, cell)
			var actual: Dictionary = index.get(cell, {})
			for key: String in ["burning", "spikes", "warning", "acid"]:
				if bool(actual.get(key, false)) != bool(expected.get(key, false)):
					return {"cell": cell, "key": key, "actual": actual.get(key, false), "expected": expected.get(key, false)}
			var actual_corpses: Array = actual.get("corpses", [])
			if actual_corpses != expected.corpses:
				return {"cell": cell, "key": "corpses", "actual": actual_corpses, "expected": expected.corpses}
			if actual.get("trap", {}) != expected.trap:
				return {"cell": cell, "key": "trap", "actual": actual.get("trap", {}), "expected": expected.trap}
	return {}


func _linear_environment_values(board: BattleDemoBoard, cell: Vector2i) -> Dictionary:
	var burning := false
	var spikes := false
	for fire: Dictionary in board._view_fires:
		if fire.get("cell", Vector2i(-1, -1)) != cell: continue
		if String(fire.get("effect", "bleeding")) == "burning": burning = true
		else: spikes = true
	var corpses: Array[Dictionary] = []
	for corpse: Dictionary in board._view_corpses:
		if corpse.cell == cell: corpses.append(corpse)
	var trap: Dictionary = {}
	for candidate: Dictionary in board._view_hazards.get("traps", []):
		if candidate.get("cell", Vector2i(-1, -1)) == cell:
			trap = {"kind": String(candidate.get("kind", "")),
				"direction": candidate.get("direction", Vector2i.ZERO),
				"armed": int(candidate.get("armed_team", -1)) >= 0}
			break
	return {"burning": burning, "spikes": spikes, "warning": cell in board._view_collapse,
		"acid": cell in board._view_hazards.get("acid", []), "corpses": corpses, "trap": trap}


func _view_values(corpses: Array[Dictionary]) -> Dictionary:
	return {
		"spikes": true,
		"burning": true,
		"warning": true,
		"corpses": corpses,
		"acid": true,
		"floor_trap": true,
		"wall_direction": Vector2i.LEFT,
		"armed": true,
	}
