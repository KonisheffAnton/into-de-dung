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
	var admission := BoardSnapshotValidator.preflight(board, unsupported_runtime_ids)
	if admission.code != BoardSnapshotResult.Code.OK: return admission
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
	return BoardSnapshotValidator._sorted_ids(raw)

static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			var child: Variant = value[key]
			result[key] = _copy_value(child) if child is Dictionary or child is Array else child
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_copy_value(item) if item is Dictionary or item is Array else item)
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
	if not BattleBoard.validate_snapshot_dict(d["board"]): return "board"
	return _validate_status_sources(d["board"]["units"])

static func _validate_status_sources(units: Array) -> String:
	var unit_ids: Dictionary = {}
	for unit: Dictionary in units:
		unit_ids[unit["id"]] = true
	for unit: Dictionary in units:
		if not unit.has("elemental"): continue
		var reason := BoardSnapshotValidator.status_source_reason(unit["id"], unit["bleeding"], unit["elemental"], unit_ids)
		if not reason.is_empty(): return reason
	return ""

static func _find_unsupported(board_value: Dictionary) -> String:
	# Сначала типы: строка вместо версии — повреждённый DTO, а неизвестное число — новая схема.
	if not _has_exact_string_keys(board_value, ["schema_version", "width", "height", "board_version", "heights", "terrain", "units", "occupancy", "height_half_steps"]): return ""
	var schema_value: Variant = board_value.get("schema_version")
	if typeof(schema_value) != TYPE_INT: return ""
	if typeof(board_value.get("width")) != TYPE_INT or typeof(board_value.get("height")) != TYPE_INT: return ""
	var w: int = board_value.width
	var h: int = board_value.height
	if w < 0 or h < 0 or w > MAX_BOARD_SIDE or h > MAX_BOARD_SIDE or w * h > MAX_CELLS: return ""
	if typeof(board_value.height_half_steps) != TYPE_ARRAY or board_value.height_half_steps.size() != w * h: return ""
	for bit: Variant in board_value.height_half_steps:
		if typeof(bit) != TYPE_INT or bit < 0 or bit > 1: return ""
	if schema_value != 2:
		# Проверяем известную форму, не превращая отказ версии в миграцию.
		var known := board_value.duplicate(false)
		known["schema_version"] = 2
		if not _board_arrays_shape(known): return ""
		var nested_unsupported := _find_unsupported(known)
		if nested_unsupported.is_empty() and not BattleBoard.validate_snapshot_dict(known): return ""
		return "board/version"
	if typeof(board_value.get("units")) != TYPE_ARRAY: return ""
	var units: Array = board_value["units"]
	for raw_unit in units:
		if typeof(raw_unit) != TYPE_DICTIONARY: continue
		var unit: Dictionary = raw_unit
		var unit_version: Variant = unit.get("schema_version")
		var unit_keys := ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals", "guard_stance"]
		var has_resource_shape := unit.has("action_resources")
		for key: String in ["action_resources", "armor", "bleeding", "control", "combat_perks", "elemental"]:
			if unit.has(key): unit_keys.append(key)
		if typeof(unit.get("guard_stance")) != TYPE_BOOL: continue
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
		if typeof(unit_version) == TYPE_INT and unit_version != UnitState.SNAPSHOT_SCHEMA_VERSION:
			# Номер старой/будущей схемы не должен скрывать повреждение данных.
			var current_shape := unit.duplicate(false)
			current_shape["schema_version"] = UnitState.SNAPSHOT_SCHEMA_VERSION
			if not UnitState.validate_snapshot_dict(current_shape): continue
			return ("unit/%d" % unit["id"] if typeof(unit.get("id")) == TYPE_INT else "unit") + "/version"
		var unit_path := "unit/%d" % unit["id"] if typeof(unit.get("id")) == TYPE_INT else "unit"
		if typeof(unit.get("ai_profile_path")) == TYPE_STRING and not unit["ai_profile_path"].is_empty(): return unit_path + "/ai_profile"
		if has_resource_shape:
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
