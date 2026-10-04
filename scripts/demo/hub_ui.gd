class_name HubUI
extends RefCounted

# Разметка живёт в PackedScene; скрипты заполняют только данные и действия.
static func instance(scene_name: String, parent: Node) -> Control:
	var scene := load("res://scenes/demo/hub/" + scene_name + ".tscn") as PackedScene
	var view := scene.instantiate() as Control
	view.set_meta(&"hub_dynamic", true)
	parent.add_child(view)
	return view

static func clear_dynamic(root: Node) -> void:
	for child: Node in root.get_children():
		if child.get_meta(&"hub_dynamic", false):
			root.remove_child(child)
			child.queue_free()
		else:
			clear_dynamic(child)

static func text(root: Node, path: NodePath, value: String) -> Label:
	var label := root.get_node(path) as Label
	label.text = value
	return label

static func bind(root: Node, path: NodePath, action: Callable) -> Button:
	var button := root.get_node(path) as Button
	# Постоянные узлы переживают обновление; прежний обработчик не должен накапливаться.
	var previous: Callable = button.get_meta(&"hub_action", Callable())
	if previous.is_valid() and button.pressed.is_connected(previous):
		button.pressed.disconnect(previous)
	button.pressed.connect(action)
	button.set_meta(&"hub_action", action)
	return button
