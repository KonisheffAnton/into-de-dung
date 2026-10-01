extends SceneTree

var passed: int = 0
var failed: int = 0
var compact_events: Array[StringName] = []
var legacy_events: Array[StringName] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_compact_bar()
	await _test_legacy_bar()
	print("FOUR SLOT BAR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL FOUR SLOT BAR: " + label)

func _capture_compact(action_id: StringName) -> void:
	compact_events.append(action_id)

func _capture_legacy(action_id: StringName) -> void:
	legacy_events.append(action_id)

func _test_compact_bar() -> void:
	var bar := BattleActionBar.new()
	bar.compact_vertical = true
	bar.action_requested.connect(_capture_compact)
	var long_label := "Длинное имя действия, которое не должно раздвигать панель"
	var descriptors: Array[Dictionary] = [
		{"action_id": &"first_dynamic", "label": long_label, "cost": "1 действие", "tooltip": "Подробное описание первого действия"},
		{"action_id": &"disabled_dynamic", "label": "Второе", "disabled": true, "tooltip": "Недоступно"},
		{"action_id": &"unassigned_extra", "label": "Третье, не должно попасть в слот"},
	]
	bar.set_dynamic_descriptors(descriptors, true)
	bar.size = Vector2(165, 360)
	root.add_child(bar)
	await process_frame
	_check(bar._buttons.size() == 4, "compact component builds exactly four buttons")
	_check(bar._buttons[0].get_meta("action_id") == &"attack" and bar._buttons[1].get_meta("action_id") == &"guard", "attack and guard occupy slots one and two")
	_check(bar._buttons[2].get_meta("action_id") == &"first_dynamic" and bar._buttons[3].get_meta("action_id") == &"disabled_dynamic", "first two descriptors occupy slots three and four")
	_check(bar._dynamic_descriptors.size() == 2, "compact descriptor set excludes unassigned extras")
	_check(bar._up_button != null and not bar._up_button.visible and bar._down_button != null and not bar._down_button.visible, "page arrows remain safe API references while hidden")
	bar._next_page()
	bar._previous_page()
	_check(bar._page == 0, "compact page callbacks are no-ops")
	_check(not bar.activate_slot(5) and compact_events.is_empty(), "slot five cannot activate or emit")
	_check(bar.activate_slot(3) and compact_events == [&"first_dynamic"], "assigned dynamic slot emits its id")
	_check(not bar.activate_slot(4) and compact_events.size() == 1, "disabled dynamic slot emits nothing")
	_check(bar._buttons[2].clip_text and bar._buttons[2].tooltip_text.contains(long_label), "long label is clipped with full text available in tooltip")
	_check(bar._buttons[2].custom_minimum_size.x == 160.0 and bar.size.x <= 165.0, "long labels do not expand fixed compact width")
	_check(bar._buttons[2].custom_minimum_size.y >= 70.0 and bar._buttons[2].custom_minimum_size.y <= 78.0, "compact buttons use specified vertical height")
	bar.queue_free()
	await process_frame

func _test_legacy_bar() -> void:
	var bar := BattleActionBar.new()
	bar.action_requested.connect(_capture_legacy)
	var descriptors: Array[Dictionary] = []
	for index: int in range(7):
		descriptors.append({"action_id": StringName("legacy_%d" % index), "label": "Legacy %d" % index})
	bar.set_dynamic_descriptors(descriptors, true)
	bar.size = Vector2(900, 52)
	root.add_child(bar)
	await process_frame
	_check(not bar.compact_vertical and bar._buttons.size() == 8, "legacy default keeps eight slots")
	_check(bar._dynamic_descriptors.size() == 7 and bar._buttons[7].get_meta("action_id") == &"legacy_5", "legacy first page still exposes six dynamic slots")
	bar._next_page()
	_check(bar._page == 1 and bar._buttons[2].get_meta("action_id") == &"legacy_6", "legacy next page still exposes later descriptors")
	_check(bar.activate_slot(3) and legacy_events == [&"legacy_6"], "legacy activation uses selected page")
	bar._previous_page()
	_check(bar._page == 0 and bar._buttons[2].get_meta("action_id") == &"legacy_0", "legacy previous page restores first assignment")
	bar.queue_free()
	await process_frame
