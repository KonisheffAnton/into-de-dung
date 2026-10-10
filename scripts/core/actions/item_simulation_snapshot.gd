extends RefCounted
class_name ItemSimulationSnapshot

## Внешний снимок владеет только значениями. P02 остаётся codec проекции доски;
## проверка ссылок предметов выполняется до создания любого нового runtime.
const SCHEMA_VERSION := 11
const SCOPE := "battle_state_v11"
const MAX_ID := 9223372036854775807
const MAX_DEPTH := 32
const MAX_STRING_BYTES := 4096
const MAX_ITEMS_TOTAL := 4096
const MAX_EFFECTS_TOTAL := 16384
const MAX_DEFINITIONS_TOTAL := 4096
const MAX_DEFINITION_EFFECTS_TOTAL := 16384
const MAX_VALUE_NODES := 2000000
const MAX_OWNERS := 65536

var _data: Dictionary = {}

static func _failure(error: String) -> ItemSnapshotResult:
	var code := ItemSnapshotResult.Code.SNAPSHOT_INVALID
	var ids: Array[StringName] = []
	if error.begins_with("UNSUPPORTED:"):
		code = ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED
		error = error.trim_prefix("UNSUPPORTED:")
		ids.append(StringName(error))
	elif error.begins_with("BUSY:"):
		code = ItemSnapshotResult.Code.SNAPSHOT_BUSY
		error = error.trim_prefix("BUSY:")
	var result := ItemSnapshotResult.new()
	result.code = code
	result.reason = error
	result.unsupported_ids = ids
	return result

static func from_dict(data: Dictionary) -> ItemSnapshotResult:
	var error := _validate(data)
	if not error.is_empty(): return _failure(error)
	var snapshot := ItemSimulationSnapshot.new()
	snapshot._data = _normalize(SimulationSnapshot._copy_value(data))
	var result := ItemSnapshotResult.new()
	result.code = ItemSnapshotResult.Code.OK
	result.snapshot = snapshot
	return result

func to_dict() -> Dictionary:
	return SimulationSnapshot._copy_value(_data)

func canonical_values() -> Array:
	return SimulationSnapshot._canonical(_data)

func canonical_bytes() -> PackedByteArray:
	var bytes := PackedByteArray([80, 48, 51, 66, _data["schema_version"] as int])
	SimulationSnapshot._encode(canonical_values(), bytes)
	return bytes

func fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_bytes())
	return context.finish().hex_encode()

