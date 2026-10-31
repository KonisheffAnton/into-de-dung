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
var _scheduled_frame: int = -1
var _released_index: int = 0
var _repeated_chain_publication: bool = false

func is_repeated_chain_publication() -> bool:
	return _repeated_chain_publication

func play(board: BattleDemoBoard, before: Dictionary, frames: Array[Dictionary], final_state: Dictionary, defer_first_frame: bool = false) -> void:
	_play_frames(board, before, frames.duplicate(true), final_state, defer_first_frame)

## Вызывающий передаёт единоличное владение отделённым пакетом и больше не
## читает его массив. Публичный play сохраняет прежнюю глубокую копию.
func play_owned_frames(board: BattleDemoBoard, before: Dictionary, frames: Array[Dictionary], final_state: Dictionary) -> void:
	_play_frames(board, before, frames, final_state, true)

func _play_frames(board: BattleDemoBoard, before: Dictionary, frames: Array[Dictionary], final_state: Dictionary, defer_first_frame: bool) -> void:
	cancel(false)
	_board = board
	_frames = frames
	_final = final_state.duplicate(true)
	_published = before.duplicate(true)
	_index = 0
	_released_index = 0
	active = true
	_board.set_presentation_animation_events([])
	_board.show_presentation_state(before)
	if defer_first_frame: _schedule_next(true)
	else: _next()

func set_speed(value: float) -> void:
	speed = clampf(value, 0.25, 8.0)
	if _tween != null and _tween.is_valid(): _tween.set_speed_scale(speed)

func _next() -> void:
	if not active: return
	_board.set_presentation_animation_events([])
	if _index >= _frames.size():
		_finish(false)
		return
	# Технические границы тоже перестраивают поле и HUD. Публикуем одну за
	# проход, чтобы длинная граница хода не задерживала весь кадр рендера.
	while active and _index < _frames.size():
		var frame: Dictionary = _frames[_index]
		var group := BattleChainTimeline.collect(_frames, _index)
		if not group.is_empty():
			var chain_events: Array = []
			for item: Dictionary in group:
				var chain_frame: Dictionary = item.frame
				chain_events.append_array(chain_frame.events)
			# Вся цепочка задаётся до первого callback: один общий tween держит её участников.
			_board.set_presentation_animation_events(chain_events)
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
		if _board.has_presentation_animation(frame.events):
			_board.set_presentation_animation_events(frame.events)
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
		_release_consumed_frames()
		if active:
			_schedule_next()
		return
	if active: _finish(false)

func _schedule_next(wait_for_frame: bool = false) -> void:
	# Нулевой интервал отдаёт управление рендеру без фиксированной игровой
	# паузы; обычный Tween сохраняет поддержку pause/skip/cancel. Скорость
	# меняет анимацию, но не объединяет технические публикации в один проход.
	_tween = create_tween()
	_scheduled_frame = Engine.get_process_frames()
	_tween.tween_interval(0.0)
	_tween.finished.connect(_resume_next if wait_for_frame else _next)

func _resume_next() -> void:
	if not active: return
	# Tween, созданный во время _process, может попасть в тот же render-кадр.
	# Начальная публикация и первый клип получают отдельные проходы; контакт
	# внутри текущего клипа по-прежнему переходит непосредственно через _next.
	if Engine.get_process_frames() <= _scheduled_frame:
		_schedule_next(true)
		return
	_next()

func _start_chain_frame(index: int) -> void:
	_board.begin_presentation_frame(_frames[index].events)
	frame_started.emit(_frames[index].duplicate(true))

func _publish_chain_frame(index: int) -> void:
	var frame: Dictionary = _frames[index]
	# Между звеньями есть технические push_chain markers с тем же after.
	# Сигнал и граница остаются; повторная сборка той же доски не нужна.
	var repeated: bool = frame.events.is_empty() and _published == frame.after
	if not repeated:
		_board.show_presentation_state(frame.after)
	_board.finish_presentation_frame(frame.events, frame.step, _published, frame.after)
	_published = frame.after
	_index = index + 1
	_repeated_chain_publication = repeated
	frame_finished.emit(frame.after.duplicate(true))
	_repeated_chain_publication = false
	# После animate timeline хранит события/позы и будущие индексы, не старые after.
	# Освобождаем снимок на границе звена, не весь пакет на последнем контакте.
	_release_consumed_frames()

func _complete_chain() -> void:
	_chain = null
	_release_consumed_frames()
	_continue_after_animation()

func _release_consumed_frames() -> void:
	# Большой ход может содержать сотни снимков. Их уничтожение одним clear
	# в конце пакета само задерживало кадр; уже опубликованный префикс не нужен.
	while _released_index < mini(_index, _frames.size()):
		_frames[_released_index] = {}
		_released_index += 1

func _continue_after_animation() -> void:
	# after законченного движения/удара уже опубликован в этом проходе.
	# Следующий технический after получает отдельный кадр. Между фазами
	# анимированного удара переход остаётся непрерывным, включая контакт.
	if _index >= _frames.size() or not _board.has_presentation_animation(_frames[_index].events):
		_schedule_next()
	else:
		_next()

func _complete_frame() -> void:
	if not active: return
	var frame: Dictionary = _frames[_index]
	var state: Dictionary = frame.after
	_board.show_presentation_state(state)
	_board.finish_presentation_frame(frame.events, frame.step, _published, state)
	_published = state
	# Поза действия уже закончена, trap tween больше не управляет фигурой.
	_board.set_presentation_animation_events([])
	var trap := BattleFieldPresentation.trap_event(frame.events) if frame.step.get("kind") in [&"hazard_contact", &"hazard_trigger"] else {}
	if not trap.is_empty():
		_tween = _board.animate_trap_retraction(trap)
		_tween.set_speed_scale(speed)
		_tween.finished.connect(_next)
	frame_finished.emit(state.duplicate(true))
	_index += 1
	_release_consumed_frames()
	# Финальный refresh получает следующий кадр. Между фазами одного удара
	# оставляем прежний непрерывный переход, иначе сдвигается момент контакта.
	if trap.is_empty():
		_continue_after_animation()

func skip() -> void:
	_finish(true)

func _finish(discard_feedback: bool) -> void:
	if not active: return
	_repeated_chain_publication = false
	if _tween != null and _tween.is_valid(): _tween.kill()
	if _chain != null: _chain.cancel()
	_chain = null
	if discard_feedback: _board.clear_presentation_feedback()
	else: _board.clear_strike_poses()
	# Последний after обычно уже опубликован. Повторная сборка того же поля
	# перед финальным refresh удваивала работу в одном кадре. Skip обязан
	# восстановить финал даже при равном DTO: он обрывает промежуточную позу.
	if discard_feedback or _published != _final: _board.show_presentation_state(_final)
	frame_finished.emit(_final.duplicate(true))
	active = false
	_frames.clear()
	_board.set_presentation_animation_events([])
	_final.clear()
	_published = {}
	finished.emit()

func cancel(discard_feedback: bool = true) -> void:
	active = false
	_repeated_chain_publication = false
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
		_board.set_presentation_animation_events([])
	_board = null

func _exit_tree() -> void:
	cancel()
