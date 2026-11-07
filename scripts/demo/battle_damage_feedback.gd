extends RefCounted
class_name BattleDamageFeedback

static func entries(events: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups: Array[Dictionary] = []
	var closed_hits: Array[Dictionary] = []
	for raw_event: Variant in events:
		if typeof(raw_event) != TYPE_DICTIONARY: continue
		var event: Dictionary = raw_event
		var kind := StringName(event.get("kind", &""))
		var actor := int(event.get("actor_unit_id", 0))
		var target := int(event.get("target_unit_id", 0))
		var source: Dictionary = event.get("source", {}).duplicate(true)
		var command_seq := int(event.get("command_seq", 0))
		var event_hit_id := String(event.get("hit_id", ""))
		var group := _find_group(groups, actor, target, source, command_seq, event_hit_id)
		match kind:
			&"damaged":
				if group < 0:
					group = _append_group(groups, result, actor, target, source, command_seq, event_hit_id)
				groups[group].amount += maxf(0.0, float(event.get("amount", 0.0)))
			&"armor_changed":
				var armor_loss := 0.0
				var armor_gain := 0.0
				for field: StringName in [&"grants", &"items"]:
					for change: Dictionary in event.get(field, []):
						var delta := float(change.get("before", 0.0)) - float(change.get("after", 0.0))
						if delta > 0.0: armor_loss += delta
						elif delta < 0.0: armor_gain += -delta
				if armor_loss > 0.0:
					if group < 0: group = _append_group(groups, result, actor, target, source, command_seq, event_hit_id)
					groups[group].amount += armor_loss
				if armor_gain > 0.0:
					_append_entry(result, &"armor_gain", actor, target, source, armor_gain, command_seq)
			&"shield_changed":
				var absorbed := maxf(0.0, float(event.get("absorbed", 0.0)))
				if absorbed > 0.0:
					if group < 0: group = _append_group(groups, result, actor, target, source, command_seq, event_hit_id)
					groups[group].amount += absorbed
				elif float(event.get("after", {}).get("hp", 0.0)) > 0.0:
					_append_entry(result, &"shield_gain", actor, target, source, float(event.after.hp), command_seq)
			&"healed":
				var healed := maxf(0.0, float(event.get("amount", 0.0)))
				if healed > 0.0: _append_entry(result, &"healed", actor, target, source, healed, command_seq)
			&"hit_resolved":
				var hit_id := String(event.get("hit_id", ""))
				if not _has_closed_hit(closed_hits, actor, target, source, command_seq, hit_id):
					if group < 0:
						# Восстановление само закрывает успешное попадание: нулевой урон рядом с ним лишний.
						if not _has_recovery_for(result, actor, target, source, command_seq):
							group = _append_group(groups, result, actor, target, source, command_seq, hit_id)
					if group >= 0:
						groups[group].closed = true
					closed_hits.append(_hit_key(actor, target, source, command_seq, hit_id))
	for group: Dictionary in groups:
		var entry: Dictionary = group.entry
		entry.amount = float(group.amount)
	for entry: Dictionary in result:
		entry.erase("_actor")
		entry.erase("_target")
		entry.erase("_source")
		entry.erase("_command_seq")
	return result

## Упор и его обязательный урон могут занимать соседние кадры готового receipt.
## Заимствуем только числа; снимки after и публикации остаются в прежнем порядке.
static func obstacle_results(frames: Array[Dictionary], index: int) -> Array:
	if index < 0 or index + 1 >= frames.size(): return []
	var frame: Dictionary = frames[index]
	if frame.get("step", {}).get("status") != &"APPLIED" or not entries(frame.get("events", [])).is_empty(): return []
	var obstacle: Dictionary = {}
	for event: Dictionary in frame.get("events", []):
		if event.get("kind") in [&"push_blocked", &"collision"]:
			if not obstacle.is_empty(): return []
			obstacle = event
	if obstacle.is_empty(): return []
	var following: Dictionary = frames[index + 1]
	var step: Dictionary = following.get("step", {})
	var expected_kind: StringName = &"push_damage" if obstacle.kind == &"push_blocked" else &"collision_damage"
	var sequence: int = int(obstacle.get("command_seq", 0)) + 1
	var root_id: int = int(obstacle.get("root_id", 0))
	if root_id <= 0 or step.get("kind") != expected_kind or step.get("status") not in [&"APPLIED", &"FAULTED"] or int(step.get("command_seq", 0)) != sequence: return []
	var targets: Array = [int(obstacle.target_unit_id)]
	if obstacle.kind == &"collision": targets.append(int(obstacle.get("blocker_unit_id", -1)))
	var found := false
	for event: Dictionary in following.get("events", []):
		if int(event.get("root_id", 0)) != root_id or int(event.get("command_seq", 0)) != sequence: return []
		if event.get("kind") not in [&"damaged", &"healed", &"armor_changed", &"shield_changed", &"hit_resolved"]: continue
		var source: Dictionary = event.get("source", {})
		var target: int = int(event.get("target_unit_id", 0))
		if int(event.get("root_id", 0)) != root_id or int(event.get("command_seq", 0)) != sequence \
			or event.get("actor_unit_id") != obstacle.get("actor_unit_id") \
			or target not in targets \
			or source.get("kind") != &"collision" or source.get("origin_cell") != obstacle.get("attempted_cell"): return []
		found = true
	return following.events.duplicate(true) if found else []

static func _append_group(groups: Array[Dictionary], result: Array[Dictionary], actor: int, target: int, source: Dictionary, command_seq: int, hit_id: String) -> int:
	var entry := {"kind": &"damage", "actor": actor, "target": target, "source": source.duplicate(true), "amount": 0.0}
	result.append(entry)
	groups.append({"actor": actor, "target": target, "source": source.duplicate(true), "command_seq": command_seq, "hit_id": hit_id,
		"amount": 0.0, "closed": false, "entry": entry})
	return groups.size() - 1

static func _append_entry(result: Array[Dictionary], kind: StringName, actor: int, target: int, source: Dictionary, amount: float, command_seq: int) -> void:
	result.append({"kind": kind, "actor": actor, "target": target, "source": source.duplicate(true), "amount": amount,
		"_actor": actor, "_target": target, "_source": source.duplicate(true), "_command_seq": command_seq})

static func _find_group(groups: Array[Dictionary], actor: int, target: int, source: Dictionary, command_seq: int, hit_id: String) -> int:
	for index: int in groups.size():
		var group: Dictionary = groups[index]
		if not bool(group.closed) and int(group.actor) == actor and int(group.target) == target \
			and int(group.command_seq) == command_seq and group.source == source \
			and (hit_id.is_empty() or String(group.hit_id).is_empty() or String(group.hit_id) == hit_id):
			return index
	return -1

static func _has_recovery_for(result: Array[Dictionary], actor: int, target: int, source: Dictionary, command_seq: int) -> bool:
	# Поля сопоставления нужны лишь внутри сборки; наружу выходят отделённые значения.
	for entry: Dictionary in result:
		if entry.get("_actor", -1) == actor and entry.get("_target", -1) == target \
			and entry.get("_command_seq", -1) == command_seq and entry.get("_source", {}) == source:
			return true
	return false

static func _hit_key(actor: int, target: int, source: Dictionary, command_seq: int, hit_id: String) -> Dictionary:
	return {"actor": actor, "target": target, "source": source.duplicate(true), "command_seq": command_seq, "hit_id": hit_id}

static func _has_closed_hit(closed_hits: Array[Dictionary], actor: int, target: int, source: Dictionary, command_seq: int, hit_id: String) -> bool:
	for hit: Dictionary in closed_hits:
		if hit.actor == actor and hit.target == target and hit.source == source and hit.command_seq == command_seq \
			and (hit_id.is_empty() or hit.hit_id == hit_id):
			return true
	return false
