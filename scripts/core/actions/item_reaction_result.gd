extends RefCounted
class_name ItemReactionResult

enum Code { OK, UNSUPPORTED, INVALID, BUSY }

var code: Code = Code.INVALID
var reason: String = ""
var _descriptions: Array[Dictionary] = []
var descriptions: Array[Dictionary]:
	get:
		# Описание реакции — DTO: наружу выдаётся глубокая копия каждого значения.
		var result: Array[Dictionary] = []
		for description in _descriptions:
			result.append(_copy_value(description) as Dictionary)
		return result
	set(value):
		_descriptions.clear()
		for description in value:
			_descriptions.append(_copy_value(description) as Dictionary)

static func ok(values: Array[Dictionary] = []) -> ItemReactionResult:
	var result := ItemReactionResult.new()
	result.code = Code.OK
	result.descriptions = values
	return result

static func failure(p_code: Code, p_reason: String) -> ItemReactionResult:
	var result := ItemReactionResult.new()
	result.code = p_code
	result.reason = p_reason
	return result

static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[key] = _copy_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_copy_value(item))
		return result
	return value
