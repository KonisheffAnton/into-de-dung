extends ActionRngPort
class_name CombatRng

## Изолированный поток: два 32-битных значения дают неотрицательный int63.
var _generator := RandomNumberGenerator.new()
var _draws: int = 0

func _init(seed_value: int = 1) -> void:
	_generator.seed = seed_value

func next_int(stream: StringName, upper_exclusive: int) -> int:
	if stream != &"combat" or upper_exclusive < 1 or _draws >= ActionContext.MAX_ID - 1: return -1
	# Rejection sampling не искажает веса при неделимом размере диапазона.
	var bound: int = ActionContext.MAX_ID - (ActionContext.MAX_ID % upper_exclusive)
	while true:
		var sample: int = (_generator.randi() << 31) | (_generator.randi() & 2147483647)
		if sample < bound:
			_draws += 1
			return sample % upper_exclusive
	return -1

func clone() -> ActionRngPort:
	var result := CombatRng.new(_generator.seed)
	result._generator.state = _generator.state
	result._draws = _draws
	return result

func to_dict() -> Dictionary:
	return {"schema_version": 1, "seed": _generator.seed, "state": _generator.state, "draws": _draws}

func from_dict(data: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(data, {"schema_version": TYPE_INT, "seed": TYPE_INT, "state": TYPE_INT, "draws": TYPE_INT}): return false
	if data["schema_version"] != 1 or data["draws"] < 0 or data["draws"] >= ActionContext.MAX_ID: return false
	_generator.seed = data["seed"]
	_generator.state = data["state"]
	_draws = data["draws"]
	return true
