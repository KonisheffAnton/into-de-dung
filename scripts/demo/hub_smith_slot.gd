extends Button
class_name HubSmithSlot

@export var gear_slot: String = "weapon"
var smith_page: HubSectionPage
var item_id: int = 0
var _drag_started: bool = false

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id <= 0 or smith_page == null: return null
	var data := HubSmithDrag.payload(smith_page, item_id, "slot")
	if data.is_empty(): return null
	_drag_started = true
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var refusal := HubSmithDrag.reason(smith_page, data, gear_slot)
	if not refusal.is_empty() and data is Dictionary and data.get("kind") == "hub_smith": HubSmithDrag.show_reason(smith_page, refusal)
	return refusal.is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	HubSmithDrag.commit(smith_page, data, gear_slot)

func _pressed() -> void:
	if not _drag_started and item_id > 0 and smith_page != null:
		smith_page._on_selected("item:%d" % item_id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("kind") == "hub_smith":
			self_modulate = Color(0.78, 1.0, 0.78) if HubSmithDrag.reason(smith_page, data, gear_slot).is_empty() else Color(1.0, 0.86, 0.82)
	elif what == NOTIFICATION_DRAG_END:
		self_modulate = Color.WHITE
		set_deferred("_drag_started", false)
	elif what == NOTIFICATION_VISIBILITY_CHANGED: self_modulate = Color.WHITE
