extends RefCounted
class_name MoveForecastWorker

## Один расчёт за раз; ни session, ни узлы UI в поток не передаются.
var _thread: Thread
var _immediate: MoveForecast

func is_started() -> bool:
	return _thread != null or _immediate != null

func start(prepared: ForecastSimulation.Prepared) -> void:
	assert(not is_started())
	if prepared.reason != &"":
		_immediate = MoveForecast.rejected(prepared.reason)
		return
	if prepared.command == null or prepared.command.get_script() != MoveCommand or (prepared.command as MoveCommand)._is_continuation() or (prepared.command as MoveCommand)._bound_actor != null:
		_immediate = MoveForecast.rejected(&"preview/unsupported_command")
		return
	# Произвольный cloneable RNG не обещает безопасности своих callbacks в другом потоке.
	if prepared.context.get_rng().get_script() not in [ActionRngPort, CombatRng]:
		_immediate = MoveForecast.rejected(&"preview/unsupported_worker_rng")
		return
	_thread = Thread.new()
	if _thread.start(MoveForecast.build_prepared.bind(prepared), Thread.PRIORITY_LOW) != OK:
		_thread = null
		_immediate = MoveForecast.rejected(&"preview/worker_unavailable")

func take_finished() -> MoveForecast:
	if _immediate != null:
		var result := _immediate
		_immediate = null
		return result
	if _thread == null or _thread.is_alive(): return null
	var result := _thread.wait_to_finish() as MoveForecast
	_thread = null
	return result

func close() -> void:
	# При уничтожении владельца присоединяем даже отменённый расчёт, чтобы не терять Thread.
	if _thread != null: _thread.wait_to_finish()
	_thread = null
	_immediate = null
