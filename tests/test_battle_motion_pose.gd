extends SceneTree

const ART_TRIAL_UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")

class CountingVisual extends BattleDemoIsoVisual:
	var sync_calls: int = 0
	var synced_poses: Array[Dictionary] = []

	func sync_scene_art() -> void:
		sync_calls += 1
		synced_poses.append({"offset": presentation_offset, "lift": presentation_lift})
		super.sync_scene_art()

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE MOTION POSE: " + label)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _check_setter_contract(viewport)
	await _check_authored_scene_equivalence(viewport)
	viewport.queue_free()
	await process_frame
	print("BATTLE MOTION POSE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_setter_contract(viewport: SubViewport) -> void:
	var legacy := CountingVisual.new()
	legacy.role = BattleDemoIsoVisual.Role.UNIT
	viewport.add_child(legacy)
	await process_frame
	legacy.sync_calls = 0
	legacy.synced_poses.clear()
	var legacy_offset := Vector2(14.0, -6.0)
	var legacy_lift := 23.0
	legacy.set_motion_pose(legacy_offset, legacy_lift)
	check(not legacy.batch_motion_pose and legacy.sync_calls == 2,
		"default scene preserves the two legacy motion synchronizations")
	check(legacy.synced_poses.size() == 2 and legacy.synced_poses[0].offset == legacy_offset
		and legacy.synced_poses[0].lift == 0.0 and legacy.synced_poses[1].lift == legacy_lift,
		"legacy calls still expose the same intermediate offset-only pose")
	legacy.sync_calls = 0
	legacy.synced_poses.clear()
	legacy.presentation_offset = Vector2(-2.0, 7.0)
	legacy.presentation_lift = 9.0
	check(legacy.sync_calls == 2 and legacy.presentation_offset == Vector2(-2.0, 7.0)
		and legacy.presentation_lift == 9.0, "public legacy setters always synchronize independently")
	legacy.sync_calls = 0
	legacy.presentation_offset = Vector2(-2.0, 7.0)
	legacy.presentation_lift = 9.0
	check(legacy.sync_calls == 2, "equal-value public setters retain legacy repair synchronizations")

	var batched := CountingVisual.new()
	batched.role = BattleDemoIsoVisual.Role.UNIT
	batched.batch_motion_pose = true
	viewport.add_child(batched)
	await process_frame
	batched.sync_calls = 0
	batched.synced_poses.clear()
	batched.set_motion_pose(legacy_offset, legacy_lift)
	check(batched.sync_calls == 1 and batched.presentation_offset == legacy_offset
		and batched.presentation_lift == legacy_lift, "opt-in pose setter synchronizes once with both values set")
	check(batched.synced_poses.size() == 1 and batched.synced_poses[0].offset == legacy_offset
		and batched.synced_poses[0].lift == legacy_lift, "batched sync never exposes a partial motion pose")
	batched.sync_calls = 0
	batched.set_motion_pose(legacy_offset, legacy_lift)
	check(batched.sync_calls == 1, "opt-in setter still repairs art on an equal pose")
	batched.sync_calls = 0
	batched.presentation_offset = Vector2.ONE
	batched.presentation_lift = 4.0
	check(batched.sync_calls == 2, "public setters keep their full sync contract when opt-in is enabled")
	legacy.queue_free()
	batched.queue_free()
	await process_frame

func _check_authored_scene_equivalence(viewport: SubViewport) -> void:
	var legacy := ART_TRIAL_UNIT.instantiate() as BattleDemoIsoVisual
	var batched := ART_TRIAL_UNIT.instantiate() as BattleDemoIsoVisual
	check(legacy != null and batched != null and batched.batch_motion_pose,
		"authored trial unit opts into batched motion pose")
	if legacy == null or batched == null: return
	legacy.batch_motion_pose = false
	legacy.role = BattleDemoIsoVisual.Role.UNIT
	batched.role = BattleDemoIsoVisual.Role.UNIT
	var unit := BattleUnitView.new()
	unit.id = 3301
	unit.faction = Faction.Type.PLAYER
	unit.debug_name = "Motion pose"
	unit.alive = true
	legacy.unit = unit
	batched.unit = unit
	legacy.visual_class_id = &"warrior"
	batched.visual_class_id = &"warrior"
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 28.0
	config.origin_offset = Vector2(310.0, 210.0)
	legacy.grid_config = config
	batched.grid_config = config
	legacy.position = IsoGridUtils.grid_to_screen(Vector2i(4, 5), config, 0)
	batched.position = legacy.position
	legacy.half_steps = 3
	batched.half_steps = 3
	viewport.add_child(legacy)
	viewport.add_child(batched)
	await process_frame
	legacy.presentation_offset = Vector2(2.5, -3.0)
	legacy.presentation_lift = 6.0
	batched.set_motion_pose(Vector2(2.5, -3.0), 6.0)
	check(_art_transforms_equal(legacy, batched),
		"trial art root, status HUD and ground shadow match after an offset/lift sample")
	legacy.half_steps = 6
	batched.half_steps = 6
	legacy.presentation_offset = Vector2(-8.0, 4.0)
	legacy.presentation_lift = 18.0
	batched.set_motion_pose(Vector2(-8.0, 4.0), 18.0)
	check(_art_transforms_equal(legacy, batched),
		"both paths match after motion and terrain geometry change together")
	legacy.presentation_offset = Vector2(-8.0, 4.0)
	legacy.presentation_lift = 18.0
	batched.set_motion_pose(Vector2(-8.0, 4.0), 18.0)
	check(_art_transforms_equal(legacy, batched),
		"equal-value repair produces the same complete authored transforms")
	legacy.queue_free()
	batched.queue_free()
	await process_frame

func _art_transforms_equal(first: BattleDemoIsoVisual, second: BattleDemoIsoVisual) -> bool:
	var first_art := first.get_node_or_null("ArtRoot") as Node2D
	var second_art := second.get_node_or_null("ArtRoot") as Node2D
	var first_hud := first.get_node_or_null("StatusHud") as Node2D
	var second_hud := second.get_node_or_null("StatusHud") as Node2D
	var first_shadow := first.get_node_or_null("GroundShadow") as Node2D
	var second_shadow := second.get_node_or_null("GroundShadow") as Node2D
	return first_art != null and second_art != null and first_hud != null and second_hud != null \
		and first_shadow != null and second_shadow != null \
		and first_art.transform.is_equal_approx(second_art.transform) \
		and first_hud.transform.is_equal_approx(second_hud.transform) \
		and first_shadow.transform.is_equal_approx(second_shadow.transform) \
		and first.get_visual_offset().is_equal_approx(second.get_visual_offset())