static func _normalize(data: Dictionary) -> Dictionary:
	if data.has("environment"): data["environment"] = CombatEnvironmentState.from_dict(data["environment"]).to_dict()
	if data.has("artifacts"): data["artifacts"] = BattleArtifactState.from_dict(data["artifacts"]).to_dict()
	data["board_snapshot"] = SimulationSnapshot._normalize(data["board_snapshot"])
	data["owners"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["owner_unit_id"] < b["owner_unit_id"])
	for owner: Dictionary in data["owners"]:
		owner["definitions"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
		owner["items"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_instance_id"] < b["item_instance_id"])
		for item: Dictionary in owner["items"]:
			item["effects"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["effect_instance_id"] < b["effect_instance_id"])
	data["summons"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["unit_id"] < b["unit_id"])
	return data

static func _walk(value: Variant, depth: int, ancestors: Array, count: Array[int], path: String) -> String:
	count[0] += 1
	if count[0] > MAX_VALUE_NODES: return path + "/nodes"
	if depth > MAX_DEPTH: return path + "/depth"
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I: return ""
		TYPE_FLOAT: return "" if is_finite(value) else path + "/finite"
		TYPE_STRING: return "" if value.to_utf8_buffer().size() <= MAX_STRING_BYTES else path + "/string_bytes"
		TYPE_ARRAY, TYPE_DICTIONARY:
			for ancestor: Variant in ancestors:
				if is_same(ancestor, value): return path + "/cycle"
			if value.size() > MAX_VALUE_NODES - count[0]: return path + "/nodes"
			ancestors.append(value)
			if value is Array:
				for i: int in value.size():
					var error := _walk(value[i], depth + 1, ancestors, count, path + "/%d" % i)
					if not error.is_empty(): return error
			else:
				for key: Variant in value:
					if typeof(key) != TYPE_STRING: return path + "/key"
				var keys: Array = value.keys()
				keys.sort()
				for key: String in keys:
					var error := _walk(key, depth + 1, ancestors, count, path + "/key")
					if not error.is_empty(): return error
					error = _walk(value[key], depth + 1, ancestors, count, path + "/" + key)
					if not error.is_empty(): return error
			ancestors.pop_back()
			return ""
	return path + "/value_type"

## Успешный снимок не нуждается в строках пути и сортировке каждого словаря.
## При отказе прежний walker сохраняет точную диагностику и её порядок.
static func _walk_valid(value: Variant, depth: int, ancestors: Array, count: Array[int]) -> bool:
	count[0] += 1
	if count[0] > MAX_VALUE_NODES or depth > MAX_DEPTH: return false
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING:
			# Один символ UTF-8 занимает не больше четырёх байт; короткие строки
			# проверяются без временного PackedByteArray, длинные — прежним лимитом.
			return value.length() <= MAX_STRING_BYTES / 4 or value.to_utf8_buffer().size() <= MAX_STRING_BYTES
		TYPE_ARRAY, TYPE_DICTIONARY: return _walk_valid_container(value, depth, ancestors, count)
	return false

static func _walk_valid_container(value: Variant, depth: int, ancestors: Array, count: Array[int]) -> bool:
	for ancestor: Variant in ancestors:
		if is_same(ancestor, value): return false
	if value.size() > MAX_VALUE_NODES - count[0]: return false
	ancestors.append(value)
	if value is Array:
		for item: Variant in value:
			# Частые скалярные leaves проверяются здесь без рекурсивного вызова walker.
			count[0] += 1
			if count[0] > MAX_VALUE_NODES or depth + 1 > MAX_DEPTH: return false
			match typeof(item):
				TYPE_BOOL, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I: pass
				TYPE_FLOAT:
					if not is_finite(item): return false
				TYPE_STRING:
					if item.length() > MAX_STRING_BYTES / 4 and item.to_utf8_buffer().size() > MAX_STRING_BYTES: return false
				TYPE_ARRAY, TYPE_DICTIONARY:
					if not _walk_valid_container(item, depth + 1, ancestors, count): return false
				_:
					return false
	else:
		for key: Variant in value:
			if typeof(key) != TYPE_STRING: return false
			# Ключ является отдельным узлом и проверяется до соответствующего значения.
			count[0] += 1
			if count[0] > MAX_VALUE_NODES or depth + 1 > MAX_DEPTH: return false
			if key.length() > MAX_STRING_BYTES / 4 and key.to_utf8_buffer().size() > MAX_STRING_BYTES: return false
			var item: Variant = value[key]
			count[0] += 1
			if count[0] > MAX_VALUE_NODES or depth + 1 > MAX_DEPTH: return false
			match typeof(item):
				TYPE_BOOL, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I: pass
				TYPE_FLOAT:
					if not is_finite(item): return false
				TYPE_STRING:
					if item.length() > MAX_STRING_BYTES / 4 and item.to_utf8_buffer().size() > MAX_STRING_BYTES: return false
				TYPE_ARRAY, TYPE_DICTIONARY:
					if not _walk_valid_container(item, depth + 1, ancestors, count): return false
				_:
					return false
	ancestors.pop_back()
	return true

static func _shape(value: Variant, fields: Dictionary) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != fields.size(): return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not fields.has(key) or typeof(value[key]) != fields[key]: return false
	return true

static func _effect_shape(effect: Variant, runtime: bool) -> bool:
	if typeof(effect) != TYPE_DICTIONARY or typeof(effect.get("kind")) != TYPE_STRING: return false
	var fields := {"kind": TYPE_STRING}
	if runtime: fields.merge({"effect_instance_id": TYPE_INT, "effect_index": TYPE_INT, "active": TYPE_BOOL})
	match effect["kind"]:
		"stat_modifier":
			fields.merge({"stat_type": TYPE_INT, "operation": TYPE_INT, "value": TYPE_FLOAT})
			if runtime: fields.merge({"source_key": TYPE_STRING, "modifier_link": TYPE_ARRAY})
		"heal_on_damage": fields.merge({"trigger_event": TYPE_INT, "heal_amount": TYPE_FLOAT})
		_:
			# Неизвестная форма остаётся capability failure после общего raw preflight.
			for key: String in fields:
				if typeof(effect.get(key)) != fields[key]: return false
			return true
	if not _shape(effect, fields): return false
	if runtime and effect["kind"] == "stat_modifier":
		for link: Variant in effect["modifier_link"]:
			if not _shape(link, {"stat_type": TYPE_INT, "source_id": TYPE_STRING, "instance_id": TYPE_INT, "local_slot": TYPE_INT}): return false
	return true

static func _structure(data: Dictionary, captured_board: SimulationSnapshot = null) -> String:
	var envelope_fields := {"schema_version": TYPE_INT, "scope": TYPE_STRING, "board_snapshot": TYPE_DICTIONARY, "owners": TYPE_ARRAY, "summons": TYPE_ARRAY}
	for key: String in ["environment", "abilities", "artifacts", "deck", "card_effects"]:
		if data.has(key): envelope_fields[key] = TYPE_DICTIONARY
	if not _shape(data, envelope_fields): return "envelope/schema"
	# Только свежий DTO из этого capture уже прошёл проверку формы и семантики.
	# Импорт/instantiate не получают свидетельство и проверяют весь внешний граф.
	if captured_board == null or not is_same(data["board_snapshot"], captured_board._data):
		var board_error := _board_structure(data["board_snapshot"])
		if not board_error.is_empty(): return board_error
	if data["owners"].size() > MAX_OWNERS: return "owners/limit"
	var items := 0
	var effects := 0
	var definitions := 0
	var definition_effects := 0
	for owner: Variant in data["owners"]:
		if not _shape(owner, {"schema_version": TYPE_INT, "owner_unit_id": TYPE_INT, "next_item_id": TYPE_INT, "next_effect_id": TYPE_INT, "closed": TYPE_BOOL, "inventory_lifecycle": TYPE_INT, "equipment_lifecycle": TYPE_INT, "inventory_order": TYPE_ARRAY, "definitions": TYPE_ARRAY, "items": TYPE_ARRAY}): return "owners/schema"
		items += owner["items"].size()
		definitions += owner["definitions"].size()
		if items > MAX_ITEMS_TOTAL: return "owners/items/limit"
		if definitions > MAX_DEFINITIONS_TOTAL: return "owners/definitions/limit"
		for id: Variant in owner["inventory_order"]:
			if typeof(id) != TYPE_INT: return "owners/inventory_order/type"
		for definition: Variant in owner["definitions"]:
			var definition_fields := {"id": TYPE_STRING, "effects": TYPE_ARRAY}
			definition_fields.merge({"use_heal_amount": TYPE_FLOAT, "max_charges": TYPE_INT})
			definition_fields["use_summon"] = TYPE_BOOL
			definition_fields["armor_max"] = TYPE_INT
			definition_fields["armor_resistances"] = TYPE_DICTIONARY
			definition_fields["summon_definition"] = TYPE_DICTIONARY
			if not _shape(definition, definition_fields): return "owners/definitions/schema"
			if definition["use_summon"]:
				if not SummonDefinition.valid_data(definition["summon_definition"]): return "owners/definitions/summon_definition"
			elif not definition["summon_definition"].is_empty(): return "owners/definitions/summon_definition/unusable"
			definition_effects += definition["effects"].size()
			if definition_effects > MAX_DEFINITION_EFFECTS_TOTAL: return "owners/definitions/effects/limit"
			for effect: Variant in definition["effects"]:
				if not _effect_shape(effect, false): return "owners/definitions/effects/schema"
		for item: Variant in owner["items"]:
			var item_fields := {"item_instance_id": TYPE_INT, "definition_id": TYPE_STRING, "placement": TYPE_INT, "active": TYPE_BOOL, "effects": TYPE_ARRAY}
			item_fields["charges_left"] = TYPE_INT
			item_fields["armor_remaining"] = TYPE_INT
			item_fields["armor_origin_owner"] = TYPE_INT
			item_fields["armor_origin_item"] = TYPE_INT
			if not _shape(item, item_fields): return "owners/items/schema"
			effects += item["effects"].size()
			if effects > MAX_EFFECTS_TOTAL: return "owners/items/effects/limit"
			for effect: Variant in item["effects"]:
				if not _effect_shape(effect, true): return "owners/items/effects/schema"
	if data["summons"].size() > MAX_OWNERS: return "summons/limit"
	for summon: Variant in data["summons"]:
		var fields := {"unit_id": TYPE_INT, "owner_unit_id": TYPE_INT, "pending": TYPE_BOOL}
		if typeof(summon) == TYPE_DICTIONARY and summon.has("source_kind"): fields["source_kind"] = TYPE_STRING
		if not _shape(summon, fields): return "summons/schema"
	return ""

static func _board_structure(envelope: Dictionary) -> String:
	# Raw-лимиты и типы проверяем раньше version capability и внутренних P02 resize.
	if not _shape(envelope, {"schema_version": TYPE_INT, "scope": TYPE_STRING, "board": TYPE_DICTIONARY}): return "board_snapshot/schema"
	var board: Dictionary = envelope["board"]
	var board_fields := {"schema_version": TYPE_INT, "width": TYPE_INT, "height": TYPE_INT, "board_version": TYPE_INT, "heights": TYPE_ARRAY, "terrain": TYPE_ARRAY, "units": TYPE_ARRAY, "occupancy": TYPE_ARRAY}
	var board_schema: Variant = board.get("schema_version")
	if typeof(board_schema) == TYPE_INT and (board_schema == 2 or board.has("height_half_steps")): board_fields["height_half_steps"] = TYPE_ARRAY
	if not _shape(board, board_fields): return "board/schema"
	if board["width"] < 0 or board["height"] < 0 or board["width"] > 1024 or board["height"] > 1024 or board["width"] * board["height"] > 65536: return "board/limit"
	if board["units"].size() > MAX_OWNERS or board["occupancy"].size() > 65536 or board["heights"].size() > 65536 or board["terrain"].size() > 65536: return "board/limit"
	for key: String in ["heights", "terrain"]:
		for cell: Variant in board[key]:
			if typeof(cell) != TYPE_INT: return "board/" + key + "/type"
	if board["schema_version"] == 2:
		if board["height_half_steps"].size() != board["width"] * board["height"]: return "board/height_half_steps/size"
		var any_half := false
		for bit: Variant in board["height_half_steps"]:
			if typeof(bit) != TYPE_INT or bit < 0 or bit > 1: return "board/height_half_steps/type"
			any_half = any_half or bit == 1
		if not any_half: return "board/height_half_steps/canonical"
	for cell: Variant in board["occupancy"]:
		if not _shape(cell, {"x": TYPE_INT, "y": TYPE_INT, "unit_id": TYPE_INT}): return "board/occupancy/schema"
	for unit: Variant in board["units"]:
		var unit_fields := {"schema_version": TYPE_INT, "id": TYPE_INT, "faction": TYPE_INT, "cell_x": TYPE_INT, "cell_y": TYPE_INT, "height": TYPE_INT, "debug_name": TYPE_STRING, "ai_profile_path": TYPE_STRING, "move_points_left": TYPE_FLOAT, "has_attacked": TYPE_BOOL, "stats": TYPE_DICTIONARY, "vitals": TYPE_DICTIONARY, "guard_stance": TYPE_BOOL}
		if typeof(unit) != TYPE_DICTIONARY: return "board/unit/schema"
		for key: String in ["action_resources", "armor", "bleeding", "control", "combat_perks", "elemental"]:
			if unit.has(key): unit_fields[key] = TYPE_DICTIONARY
		if not _shape(unit, unit_fields): return "board/unit/schema"
		if not _shape(unit["stats"], {"schema_version": TYPE_INT, "stats": TYPE_ARRAY}): return "board/unit/stats/schema"
		if not _shape(unit["vitals"], {"hp": TYPE_FLOAT, "balance": TYPE_FLOAT, "is_alive": TYPE_BOOL}): return "board/unit/vitals/schema"
		for entry: Variant in unit["stats"]["stats"]:
			if not _shape(entry, {"stat_type": TYPE_INT, "stat": TYPE_DICTIONARY}): return "board/unit/stat/schema"
			if not _shape(entry["stat"], {"schema_version": TYPE_INT, "base_value": TYPE_FLOAT, "next_modifier_slot": TYPE_INT, "modifiers": TYPE_ARRAY}): return "board/unit/stat/schema"
			for modifier: Variant in entry["stat"]["modifiers"]:
				if not _shape(modifier, {"source_id": TYPE_STRING, "instance_id": TYPE_INT, "local_slot": TYPE_INT, "evaluation_order": TYPE_INT, "operation": TYPE_INT, "value": TYPE_FLOAT}): return "board/unit/modifier/schema"
	return ""

static func _definition_value(definition: ItemDef) -> Dictionary:
	var effects: Array = []
	for effect: ItemEffect in definition.effects:
		if effect.get_script() == StatModifierEffect:
			var stat := effect as StatModifierEffect
			effects.append({"kind": "stat_modifier", "stat_type": int(stat.stat_type), "operation": int(stat.operation), "value": stat.value})
		else:
			var heal := effect as HealOnDamageEffect
			effects.append({"kind": "heal_on_damage", "trigger_event": int(heal.trigger_event), "heal_amount": heal.heal_amount})
	return {"id": String(definition.id), "effects": effects,
		"use_heal_amount": definition.use_heal_amount, "max_charges": definition.max_charges,
		"use_summon": definition.use_summon, "armor_max": definition.armor_max,
		"armor_resistances": definition.armor_resistances.duplicate(true),
		"summon_definition": definition.get_summon_definition().to_dict() if definition.use_summon else {}}


static func _definition_error(definition: ItemDef, path: String) -> String:
	if definition != null and definition.cooldown_turns != 0: return "UNSUPPORTED:" + path + "/cooldown"
	if definition != null:
		for effect: ItemEffect in definition.effects:
			if effect != null and effect.cooldown_turns != 0: return "UNSUPPORTED:" + path + "/effect_cooldown"
	if definition == null: return path
	if definition.get_script() != ItemDef and definition.get_script() != Item: return "UNSUPPORTED:" + path + "/subclass"
	if not definition.summon_definition_valid(): return path + "/summon_definition"
	if definition.id == &"" or String(definition.id).to_utf8_buffer().size() > MAX_STRING_BYTES: return path + "/id"
	if not is_finite(definition.use_heal_amount): return path + "/use_heal_amount/finite"
	if (definition.use_heal_amount == 0.0 and not definition.use_summon) != (definition.max_charges == 0): return path + "/usable_pair"
	if definition.use_heal_amount < 0.0 or (definition.max_charges != 0 and (definition.max_charges < 1 or definition.max_charges > 4096)) or (definition.use_summon and definition.use_heal_amount != 0.0): return path + "/usable_pair"
	if definition.armor_max < 0 or definition.armor_max > MAX_ID or not _armor_resistances_valid(definition.armor_resistances): return path + "/armor"
	if definition.effects.size() > MAX_DEFINITION_EFFECTS_TOTAL: return path + "/effects/limit"
	for effect: ItemEffect in definition.effects:
		if effect == null: return path + "/effect"
		if effect.get_script() == StatModifierEffect:
			var stat := effect as StatModifierEffect
			if not is_finite(stat.value): return path + "/effect/value"
			if not StatTypes.is_valid_id(stat.stat_type) or int(stat.operation) not in [0, 1, 2]: return "UNSUPPORTED:" + path + "/effect/enum"
		elif effect.get_script() == HealOnDamageEffect:
			var heal := effect as HealOnDamageEffect
			if not is_finite(heal.heal_amount) or heal.heal_amount < 0.0: return path + "/effect/heal_amount"
			if int(heal.trigger_event) != 0: return "UNSUPPORTED:" + path + "/effect/trigger"
		else: return "UNSUPPORTED:" + path + "/effect/subclass"
	return ""

static func _armor_resistances_valid(value: Variant) -> bool:
	return _shape(value, {"physical": TYPE_INT, "fire": TYPE_INT})

static func capture(state: ItemSimulationState, unsupported_runtime_ids: Array[StringName]) -> ItemSnapshotResult:
	var external := SimulationSnapshot._sorted_ids(unsupported_runtime_ids)
	if not external.is_empty():
		var result := _failure("UNSUPPORTED:unsupported_runtime_ids")
		result.unsupported_ids = external
		return result
	if state == null: return _failure("state")
	# Guard читается до capability/графа и никогда не снимается чтением снимка.
	var busy_id := MAX_ID
	var busy := false
	for owner: ItemOwnerState in state._owners:
		if owner != null and owner._guard and not owner._closed:
			busy = true
			busy_id = mini(busy_id, owner._owner.id if owner._owner != null else 0)
	if busy: return _failure("BUSY:owner/%d/guard" % busy_id)
	var shape_error := _live_shape_error(state)
	if not shape_error.is_empty(): return _failure(shape_error)
	if state.get_script() != ItemSimulationState: return _failure("UNSUPPORTED:state/subclass")
	var error := _live_structure(state)
	if not error.is_empty(): return _failure(error)
	var board_result := SimulationSnapshot.capture_board(state.get_board(), [])
	if board_result.code != BoardSnapshotResult.Code.OK:
		return _failure(("UNSUPPORTED:" if board_result.code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED else "") + board_result.reason)
	# Этот DTO создан здесь и ещё никому не передан. Внешний снимок ниже всё
	# равно копирует payload; промежуточная копия всей доски не нужна.
	var board_data := board_result.snapshot._data
	var units: Dictionary = {}
	for unit: Dictionary in board_data["board"]["units"]: units[unit["id"]] = unit
	var records: Array = []
	var owners := state.get_owners()
	owners.sort_custom(func(a: ItemOwnerState, b: ItemOwnerState) -> bool: return a._owner.id < b._owner.id)
	for owner: ItemOwnerState in owners:
		var id := owner._owner.id
		var sources := _modifiers(units[id])
		var definitions: Array = []
		for definition: ItemDef in owner._definitions.values():
			if owner._owner.armor == null and (definition.armor_max != 0 or definition.armor_resistances != {"physical": 0, "fire": 0}): return _failure("UNSUPPORTED:capability_required")
			definitions.append(_definition_value(definition))
		var items: Array = []
		for item: ItemInstance in owner._items.values():
			var effects: Array = []
			for runtime: ItemEffectRuntime in item._effects:
				var effect := {"effect_instance_id": runtime._effect_instance_id, "effect_index": runtime._effect_index, "active": runtime._active}
				if runtime.get_script() == StatModifierEffectRuntime:
					var stat := runtime as StatModifierEffectRuntime
					var source := String(stat.get_source_key())
					var links: Array = []
					if stat._active and sources.has(source):
						for occurrence: Dictionary in sources[source]:
							links.append({"stat_type": occurrence["stat_type"], "source_id": source, "instance_id": occurrence["record"]["instance_id"], "local_slot": occurrence["record"]["local_slot"]})
					effect.merge({"kind": "stat_modifier", "stat_type": int(stat._stat_type), "operation": int(stat._operation), "value": stat._value, "source_key": source, "modifier_link": links})
				else:
					var heal := runtime as HealOnDamageEffectRuntime
					effect.merge({"kind": "heal_on_damage", "trigger_event": int(heal._trigger_event), "heal_amount": heal._heal_amount})
				effects.append(effect)
			var item_record := {"item_instance_id": item._item_id, "definition_id": String(item._definition_id), "placement": item._placement, "active": item._active, "effects": effects}
			item_record["charges_left"] = item._charges_left
			item_record["armor_remaining"] = item.armor_remaining
			item_record["armor_origin_owner"] = item.armor_origin_owner
			item_record["armor_origin_item"] = item.armor_origin_item
			items.append(item_record)
		records.append({"schema_version": 1, "owner_unit_id": id, "next_item_id": owner._next_item_id, "next_effect_id": owner._next_effect_id, "closed": owner._closed, "inventory_lifecycle": _lifecycle(owner._inventory_registered, owner._inventory_retired), "equipment_lifecycle": _lifecycle(owner._equipment_registered, owner._equipment_retired), "inventory_order": Array(owner._inventory_order), "definitions": definitions, "items": items})
	var payload := {"schema_version": SCHEMA_VERSION, "scope": SCOPE, "board_snapshot": board_data, "owners": records, "summons": state.get_summons()}
	if state.abilities != null: payload["abilities"] = state.abilities.to_dict()
	if state.environment != null: payload["environment"] = state.environment.to_dict()
	if state.artifacts != null: payload["artifacts"] = state.artifacts.to_dict()
	if state.deck != null:
		payload["deck"] = state.deck.to_dict(); payload["card_effects"] = state.card_effects.to_dict()
	# Между capture_board и этой проверкой менялись только записи предметов.
	# Уже проверенная доска остаётся тем же локальным DTO, а общий raw preflight,
	# лимиты и связи владельцев выполняются по-прежнему для всего payload.
	error = _validate(payload, board_result.snapshot)
	if not error.is_empty(): return _failure(error)
	# Доска уже отделена от runtime внутри capture_board и принадлежит только
	# этому вызову. Передаём её внешнему снимку без второго рекурсивного копирования;
	# остальные ветви отделяем по-прежнему, включая вложенные определения предметов.
	var owned_payload: Dictionary = {}
	for key: String in payload:
		owned_payload[key] = board_data if key == "board_snapshot" else SimulationSnapshot._copy_value(payload[key])
	var snapshot := ItemSimulationSnapshot.new()
	snapshot._data = _normalize(owned_payload)
	var result := ItemSnapshotResult.new()
	result.code = ItemSnapshotResult.Code.OK
	result.snapshot = snapshot
	return result

static func _lifecycle(registered: bool, retired: bool) -> int:
	return 1 if registered else (2 if retired else 0)

static func _live_shape_error(state: ItemSimulationState) -> String:
	if not MageDeckRules.live_valid(state): return "deck/invalid_state"
	if state.abilities != null and (state.abilities.get_script() != BattleAbilityState or not BattleAbilityState.valid(state.abilities.to_dict())): return "abilities/invalid_state"
	if state.environment != null and (state.environment.get_script() != CombatEnvironmentState or not CombatEnvironmentState.valid(state.environment.to_dict())): return "environment/invalid_state"
	if state._summons.size() > MAX_OWNERS: return "summons/limit"
	var nodes: Array[int] = [0]
	var metadata_error := _walk(state._summons, 0, [], nodes, "summons")
	if metadata_error != "": return metadata_error
	for record: Dictionary in state._summons:
		var fields := {"unit_id": TYPE_INT, "owner_unit_id": TYPE_INT, "pending": TYPE_BOOL}
		if typeof(record) == TYPE_DICTIONARY and record.has("source_kind"): fields["source_kind"] = TYPE_STRING
		if not _shape(record, fields): return "summons/schema"
	if state.artifacts != null:
		if state.artifacts.get_script() != BattleArtifactState or not BattleArtifactState.valid(state.artifacts.to_dict()) or not state.artifacts.references_valid(state._board): return "artifacts/invalid_state"
		for hero_id: int in state.artifacts.heroes:
			if state.is_summon(hero_id): return "artifacts/summon_reference"
		for item: Dictionary in state.artifacts.equipped:
			if state.is_summon(item["unit_id"]): return "artifacts/summon_equipped"
	# Общий проход до capability: поздний повреждённый контейнер/NaN/overflow
	# не должен маскироваться ранним неизвестным подклассом другого owner.
	if state._board == null: return "board"
	var board_error := _live_board_shape_error(state._board)
	if not board_error.is_empty(): return board_error
	if state._owners.size() > MAX_OWNERS: return "owners/limit"
	var items := 0
	var effects := 0
	var definitions := 0
	var definition_effects := 0
	var live_armor_keys: Dictionary = {}
	for owner: ItemOwnerState in state._owners:
		if owner == null or owner._owner == null: return "owners/owner"
		items += owner._items.size()
		definitions += owner._definitions.size()
		if items > MAX_ITEMS_TOTAL or definitions > MAX_DEFINITIONS_TOTAL: return "owners/limit"
		for key: Variant in owner._placements:
			if typeof(key) != TYPE_INT or typeof(owner._placements[key]) != TYPE_INT: return "owners/placements/type"
		for key: Variant in owner._definitions:
			if typeof(key) != TYPE_STRING_NAME or not (owner._definitions[key] is ItemDef): return "owners/definitions/type"
			var definition: ItemDef = owner._definitions[key]
			var summon_definition := definition.summon_definition
			if summon_definition != null and (not definition.use_summon or not SummonDefinition.valid_definition(summon_definition)): return "owners/definitions/summon_definition"
			if definition.armor_max < 0 or not ArmorState.valid_resistances(definition.armor_resistances): return "owners/definitions/armor"
			if not is_finite(definition.use_heal_amount): return "owners/definitions/use_heal_amount/finite"
			if (definition.use_heal_amount == 0.0 and not definition.use_summon) != (definition.max_charges == 0) or definition.use_heal_amount < 0.0 or definition.max_charges < 0 or definition.max_charges > 4096 or (definition.use_summon and definition.use_heal_amount != 0.0): return "owners/definitions/usable_pair"
			definition_effects += definition.effects.size()
			if definition_effects > MAX_DEFINITION_EFFECTS_TOTAL: return "owners/definitions/effects/limit"
			if String(key).to_utf8_buffer().size() > MAX_STRING_BYTES or String(definition.id).to_utf8_buffer().size() > MAX_STRING_BYTES: return "owners/definitions/string_bytes"
			for effect: ItemEffect in definition.effects:
				if effect == null: return "owners/definitions/effect"
				if effect is StatModifierEffect and not is_finite((effect as StatModifierEffect).value): return "owners/definitions/value/finite"
				if effect is HealOnDamageEffect and not is_finite((effect as HealOnDamageEffect).heal_amount): return "owners/definitions/heal_amount/finite"
		for key: Variant in owner._items:
			if typeof(key) != TYPE_INT or not (owner._items[key] is ItemInstance): return "owners/items/type"
			var item: ItemInstance = owner._items[key]
			if item._definition == null: return "owners/items/definition"
			if item.armor_remaining < 0 or item.armor_remaining > item._definition.armor_max or item.armor_origin_owner < 1 or item.armor_origin_item < 1 or item.armor_origin_owner >= MAX_ID or item.armor_origin_item >= MAX_ID: return "owners/items/armor"
			var armor_key := [item.armor_origin_owner, item.armor_origin_item]
			if live_armor_keys.has(armor_key): return "armor/identity"
			live_armor_keys[armor_key] = true
			if item._charges_left < 0 or item._charges_left > item._definition.max_charges: return "owners/items/charges"
			if String(item._definition_id).to_utf8_buffer().size() > MAX_STRING_BYTES: return "owners/items/definition_id/string_bytes"
			effects += item._effects.size()
			if effects > MAX_EFFECTS_TOTAL: return "owners/effects/limit"
			for runtime: ItemEffectRuntime in item._effects:
				if runtime == null: return "owners/runtime"
				if runtime is StatModifierEffectRuntime and not is_finite((runtime as StatModifierEffectRuntime)._value): return "owners/runtime/value/finite"
				if runtime is HealOnDamageEffectRuntime and not is_finite((runtime as HealOnDamageEffectRuntime)._heal_amount): return "owners/runtime/heal_amount/finite"
	for facade: InventoryState in state._inventories:
		if facade == null or facade._state == null: return "inventories/facade"
	for facade: EquipmentState in state._equipment:
		if facade == null or facade._state == null: return "equipment/facade"
	return ""

static func _live_board_shape_error(board: BattleBoard) -> String:
	if board.width < 0 or board.height < 0 or board.width > 1024 or board.height > 1024 or board.width * board.height > 65536 or board._units.size() > MAX_OWNERS: return "board/limit"
	if board._heights.size() != board.width * board.height or board._terrain.size() != board.width * board.height: return "board/cells"
	for key: Variant in board._units:
		if typeof(key) != TYPE_INT or not (board._units[key] is UnitState): return "board/units/type"
		var unit: UnitState = board._units[key]
		if unit.get_script() != UnitState: return "UNSUPPORTED:board/unit/subclass"
		if unit.stats == null or unit.vitals == null: return "board/unit/state"
		if unit.stats.get_script() != StatsBag: return "UNSUPPORTED:board/unit/stats/subclass"
		if unit.vitals.get_script() != Vitals: return "UNSUPPORTED:board/unit/vitals/subclass"
		if unit.action_resources != null and unit.action_resources.get_script() != ActionResources: return "UNSUPPORTED:board/unit/action_resources/subclass"
		if unit.control != null:
			if unit.control.get_script() != ControlState: return "UNSUPPORTED:board/unit/control/subclass"
			if not ControlState.valid(unit.control.to_dict()): return "board/unit/control"
		if unit.elemental != null:
			if unit.elemental.get_script() != ElementalState: return "UNSUPPORTED:board/unit/elemental/subclass"
			if not ElementalRules.valid_unit(unit): return "board/unit/elemental"
		if unit.combat_perks != null:
			if unit.combat_perks.get_script() != CombatPerksState: return "UNSUPPORTED:board/unit/combat_perks/subclass"
			if unit.combat_perks.definition != null and unit.combat_perks.definition.get_script() != CombatPerksDefinition: return "UNSUPPORTED:board/unit/combat_perks/definition/subclass"
			if unit.combat_perks.to_dict().is_empty(): return "board/unit/combat_perks"
		if unit.debug_name.to_utf8_buffer().size() > MAX_STRING_BYTES: return "board/unit/name/string_bytes"
		if not is_finite(unit.move_points_left) or not is_finite(unit.vitals._hp) or not is_finite(unit.vitals._balance): return "board/unit/finite"
		for stat_key: Variant in unit.stats._stats:
			if typeof(stat_key) != TYPE_INT or not (unit.stats._stats[stat_key] is Stat): return "board/unit/stats/type"
			var stat: Stat = unit.stats._stats[stat_key]
			if stat.get_script() != Stat: return "UNSUPPORTED:board/unit/stat/subclass"
			if not is_finite(stat.base_value): return "board/unit/stat/base/finite"
			if stat._modifiers.size() != stat._modifier_slots.size(): return "board/unit/stat/slots"
			for modifier: StatModifier in stat._modifiers:
				if modifier == null: return "board/unit/modifier"
				if modifier.get_script() != StatModifier: return "UNSUPPORTED:board/unit/modifier/subclass"
				if not is_finite(modifier.value): return "board/unit/modifier/finite"
				if String(modifier.source_id).to_utf8_buffer().size() > MAX_STRING_BYTES: return "board/unit/modifier/source/string_bytes"
	for key: Variant in board._occupancy:
		if typeof(key) != TYPE_VECTOR2I or typeof(board._occupancy[key]) != TYPE_INT: return "board/occupancy/type"
	return ""

static func _live_structure(state: ItemSimulationState) -> String:
	var board := state.get_board()
	if board == null: return "board"
	var owners := state.get_owners()
	if owners.size() > MAX_OWNERS or owners.size() != board._units.size(): return "owners/count"
	var seen: Dictionary = {}
	var item_count := 0
	var effect_count := 0
	var definition_count := 0
	var definition_effect_count := 0
	for owner: ItemOwnerState in owners:
		if owner == null or owner._owner == null: return "owners/owner"
		if owner.get_script() != ItemOwnerState: return "UNSUPPORTED:owners/subclass"
		var id := owner._owner.id
		if seen.has(id) or board._units.get(id) != owner._owner: return "owner/%d/identity" % id
		seen[id] = owner
	owners.sort_custom(func(a: ItemOwnerState, b: ItemOwnerState) -> bool: return a._owner.id < b._owner.id)
	for owner: ItemOwnerState in owners:
		var id := owner._owner.id
		var path := "owner/%d" % id
		if (owner._inventory_registered and owner._inventory_retired) or (owner._equipment_registered and owner._equipment_retired): return path + "/lifecycle"
		item_count += owner._items.size()
		definition_count += owner._definitions.size()
		if item_count > MAX_ITEMS_TOTAL or definition_count > MAX_DEFINITIONS_TOTAL: return path + "/limit"
		if owner._placements.size() != owner._items.size(): return path + "/placements"
		for key: Variant in owner._definitions:
			if typeof(key) != TYPE_STRING_NAME or not (owner._definitions[key] is ItemDef): return path + "/definitions/registry"
		var definition_keys: Array = owner._definitions.keys()
		definition_keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for key: StringName in definition_keys:
			var definition: ItemDef = owner._definitions[key]
			if definition.id != key: return path + "/definitions/id"
			definition_effect_count += definition.effects.size()
			if definition_effect_count > MAX_DEFINITION_EFFECTS_TOTAL: return path + "/definitions/effects/limit"
			var error := _definition_error(definition, path + "/definition/" + String(key))
			if not error.is_empty(): return error
		for key: Variant in owner._items:
			if typeof(key) != TYPE_INT or not (owner._items[key] is ItemInstance): return path + "/items/registry"
		var item_keys: Array = owner._items.keys()
		item_keys.sort()
		for key: int in item_keys:
			if not owner._placements.has(key) or typeof(owner._placements[key]) != TYPE_INT: return path + "/placements"
			var item: ItemInstance = owner._items[key]
			if item.get_script() != ItemInstance: return "UNSUPPORTED:" + path + "/item/subclass"
			if item._item_id != key or item._owner_id != id or item._placement != owner._placements[key]: return path + "/item/identity"
			if item._definition == null or item._definition_id != item._definition.id or owner._definitions.get(item._definition_id) != item._definition: return path + "/item/definition_identity"
			effect_count += item._effects.size()
			if effect_count > MAX_EFFECTS_TOTAL: return path + "/effects/limit"
			for runtime: ItemEffectRuntime in item._effects:
				if runtime == null: return path + "/runtime"
			var runtimes := item._effects.duplicate()
			runtimes.sort_custom(func(a: ItemEffectRuntime, b: ItemEffectRuntime) -> bool: return a._effect_instance_id < b._effect_instance_id)
			for runtime: ItemEffectRuntime in runtimes:
				if runtime.get_script() != StatModifierEffectRuntime and runtime.get_script() != HealOnDamageEffectRuntime: return "UNSUPPORTED:" + path + "/runtime/subclass"
				if runtime._owner_unit_id != id or runtime._item_instance_id != key: return path + "/runtime/identity"
	var error := _facades(state.get_inventories(), seen, true)
	if not error.is_empty(): return error
	return _facades(state.get_equipment_facades(), seen, false)

static func _facades(facades: Array, owners: Dictionary, inventory: bool) -> String:
	var seen: Dictionary = {}
	var path := "inventories" if inventory else "equipment"
	for facade: Variant in facades:
		if facade == null: return path + "/facade"
		if facade.get_script() != (InventoryState if inventory else EquipmentState): return "UNSUPPORTED:" + path + "/subclass"
		var owner: ItemOwnerState = facade._state
		if owner == null or owner._owner == null: return path + "/owner"
		var id := owner._owner.id
		if owners.get(id) != owner or seen.has(id) or facade._closed or owner._closed: return path + "/identity"
		if not (owner._inventory_registered if inventory else owner._equipment_registered): return path + "/lifecycle"
		seen[id] = true
	var ids: Array = owners.keys()
	ids.sort()
	for id: int in ids:
		var owner: ItemOwnerState = owners[id]
		if (owner._inventory_registered if inventory else owner._equipment_registered) != seen.has(id): return path + "/missing/%d" % id
	return ""

func instantiate(definitions: Dictionary) -> ItemSnapshotResult:
	var error := _validate(_data)
	if not error.is_empty(): return _failure(error)
	# Каталог проверяется целиком до P02 allocation, но лишний контент не включается в DTO.
	for key: Variant in definitions:
		if typeof(key) != TYPE_STRING_NAME or not (definitions[key] is ItemDef): return _failure("definitions/catalogue/type")
	var checked: Dictionary = {}
	for owner: Dictionary in _data["owners"]:
		for descriptor: Dictionary in owner["definitions"]:
			var id := StringName(descriptor["id"])
			if checked.has(id): continue
			if not definitions.has(id): return _failure("UNSUPPORTED:definitions/" + String(id) + "/missing")
			var definition: ItemDef = definitions[id]
			error = _definition_error(definition, "definitions/" + String(id))
			if not error.is_empty(): return _failure(error)
			if definition.id != id or _definition_value(definition) != descriptor: return _failure("definitions/" + String(id) + "/content")
			checked[id] = definition
	# _validate выше уже проверил envelope. Повторный from_dict создавал ещё
	# копию и нормализовал её, хотя BattleBoard сам проверяет DTO при восстановлении.
	var board := BattleBoard.from_snapshot_dict(_data["board_snapshot"]["board"])
	if board == null: return _failure("board/instantiate")
	var result := ItemSnapshotResult.new()
	result.code = ItemSnapshotResult.Code.OK
	result.state = _build_checked_state(_data, checked, board)
	return result

static func _build_checked_state(data: Dictionary, checked: Dictionary, board: BattleBoard) -> ItemSimulationState:
	# Только сразу после свежей проверки, с её DTO, соответствующей новой доской
	# и проверенным каталогом. Долгоживущий допуск этот внутренний builder не создаёт.
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	for record: Dictionary in data["owners"]:
		var owner := ItemOwnerState.new(board.get_unit_by_id(record["owner_unit_id"]))
		owner._next_item_id = record["next_item_id"]
		owner._next_effect_id = record["next_effect_id"]
		owner._closed = record["closed"]
		owner._inventory_registered = record["inventory_lifecycle"] == 1
		owner._inventory_retired = record["inventory_lifecycle"] == 2
		owner._equipment_registered = record["equipment_lifecycle"] == 1
		owner._equipment_retired = record["equipment_lifecycle"] == 2
		owner._inventory_order.assign(record["inventory_order"])
		for descriptor: Dictionary in record["definitions"]:
			var id := StringName(descriptor["id"])
			# Каждое восстановление и владелец получают свою зафиксированную печать.
			var definition: ItemDef = checked[id]
			owner._definitions[id] = definition.duplicate(true) if definition.use_summon else definition
		for item_record: Dictionary in record["items"]:
			var effects: Array[ItemEffectRuntime] = []
			effects.resize(item_record["effects"].size())
			for effect: Dictionary in item_record["effects"]:
				var runtime: ItemEffectRuntime
				if effect["kind"] == "stat_modifier":
					runtime = StatModifierEffectRuntime.new(record["owner_unit_id"], item_record["item_instance_id"], effect["effect_instance_id"], effect["effect_index"], effect["stat_type"] as StatTypes.StatType, effect["operation"] as StatModifier.Operation, effect["value"])
				else:
					runtime = HealOnDamageEffectRuntime.new(record["owner_unit_id"], item_record["item_instance_id"], effect["effect_instance_id"], effect["effect_index"], effect["heal_amount"], effect["trigger_event"] as TriggeredEffect.TriggerEvent)
				runtime._active = effect["active"]
				effects[effect["effect_index"]] = runtime
			var charges: int = item_record["charges_left"]
			var item := ItemInstance.new(owner._definitions[StringName(item_record["definition_id"])], record["owner_unit_id"], item_record["item_instance_id"], effects, charges)
			item._placement = item_record["placement"]
			item._active = item_record["active"]
			item.armor_remaining = item_record["armor_remaining"]
			item.armor_origin_owner = item_record["armor_origin_owner"]
			item.armor_origin_item = item_record["armor_origin_item"]
			owner._items[item._item_id] = item
			owner._placements[item._item_id] = item._placement
		owners.append(owner)
		if owner._inventory_registered: inventories.append(InventoryState._restore_registered(owner))
		if owner._equipment_registered: equipment.append(EquipmentState._restore_registered(owner))
	var state := ItemSimulationState.new(board, owners, inventories, equipment)
	for record: Dictionary in data["summons"]:
		state._summons.append(record.duplicate(true))
	if data.has("abilities"): state.abilities = BattleAbilityState.from_dict(data["abilities"])
	if data.has("environment"): state.environment = CombatEnvironmentState.from_dict(data["environment"])
	if data.has("artifacts"): state.artifacts = BattleArtifactState.from_dict(data["artifacts"])
	if data.has("deck"):
		state.deck = BattleDeckState.from_dict(data["deck"])
		state.card_effects = BattleCardEffectState.from_dict(data["card_effects"])
	return state

static func _effect_capability(effect: Dictionary) -> bool:
	match effect["kind"]:
		"stat_modifier": return StatTypes.is_valid_id(effect["stat_type"]) and effect["operation"] >= 0 and effect["operation"] <= 2
		"heal_on_damage": return effect["trigger_event"] == 0
	return false

static func _validate(data: Dictionary, captured_board: SimulationSnapshot = null) -> String:
	var nodes: Array[int] = [0]
	var error := ""
	if not _walk_valid(data, 0, [], nodes):
		nodes[0] = 0
		error = _walk(data, 0, [], nodes, "envelope")
		if not error.is_empty(): return error
	error = _structure(data, captured_board)
	if not error.is_empty(): return error
	if data["schema_version"] != SCHEMA_VERSION: return "UNSUPPORTED:envelope/version"
	if data["scope"] != SCOPE: return "UNSUPPORTED:envelope/scope"
	if data.has("abilities") and not BattleAbilityState.valid(data["abilities"]): return "abilities/invalid_state"
	if not data.has("deck") and data.has("abilities") and data.abilities.get("schema_version") != 1: return "abilities/deck_required"
	if data.has("artifacts") and not BattleArtifactState.valid(data["artifacts"]): return "artifacts/invalid_state"
	if data.has("deck") != data.has("card_effects") or (data.has("deck") and not data.has("abilities")): return "deck/invalid_state"
	# Числовой порядок делает диагностику независимой от перестановки records.
	var owners: Array = data["owners"].duplicate()
	owners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["owner_unit_id"] < b["owner_unit_id"])
	for owner: Dictionary in owners:
		var path := "owner/%d" % owner["owner_unit_id"]
		if owner["schema_version"] != 1: return "UNSUPPORTED:" + path + "/version"
		var definitions: Array = owner["definitions"].duplicate()
		definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
		var definition_map: Dictionary = {}
		for definition: Dictionary in definitions:
			definition_map[definition["id"]] = definition
			if definition["armor_max"] < 0 or not _armor_resistances_valid(definition["armor_resistances"]): return path + "/definition/armor"
			var summon_flag: bool = definition.get("use_summon", false)
			if ((definition["use_heal_amount"] == 0.0 and not summon_flag) != (definition["max_charges"] == 0) or definition["use_heal_amount"] < 0.0 or definition["max_charges"] < 0 or definition["max_charges"] > 4096 or (summon_flag and definition["use_heal_amount"] != 0.0)): return path + "/definition/usable_pair"
			for effect: Dictionary in definition["effects"]:
				if not _effect_capability(effect): return "UNSUPPORTED:" + path + "/definition/" + definition["id"] + "/effect"
		var items: Array = owner["items"].duplicate()
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_instance_id"] < b["item_instance_id"])
		for item: Dictionary in items:
			var item_definition: Dictionary = definition_map.get(item["definition_id"], {})
			var max_armor: int = int(item_definition.get("armor_max", -1))
			if item["armor_remaining"] < 0 or item["armor_remaining"] > max_armor or item["armor_origin_owner"] <= 0 or item["armor_origin_owner"] >= MAX_ID or item["armor_origin_item"] <= 0 or item["armor_origin_item"] >= MAX_ID: return path + "/item/armor"
			if item["charges_left"] < 0 or item["charges_left"] > int(item_definition.get("max_charges", 0)): return path + "/item/%d/charges" % item["item_instance_id"]
			var effects: Array = item["effects"].duplicate()
			effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["effect_instance_id"] < b["effect_instance_id"])
			for effect: Dictionary in effects:
				if not _effect_capability(effect): return "UNSUPPORTED:" + path + "/effect/%d" % effect["effect_instance_id"]
	# Исключение только для локального DTO из capture_board. from_dict и
	# instantiate никогда не используют это свидетельство и проверяют доску заново.
	if captured_board == null or not is_same(data["board_snapshot"], captured_board._data):
		error = SimulationSnapshot._validate_envelope(data["board_snapshot"])
		if not error.is_empty(): return error
	if data.has("deck"):
		if not MageDeckRules.snapshot_valid(data): return "deck/invalid_state"
	if data.has("environment"):
		error = EnvironmentRules.snapshot_reason(data["environment"], data["board_snapshot"]["board"], data["summons"])
		if not error.is_empty(): return error
	var units: Array = data["board_snapshot"]["board"]["units"]
	if units.size() != owners.size(): return "owners/count"
	var unit_map: Dictionary = {}
	for unit: Dictionary in units:
		unit_map[unit["id"]] = unit
	for unit: Dictionary in units:
		if not data.has("deck"):
			for source: Dictionary in [unit.get("bleeding",{}).get("source",{}),unit.get("elemental",{}).get("burning_source",{})]:
				if source.get("kind") == &"mage" and source.get("source_instance_id",0) >= 13: return "deck/source_capability"
			if unit.get("armor",{}).get("shield",{}).get("spell_id") == "card.shield": return "deck/shield_capability"
		if unit.get("bleeding", {}).get("ticks_left", 0) > 0:
			var bleeding: Dictionary = unit["bleeding"]
			var source: Dictionary = bleeding["source"]
			if source["kind"] == &"attack" and (not unit_map.has(source["instigator_unit_id"]) or not unit_map.has(source["credit_unit_id"])):
				return "board/unit/bleeding/source"
		if unit.has("elemental"):
			var elemental: Dictionary = unit["elemental"]
			if elemental["burning_stacks"] > 0 and elemental["burning_source"]["kind"] == &"attack":
				var burning_source: Dictionary = elemental["burning_source"]
				if not unit_map.has(burning_source["instigator_unit_id"]) or not unit_map.has(burning_source["credit_unit_id"]): return "board/unit/elemental/burning_source"
	var seen: Dictionary = {}
	var armor_identities: Dictionary = {}
	var catalogue: Dictionary = {}
	for owner: Dictionary in owners:
		var id: int = owner["owner_unit_id"]
		if id <= 0 or seen.has(id) or not unit_map.has(id): return "owner/%d/identity" % id
		seen[id] = true
		error = _owner_graph(owner, unit_map[id], catalogue)
		if not error.is_empty(): return "owner/%d/" % id + error
		for definition: Dictionary in owner["definitions"]:
			if (definition["armor_max"] != 0 or definition["armor_resistances"] != {"physical": 0, "fire": 0}) and not unit_map[id].has("armor"): return "armor/capability_required"
		for item: Dictionary in owner["items"]:
			var armor_key := "%d:%d" % [item["armor_origin_owner"], item["armor_origin_item"]]
			if armor_identities.has(armor_key): return "armor/identity"
			armor_identities[armor_key] = true
	if data.has("abilities"):
		var expected_items: Dictionary = {}
		for descriptor: Dictionary in catalogue.values():
			var item_id: String = descriptor["id"]
			if descriptor["use_summon"]: expected_items["item_use:" + item_id + ":summon_adjacent"] = true
			elif descriptor["use_heal_amount"] > 0.0: expected_items["item_use:" + item_id + ":heal_self"] = true
			for index: int in descriptor["effects"].size(): expected_items["item_effect:%s:%d" % [item_id, index]] = true
		for descriptor: Dictionary in data["abilities"]["catalog"]:
			var id: String = descriptor["ability_id"]
			if not (id.begins_with("item_use:") or id.begins_with("item_effect:")): continue
			if not expected_items.erase(id): return "abilities/item_catalog/reference"
		if not expected_items.is_empty(): return "abilities/item_catalog/missing"
	var snapshot_summon_ids: Dictionary = {}
	var live_by_owner: Dictionary = {}
	var owner_ids: Dictionary = {}
	var metadata_units: Dictionary = {}
	for owner: Dictionary in owners: owner_ids[owner["owner_unit_id"]] = true
	for summon: Dictionary in data["summons"]: metadata_units[summon["unit_id"]] = true
	for summon: Dictionary in data["summons"]:
		var sid: int = summon["unit_id"]
		var oid: int = summon["owner_unit_id"]
		if sid <= 0 or snapshot_summon_ids.has(sid) or not unit_map.has(sid): return "summons/reference"
		if summon.has("source_kind"):
			if summon.source_kind != "mage" or oid != 0 or unit_map[sid].faction != Faction.Type.PLAYER: return "summons/mage_reference"
		else:
			if oid <= 0 or sid == oid or not unit_map.has(oid) or not owner_ids.has(oid) or metadata_units.has(oid): return "summons/reference"
			if unit_map[sid]["faction"] != unit_map[oid]["faction"]: return "summons/faction"
			if unit_map[sid]["vitals"]["is_alive"]:
				if live_by_owner.has(oid): return "summons/owner_limit"
				live_by_owner[oid] = true
		if summon["pending"]:
			var unit_data: Dictionary = unit_map[sid]
			if unit_data.get("guard_stance", false): return "summons/pending/guard"
			if not unit_data.has("action_resources") or typeof(unit_data["action_resources"]) != TYPE_DICTIONARY: return "summons/pending/resources"
			var resources: Dictionary = unit_data["action_resources"]
			if resources.get("main_left", -1) != 0 or resources.get("bonus_left", -1) != 0 or unit_data["move_points_left"] != 0.0: return "summons/pending/resources"
		snapshot_summon_ids[sid] = true
	if data.has("artifacts"):
		for hero_id: int in data["artifacts"]["heroes"]:
			if not unit_map.has(hero_id) or unit_map[hero_id]["faction"] != Faction.Type.PLAYER or snapshot_summon_ids.has(hero_id): return "artifacts/hero_reference"
	return ""

