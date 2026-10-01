extends Control
class_name BattleActionBar

signal action_requested(action_id: StringName)
signal action_hovered(action_id: StringName)
signal action_hover_left(action_id: StringName)

const FIXED_SLOTS: int = 2
const VISIBLE_SLOTS: int = 8
const DYNAMIC_PAGE_SIZE: int = 6
const COMPACT_DYNAMIC_SLOTS: int = 2
const COMPACT_WIDTH: float = 160.0
const COMPACT_BUTTON_HEIGHT: float = 74.0

## Включается до add_child: старая горизонтальная панель остаётся режимом по умолчанию.
var compact_vertical: bool = false
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
	if compact_vertical:
		_build_compact()
		return
	custom_minimum_size.y = 52.0
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_up_button = _arrow_button("↑")
	_up_button.pressed.connect(_previous_page)
	row.add_child(_up_button)
	for index in VISIBLE_SLOTS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.set_meta("slot", index + 1)
		button.pressed.connect(_slot_pressed.bind(index))
		button.mouse_entered.connect(_slot_mouse_entered.bind(index))
		button.mouse_exited.connect(_slot_mouse_exited.bind(index))
		_buttons.append(button)
		row.add_child(button)
	_down_button = _arrow_button("↓")
	_down_button.pressed.connect(_next_page)
	row.add_child(_down_button)

func _build_compact() -> void:
	_page = 0
	custom_minimum_size = Vector2(COMPACT_WIDTH, COMPACT_BUTTON_HEIGHT * 4 + 12)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	for index: int in range(4):
		var button := Button.new()
		button.custom_minimum_size = Vector2(COMPACT_WIDTH, COMPACT_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		button.set_meta("slot", index + 1)
		button.pressed.connect(_slot_pressed.bind(index))
		button.mouse_entered.connect(_slot_mouse_entered.bind(index))
		button.mouse_exited.connect(_slot_mouse_exited.bind(index))
		_buttons.append(button)
		column.add_child(button)
	# Ссылки на стрелки сохраняют безопасный API старого компонента, но не занимают место.
	_up_button = _arrow_button("↑")
	_down_button = _arrow_button("↓")
	_up_button.visible = false
	_down_button.visible = false
	_up_button.pressed.connect(_previous_page)
	_down_button.pressed.connect(_next_page)
	add_child(_up_button)
	add_child(_down_button)

func _arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 36)
	button.add_theme_font_size_override("font_size", 18)
	return button

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
