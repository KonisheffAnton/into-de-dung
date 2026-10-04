extends Control
class_name BattleActionBar

signal action_requested(action_id: StringName)
signal action_hovered(action_id: StringName)
signal action_hover_left(action_id: StringName)

const FIXED_SLOTS: int = 2
const VISIBLE_SLOTS: int = 8
const DYNAMIC_PAGE_SIZE: int = 6
const COMPACT_DYNAMIC_SLOTS: int = 2

## Режим сохраняется в сцене, а выставление до add_child остаётся совместимым.
@export var compact_vertical: bool = false
var _dynamic_descriptors: Array[Dictionary] = []
var _page: int = 0
var _buttons: Array[Button] = []
var _up_button: Button
var _down_button: Button
var _slot_states: Dictionary = {}

func _ready() -> void:
	_build()
	_refresh()

func set_dynamic_descriptors(descriptors: Array[Dictionary], reset_page: bool = false) -> void:
	_dynamic_descriptors.clear()
	var count := mini(descriptors.size(), COMPACT_DYNAMIC_SLOTS) if compact_vertical else descriptors.size()
	for index: int in range(count):
		_dynamic_descriptors.append(descriptors[index].duplicate(true))
	if reset_page or compact_vertical: _page = 0
	_page = mini(_page, maxi(0, ceili(float(_dynamic_descriptors.size()) / DYNAMIC_PAGE_SIZE) - 1))
	_refresh()

func activate_slot(slot: int) -> bool:
	var maximum := 4 if compact_vertical else VISIBLE_SLOTS
	if slot < 1 or slot > maximum: return false
	var button := _buttons[slot - 1] if slot - 1 < _buttons.size() else null
	if button == null or button.disabled or not button.visible: return false
	button.emit_signal("pressed")
	return true

func set_slot_enabled(action_id: StringName, enabled: bool, reason: String = "") -> void:
	_slot_states[action_id] = {"enabled": enabled, "reason": reason}
	for button in _buttons:
		if StringName(button.get_meta("action_id", &"")) == action_id:
			button.disabled = not enabled
			button.tooltip_text = reason

func _build() -> void:
	if _buttons.size() == (4 if compact_vertical else VISIBLE_SLOTS) and _up_button != null and _down_button != null: return
	if _bind_authored_layout(): return
	var layout_path := "res://scenes/demo/battle/action_bar.tscn" if compact_vertical else "res://scenes/demo/battle/action_bar_legacy.tscn"
	var layout := (load(layout_path) as PackedScene).instantiate() as Control
	# Совместимый .new() переносит готовую разметку; её размеры и шрифты не пересобираются.
	if compact_vertical:
		custom_minimum_size = layout.custom_minimum_size
		# Горизонтальный режим сохраняет флаг, выставленный вызывающим кодом.
		size_flags_horizontal = layout.size_flags_horizontal
	else:
		custom_minimum_size.y = layout.custom_minimum_size.y
	while layout.get_child_count() > 0:
		var child := layout.get_child(0)
		layout.remove_child(child)
		_set_runtime_owner(child)
		add_child(child)
	layout.free()
	if _bind_authored_layout(): return