static func _scalar_descriptor(effect: Dictionary) -> Dictionary:
	if effect["kind"] == "stat_modifier":
		return {"kind": "stat_modifier", "stat_type": effect["stat_type"], "operation": effect["operation"], "value": effect["value"]}
	return {"kind": "heal_on_damage", "trigger_event": effect["trigger_event"], "heal_amount": effect["heal_amount"]}

static func _modifiers(unit: Dictionary) -> Dictionary:
	var sources: Dictionary = {}
	for entry: Dictionary in unit["stats"]["stats"]:
		for modifier: Dictionary in entry["stat"]["modifiers"]:
			var source: String = modifier["source_id"]
			if not sources.has(source): sources[source] = []
			sources[source].append({"stat_type": entry["stat_type"], "record": modifier})
	return sources

static func _owner_graph(owner: Dictionary, unit: Dictionary, catalogue: Dictionary) -> String:
	if owner["next_item_id"] < 1 or owner["next_effect_id"] < 1: return "counters"
	if owner["inventory_lifecycle"] not in [0, 1, 2] or owner["equipment_lifecycle"] not in [0, 1, 2]: return "lifecycle"
	if owner["closed"] and (owner["inventory_lifecycle"] != 2 or owner["equipment_lifecycle"] != 2): return "closed/lifecycle"
	var definitions: Dictionary = {}
	for definition: Dictionary in owner["definitions"]:
		var id: String = definition["id"]
		if unit.has("armor"):
			var heal: float = definition.get("use_heal_amount", 0.0)
			if heal != floorf(heal) or heal > ArmorRuntime.MAX_EXACT_HP: return "armor/fractional_heal"
			for effect: Dictionary in definition["effects"]:
				if effect["kind"] == "heal_on_damage" and (effect["heal_amount"] != floorf(effect["heal_amount"]) or effect["heal_amount"] > ArmorRuntime.MAX_EXACT_HP): return "armor/fractional_heal"
		if id.is_empty() or definitions.has(id): return "definitions/id"
		if catalogue.has(id) and catalogue[id] != definition: return "definitions/" + id + "/conflict"
		for effect: Dictionary in definition["effects"]:
			if effect["kind"] == "heal_on_damage" and effect["heal_amount"] < 0.0: return "definitions/" + id + "/heal_amount"
		definitions[id] = definition
		catalogue[id] = definition
	var item_ids: Dictionary = {}
	var effect_ids: Dictionary = {}
	var slots: Dictionary = {}
	var inventory: Dictionary = {}
	var sources := _modifiers(unit)
	var claimed: Dictionary = {}
	var items: Array = owner["items"].duplicate()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_instance_id"] < b["item_instance_id"])
	for item: Dictionary in items:
		var id: int = item["item_instance_id"]
		var path := "item/%d/" % id
		if id < 1 or id >= owner["next_item_id"] or item_ids.has(id): return path + "id"
		item_ids[id] = true
		if not definitions.has(item["definition_id"]): return path + "definition"
		var definition: Dictionary = definitions[item["definition_id"]]
		var placement: int = item["placement"]
		if placement not in [0, 1, 100, 101, 102] or item["active"] != (placement != 0): return path + "placement"
		if owner["closed"] and placement != 0: return path + "closed"
		if placement == 1:
			if owner["inventory_lifecycle"] != 1: return path + "inventory_lifecycle"
			inventory[id] = true
		elif placement >= 100:
			if owner["equipment_lifecycle"] != 1 or slots.has(placement): return path + "equipment_slot"
			slots[placement] = true
		if item["effects"].size() != definition["effects"].size(): return path + "effect_count"
		var indices: Dictionary = {}
		var effects: Array = item["effects"].duplicate()
		effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["effect_instance_id"] < b["effect_instance_id"])
		for effect: Dictionary in effects:
			var eid: int = effect["effect_instance_id"]
			var ep := path + "effect/%d/" % eid
			if eid < 1 or eid >= owner["next_effect_id"] or effect_ids.has(eid): return ep + "id"
			effect_ids[eid] = true
			var index: int = effect["effect_index"]
			if index < 0 or index >= definition["effects"].size() or indices.has(index): return ep + "index"
			indices[index] = true
			if effect["active"] != item["active"] or _scalar_descriptor(effect) != definition["effects"][index]: return ep + "definition"
			if effect["kind"] != "stat_modifier": continue
			var source := "p03a/o%d/i%d/e%d" % [owner["owner_unit_id"], id, eid]
			if effect["source_key"] != source: return ep + "source_key"
			var links: Array = effect["modifier_link"]
			if not effect["active"]:
				if not links.is_empty() or sources.has(source): return ep + "inactive_source"
				continue
			if links.size() != 1 or not sources.has(source) or sources[source].size() != 1: return ep + "modifier_link"
			var occurrence: Dictionary = sources[source][0]
			var modifier: Dictionary = occurrence["record"]
			var expected := {"stat_type": effect["stat_type"], "source_id": source, "instance_id": 0, "local_slot": modifier["local_slot"]}
			if links[0] != expected or occurrence["stat_type"] != effect["stat_type"] or modifier["instance_id"] != 0 or modifier["operation"] != effect["operation"] or modifier["value"] != effect["value"]: return ep + "modifier_link"
			claimed[source] = true
	var ordered: Dictionary = {}
	for id: int in owner["inventory_order"]:
		if not inventory.has(id) or ordered.has(id): return "inventory_order"
		ordered[id] = true
	if ordered.size() != inventory.size(): return "inventory_order"
	var source_keys: Array = sources.keys()
	source_keys.sort()
	for source: String in source_keys:
		if source.begins_with("p03a/") and not claimed.has(source): return "orphan_source/" + source
	return ""
