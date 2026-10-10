extends RefCounted
class_name BattleRosterPresenter

## PackedScene удерживается, чтобы строки повторно использовали авторскую тему.
const ROSTER_ENTRY_SCENE: PackedScene = preload("res://scenes/demo/battle/roster_entry.tscn")

var _container: VBoxContainer
var _pressed_handler: Callable
var _legacy_button_factory: Callable
var _buttons: Dictionary[int, Button] = {}
var _session_id: int = 0
var _authored_mode: bool = false
var _mode_initialized: bool = false

func bind(container: VBoxContainer, pressed_handler: Callable, legacy_button_factory: Callable) -> void:
	if _container != container:
		reset()
	_container = container
	_pressed_handler = pressed_handler
	_legacy_button_factory = legacy_button_factory

func reset() -> void:
	_buttons.clear()
	_session_id = 0
	if _container == null: return
	for child: Node in _container.get_children():
		if not child.has_meta("runtime_roster_entry"): continue
		_container.remove_child(child)
		child.queue_free()

func ensure_scope(session_id: int, authored_mode: bool) -> void:
	ensure_mode(authored_mode)
	var session_changed: bool = session_id != 0 and _session_id != session_id
	if session_changed: reset()
	if session_id != 0: _session_id = session_id

func ensure_mode(authored_mode: bool) -> void:
	var mode_changed: bool = _mode_initialized and _authored_mode != authored_mode
	if mode_changed: reset()
	if not _mode_initialized or mode_changed:
		_authored_mode = authored_mode
		_mode_initialized = true

func get_or_create_button(unit_id: int) -> Button:
	var button := get_button(unit_id)
	if button == null:
		button = ROSTER_ENTRY_SCENE.instantiate() as Button if _authored_mode else _legacy_button_factory.call("") as Button
		button.text = ""
		button.set_meta("runtime_roster_entry", true)
		button.set_meta("runtime_roster_unit_id", unit_id)
		button.pressed.connect(_pressed_handler.bind(unit_id))
		_container.add_child(button)
		_buttons[unit_id] = button
	return button

func get_button(unit_id: int) -> Button:
	var button := _buttons.get(unit_id) as Button
	if button != null:
		if not is_instance_valid(button) or button.get_parent() != _container:
			_buttons.erase(unit_id)
			return null
	return button

func retain_ordered(ordered_ids: Array[int]) -> void:
	var removed: Array[int] = []
	for unit_id: int in _buttons:
		if not ordered_ids.has(unit_id): removed.append(unit_id)
	for unit_id: int in removed:
		var button: Button = _buttons[unit_id]
		_buttons.erase(unit_id)
		if is_instance_valid(button) and button.get_parent() == _container:
			_container.remove_child(button)
			button.queue_free()
	# Чистим только наши узлы, если внешняя правка нарушила карту соответствий.
	for child: Node in _container.get_children():
		if not child.has_meta("runtime_roster_entry"): continue
		var unit_id: int = int(child.get_meta("runtime_roster_unit_id", UnitId.NONE))
		if _buttons.get(unit_id) == child: continue
		_container.remove_child(child)
		child.queue_free()
	var destination: int = 0
	for child: Node in _container.get_children():
		if not child.has_meta("runtime_roster_entry"): destination += 1
	for offset: int in ordered_ids.size():
		var unit_id: int = ordered_ids[offset]
		var button := _buttons.get(unit_id) as Button
		if button == null: continue
		if not is_instance_valid(button):
			_buttons.erase(unit_id)
			continue
		if button.get_parent() == _container and button.get_index() != destination + offset:
			_container.move_child(button, destination + offset)
