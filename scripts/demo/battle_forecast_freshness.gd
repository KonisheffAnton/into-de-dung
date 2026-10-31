extends RefCounted
class_name BattleForecastFreshness

## Только свидетель неизменности входов. Он не допускает команду и не заменяет capture.
## Строится владельцем после TransferAudit/prepare; matches читает только на владельце.
const MAX_VALUES: int = 50000
const MAX_CONTAINER_DEPTH: int = 32

class Row extends RefCounted:
	var object: Object
	var source_script: Script
	var fields: Array[StringName] = []
	var dynamic_fields: bool = false
	var signals: Array[StringName] = []
	var connections: Array = []
	var native_rng: bool = false

var _session: BattleCoreReactionsSession
var _rows: Array[Row] = []
var _values: Array = []
var _typed_values: PackedByteArray
var _death_callbacks: Dictionary = {}
var _pending: Array[Object] = []
var _seen: Dictionary = {}
var _field_cache: Dictionary[Script, Array] = {}
var _allowed: Array[Script] = []
var _remaining: int = MAX_VALUES

static func capture(session: BattleCoreReactionsSession) -> BattleForecastFreshness:
	if session == null or session.board == null or session.get_script() != BattleCoreReactionsSession: return null
	var witness := BattleForecastFreshness.new()
	witness._session = session
	witness._allowed = BattleExecutionWorker.TransferAudit.new(session).runtime_scripts
	witness._pending.append(session)
	while not witness._pending.is_empty():
		if not witness._capture_object(witness._pending.pop_back()): return null
	witness._values = witness._values.duplicate(true)
	# var_to_bytes хранит типы scalar/container и ID Object, не сериализует живые объекты.
	witness._typed_values = var_to_bytes(witness._values)
	if witness._typed_values.is_empty(): return null
	# Callable нельзя сериализовать в typed-values; реестр уже проверен через died.
	witness._death_callbacks = session.board._death_callbacks.duplicate()
	witness._seen.clear()
	witness._field_cache.clear()
	witness._allowed.clear()
	return witness

static func _fields(object: Object) -> Array[StringName]:
	var result: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			result.append(StringName(property.name))
	return result

func _capture_object(object: Object) -> bool:
	if object == null: return true
	if _seen.has(object.get_instance_id()): return true
	_seen[object.get_instance_id()] = true
	var row := Row.new()
	row.object = object
	row.source_script = object.get_script() as Script
	row.native_rng = object is RandomNumberGenerator and row.source_script == null
	if not row.native_rng and row.source_script not in _allowed: return false
	row.dynamic_fields = object.has_method(&"_get_property_list")
	if row.native_rng:
		row.fields.assign([&"seed", &"state"])
	else:
		if row.dynamic_fields or not _field_cache.has(row.source_script): _field_cache[row.source_script] = _fields(object)
		row.fields.assign(_field_cache[row.source_script])
		# Receipt не является входом прогноза; callbacks проверяются отдельно через сигналы.
		if object == _session: row.fields.erase(&"last_receipt")
		if object == _session.board: row.fields.erase(&"_death_callbacks")
	for field: StringName in row.fields:
		var value: Variant = object.get(field)
		if not _visit_value(value, 0, []): return false
		_values.append(value)
	var metadata := _metadata(object)
	if not _visit_value(metadata, 0, []): return false
	_values.append(metadata)
	for info: Dictionary in object.get_signal_list():
		var signal_name: StringName = info.name
		var connections := object.get_signal_connection_list(signal_name)
		for connection: Dictionary in connections:
			if not BattleExecutionWorker._owned_death_callback(_session, object, signal_name, connection): return false
		row.signals.append(signal_name)
		row.connections.append(connections)
	_rows.append(row)
	return true

static func _metadata(object: Object) -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in object.get_meta_list(): result[key] = object.get_meta(key)
	return result

func _visit_value(value: Variant, depth: int, ancestors: Array) -> bool:
	_remaining -= 1
	if _remaining < 0 or depth > MAX_CONTAINER_DEPTH: return false
	if value is Callable or value is Signal or value is RID: return false
	if value is Object:
		if value != null: _pending.append(value)
	elif value is Array or value is Dictionary:
		for ancestor: Variant in ancestors:
			if is_same(ancestor, value): return false
		ancestors.append(value)
		if value is Dictionary:
			for key: Variant in value:
				if not _visit_value(key, depth + 1, ancestors): return false
				if not _visit_value(value[key], depth + 1, ancestors): return false
		else:
			for item: Variant in value:
				if not _visit_value(item, depth + 1, ancestors): return false
		ancestors.pop_back()
	return true

func matches(session: BattleCoreReactionsSession) -> bool:
	if session == null or session != _session: return false
	if session.board == null or session.board._death_callbacks != _death_callbacks: return false
	var current: Array = []
	for row: Row in _rows:
		var object := row.object
		if not is_instance_valid(object) or object.get_script() != row.source_script: return false
		if row.dynamic_fields:
			var fields := _fields(object)
			if object == _session: fields.erase(&"last_receipt")
			if object == _session.board: fields.erase(&"_death_callbacks")
			if fields != row.fields: return false
		for field: StringName in row.fields: current.append(object.get(field))
		current.append(_metadata(object))
		for index: int in row.signals.size():
			if object.get_signal_connection_list(row.signals[index]) != row.connections[index]: return false
	# Сначала finite baseline отсеивает изменённую структуру, включая новые циклы.
	# Затем байты отличают int/float, String/StringName и типизированные контейнеры.
	return current == _values and var_to_bytes(current) == _typed_values
