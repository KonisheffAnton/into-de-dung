extends SceneTree

const CameraScript = preload("res://scripts/demo/battle_board_camera.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE BOARD CAMERA: " + label)

func _run() -> void:
	_test_transform_roundtrip()
	_test_zoom_clamps_and_anchor()
	_test_pan_and_nonfinite_inputs()
	_test_reset_and_recenter()
	print("BATTLE BOARD CAMERA RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_transform_roundtrip() -> void:
	var camera: BattleBoardCamera = CameraScript.new()
	camera.zoom = 1.75
	camera.offset = Vector2(23.0, -41.0)
	var world_point: Vector2 = Vector2(-8.5, 102.25)
	var view_point: Vector2 = camera.world_to_view(world_point)
	check(camera.view_to_world(view_point).is_equal_approx(world_point), "world/view conversion roundtrip")
	check(camera.get_transform() * world_point == view_point, "transform matches conversion")

func _test_zoom_clamps_and_anchor() -> void:
	var camera: BattleBoardCamera = CameraScript.new()
	camera.zoom = 1.0
	camera.offset = Vector2(13.0, -7.0)
	var anchor: Vector2 = Vector2(120.0, 75.0)
	var world_anchor: Vector2 = camera.view_to_world(anchor)
	camera.zoom_at(0.1, anchor)
	check(is_equal_approx(camera.zoom, 0.75), "zoom clamps to minimum")
	check(camera.world_to_view(world_anchor).is_equal_approx(anchor), "minimum zoom preserves cursor world point")
	camera.zoom_at(9.0, anchor)
	check(is_equal_approx(camera.zoom, 2.5), "zoom clamps to maximum")
	check(camera.world_to_view(world_anchor).is_equal_approx(anchor), "maximum zoom preserves cursor world point")

func _test_pan_and_nonfinite_inputs() -> void:
	var camera: BattleBoardCamera = CameraScript.new()
	camera.pan(Vector2(4.0, -6.0))
	check(camera.offset == Vector2(4.0, -6.0), "pan applies finite delta")
	camera.zoom_at(2.0, Vector2(30.0, 40.0))
	var old_zoom: float = camera.zoom
	var old_offset: Vector2 = camera.offset
	camera.zoom_at(INF, Vector2.ZERO)
	camera.zoom_at(1.5, Vector2(NAN, 0.0))
	camera.pan(Vector2(INF, 0.0))
	camera.pan(Vector2(0.0, NAN))
	camera.recenter_after_resize(Vector2.ZERO, Vector2(INF, 0.0))
	check(camera.zoom == old_zoom and camera.offset == old_offset, "non-finite inputs ignored")

func _test_reset_and_recenter() -> void:
	var camera: BattleBoardCamera = CameraScript.new()
	camera.zoom = 2.0
	camera.offset = Vector2(10.0, 15.0)
	camera.recenter_after_resize(Vector2(20.0, 30.0), Vector2(60.0, 50.0))
	check(camera.offset.is_equal_approx(Vector2(-30.0, -5.0)), "resize recenters camera contribution")
	camera.reset()
	check(is_equal_approx(camera.zoom, 1.0) and camera.offset == Vector2.ZERO, "reset restores defaults")
