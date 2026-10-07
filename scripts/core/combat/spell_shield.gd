extends RefCounted
class_name SpellShield

## Один щит на фигуру. ID задаёт обновление/замену, а не дополнительный слой.
static func valid(value: Variant) -> bool:
	return ItemSimulationSnapshot._shape(value, {"spell_id": TYPE_STRING, "hp": TYPE_INT, "hits_left": TYPE_INT}) and not value.spell_id.is_empty() and value.spell_id.to_utf8_buffer().size() <= 128 and value.hp > 0 and value.hp <= ArmorRuntime.MAX_EXACT_HP and value.hits_left > 0 and value.hits_left <= 4096

static func make(id: StringName, hp: int, hits: int) -> Dictionary:
	var value := {"spell_id": String(id), "hp": hp, "hits_left": hits}
	return value if valid(value) else {}

static func write_state(state: Dictionary, value: Dictionary) -> void:
	if value.is_empty():
		state.erase("shield")
		state["schema_version"] = 3 if state.has("raised_shield") else 1
	else:
		state["shield"] = value.duplicate(true)
		state["schema_version"] = 3 if state.has("raised_shield") else 2

## Округление групп совпадает с D0. Поглощение распределяется пропорционально
## между типами/политиками; остаточные единицы идут в неизменном порядке D0.
static func intercept(raw: Array[Dictionary], shield: Dictionary) -> Dictionary:
	var failed := {"reason": &"shield/invalid_hit"}
	if not valid(shield): return failed
	var neutral := {&"physical": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}, &"fire": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}}
	var prepared := ArmorRuntime.components(raw)
	if prepared.is_empty(): return failed
	var base := ArmorHitCalculation.calculate(prepared, 0, 0, 0, 0, neutral)
	if base.reason != &"": return {"reason": base.reason}
	var total := base.total_damage
	if total == 0: return {"reason": &"", "raw": raw.duplicate(true), "before": shield.duplicate(true), "after": shield.duplicate(true), "absorbed": 0}
	var absorbed := mini(total, int(shield.hp))
	var allocation: Array[int] = []
	var left := absorbed
	for row: Dictionary in base.rows:
		var share := ArmorFraction.make(absorbed, total).multiply(ArmorFraction.make(int(row[&"D"])))
		if not share.valid: return {"reason": &"armor/overflow"}
		allocation.append(share.floor_value())
		left -= share.floor_value()
	for index: int in allocation.size():
		if left > 0 and allocation[index] < int(base.rows[index][&"D"]):
			allocation[index] += 1
			left -= 1
	var remaining: Dictionary = {}
	for index: int in base.rows.size():
		var row: Dictionary = base.rows[index]
		remaining[String(row[&"type"]) + "|" + String(row[&"policy"])] = int(row[&"D"]) - allocation[index]
	var adjusted: Array[Dictionary] = []
	for component: Dictionary in raw:
		var copy := component.duplicate(true)
		var key := String(component.type) + "|" + String(component.policy)
		# Источники строк остаются прежними; сумма группы теперь равна overflow.
		copy.numerator = int(remaining.get(key, 0)); copy.denominator = 1
		remaining[key] = 0
		adjusted.append(copy)
	var after := shield.duplicate(true)
	after.hp -= absorbed; after.hits_left -= 1
	if after.hp == 0 or after.hits_left == 0: after = {}
	return {"reason": &"", "raw": adjusted, "before": shield.duplicate(true), "after": after, "absorbed": absorbed}

static func valid_event(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY, "absorbed": TYPE_INT, "reason": TYPE_STRING}): return false
	if event.kind != &"shield_changed" or event.target_unit_id <= 0 or event.target_unit_id >= ActionContext.MAX_ID or event.actor_unit_id < 0 or event.actor_unit_id >= ActionContext.MAX_ID or not ItemSimulationSnapshot._shape(event.source, {"kind": TYPE_STRING_NAME, "source_instance_id": TYPE_INT, "origin_cell": TYPE_VECTOR2I, "instigator_unit_id": TYPE_INT, "credit_unit_id": TYPE_INT}): return false
	var source: Dictionary = event.source
	if source.kind not in DamageSource.KINDS or source.instigator_unit_id != event.actor_unit_id: return false
	for key: String in ["source_instance_id", "instigator_unit_id", "credit_unit_id"]:
		if source[key] < 0 or source[key] >= ActionContext.MAX_ID: return false
	if source.kind == &"mage":
		if not DamageSource.valid_mage(source): return false
	elif source.origin_cell == Vector2i(-1, -1): return false
	if (not event.before.is_empty() and not valid(event.before)) or (not event.after.is_empty() and not valid(event.after)): return false
	if event.reason in ["applied", "refreshed", "replaced"]:
		if source not in [DamageSource.new(&"mage", 12, Vector2i(-1, -1), 0, 0).to_dict(), DamageSource.new(&"mage", 15, Vector2i(-1, -1), 0, 0).to_dict()] or event.after.get("spell_id") not in ["mage.shield", "card.shield"]: return false
		if (source.source_instance_id == 12) != (event.after.spell_id == "mage.shield"): return false
		return event.absorbed == 0 and not event.after.is_empty() and (event.reason == "applied" if event.before.is_empty() else event.reason == ("refreshed" if event.before.spell_id == event.after.spell_id else "replaced"))
	if event.reason != "absorbed" or event.before.is_empty() or event.absorbed <= 0 or event.absorbed > event.before.hp: return false
	var after: Dictionary = event.before.duplicate(true)
	after.hp -= event.absorbed; after.hits_left -= 1
	if after.hp == 0 or after.hits_left == 0: after = {}
	return event.after == after
