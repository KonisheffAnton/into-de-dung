extends RefCounted
class_name BattleExecutionWorker

## Session передаётся целиком одному исполнителю; UI возвращает её только после join.
const METHODS: Array[StringName] = [&"click_attack", &"move_to", &"retreat_to", &"attack_unit", &"cast_unit", &"cast_mage_spell", &"cast_mage_cell", &"play_mage_card", &"replace_mage_card", &"guard_selected", &"raise_shields", &"use_healing_item", &"use_summoning_item", &"raise_corpse", &"restore_selected_armor", &"set_reaction_guard", &"end_player_turn", &"step_enemy"]

var _thread: Thread
var _audit: TransferAudit
var _pending_args: Array = []
var _pending_capture: bool = false
var _session: BattleCoreReactionsSession
var _presentation_before: Dictionary = {}
var _capture_on_worker: bool = false
var _worker_before: Dictionary = {}
var _worker_after: Dictionary = {}
var method: StringName
var target_attempt: bool = false

static func can_transfer(session: BattleDemoSession) -> bool:
	var audit := TransferAudit.new(session)
	audit.advance(0)
	return audit.accepted

## После start граф принадлежит job даже до создания потока. UI не читает его
## между порциями main-аудита; callbacks и неизвестные классы не исполняются.
class TransferAudit extends RefCounted:
	var session: BattleDemoSession
	var pending: Array = []
	var seen: Dictionary = {}
	var script_fields: Dictionary[Script, Array] = {}
	var budget: int = 50000
	var initialized: bool = false
	var done: bool = false
	var accepted: bool = false
	var runtime_scripts: Array[Script] = [BattleAbilityState, AbilityDefinition, BattleCoreReactionsSession, BattleBoard, ItemSimulationState, ActionQueue, ActionContext, ActionRngPort, CombatRng, ActionEventSink, MoveRules, AttackRules, AttackDefinition, UnitState, StatsBag, Stat, StatModifier, Vitals, ActionResources, ArmorState, BleedingState, ElementalState, ControlState, CombatPerksState, CombatPerksDefinition, CombatEnvironmentState, ItemOwnerState, InventoryState, EquipmentState, ItemInstance, ItemDef, SummonDefinition, HealOnDamageEffect, HealOnDamageEffectRuntime, StatModifierEffect, StatModifierEffectRuntime]

	func _init(value: BattleDemoSession) -> void:
		session = value
		runtime_scripts.append(BattleArtifactState)
		runtime_scripts.append_array([BattleDeckState,BattleCardEffectState])

	func _refuse() -> void:
		done = true
		accepted = false
		pending.clear()

	func advance(slice_usec: int) -> bool:
		if done: return true
		var deadline := Time.get_ticks_usec() + slice_usec
		if not initialized:
			initialized = true
			if session == null or session.get_script() != BattleCoreReactionsSession: _refuse(); return true
			if session.context == null or session._queue == null or session._queue.get_script() != ActionQueue: _refuse(); return true
			if session.context.is_busy() or session._queue._busy: _refuse(); return true
			if not MageDeckRules.references_valid(session.context): _refuse(); return true
			if session.state.artifacts != null and not BattleArtifactRules.references_valid(session.context): _refuse(); return true
			# Это проверка владения, не замена capture/admission внутри реального submit.
			# Старый receipt не исполняется повторно; очередь тоже входит в аудит графа.
			pending.append(session)
			if slice_usec > 0: return false
		while not pending.is_empty():
			if slice_usec > 0 and Time.get_ticks_usec() >= deadline: return false
			budget -= 1
			if budget < 0: _refuse(); return true
			var value: Variant = pending.pop_back()
			if value is Callable or value is Signal: _refuse(); return true
			if value is Array:
				pending.append_array(value)
			elif value is Dictionary:
				pending.append_array(value.keys())
				pending.append_array(value.values())
			elif value is Object:
				var object := value as Object
				if object == null: continue
				if seen.has(object.get_instance_id()): continue
				seen[object.get_instance_id()] = true
				if not (object is RandomNumberGenerator and object.get_script() == null) and object.get_script() not in runtime_scripts:
					_refuse(); return true
				for signal_info: Dictionary in object.get_signal_list():
					for connection: Dictionary in object.get_signal_connection_list(signal_info.name):
						if not BattleExecutionWorker._owned_death_callback(session, object, signal_info.name, connection):
							_refuse(); return true
				var script := object.get_script() as Script
				if script == null: continue
				var dynamic_fields := object.has_method(&"_get_property_list")
				if dynamic_fields or not script_fields.has(script):
					var fields: Array[StringName] = []
					for property: Dictionary in object.get_property_list():
						if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
							fields.append(StringName(property.name))
					script_fields[script] = fields
				for key: StringName in script_fields[script]:
					if object == session and key == &"last_receipt": continue
					if object == session.board and key == &"_death_callbacks": continue
					pending.append(object.get(key))
		done = true
		accepted = true
		return true