func _set_runtime_owner(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children(): _set_runtime_owner(child)

func _bind_authored_layout() -> bool:
	var row := get_node_or_null("Row") as HBoxContainer
	var column := get_node_or_null("Column") as VBoxContainer
	var slots: Array[Button] = []
	if compact_vertical:
		if column == null or column.get_child_count() < 4: return false
		_up_button = get_node_or_null("Previous") as Button
		_down_button = get_node_or_null("Next") as Button
		if _up_button == null or _down_button == null: return false
		for index: int in range(4):
			var button := column.get_node_or_null("Slot%d" % (index + 1)) as Button
			if button == null: return false
			slots.append(button)
	else:
		if row == null: return false
		_up_button = row.get_node_or_null("Previous") as Button
		_down_button = row.get_node_or_null("Next") as Button
		if _up_button == null or _down_button == null: return false
		for index: int in range(VISIBLE_SLOTS):
			var button := row.get_node_or_null("Slot%d" % (index + 1)) as Button
			if button == null: return false
			slots.append(button)
	_buttons.clear()
	for index: int in range(slots.size()): _bind_slot(slots[index], index)
	if _up_button == null or _down_button == null: return false
	if not _up_button.pressed.is_connected(_previous_page): _up_button.pressed.connect(_previous_page)
	if not _down_button.pressed.is_connected(_next_page): _down_button.pressed.connect(_next_page)
	return true

func _bind_slot(button: Button, index: int) -> void:
	button.set_meta("slot", index + 1)
	if not button.pressed.is_connected(_slot_pressed.bind(index)): button.pressed.connect(_slot_pressed.bind(index))
	if not button.mouse_entered.is_connected(_slot_mouse_entered.bind(index)): button.mouse_entered.connect(_slot_mouse_entered.bind(index))
	if not button.mouse_exited.is_connected(_slot_mouse_exited.bind(index)): button.mouse_exited.connect(_slot_mouse_exited.bind(index))
	_buttons.append(button)

func _refresh() -> void:
	if compact_vertical:
		_refresh_compact()
		return
	if _buttons.size() < VISIBLE_SLOTS: return
	_set_fixed(_buttons[0], 1, &"attack", "1  Атака\n1 основное", "1 основное действие")
	_set_fixed(_buttons[1], 2, &"guard", "2  Защита\n1 основное", "1 основное действие")
	for dynamic_index in DYNAMIC_PAGE_SIZE:
		var descriptor_index := _page * DYNAMIC_PAGE_SIZE + dynamic_index
		var button := _buttons[FIXED_SLOTS + dynamic_index]
		if descriptor_index < _dynamic_descriptors.size():
			var descriptor := _dynamic_descriptors[descriptor_index]
			var action_id := StringName(descriptor.get("action_id", &""))
			button.set_meta("action_id", action_id)
			var cost := String(descriptor.get("cost", ""))
			button.text = "%d  %s%s" % [FIXED_SLOTS + dynamic_index + 1, String(descriptor.get("label", action_id)), ("\n" + cost) if not cost.is_empty() else ""]
			button.tooltip_text = String(descriptor.get("tooltip", ""))
			button.disabled = bool(descriptor.get("disabled", false))
			button.visible = true
		else:
			button.set_meta("action_id", &"")
			button.text = "%d  —" % (FIXED_SLOTS + dynamic_index + 1)
			button.tooltip_text = "Нет назначенного действия"
			button.disabled = true
			button.visible = true
	_up_button.disabled = _page <= 0
	_down_button.disabled = (_page + 1) * DYNAMIC_PAGE_SIZE >= _dynamic_descriptors.size()
	# Страница меняет только назначения, а не доступность постоянных действий.
	for id: StringName in _slot_states:
		set_slot_enabled(id, _slot_states[id]["enabled"], _slot_states[id]["reason"])

func _refresh_compact() -> void:
	_page = 0
	if _buttons.size() != 4: return
	_set_fixed(_buttons[0], 1, &"attack", "1  Атака\n1 основное", "1 основное действие")
	_set_fixed(_buttons[1], 2, &"guard", "2  Защита\n1 основное", "1 основное действие")
	for dynamic_index: int in range(COMPACT_DYNAMIC_SLOTS):
		var slot := FIXED_SLOTS + dynamic_index + 1
		var button := _buttons[slot - 1]
		if dynamic_index < _dynamic_descriptors.size():
			var descriptor := _dynamic_descriptors[dynamic_index]
			var action_id := StringName(descriptor.get("action_id", &""))
			var label := String(descriptor.get("label", action_id))
			var cost := String(descriptor.get("cost", ""))
			var full_text := "%d  %s%s" % [slot, label, ("\n" + cost) if not cost.is_empty() else ""]
			button.set_meta("slot", slot)
			button.set_meta("action_id", action_id)
			button.text = full_text
			var detail := String(descriptor.get("tooltip", ""))
			button.tooltip_text = full_text if detail.is_empty() else detail + "\n\n" + full_text
			button.disabled = bool(descriptor.get("disabled", false))
			button.visible = true
		else:
			button.set_meta("slot", slot)
			button.set_meta("action_id", &"")
			button.text = "%d  —" % slot
			button.tooltip_text = "Нет назначенного действия"
			button.disabled = true
			button.visible = true
		for id: StringName in _slot_states:
			if StringName(button.get_meta("action_id", &"")) == id:
				button.disabled = not bool(_slot_states[id]["enabled"])
				button.tooltip_text = String(_slot_states[id]["reason"])
	for id: StringName in _slot_states:
		if id in [&"attack", &"guard"]:
			set_slot_enabled(id, bool(_slot_states[id]["enabled"]), String(_slot_states[id]["reason"]))

func _set_fixed(button: Button, slot: int, action_id: StringName, label: String, tooltip: String) -> void:
	button.visible = true
	button.text = label
	button.set_meta("slot", slot)
	button.set_meta("action_id", action_id)
	button.tooltip_text = tooltip

func _slot_pressed(index: int) -> void:
	var action_id := StringName(_buttons[index].get_meta("action_id", &""))
	if action_id != &"": action_requested.emit(action_id)

func _slot_mouse_entered(index: int) -> void:
	if index < 0 or index >= _buttons.size(): return
	var action_id := StringName(_buttons[index].get_meta("action_id", &""))
	if action_id != &"": action_hovered.emit(action_id)

func _slot_mouse_exited(index: int) -> void:
	if index < 0 or index >= _buttons.size(): return
	var action_id := StringName(_buttons[index].get_meta("action_id", &""))
	if action_id != &"": action_hover_left.emit(action_id)

func _previous_page() -> void:
	if compact_vertical:
		_page = 0
		return
	if _page <= 0: return
	_page -= 1
	_refresh()

func _next_page() -> void:
	if compact_vertical:
		_page = 0
		return
	if (_page + 1) * DYNAMIC_PAGE_SIZE >= _dynamic_descriptors.size(): return
	_page += 1
	_refresh()
