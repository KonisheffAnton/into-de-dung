extends PanelContainer
class_name BattleForecastCard

## Экранный текст следует за клеткой, но не перехватывает выбор цели и масштаб.
var label: Label
var model: Dictionary = {}
var anchor_cell := Vector2i(-1, -1)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = RenderLayers.z_index_for(RenderLayers.Layer.UI_PREVIEW) + 2
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172230", 0.97)
	style.border_color = Color("a5b3c5", 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e6ecf4"))
	add_child(label)
	hide()

func publish(value: Dictionary, cell: Vector2i, board: BattleDemoBoard) -> void:
	model = value.duplicate(true)
	anchor_cell = cell
	visible = not String(model.get("text", "")).is_empty()
	label.text = String(model.get("text", ""))
	if visible: place(board)
	if visible: call_deferred("place", board)

func place(board: BattleDemoBoard) -> void:
	if not visible or label == null: return
	var width := minf(370.0, maxf(160.0, board.size.x - 24.0))
	label.custom_minimum_size.x = width - 24.0
	size = Vector2(width, 0)
	var height := get_combined_minimum_size().y
	size.y = height
	var anchor := board.cell_center(anchor_cell) if anchor_cell.x >= 0 else Vector2(12, board.size.y - 12)
	var next := anchor + Vector2(38, -height - 42)
	if next.x + width > board.size.x - 12: next.x = anchor.x - width - 38
	position = Vector2(clampf(next.x, 12, maxf(12, board.size.x - width - 12)), clampf(next.y, 48, maxf(48, board.size.y - height - 12)))
