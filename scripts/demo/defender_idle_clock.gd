class_name DefenderIdleClock
extends RefCounted

const FRAME_DURATION: float = 0.2
const FRAME_COUNT: int = 12
const CYCLE_DURATION: float = 2.4
const TIME_EPSILON: float = 0.000000001

var _unit_id: int = 0
var _min_normal_cycles: int = 24
var _max_normal_cycles: int = 36
var _normal_cycle_count: int = 24
var _initial_phase_frames: int = 0
var _elapsed: float = 0.0


func configure(unit_id: int, min_normal_cycles: int = 24, max_normal_cycles: int = 36) -> void:
	_unit_id = unit_id
	_min_normal_cycles = maxi(1, min_normal_cycles)
	_max_normal_cycles = maxi(_min_normal_cycles, max_normal_cycles)
	var cycle_span: int = _max_normal_cycles - _min_normal_cycles + 1
	# Локальная арифметика по ID не расходует RNG игры и даёт воспроизводимый разброс.
	var stable_id_part: int = posmod(_unit_id, cycle_span)
	_normal_cycle_count = _min_normal_cycles + stable_id_part
	# Смещение влияет только на кадр, поэтому первый показ всегда остаётся обычным.
	_initial_phase_frames = posmod(posmod(_unit_id, FRAME_COUNT) * 7, FRAME_COUNT)
	reset()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var schedule_duration: float = float(_normal_cycle_count + 1) * CYCLE_DURATION
	# Храним только фазу расписания: даже огромный delta не раздувает счётчик времени.
	_elapsed = fposmod(_elapsed + fposmod(delta, schedule_duration), schedule_duration)
	if _elapsed < TIME_EPSILON or schedule_duration - _elapsed < TIME_EPSILON:
		_elapsed = 0.0


func reset() -> void:
	_elapsed = 0.0


func get_frame_index() -> int:
	var frame_time: float = fposmod(_elapsed, CYCLE_DURATION)
	var phase_time: float = float(_initial_phase_frames) * FRAME_DURATION
	var phase_position: float = fposmod(frame_time + phase_time, CYCLE_DURATION)
	return posmod(int(floor((phase_position + TIME_EPSILON) / FRAME_DURATION)), FRAME_COUNT)


func is_rare() -> bool:
	return _elapsed + TIME_EPSILON >= float(_normal_cycle_count) * CYCLE_DURATION


func get_normal_cycle_count() -> int:
	return _normal_cycle_count


func get_elapsed() -> float:
	return _elapsed
