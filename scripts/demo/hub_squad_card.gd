extends Button
class_name HubSquadCard

signal slot_selected(slot_index: int)
signal move_requested(hero_id: int, direction: int)

var hero_id: int = 0
var slot_index: int = 0
var drag_context: Dictionary = {}
var drop_check: Callable
var drop_request: Callable
var _drag_started: bool = false

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if not _drag_started: slot_selected.emit(slot_index)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if hero_id <= 0 or drag_context.is_empty(): return null
	_drag_started = true
	var preview := PanelContainer.new()
	preview.theme = theme
	if preview.theme == null:
		preview.theme = load("res://assets/ui/hub/skeleton_theme.tres") as Theme
	preview.add_theme_stylebox_override("panel", get_theme_stylebox("normal"))
	var label := Label.new()
	label.text = "%s\n%s" % [($Name as Label).text, ($Identity as Label).text]
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", ($Name as Label).get_theme_color("font_color"))
	preview.add_child(label)
	set_drag_preview(preview)
	return drag_context.duplicate(true)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return drop_check.is_valid() and bool(drop_check.call(get_global_rect().position + at_position, data))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drop_request.is_valid(): drop_request.call(get_global_rect().position + at_position, data)

func _gui_input(event: InputEvent) -> void:
	if hero_id <= 0: return
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed:
		if event.keycode in [KEY_UP, KEY_DOWN]:
			move_requested.emit(hero_id, -1 if event.keycode == KEY_UP else 1)
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Mouse release в том же кадре не должен открыть выбор после завершённого drag.
		set_deferred("_drag_started", false)
