extends RefCounted
class_name BattleConsequenceFeedback

## Причины берём из событий; заполненная шкала сама по себе не доказывает пробой.
static func entries(events: Array, before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var chain_targets: Dictionary = {}
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = value
		if StringName(event.get("kind", &"")) == &"chain_link":
			chain_targets[int(event.get("target_unit_id", 0))] = true
	var seen: Dictionary = {}
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = value
		var kind := StringName(event.get("kind", &""))
		var target_id := int(event.get("target_unit_id", 0))
		match kind:
			&"hit_resolved":
				var old_unit := _unit(before, target_id)
				var new_unit := _unit(after, target_id)
				var old_armor := _armor_current(old_unit)
				var new_armor := _armor_current(new_unit)
				if old_armor > 0 and new_unit.get("armor", {}).has("current") and new_armor == 0 and _has_negative_armor_delta(events, target_id):
					_add(result, seen, target_id, "Броня исчерпана", &"armor")
				var hit: Dictionary = event.get("hit", {})
				var rows: Variant = hit.get("rows", [])
				if old_armor > 0 and typeof(rows) == TYPE_ARRAY:
					for row_value: Variant in rows:
						if typeof(row_value) != TYPE_DICTIONARY:
							continue
						var row: Dictionary = row_value
						if StringName(row.get("policy", &"")) == &"hp_only_natural" and int(row.get("hp_damage", 0)) > 0:
							_add(result, seen, target_id, "Сквозь броню", &"armor")
							break
			&"balance_broken":
				_add(result, seen, target_id, "Потеря равновесия", &"balance")
			&"balance_changed":
				if not bool(event.get("broke", false)) and float(event.get("impact", 0.0)) > 0.0 and not chain_targets.has(target_id):
					_add(result, seen, target_id, "Устоял · %.1f/%.1f" % [float(event.get("balance_after", 0.0)), float(event.get("balance_max", 0.0))], &"balance")
			&"chain_link":
				_add(result, seen, int(event.get("from_unit_id", 0)), "Импульс передан", &"push")
				if not bool(event.get("broke", false)):
					var unit := _unit(after, target_id)
					var text := "Цепь остановлена · невосприимчив" if unit.has("balance_max") and float(unit.balance_max) == 0.0 else "Цепь остановлена · устоял"
					_add(result, seen, target_id, text, &"balance")
			&"push_blocked":
				var reason := StringName(event.get("reason", &""))
				var text := "Упор: стена" if reason == &"wall" else "Упор: уступ" if reason == &"height" else "Сдвиг остановлен"
				_add(result, seen, target_id, text, &"push")
			&"collision":
				var blocker_id := int(event.get("blocker_unit_id", 0))
				var blocker := _unit(after, blocker_id)
				if blocker.is_empty():
					blocker = _unit(before, blocker_id)
				var text := "Столкновение: " + String(blocker.get("name", "")) if not blocker.is_empty() else "Столкновение"
				_add(result, seen, target_id, text, &"push")
			&"moved":
				if StringName(event.get("movement_kind", &"")) == &"push" and event.get("from_cell") != event.get("to_cell"):
					_add(result, seen, target_id, "Сдвиг", &"push")
			&"fell":
				_add(result, seen, target_id, "Падение", &"push")
			&"died":
				# Внутри поля пропасть публикует moved+died, а fell относится к краю доски.
				if StringName(event.get("source", {}).get("kind", &"")) == &"fall":
					_add(result, seen, target_id, "Падение", &"push")
	return result

static func recovery_entries(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in after.get("units", {}):
		var old_unit := _unit(before, id)
		var new_unit := _unit(after, id)
		if not old_unit.get("alive", false) or not new_unit.get("alive", false): continue
		var old_balance := float(old_unit.get("balance", 0.0))
		var new_balance := float(new_unit.get("balance", 0.0))
		if new_balance < old_balance and new_balance == maxf(0.0, old_balance - BattleTurnRefill.BALANCE_RECOVERY):
			result.append({"unit_id": id, "text": "Восстановлено равновесие · %.1f" % (old_balance - new_balance), "kind": &"balance"})
	return result

static func _unit(snapshot: Dictionary, unit_id: int) -> Dictionary:
	var units: Variant = snapshot.get("units", {})
	if typeof(units) != TYPE_DICTIONARY:
		return {}
	var value: Variant = (units as Dictionary).get(unit_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}

static func _armor_current(unit: Dictionary) -> int:
	var armor: Variant = unit.get("armor", {})
	if typeof(armor) != TYPE_DICTIONARY:
		return 0
	return int((armor as Dictionary).get("current", 0))

static func _has_negative_armor_delta(events: Array, target_id: int) -> bool:
	var total_delta := 0.0
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = value
		if StringName(event.get("kind", &"")) != &"armor_changed" or int(event.get("target_unit_id", 0)) != target_id:
			continue
		for key: String in ["grants", "items"]:
			var deltas: Variant = event.get(key, [])
			if typeof(deltas) != TYPE_ARRAY:
				continue
			for delta_value: Variant in deltas:
				if typeof(delta_value) != TYPE_DICTIONARY:
					continue
				var delta: Dictionary = delta_value
				total_delta += float(delta.get("after", 0.0)) - float(delta.get("before", 0.0))
	return total_delta < 0.0

static func _add(result: Array[Dictionary], seen: Dictionary, unit_id: int, text: String, kind: StringName) -> void:
	var key := "%d|%s|%s" % [unit_id, text, String(kind)]
	if seen.has(key):
		return
	seen[key] = true
	result.append({"unit_id": unit_id, "text": text, "kind": kind})
