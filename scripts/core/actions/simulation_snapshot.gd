extends RefCounted
class_name SimulationSnapshot

const SCOPE := "board_only_no_items_v1"
const MAX_BOARD_SIDE := 1024
const MAX_CELLS := 65536

var _data: Dictionary = {}

func _init() -> void:
	# DTO назначает только from_dict после полной проверки raw graph.
	pass

static func capture_board(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult:
	var ids := _sorted_ids(unsupported_runtime_ids)
	if not ids.is_empty(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unsupported_runtime_ids", ids)
	if board == null: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, "board")
	if board.get_script() != BattleBoard: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "board/subclass", [&"board/subclass"])
	if typeof(board._units) != TYPE_DICTIONARY: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, "board/units")
	for id in board._units.keys():
		if typeof(id) != TYPE_INT or not (board._units[id] is UnitState): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, "board/units")
		var unit := board._units[id] as UnitState
		var path := "unit/%d" % id
		if unit == null: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path)
		if unit.get_script() != UnitState: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/subclass", [StringName(path + "/subclass")])
		if unit.ai_profile != null: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/ai_profile", [StringName(path + "/ai_profile")])
		if unit.stats == null or unit.vitals == null: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stats")
		if unit.stats.get_script() != StatsBag: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/stats/subclass", [StringName(path + "/stats/subclass")])
		if unit.vitals.get_script() != Vitals: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/vitals/subclass", [StringName(path + "/vitals/subclass")])
		if unit.action_resources != null and unit.action_resources.get_script() != ActionResources:
			return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/action_resources/subclass", [StringName(path + "/action_resources/subclass")])
		if typeof(unit.stats._stats) != TYPE_DICTIONARY: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stats")
		for stat_key in unit.stats._stats.keys():
			if typeof(stat_key) != TYPE_INT or stat_key < 0 or stat_key > 10: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stats")
			if not (unit.stats._stats[stat_key] is Stat): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stat")
			var stat := unit.stats._stats[stat_key] as Stat
			if stat.get_script() != Stat: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/stat/subclass", [StringName(path + "/stat/subclass")])
			if stat._modifiers.size() != stat._modifier_slots.size(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stat/modifiers")
			for modifier in stat._modifiers:
				if modifier == null: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, path + "/stat/modifier")
				if modifier.get_script() != StatModifier: return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, path + "/stat/modifier/subclass", [StringName(path + "/stat/modifier/subclass")])
	# Кэш проверяется отдельным проходом: subtype обязан дать UNSUPPORTED даже со stale cache.
	for id in board._units.keys():
		var unit := board._units[id] as UnitState
		for stat_key in unit.stats._stats.keys():
			var stat := unit.stats._stats[stat_key] as Stat
			if stat.snapshot_cache_is_stale(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, "unit/%d/stats/%d/cache" % [id, stat_key])
	var raw := board.to_snapshot_dict()
	if raw.is_empty(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, "board")
	return from_dict({"schema_version": 1, "scope": SCOPE, "board": raw})

static func from_dict(data: Dictionary) -> BoardSnapshotResult:
	var error := _validate_envelope(data)
	if not error.is_empty():
		var unsupported := error.begins_with("UNSUPPORTED:")
		var reason := error.trim_prefix("UNSUPPORTED:")
		var ids: Array[StringName] = []
		if unsupported: ids.append(StringName(reason))
		return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED if unsupported else BoardSnapshotResult.Code.SNAPSHOT_INVALID, reason, ids)
	var snapshot := SimulationSnapshot.new()
	snapshot._data = _normalize(_copy_value(data))
	return BoardSnapshotResult.ok(snapshot)

func to_dict() -> Dictionary:
	return _copy_value(_data)

func instantiate_board() -> BattleBoard:
	if _data.is_empty() or typeof(_data.get("board")) != TYPE_DICTIONARY: return null
	return BattleBoard.from_snapshot_dict(_data["board"])

func canonical_values() -> Array:
	return _copy_value(_canonical(_data))

func canonical_bytes() -> PackedByteArray:
	var out := PackedByteArray([80, 48, 50, 83, 1])
	_encode(_canonical(_data), out)
	return out

func fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_bytes())
	return context.finish().hex_encode()

static func _sorted_ids(raw: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in raw:
		if not result.has(id): result.append(id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result

static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys(): result[key] = _copy_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_copy_value(item))
		return result
	return value

static func _normalize(value: Dictionary) -> Dictionary:
	var result: Dictionary = value
	var board: Dictionary = result["board"]
	var units: Array = board["units"]
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	for unit_variant in units:
		var unit: Dictionary = unit_variant
		var stats: Array = unit["stats"]["stats"]
		stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["stat_type"] < b["stat_type"])
		for entry_variant in stats:
			var modifiers: Array = entry_variant["stat"]["modifiers"]
			modifiers.sort_custom(_modifier_less)
	var occupancy: Array = board["occupancy"]
	occupancy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] < b["y"] or (a["y"] == b["y"] and a["x"] < b["x"]))
	return result

static func _modifier_less(a: Dictionary, b: Dictionary) -> bool:
	if a["source_id"] != b["source_id"]: return a["source_id"] < b["source_id"]
	if a["instance_id"] != b["instance_id"]: return a["instance_id"] < b["instance_id"]
	return a["local_slot"] < b["local_slot"]

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys(): keys.append(key)
		keys.sort()
		var result: Array = []
		for key in keys: result.append([key, _canonical(value[key])])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_canonical(item))
		return result
	if value is float and value == 0.0: return 0.0
	return value

static func _append_u64_le(out: PackedByteArray, value: int) -> void:
	for shift in 8: out.append((value >> (shift * 8)) & 255)

static func _encode(value: Variant, out: PackedByteArray) -> void:
	if value is bool:
		out.append(1); out.append(1 if value else 0)
	elif value is int:
		out.append(2); _append_u64_le(out, value)
	elif value is float:
		out.append(3)
		var peer := StreamPeerBuffer.new(); peer.big_endian = false; peer.put_double(0.0 if value == 0.0 else value)
		out.append_array(peer.data_array)
	elif value is String:
		var bytes: PackedByteArray = value.to_utf8_buffer()
		out.append(4); _append_u64_le(out, bytes.size()); out.append_array(bytes)
	elif value is StringName:
		var bytes: PackedByteArray = String(value).to_utf8_buffer()
		out.append(6); _append_u64_le(out, bytes.size()); out.append_array(bytes)
	elif value is Vector2i:
		out.append(7); _append_u64_le(out, value.x); _append_u64_le(out, value.y)
	elif value is Array:
		out.append(5); _append_u64_le(out, value.size())
		for item in value: _encode(item, out)

