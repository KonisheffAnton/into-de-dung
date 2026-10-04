extends PanelContainer
class_name BattleForecastCard

## Экранный текст следует за клеткой, но не перехватывает выбор цели и масштаб.
var label: Label
var model: Dictionary = {}
var anchor_cell := Vector2i(-1, -1)
@export var preferred_width: float = 370.0
@export var minimum_width: float = 160.0
@export var edge_margin: float = 12.0
@export var anchor_gap: Vector2 = Vector2(38.0, 42.0)
@export var top_margin: float = 48.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = RenderLayers.z_index_for(RenderLayers.Layer.UI_PREVIEW) + 2
	label = get_node_or_null("Label") as Label
	if label == null:
		var layout := (load("res://scenes/demo/battle/forecast_card.tscn") as PackedScene).instantiate() as PanelContainer
		# Переносим сценовые стиль/лейбл для прямого .new(), не меняя настройки авторского экземпляра.
		var panel_style := layout.get_theme_stylebox("panel")
		add_theme_stylebox_override("panel", panel_style)
		while layout.get_child_count() > 0:
			var child := layout.get_child(0)
			layout.remove_child(child)
			_set_runtime_owner(child)
			add_child(child)
		layout.free()
		label = get_node_or_null("Label") as Label
	hide()

func _set_runtime_owner(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children(): _set_runtime_owner(child)

func publish(value: Dictionary, cell: Vector2i, board: BattleDemoBoard) -> void:
	model = value.duplicate(true)
	anchor_cell = cell
	visible = not String(model.get("text", "")).is_empty()
	label.text = String(model.get("text", ""))
	if visible: place(board)
	if visible: call_deferred("place", board)

func place(board: BattleDemoBoard) -> void:
	if not visible or label == null: return
	var width := minf(preferred_width, maxf(minimum_width, board.size.x - edge_margin * 2.0))
	var panel_style := get_theme_stylebox("panel")
	var horizontal_insets := panel_style.get_minimum_size().x
	label.custom_minimum_size.x = maxf(0.0, width - horizontal_insets)
	size = Vector2(width, 0)
	var height := get_combined_minimum_size().y
	size.y = height
	var anchor := board.cell_center(anchor_cell) if anchor_cell.x >= 0 else Vector2(edge_margin, board.size.y - edge_margin)
	var next := anchor + Vector2(anchor_gap.x, -height - anchor_gap.y)
	if next.x + width > board.size.x - edge_margin: next.x = anchor.x - width - anchor_gap.x
	position = Vector2(clampf(next.x, edge_margin, maxf(edge_margin, board.size.x - width - edge_margin)), clampf(next.y, top_margin, maxf(top_margin, board.size.y - height - edge_margin)))
