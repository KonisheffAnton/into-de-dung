extends Button
class_name HubFeatureIcon

@export var passive_normal_style: StyleBoxFlat
@export var passive_hover_style: StyleBoxFlat
@export var passive_focus_style: StyleBoxFlat
@export var ability_normal_style: StyleBoxFlat
@export var ability_hover_style: StyleBoxFlat
@export var ability_focus_style: StyleBoxFlat

@onready var _tooltip: PanelContainer = $TooltipLayer/TooltipPanel
@onready var _title_label: Label = $TooltipLayer/TooltipPanel/TooltipMargin/TooltipBody/Title
@onready var _description_label: Label = $TooltipLayer/TooltipPanel/TooltipMargin/TooltipBody/Description

var _passive: bool = false
var _hovered: bool = false
var _focused: bool = false
var _pinned: bool = false
var _dismissed: bool = false
var _last_style_kind: int = -1
var _feature_title: String = ""
var _feature_description: String = ""

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"hub_feature_tooltips")
	tooltip_text = ""
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.hide()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)
	tree_exiting.connect(_close_tooltip)
	_title_label.text = _feature_title
	_description_label.text = _feature_description
	_update_visibility()

func set_feature(title: String, description: String, texture: Texture2D, passive: bool) -> void:
	_passive = passive
	_feature_title = title
	_feature_description = description
	icon = texture
	accessibility_name = title
	accessibility_description = description
	if is_node_ready():
		if _title_label.text != title: _close_tooltip()
		_title_label.text = title
		_description_label.text = description
		_apply_style()
		_position_tooltip()

func _input(event: InputEvent) -> void:
	if not is_node_ready() or not _tooltip.visible:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		var click_position: Vector2 = event.position
		if not get_global_rect().has_point(click_position):
			_close_tooltip()

func _unhandled_key_input(event: InputEvent) -> void:
	if _tooltip.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_tooltip()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_close_tooltip()

func _on_mouse_entered() -> void:
	_hovered = true
	_dismissed = false
	_update_visibility()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_visibility()

func _on_focus_entered() -> void:
	_focused = true
	_dismissed = false
	_apply_style()
	_update_visibility()

func _on_focus_exited() -> void:
	_focused = false
	_apply_style()
	_update_visibility()

func _on_pressed() -> void:
	if _pinned:
		_close_tooltip()
		return
	_pinned = true
	_dismissed = false
	_update_visibility()

func _update_visibility() -> void:
	if not is_node_ready():
		return
	_tooltip.visible = not _dismissed and (_hovered or _focused or _pinned) and is_visible_in_tree()
	if _tooltip.visible:
		# Фокус предыдущей кнопки не должен оставлять вторую подсказку поверх новой.
		for other: Node in get_tree().get_nodes_in_group(&"hub_feature_tooltips"):
			if other != self and other.get_viewport() == get_viewport(): other._close_tooltip()
		_position_tooltip()
		call_deferred("_position_tooltip")
	_apply_style()

func _close_tooltip() -> void:
	_pinned = false
	_dismissed = true
	if is_node_ready():
		_tooltip.hide()

func _apply_style() -> void:
	if not is_node_ready():
		return
	var kind: int = 0 if _passive else 1
	if _last_style_kind != kind:
		add_theme_stylebox_override(&"normal", passive_normal_style if _passive else ability_normal_style)
		add_theme_stylebox_override(&"hover", passive_hover_style if _passive else ability_hover_style)
		_last_style_kind = kind
	var focus_style: StyleBoxFlat = passive_focus_style if _passive else ability_focus_style
	add_theme_stylebox_override(&"focus", focus_style)

func _position_tooltip() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_tooltip.reset_size()
	var size: Vector2 = _tooltip.size.max(_tooltip.get_combined_minimum_size())
	var origin: Vector2 = get_global_rect().position
	origin.y = get_global_rect().end.y + 6.0
	if origin.y + size.y > viewport_size.y:
		origin.y = get_global_rect().position.y - size.y - 6.0
	origin.x = clampf(origin.x, 4.0, maxf(4.0, viewport_size.x - size.x - 4.0))
	origin.y = clampf(origin.y, 4.0, maxf(4.0, viewport_size.y - size.y - 4.0))
	_tooltip.position = origin
