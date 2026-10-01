extends Node
class_name BattlePresentationPlayer

## Порядок готовых кадров; движение и эффекты исполняет штатный Tween доски.
signal frame_started(frame: Dictionary)
signal frame_finished(state: Dictionary)
signal finished

var active: bool = false
var speed: float = 1.0
var _board: BattleDemoBoard
var _frames: Array[Dictionary] = []
var _final: Dictionary = {}
var _published: Dictionary = {}
var _index: int = 0
var _tween: Tween
var _chain: BattleChainTimeline

func play(board: BattleDemoBoard, before: Dictionary, frames: Array[Dictionary], final_state: Dictionary) -> void:
	cancel(false)
	_board = board
	_frames = frames.duplicate(true)
	_final = final_state.duplicate(true)
	_published = before.duplicate(true)
	_index = 0
	active = true
	_board.show_presentation_state(before)
	_next()

func set_speed(value: float) -> void:
	speed = clampf(value, 0.25, 8.0)
	if _tween != null and _tween.is_valid(): _tween.set_speed_scale(speed)

func _next() -> void:
	if not active: return
	if _index >= _frames.size():
		_finish(false)
		return
	# Техническая граница без видимого события публикуется без искусственной паузы.
	# Снимки и сигналы не пропускаются, порядок настоящих последствий сохранён.
	while active and _index < _frames.size():
		var frame: Dictionary = _frames[_index]
		var group := BattleChainTimeline.collect(_frames, _index)
		if not group.is_empty():
			_chain = BattleChainTimeline.new()
			var chain := _chain
			var chain_tween := chain.animate(_board, group, _start_chain_frame, _publish_chain_frame)
			if not active or _chain != chain:
				chain_tween.kill()
				return
			_tween = chain_tween
			_tween.set_speed_scale(speed)
			_tween.finished.connect(_complete_chain)
			return
		_start_chain_frame(_index)
		if _board.has_presentation_animation(frame.events):
			_tween = _board.animate_presentation_frame(frame.events, frame.step)
			_tween.set_speed_scale(speed)
			_tween.finished.connect(_complete_frame)
			return
		_board.show_presentation_state(frame.after)
		_board.finish_presentation_frame(frame.events, frame.step, _published, frame.after)
		_published = frame.after
		frame_finished.emit(frame.after.duplicate(true))
		_index += 1
	if active: _finish(false)

func _start_chain_frame(index: int) -> void:
	_board.begin_presentation_frame(_frames[index].events)
	frame_started.emit(_frames[index].duplicate(true))

func _publish_chain_frame(index: int) -> void:
	var frame: Dictionary = _frames[index]
	_board.show_presentation_state(frame.after)
	_board.finish_presentation_frame(frame.events, frame.step, _published, frame.after)
	_published = frame.after
	_index = index + 1
	frame_finished.emit(frame.after.duplicate(true))

func _complete_chain() -> void:
	_chain = null
	_next()

func _complete_frame() -> void:
	if not active: return
	var state: Dictionary = _frames[_index].after
	_board.show_presentation_state(state)
	_board.finish_presentation_frame(_frames[_index].events, _frames[_index].step, _published, state)
	_published = state
	frame_finished.emit(state.duplicate(true))
	_index += 1
	_next()

func skip() -> void:
	_finish(true)

func _finish(discard_feedback: bool) -> void:
	if not active: return
	if _tween != null and _tween.is_valid(): _tween.kill()
	if _chain != null: _chain.cancel()
	_chain = null
	if discard_feedback: _board.clear_presentation_feedback()
	else: _board.clear_strike_poses()
	_board.show_presentation_state(_final)
	frame_finished.emit(_final.duplicate(true))
	active = false
	_frames.clear()
	_final.clear()
	_published = {}
	finished.emit()

func cancel(discard_feedback: bool = true) -> void:
	active = false
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
	if _chain != null: _chain.cancel()
	_chain = null
	_frames.clear()
	_final.clear()
	_published = {}
	if is_instance_valid(_board):
		if discard_feedback: _board.clear_presentation_feedback()
		else:
			_board.clear_presentation_effects()
			_board.clear_strike_poses()
	_board = null

func _exit_tree() -> void:
	cancel()
