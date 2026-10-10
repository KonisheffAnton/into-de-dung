extends RefCounted

static func values(result: ForecastSimulation) -> Dictionary:
	var data: Dictionary = {}
	for key: String in ["status", "reason", "events", "steps", "snapshot_before", "snapshot_after", "rng_after", "counters_after", "admission_before", "admission_after", "units_before", "units_after", "items", "corpses_before", "corpses_after"]:
		data[key] = result.get(key)
	return data

static func canonical(value: Variant) -> Variant:
	# UI-проекции индексированы int ID; canonical codec снимка принимает только
	# строковые ключи. Здесь сохраняем тип ключа и различаем dictionary/array.
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(typeof(a), ":", a) < str(typeof(b), ":", b))
		var rows: Array = []
		for key: Variant in keys: rows.append([key, canonical(value[key])])
		return ["dictionary", rows]
	if value is Array:
		var rows: Array = []
		for item: Variant in value: rows.append(canonical(item))
		return ["array", rows]
	if value is float and value == 0.0: return 0.0
	return value

static func digest(value: Variant) -> String:
	return var_to_bytes(canonical(value)).hex_encode().sha256_text()
