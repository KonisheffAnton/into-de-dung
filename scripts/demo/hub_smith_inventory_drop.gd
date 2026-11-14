extends Panel
class_name HubSmithInventoryDrop

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var page := _page()
	if page == null: return false
	var refusal := HubSmithDrag.reason(page, data, "inventory")
	if not refusal.is_empty() and data is Dictionary and data.get("kind") == "hub_smith": HubSmithDrag.show_reason(page, refusal)
	return refusal.is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	HubSmithDrag.commit(_page(), data, "inventory")

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var page := _page()
		var data: Variant = get_viewport().gui_get_drag_data()
		if page != null and data is Dictionary and data.get("kind") == "hub_smith":
			self_modulate = Color(0.78, 1.0, 0.78) if HubSmithDrag.reason(page, data, "inventory").is_empty() else Color(1.0, 0.86, 0.82)
	elif what == NOTIFICATION_DRAG_END or what == NOTIFICATION_VISIBILITY_CHANGED:
		self_modulate = Color.WHITE

func _page() -> HubSectionPage:
	var node: Node = get_parent()
	while node != null:
		if node is HubSectionPage: return node as HubSectionPage
		node = node.get_parent()
	return null
