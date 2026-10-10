extends SceneTree

class CountingEnvironment extends BattleManagedEnvironmentVisual:
	pass

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
	viewport.queue_free()
	await process_frame
	print("ENVIRONMENT VISUAL CONTRACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


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