static func _owned_death_callback(session: BattleDemoSession, object: Object, signal_name: StringName, connection: Dictionary) -> bool:
	if not object is Vitals or signal_name != &"died" or int(connection.flags) != 0: return false
	var callback: Callable = connection.callable
	if callback.get_object() != session.board or callback.get_method() != &"_on_registered_unit_died": return false
	var args := callback.get_bound_arguments()
	if args.size() != 3 or not args[0] is int or not args[1] is WeakRef or not args[2] is WeakRef: return false
	var unit := session.board.get_unit_by_id(args[0])
	return unit != null and unit.vitals == object and args[1].get_ref() == unit and args[2].get_ref() == object and session.board._death_callbacks.get(unit.id) == callback

func is_started() -> bool:
	return _thread != null or _audit != null

func start(session: BattleCoreReactionsSession, action: StringName, args: Array, attempt: bool = false, capture_presentation: bool = false, defer_presentation: bool = false, prepare_across_frames: bool = false) -> bool:
	if is_started(): return false
	_presentation_before.clear()
	_worker_before.clear()
	_worker_after.clear()
	_capture_on_worker = capture_presentation and defer_presentation
	if not _valid_request(action, args): return false
	if prepare_across_frames:
		if session == null or session.get_script() != BattleCoreReactionsSession: return false
		_session = session
		method = action
		target_attempt = attempt
		_pending_args = args.duplicate()
		_pending_capture = capture_presentation
		_capture_on_worker = capture_presentation
		_audit = TransferAudit.new(session)
		return true
	if not can_transfer(session): return false
	if capture_presentation and not _capture_on_worker:
		# Снимок делается только после успешного аудита, пока worker ещё не владеет session.
		_presentation_before = ActionPresentationState.capture(session.state)
		session.begin_presentation_capture()
	_session = session
	method = action
	target_attempt = attempt
	_thread = Thread.new()
	if _start_thread(args) == OK: return true
	_thread = null
	_session = null
	if _capture_on_worker:
		# Поток не стартовал: единственный sync fallback получает такой же пакет.
		_presentation_before = ActionPresentationState.capture(session.state)
		session.begin_presentation_capture()
	return false

func _start_thread(args: Array) -> Error:
	# Отдельная точка запуска позволяет проверить отказ ОС без реального исчерпания потоков.
	return _thread.start(_run.bind(args.duplicate()))

func take_presentation_before() -> Dictionary:
	# _run не читает этот DTO: main забирает значения даже во время исполнения session.
	var result := _presentation_before
	_presentation_before = {}
	return result

static func _valid_request(action: StringName, args: Array) -> bool:
	if action not in METHODS: return false
	if action == &"play_mage_card": return args.size() == 3 and typeof(args[0]) == TYPE_INT and typeof(args[1]) == TYPE_INT and typeof(args[2]) == TYPE_VECTOR2I
	if action == &"replace_mage_card": return args.size() == 1 and typeof(args[0]) == TYPE_INT
	if action in [&"move_to", &"retreat_to", &"use_summoning_item", &"raise_corpse"]:
		return args.size() == 1 and args[0] is Vector2i
	if action in [&"attack_unit", &"click_attack", &"cast_unit"]: return args.size() == 1 and args[0] is int
	if action == &"cast_mage_spell": return args.size() == 2 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(args[1]) == TYPE_INT
	if action == &"cast_mage_cell": return args.size() == 2 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(args[1]) == TYPE_VECTOR2I
	if action == &"set_reaction_guard":
		return args.size() in [1, 2] and args[0] is int and (args.size() == 1 or args[1] is int)
	return args.is_empty()

func _run(args: Array) -> Variant:
	# После аудита весь граф уже принадлежит потоку. Кадры остаются закрыты
	# для main до join, поэтому их сборка не задерживает анимацию ожидания.
	if _capture_on_worker:
		_worker_before = ActionPresentationState.capture(_session.state)
		_session.begin_presentation_capture()
	var result: Variant = _session.callv(method, args)
	if _capture_on_worker: _worker_after = ActionPresentationState.capture(_session.state)
	return result

func take_finished(wait: bool = false) -> Dictionary:
	if _audit != null:
		if not _audit.advance(0 if wait else 2000): return {}
		var accepted := _audit.accepted
		_audit = null
		if accepted:
			_thread = Thread.new()
			if _start_thread(_pending_args) != OK: _thread = null
		if _thread == null:
			# Отказ аудита не включает capture. После отказа ОС сохраняем показ,
			# но единственный вызов команды произойдёт на main после возврата владельца.
			if accepted and _pending_capture:
				_presentation_before = ActionPresentationState.capture(_session.state)
				_session.begin_presentation_capture()
			var fallback := {"session": _session, "method": method, "result": null,
				"target_attempt": target_attempt, "sync_fallback": true, "args": _pending_args,
				"presentation_before": take_presentation_before()}
			_session = null
			_pending_args = []
			return fallback
		_pending_args = []
	if _thread == null or (not wait and _thread.is_alive()): return {}
	var result: Variant = _thread.wait_to_finish()
	_thread = null
	var completed := {"session": _session, "method": method, "result": result, "target_attempt": target_attempt}
	if _capture_on_worker:
		completed["presentation_before"] = _worker_before
		completed["presentation_after"] = _worker_after
	_worker_before = {}
	_worker_after = {}
	_session = null
	return completed
