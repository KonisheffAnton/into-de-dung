extends HubSkeletonCard
class_name HubSmithItemCard

var smith_page: HubSectionPage
var item_id: int = 0
var _drag_started: bool = false

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or item_id <= 0 or smith_page == null: return null
	var data := HubSmithDrag.payload(smith_page, item_id, "inventory")
	if data.is_empty(): return null
	_drag_started = true
	var preview := Label.new()
	var title := get_node_or_null("Title") as Label
	preview.text = title.text if title != null else tooltip_text.get_slice("\n", 0)
	set_drag_preview(preview)
	return data

func _on_pressed() -> void:
	if not _drag_started: super._on_pressed()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var inventory := HubSmithDrag.inventory_target(self)
	return inventory != null and inventory._can_drop_data(at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var inventory := HubSmithDrag.inventory_target(self)
	if inventory != null: inventory._drop_data(at_position, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: set_deferred("_drag_started", false)
