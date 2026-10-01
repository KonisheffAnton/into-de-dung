extends RefCounted
class_name BattleChainTimeline

## Общие часы Tween для связанных контактов: after остаются последовательными,
## но возврат предыдущего тела уже не задерживает получение следующего импульса.
var _board: BattleDemoBoard
var _clips: Array[Dictionary] = []
var _cues: Array[Dictionary] = []
var _cue_index: int = 0
var _started: Callable
var _completed: Callable
var duration: float = 0.0
var _cancelled: bool = false

func cancel() -> void:
	_cancelled = true

static func _event(frame: Dictionary) -> Dictionary:
	if frame.step.get("status") != &"APPLIED": return {}
	var found: Dictionary = {}
	for event: Dictionary in frame.events:
		if event.kind in [&"collision", &"push_blocked", &"moved"]:
			if not found.is_empty(): return {}
			found = event
		elif event.kind not in [&"damaged", &"healed", &"armor_changed", &"hit_resolved", &"died", &"control_changed"]:
			return {}
	if found.is_empty(): return {}
	if found.kind == &"collision" and frame.step.kind != &"push_chain": return {}
	if found.kind != &"collision" and frame.step.kind != &"push": return {}
	for event: Dictionary in frame.events:
		if event.root_id != found.root_id or event.command_seq != found.command_seq: return {}
		if event == found: continue
		if found.kind == &"collision":
			if event.get("source", {}).get("kind") != &"collision" or event.target_unit_id not in [found.target_unit_id, found.blocker_unit_id]: return {}
	# Падение и другие последствия движения сохраняют свой обычный клип.
	if found.kind == &"moved":
		if found.get("movement_kind") != &"push": return {}
		for event: Dictionary in frame.events:
			if event.kind not in [&"moved", &"control_changed"]: return {}
	return found

static func collect(frames: Array[Dictionary], first: int) -> Array[Dictionary]:
	var group: Array[Dictionary] = []
	var previous := _event(frames[first])
	if previous.get("kind") != &"collision": return group
	group.append({"index": first, "frame": frames[first], "event": previous})
	var pending: Array[Dictionary] = []
	for index: int in range(first + 1, frames.size()):
		var frame: Dictionary = frames[index]
		var prior: Dictionary = frames[index - 1]
		if int(frame.step.command_seq) != int(prior.step.command_seq) + 1: break
		if frame.events.is_empty():
			if frame.step.kind != &"push_chain" or frame.step.status != &"APPLIED" or frame.after != prior.after: break
			pending.append({"index": index, "frame": frame, "event": {}})
			continue
		var event := _event(frame)
		if event.is_empty() or event.root_id != previous.root_id or event.actor_unit_id != previous.actor_unit_id: break
		if event.target_unit_id != previous.blocker_unit_id or event.from_cell != previous.attempted_cell: break
		var destination: Vector2i = event.get("to_cell", event.get("attempted_cell", event.from_cell))
		if destination - event.from_cell != previous.attempted_cell - previous.from_cell: break
		group.append_array(pending)
		pending.clear()
		group.append({"index": index, "frame": frame, "event": event})
		if event.kind != &"collision": break
		previous = event
	if group.size() <= 1: group.clear()
	return group

func animate(board: BattleDemoBoard, group: Array[Dictionary], started: Callable, completed: Callable) -> Tween:
	_board = board
	_started = started
	_completed = completed
	var cursor := 0.0
	var incoming := Vector2.ZERO
	for item: Dictionary in group:
		var event: Dictionary = item.event
		_cues.append({"time": cursor, "kind": &"start", "index": item.index})
		if not event.is_empty():
			var moving: bool = event.kind == &"moved"
			var end := cursor + (BattleDemoBoard.FORCED_MOVE_SEGMENT_SECONDS if moving else BattleDemoBoard.OBSTACLE_APPROACH_SECONDS + BattleDemoBoard.OBSTACLE_HOLD_SECONDS)
			_clips.append({"event": event, "events": item.frame.events, "start": cursor, "end": end, "incoming": incoming})
			if not moving:
				_cues.append({"time": cursor + BattleDemoBoard.OBSTACLE_APPROACH_SECONDS, "kind": &"contact", "event": event})
				duration = maxf(duration, end + BattleDemoBoard.OBSTACLE_RECOVERY_SECONDS)
			incoming = board._obstacle_direction(event) * 10.0 if event.kind == &"collision" else Vector2.ZERO
			cursor = end
		_cues.append({"time": cursor, "kind": &"finish", "index": item.index})
	duration = maxf(duration, cursor)
	_advance(0.0)
	var tween := board.create_tween()
	tween.tween_method(_advance, 0.0, duration, duration)
	return tween

func _advance(time: float) -> void:
	if _cancelled: return
	while _cue_index < _cues.size() and float(_cues[_cue_index].time) <= time + 0.000001:
		var cue: Dictionary = _cues[_cue_index]
		_pose(float(cue.time))
		_cue_index += 1
		match cue.kind:
			&"start": _started.call(int(cue.index))
			&"contact": _board._obstacle_impact(cue.event)
			&"finish": _completed.call(int(cue.index))
		if _cancelled: return
	_pose(time)

static func _decay(time: float, end: float) -> float:
	var p := clampf((time - end) / BattleDemoBoard.OBSTACLE_RECOVERY_SECONDS, 0.0, 1.0)
	return cos(p * TAU) * pow(1.0 - p, 2.0)

func _pose(time: float) -> void:
	var offsets: Dictionary = {}
	for clip: Dictionary in _clips:
		if time < float(clip.start): break
		var event: Dictionary = clip.event
		var id := int(event.target_unit_id)
		if event.kind == &"moved":
			var p := clampf((time - float(clip.start)) / BattleDemoBoard.FORCED_MOVE_SEGMENT_SECONDS, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - p, 2.0)
			_board._presentation_motion(eased, id, event.from_cell, event.to_cell)
			offsets[id] = (clip.incoming as Vector2) * (1.0 - eased)
			continue
		var direction := _board._obstacle_direction(event)
		var contact := float(clip.start) + BattleDemoBoard.OBSTACLE_APPROACH_SECONDS
		var approach := clampf((time - float(clip.start)) / BattleDemoBoard.OBSTACLE_APPROACH_SECONDS, 0.0, 1.0)
		var amount := _decay(time, float(clip.end))
		# Более позднее звено владеет позой своего тела: хвост предыдущей пары
		# не перетирает новый разгон и не сбрасывает полученные 10 px в ноль.
		offsets[id] = (clip.incoming as Vector2).lerp(direction * 28.0, pow(approach, 3.0)) if time < contact else direction * 28.0 * amount
		if event.kind == &"collision" and time >= contact:
			offsets[int(event.blocker_unit_id)] = direction * 10.0 * amount
		if time >= contact and time < float(clip.end):
			for result: Dictionary in clip.events:
				if result.kind != &"died": continue
				var visual := _board._presentation_visual(int(result.target_unit_id))
				if visual != null: visual.modulate.a = 1.0 - (time - contact) / BattleDemoBoard.OBSTACLE_HOLD_SECONDS
	for id: int in offsets:
		_board._set_action_offset(id, offsets[id] if _board._obstacle_participant_alive(id) else Vector2.ZERO)
