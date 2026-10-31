extends RefCounted
class_name BattleForecastPreparationWorker

## Подготовка снимка может быть дорогой; живой session возвращается только после join.
var _thread: Thread
var _audit: BattleExecutionWorker.TransferAudit
var _session: BattleCoreReactionsSession
var _method: StringName = &""
var _args: Array = []
var _prepared: Variant
var _sync_fallback: bool = false

func is_started() -> bool:
	return _thread != null or _audit != null

func start(session: BattleCoreReactionsSession, method: StringName, args: Array) -> bool:
	if is_started() or session == null or session.get_script() != BattleCoreReactionsSession:
		return false
	if not _valid_request(method, args):
		return false
	# Владелец передаётся после дешёвой проверки формы; весь граф проверяет sliced audit.
	_session = session
	_method = method
	_args = args.duplicate()
	_audit = BattleExecutionWorker.TransferAudit.new(session)
	_prepared = null
	_sync_fallback = false
	return true

static func _valid_request(method: StringName, args: Array) -> bool:
	match method:
		&"move", &"retreat", &"raise_corpse":
			return args.size() == 1 and typeof(args[0]) == TYPE_VECTOR2I
		&"attack", &"cast":
			return args.size() == 1 and typeof(args[0]) == TYPE_INT
		&"item":
			return args.size() in [1, 2] and typeof(args[0]) == TYPE_INT and (args.size() == 1 or typeof(args[1]) == TYPE_VECTOR2I)
		&"guard":
			return args.size() in [0, 1, 2] and (args.is_empty() or typeof(args[0]) == TYPE_INT) and (args.size() < 2 or typeof(args[1]) == TYPE_INT)
		&"raise_shields", &"restore_armor", &"environment", &"turn":
			return args.is_empty()
		&"mage_cell":
			return args.size() == 2 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(args[1]) == TYPE_VECTOR2I
		&"mage_card":
			return args.size() == 3 and typeof(args[0]) == TYPE_INT and typeof(args[1]) == TYPE_INT and typeof(args[2]) == TYPE_VECTOR2I
	return false

func _start_thread() -> Error:
	_thread = Thread.new()
	return _thread.start(_run.bind(), Thread.PRIORITY_LOW)

func _run() -> Variant:
	# Worker делает только whitelist-вызов на переданной session; UI и scene graph сюда не попадают.
	if _method == &"turn":
		return TurnForecast.prepare(_session)
	var api_method: StringName = _prepare_method(_method)
	return _session.callv(api_method, _args)

static func _prepare_method(method: StringName) -> StringName:
	match method:
		&"move": return &"prepare_move_forecast"
		&"retreat": return &"prepare_retreat_forecast"
		&"attack": return &"prepare_attack_forecast"
		&"item": return &"prepare_item_forecast"
		&"guard": return &"prepare_guard_forecast"
		&"raise_corpse": return &"prepare_raise_corpse_forecast"
		&"raise_shields": return &"prepare_raise_shields_forecast"
		&"restore_armor": return &"prepare_restore_armor_forecast"
		&"cast": return &"prepare_cast_forecast"
		&"mage_cell": return &"prepare_mage_cell_forecast"
		&"mage_card": return &"prepare_mage_card_forecast"
		&"environment": return &"prepare_environment_forecast"
	return &""

func take_finished(wait: bool = false) -> Dictionary:
	if _audit != null:
		if not _audit.advance(0 if wait else 2000):
			return {}
		var accepted := _audit.accepted
		_audit = null
		if not accepted:
			_sync_fallback = true
		else:
			if _start_thread() != OK:
				_thread = null
				_sync_fallback = true
	if _thread == null:
		if not _sync_fallback:
			return {}
		return _take_package(null, true)
	if not wait and _thread.is_alive():
		return {}
	_prepared = _thread.wait_to_finish()
	_thread = null
	return _take_package(_prepared, false)

func _take_package(prepared: Variant, fallback: bool) -> Dictionary:
	var result := {"session": _session, "method": _method, "args": _args,
		"prepared": prepared, "sync_fallback": fallback}
	# До этого момента поток или аудит владели ссылкой на session.
	_session = null
	_method = &""
	_args = []
	_prepared = null
	_sync_fallback = false
	return result
