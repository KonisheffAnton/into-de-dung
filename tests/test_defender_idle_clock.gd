extends SceneTree

const IdleClockScript = preload("res://scripts/demo/defender_idle_clock.gd")

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL DEFENDER IDLE CLOCK: " + label)


func _run() -> void:
	var clock := IdleClockScript.new()
	clock.configure(0, 2, 2)
	check(clock.get_frame_index() == 0 and not clock.is_rare(), "starts on normal frame zero")
	clock.advance(0.2)
	check(clock.get_frame_index() == 1, "advances one frame per 200 ms")
	clock.reset()
	clock.advance(2.4)
	check(clock.get_frame_index() == 0 and not clock.is_rare(), "full 2.4 second normal cycle")
	clock.advance(2.4 - 0.0001)
	check(not clock.is_rare(), "rare cycle does not begin before normal-cycle boundary")
	clock.advance(0.0001)
	check(clock.is_rare(), "configured normal loops lead into rare cycle")
	clock.advance(2.4 - 0.0001)
	check(clock.is_rare(), "rare cycle remains active before its duration ends")
	clock.advance(0.0001)
	check(not clock.is_rare(), "rare cycle lasts exactly one 2.4 second loop")
	clock.advance(2.4)
	check(not clock.is_rare(), "normal loop repeats before next rare cycle")
	clock.advance(2.4)
	check(clock.is_rare(), "next rare cycle follows the configured normal loops")

	var phased := IdleClockScript.new()
	phased.configure(5, 4, 8)
	var same_id := IdleClockScript.new()
	same_id.configure(5, 4, 8)
	var other_id := IdleClockScript.new()
	other_id.configure(6, 4, 8)
	check(phased.get_normal_cycle_count() >= 4 and phased.get_normal_cycle_count() <= 8, "ID selects inclusive normal-cycle range")
	check(phased.get_normal_cycle_count() == same_id.get_normal_cycle_count() and phased.get_frame_index() == same_id.get_frame_index(), "same ID is deterministic")
	check(phased.get_frame_index() != other_id.get_frame_index(), "neighbor IDs dephase initial frame")
	check(not phased.is_rare(), "dephased initial frame remains in normal loop")

	var isolated := IdleClockScript.new()
	isolated.configure(5, 4, 8)
	var before: int = isolated.get_frame_index()
	phased.advance(0.2)
	check(isolated.get_frame_index() == before and isolated.get_elapsed() == 0.0, "clock instances advance independently")
	phased.reset()
	check(phased.get_elapsed() == 0.0 and phased.get_frame_index() == 11 and not phased.is_rare(), "reset restores dephased starting frame")
	for invalid_delta: float in [0.0, -1.0, INF, NAN]:
		var elapsed_before: float = phased.get_elapsed()
		phased.advance(invalid_delta)
		check(phased.get_elapsed() == elapsed_before, "ignores invalid delta %s" % str(invalid_delta))

	var sanitized := IdleClockScript.new()
	sanitized.configure(10, 0, -4)
	check(sanitized.get_normal_cycle_count() == 1, "sanitizes cycle bounds to at least one")
	sanitized.configure(10, 7, 2)
	check(sanitized.get_normal_cycle_count() == 7, "sanitizes max below min")

	var looping := IdleClockScript.new()
	looping.configure(2, 2, 2)
	looping.advance(7.2 * 10000.0)
	check(is_zero_approx(looping.get_elapsed()) and not looping.is_rare(), "many complete schedules wrap to initial phase")
	looping.advance(1.0e30)
	check(looping.get_elapsed() >= 0.0 and looping.get_elapsed() < 7.2, "huge finite delta remains bounded")

	seed(123456)
	var expected_global_next: int = randi()
	seed(123456)
	var rng_clock := IdleClockScript.new()
	rng_clock.configure(31)
	check(randi() == expected_global_next, "configuration does not consume global RNG")

	print("DEFENDER IDLE CLOCK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
