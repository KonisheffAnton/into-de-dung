extends Control
class_name BattleActionBar

signal action_requested(action_id: StringName)

const FIXED_SLOTS: int = 2
const VISIBLE_SLOTS: int = 8
const DYNAMIC_PAGE_SIZE: int = 6

var _dynamic_descriptors: Array[Dictionary] = []
var _page: int = 0
var _buttons: Array[Button] = []
var _up_button: Button
var _down_button: Button
var _slot_states: Dictionary = {}

func _ready() -> void:
	_build()
	_refresh()

func set_dynamic_descriptors(descriptors: Array[Dictionary]) -> void:
	_dynamic_descriptors = descriptors.duplicate(true)
	_page = 0
	_refresh()

func activate_slot(slot: int) -> bool:
	if slot < 1 or slot > VISIBLE_SLOTS: return false
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
		_buttons.append(button)
		row.add_child(button)
	_down_button = _arrow_button("↓")
	_down_button.pressed.connect(_next_page)
	row.add_child(_down_button)

func _arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 36)
	button.add_theme_font_size_override("font_size", 18)
	return button

func _refresh() -> void:
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

func _set_fixed(button: Button, slot: int, action_id: StringName, label: String, tooltip: String) -> void:
	button.visible = true
	button.text = label
	button.set_meta("slot", slot)
	button.set_meta("action_id", action_id)
	button.tooltip_text = tooltip

func _slot_pressed(index: int) -> void:
	var action_id := StringName(_buttons[index].get_meta("action_id", &""))
	if action_id != &"": action_requested.emit(action_id)

func _previous_page() -> void:
	if _page <= 0: return
	_page -= 1
	_refresh()

func _next_page() -> void:
	if (_page + 1) * DYNAMIC_PAGE_SIZE >= _dynamic_descriptors.size(): return
	_page += 1
	_refresh()
