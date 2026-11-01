class_name CharacterIdleClock
extends RefCounted

var _random := RandomNumberGenerator.new()
var _normal_duration: float = 1.0
var _secondary_duration: float = 0.0
var _normal_cycles: int = 3
var _completed_cycles: int = 0
var elapsed: float = 0.0
var secondary: bool = false

func configure(visual_seed: int, normal_duration: float, secondary_duration: float) -> void:
	# Частный генератор принадлежит только рисунку: не читает RNG боя/профиля/global.
	_random.seed = visual_seed
	_normal_duration = maxf(0.001, normal_duration)
	_secondary_duration = maxf(0.0, secondary_duration)
	_normal_cycles = _random.randi_range(3, 6)
	_completed_cycles = 0
	elapsed = 0.0
	secondary = false

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	if _secondary_duration <= 0.0:
		elapsed = fposmod(elapsed + fposmod(delta, _normal_duration), _normal_duration)
		return
	elapsed += delta
	var duration := _secondary_duration if secondary else _normal_duration
	while elapsed >= duration:
		elapsed -= duration
		if secondary:
			secondary = false
			_completed_cycles = 0
			_normal_cycles = _random.randi_range(3, 6)
		else:
			_completed_cycles += 1
			secondary = _completed_cycles >= _normal_cycles
		duration = _secondary_duration if secondary else _normal_duration
