extends CheckButton
class_name HubSmithFitFilter

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var inventory := HubSmithDrag.inventory_target(self)
	return inventory != null and inventory._can_drop_data(at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var inventory := HubSmithDrag.inventory_target(self)
	if inventory != null: inventory._drop_data(at_position, data)
