@tool
extends Line2D
class_name HubSkeletonLink

@export var from_action: StringName = &"skill_0"
@export var to_action: StringName = &"skill_1"

func _process(_delta: float) -> void:
	var start := _endpoint(from_action)
	var finish := _endpoint(to_action)
	if start == null or finish == null or not start.is_visible_in_tree() or not finish.is_visible_in_tree():
		if not points.is_empty(): clear_points()
		return
	var next := PackedVector2Array([to_local(start.get_global_rect().get_center()), to_local(finish.get_global_rect().get_center())])
	# Меняется только линия; соседние узлы сохраняют authored-положение в редакторе и игре.
	if points != next: points = next

func _endpoint(action: StringName) -> Control:
	if get_parent() == null: return null
	var scope: Node = get_parent()
	var ancestor: Node = scope
	while ancestor != null:
		if ancestor is HubSectionPage:
			scope = ancestor
			break
		ancestor = ancestor.get_parent()
	for child: Node in scope.find_children("*", "Button", true, false):
		if StringName(child.get_meta(&"hub_action", &"")) == action: return child as Control
	return null