static func _validate_envelope(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY: return "envelope"
	var d: Dictionary = data
	if not _has_exact_string_keys(d, ["schema_version", "scope", "board"]): return "envelope/schema"
	if typeof(d["schema_version"]) != TYPE_INT: return "envelope/version"
	if d["schema_version"] != 1: return "UNSUPPORTED:version"
	if typeof(d["scope"]) != TYPE_STRING: return "envelope/scope"
	if d["scope"] != SCOPE: return "UNSUPPORTED:scope"
	if typeof(d["board"]) != TYPE_DICTIONARY: return "board"
	var unsupported := _find_unsupported(d["board"])
	if not unsupported.is_empty(): return "UNSUPPORTED:" + unsupported
	return "" if BattleBoard.validate_snapshot_dict(d["board"]) else "board"

static func _find_unsupported(board_value: Dictionary) -> String:
	# Сначала типы: строка вместо версии — повреждённый DTO, а неизвестное число — новая схема.
	var shape_v2 := _has_exact_string_keys(board_value, ["schema_version", "width", "height", "board_version", "heights", "terrain", "units", "occupancy", "height_half_steps"])
	var shape_v1 := _has_exact_string_keys(board_value, ["schema_version", "width", "height", "board_version", "heights", "terrain", "units", "occupancy"])
	if not shape_v1 and not shape_v2: return ""
	if shape_v2:
		var halves: Variant = board_value.get("height_half_steps")
		if typeof(halves) != TYPE_ARRAY: return ""
		if typeof(board_value.get("width")) != TYPE_INT or typeof(board_value.get("height")) != TYPE_INT: return ""
		var w: int = board_value["width"]
		var h: int = board_value["height"]
		if w < 0 or h < 0 or w > 1024 or h > 1024 or w * h > MAX_CELLS or halves.size() != w * h: return ""
		var any_half := false
		for bit: Variant in halves:
			if typeof(bit) != TYPE_INT or bit < 0 or bit > 1: return ""
			any_half = any_half or bit == 1
		if not any_half: return ""
	var schema_value: Variant = board_value.get("schema_version")
	if typeof(schema_value) != TYPE_INT: return ""
	if schema_value not in [1, 2]:
		# Неизвестная версия не скрывает повреждение известной формы. Копируется
		# только внешний словарь; runtime/массивы/юниты не создаются и не меняются.
		var known := board_value.duplicate(false)
		known["schema_version"] = 2 if shape_v2 else 1
		if not _board_arrays_shape(known): return ""
		var nested_unsupported := _find_unsupported(known)
		if nested_unsupported.is_empty() and not BattleBoard.validate_snapshot_dict(known): return ""
		return "board/version"
	if typeof(schema_value) == TYPE_INT and schema_value == 2 and not shape_v2: return ""
	if typeof(schema_value) == TYPE_INT and schema_value == 1 and not shape_v1: return ""
	if typeof(board_value.get("units")) != TYPE_ARRAY: return ""
	var units: Array = board_value["units"]
	for raw_unit in units:
		if typeof(raw_unit) != TYPE_DICTIONARY: continue
		var unit: Dictionary = raw_unit
		var unit_version: Variant = unit.get("schema_version")
		var unit_keys := ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals"]
		var has_resource_shape: bool = typeof(unit_version) == TYPE_INT and (unit_version == 2 or (unit_version != 1 and unit.has("action_resources")))
		# Новую версию распознаём только после проверки полной формы и типов DTO:
		# повреждённые данные не должны маскироваться под неподдержанную схему.
		if has_resource_shape:
			unit_keys.append("action_resources")
		var has_stance_shape: bool = typeof(unit_version) == TYPE_INT and (unit_version == 3 or (unit_version not in [1, 2] and unit.has("guard_stance")))
		if has_stance_shape:
			unit_keys.append("guard_stance")
			if typeof(unit.get("guard_stance")) != TYPE_BOOL: continue
		var has_armor_shape: bool = typeof(unit_version) == TYPE_INT and (unit_version == 4 or (unit_version not in [1, 2, 3] and unit.has("armor")))
		if has_armor_shape:
			unit_keys.append("armor")
			if typeof(unit.get("armor")) != TYPE_DICTIONARY or not ArmorState.valid(unit["armor"]): continue
		var has_bleeding_shape: bool = typeof(unit_version) == TYPE_INT and (unit_version == 5 or (unit_version not in [1, 2, 3, 4] and unit.has("bleeding")))
		if has_bleeding_shape:
			unit_keys.append("bleeding")
			if typeof(unit.get("bleeding")) != TYPE_DICTIONARY or not BleedingState.valid(unit["bleeding"]): continue
		if not _has_exact_string_keys(unit, unit_keys): continue
		var unit_types_valid := true
		for key in ["schema_version", "id", "faction", "cell_x", "cell_y", "height"]:
			if typeof(unit[key]) != TYPE_INT:
				unit_types_valid = false
				break
		if not unit_types_valid or typeof(unit["debug_name"]) != TYPE_STRING or typeof(unit["ai_profile_path"]) != TYPE_STRING or typeof(unit["move_points_left"]) != TYPE_FLOAT or typeof(unit["has_attacked"]) != TYPE_BOOL or typeof(unit["stats"]) != TYPE_DICTIONARY or typeof(unit["vitals"]) != TYPE_DICTIONARY: continue
		var resources: Dictionary = {}
		if has_resource_shape:
			if typeof(unit["action_resources"]) != TYPE_DICTIONARY: continue
			resources = unit["action_resources"]
			if not _has_exact_string_keys(resources, ["schema_version", "owner_unit_id", "main_left", "bonus_left"]): continue
			for key in ["schema_version", "owner_unit_id", "main_left", "bonus_left"]:
				if typeof(resources[key]) != TYPE_INT:
					resources = {}
					break
			if resources.is_empty(): continue
		if typeof(unit_version) == TYPE_INT and unit_version not in [1, 2, 3, 4, 5]:
			return ("unit/%d" % unit["id"] if typeof(unit.get("id")) == TYPE_INT else "unit") + "/version"
		var unit_path := "unit/%d" % unit["id"] if typeof(unit.get("id")) == TYPE_INT else "unit"
		if typeof(unit.get("ai_profile_path")) == TYPE_STRING and not unit["ai_profile_path"].is_empty(): return unit_path + "/ai_profile"
		if unit["schema_version"] == 5 and (not unit.has("action_resources") or not unit.has("guard_stance") or not unit.has("armor") or not unit.has("bleeding")): return unit_path + "/capability"
		if unit["schema_version"] in [2, 3, 4, 5]:
			if typeof(resources.get("schema_version")) == TYPE_INT and resources["schema_version"] != 1: return unit_path + "/action_resources/version"
		if typeof(unit.get("stats")) != TYPE_DICTIONARY: continue
		var bag: Dictionary = unit["stats"]
		if not _has_exact_string_keys(bag, ["schema_version", "stats"]): continue
		if typeof(bag.get("schema_version")) == TYPE_INT and bag["schema_version"] != 1: return unit_path + "/stats/version"
		if typeof(bag.get("stats")) != TYPE_ARRAY: continue
		for raw_entry in bag["stats"]:
			if typeof(raw_entry) != TYPE_DICTIONARY or typeof(raw_entry.get("stat")) != TYPE_DICTIONARY: continue
			if not _has_exact_string_keys(raw_entry, ["stat_type", "stat"]): continue
			var stat: Dictionary = raw_entry["stat"]
			if not _has_exact_string_keys(stat, ["schema_version", "base_value", "next_modifier_slot", "modifiers"]): continue
			if typeof(stat.get("schema_version")) == TYPE_INT and stat["schema_version"] != 1: return unit_path + "/stats/%s/version" % str(raw_entry.get("stat_type"))
			if typeof(stat.get("modifiers")) != TYPE_ARRAY: continue
			for raw_modifier in stat["modifiers"]:
				if typeof(raw_modifier) != TYPE_DICTIONARY: continue
				if not _has_exact_string_keys(raw_modifier, ["source_id", "instance_id", "local_slot", "evaluation_order", "operation", "value"]): continue
				if typeof(raw_modifier.get("instance_id")) == TYPE_INT and raw_modifier["instance_id"] != 0: return unit_path + "/stats/%s/modifier/instance_id" % str(raw_entry.get("stat_type"))
	return ""

static func _board_arrays_shape(board: Dictionary) -> bool:
	for key: String in ["width", "height", "board_version"]:
		if typeof(board[key]) != TYPE_INT: return false
	var w: int = board["width"]
	var h: int = board["height"]
	if w < 0 or h < 0 or w > MAX_BOARD_SIDE or h > MAX_BOARD_SIDE or w * h > MAX_CELLS or board["board_version"] < 0: return false
	for key: String in ["heights", "terrain", "units", "occupancy"]:
		if typeof(board[key]) != TYPE_ARRAY: return false
	if board["heights"].size() != w * h or board["terrain"].size() != w * h or board["units"].size() > MAX_CELLS or board["occupancy"].size() > MAX_CELLS: return false
	for value: Variant in board["heights"]:
		if typeof(value) != TYPE_INT or value < -2147483648 or value > 2147483647: return false
	for value: Variant in board["terrain"]:
		if typeof(value) != TYPE_INT or value < 0 or value > 3: return false
	for unit: Variant in board["units"]:
		if typeof(unit) != TYPE_DICTIONARY: return false
	for occupant: Variant in board["occupancy"]:
		if typeof(occupant) != TYPE_DICTIONARY or not _has_exact_string_keys(occupant,["x","y","unit_id"]): return false
		for key: String in ["x","y","unit_id"]:
			if typeof(occupant[key]) != TYPE_INT: return false
	return true

static func _has_exact_string_keys(value: Dictionary, required: Array) -> bool:
	if value.keys().size() != required.size(): return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key): return false
	return true
