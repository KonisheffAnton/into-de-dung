extends RefCounted
class_name ItemReactionCollector

## Описания не являются pending-командами: повторная доставка и проверка
## перед исполнением принадлежат будущей очереди, а этот шов только читает.
static func collect_damage(state: ItemSimulationState, event: Dictionary) -> ItemReactionResult:
	var capture := ItemSimulationSnapshot.capture(state, [])
	if capture.code != ItemSnapshotResult.Code.OK:
		var failure := ItemReactionResult.new()
		failure.code = int(capture.code) as ItemReactionResult.Code
		failure.reason = capture.reason
		return failure
	if not ItemSimulationSnapshot._shape(event, {"event_seq": TYPE_INT, "target_unit_id": TYPE_INT, "dealt": TYPE_FLOAT}):
		return _invalid("event/schema")
	if event["event_seq"] < 1 or event["event_seq"] >= ItemSimulationSnapshot.MAX_ID or event["target_unit_id"] < 1 or not is_finite(event["dealt"]) or event["dealt"] < 0.0:
		return _invalid("event/value")
	var target := state.get_board().get_unit_by_id(event["target_unit_id"])
	if target == null: return _invalid("event/target_unit_id")
	var result := ItemReactionResult.new()
	result.code = ItemReactionResult.Code.OK
	var owner := state.get_owner(target.id)
	if event["dealt"] == 0.0 or not target.is_alive() or owner.is_closed(): return result
	var descriptions: Array[Dictionary] = []
	# DTO уже проверен и упорядочен по stable ids; чтение не вычисляет stat cache.
	for record: Dictionary in capture.snapshot._data["owners"]:
		if record["owner_unit_id"] != target.id: continue
		for item: Dictionary in record["items"]:
			for effect: Dictionary in item["effects"]:
				if effect["kind"] != "heal_on_damage" or not effect["active"]: continue
				descriptions.append({"kind": "heal", "event_seq": event["event_seq"], "priority": 0, "owner_unit_id": target.id, "item_instance_id": item["item_instance_id"], "effect_instance_id": effect["effect_instance_id"], "local_index": 0, "target_unit_id": target.id, "definition_id": item["definition_id"], "heal_amount": effect["heal_amount"]})
	descriptions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["effect_instance_id"] < b["effect_instance_id"])
	# Прочие компоненты полного ключа фиксированы этим damage seam.
	var previous := 0
	for description: Dictionary in descriptions:
		if description["effect_instance_id"] == previous: return _invalid("descriptions/duplicate_key")
		previous = description["effect_instance_id"]
	result.descriptions = descriptions
	return result

static func _invalid(reason: String) -> ItemReactionResult:
	var result := ItemReactionResult.new()
	result.code = ItemReactionResult.Code.INVALID
	result.reason = reason
	return result
