extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL MAGE BAR: " + label)

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	root.add_child(viewport)
	var bar := BattleMageBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size.y = 64
	viewport.add_child(bar)
	var buttons: Array[Button] = []
	var activations: Array[int] = []
	for index: int in range(18):
		var button := Button.new()
		button.text = "Spell %d" % index
		button.custom_minimum_size = Vector2(96, 64)
		button.disabled = index == 3
		button.tooltip_text = "tooltip %d" % index
		button.pressed.connect(func() -> void: activations.append(index))
		buttons.append(button)
	var page_changes: Array[int] = []
	bar.page_changed.connect(func(page: int) -> void: page_changes.append(page))
	bar.configure(buttons)
	await process_frame
	check(bar.get_page() == 0 and bar.get_page_count() == 3, "initial page/count")
	check(bar._previous_button.visible and bar._next_button.visible and bar._page_label.text == "1/3", "pager visible with page label")
	check(buttons[0].visible and buttons[7].visible and not buttons[8].visible, "first page visibility")
	check(buttons[3].disabled and buttons[3].tooltip_text == "tooltip 3", "button state retained")
	bar._next_button.emit_signal("pressed")
	check(bar.get_page() == 1 and page_changes == [1] and activations.is_empty(), "page click navigates without activating spell")
	check(buttons[8].visible and buttons[15].visible and not buttons[7].visible and not buttons[16].visible, "second page visibility")
	bar._next_button.emit_signal("pressed")
	bar._next_button.emit_signal("pressed")
	check(bar.get_page() == 2 and page_changes == [1, 2], "last page does not wrap")
	bar.set_paging_enabled(false)
	bar._previous_button.emit_signal("pressed")
	check(bar.get_page() == 2 and bar._previous_button.disabled and bar._next_button.disabled, "disabled arrows cannot change page")
	bar.set_paging_enabled(true)
	bar.set_page(1)
	var reduced: Array[Button] = []
	for index: int in range(5): reduced.append(buttons[index])
	bar.configure(reduced)
	check(bar.get_page() == 0 and bar.get_page_count() == 1 and page_changes == [1, 2, 1, 0], "fewer entries clamp and notify only on page change")
	check(not bar._previous_button.visible and not bar._next_button.visible and not bar._page_label.visible, "controls hidden at one page")
	check(buttons[0].visible and buttons[4].visible and not buttons[5].visible
		and buttons[8].get_parent() == bar._button_row and buttons[8].is_inside_tree() and not buttons[8].visible,
		"filtered buttons stay owned by the bar and hidden")
	check(buttons[3].disabled and buttons[3].tooltip_text == "tooltip 3", "reconfigure preserves button state")
	bar.configure(reduced)
	check(bar.get_page() == 0 and page_changes == [1, 2, 1, 0], "same-page configure emits no page change")
	check(bar.size.x <= 1280 and bar.size.y <= 850, "bar fits 1280x850 with 96x64 buttons")
	var empty: Array[Button] = []
	bar.configure(empty)
	check(bar.get_page() == 0 and bar.get_page_count() == 1 and not bar._page_label.visible, "empty list is safe")
	bar.queue_free()
	await process_frame
	check(not is_instance_valid(buttons[8]), "bar frees filtered buttons with the owned subtree")
	viewport.queue_free()
	await process_frame
	print("BATTLE MAGE BAR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
