extends Control
class_name BattleHudInput

var board: BattleDemoBoard

static func install(host: Control, board_view: BattleDemoBoard) -> BattleHudInput:
	var existing := host.get_node_or_null("BattleHudInput") as BattleHudInput
	if existing != null:
		existing.board = board_view
		existing._prepare_host()
		return existing
	var surface := BattleHudInput.new()
	surface.name = "BattleHudInput"
	surface.board = board_view
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(surface)
	# Поверхность ниже HUD: реальные кнопки получают событие раньше поля.
	host.move_child(surface, mini(1, host.get_child_count() - 1))
	surface._prepare_host()
	surface.mouse_exited.connect(surface._clear_board_hover)
	surface.call_deferred("_prepare_host")
	return surface

func _prepare_host() -> void:
	if board == null or not is_instance_valid(board): return
	if get_parent() is Control:
		# Текст пропускает клики к полю; подробности доступны через полосы прокрутки.
		_set_noninteractive_controls(get_parent() as Control)

func _set_noninteractive_controls(node: Node) -> void:
	if node == self: return
	if node is Control:
		var control := node as Control
		if control is Button or control is HScrollBar or control is VScrollBar:
			pass
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_noninteractive_controls(child)

func _gui_input(event: InputEvent) -> void:
	if board == null or not is_instance_valid(board): return
	var forwarded := event.duplicate() as InputEvent
	if event is InputEventMouse:
		var mouse_event := forwarded as InputEventMouse
		mouse_event.position = board.get_global_transform_with_canvas().affine_inverse() * (event as InputEventMouse).global_position
	board._gui_input(forwarded)
	if forwarded is InputEventMouseButton and (forwarded as InputEventMouseButton).pressed:
		accept_event()

func _clear_board_hover() -> void:
	if board != null and is_instance_valid(board): board._clear_hover()
