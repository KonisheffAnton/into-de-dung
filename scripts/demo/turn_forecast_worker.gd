extends RefCounted
class_name TurnForecastWorker

var _thread: Thread
var _immediate: TurnForecast

func is_started() -> bool:
	return _thread != null or _immediate != null

func start(prepared: TurnForecast.Prepared) -> void:
	assert(not is_started())
	if prepared == null:
		_immediate = TurnForecast.rejected(&"preview/request_consumed")
		return
	if prepared.consumed:
		_immediate = TurnForecast.rejected(&"preview/request_consumed")
		return
	if prepared.reason != &"":
		prepared.consumed = true
		_immediate = TurnForecast.rejected(prepared.reason)
		return
	if prepared.context == null or prepared.context.get_rng() == null or prepared.context.get_rng().get_script() not in [ActionRngPort, CombatRng]:
		prepared.consumed = true
		_immediate = TurnForecast.rejected(&"preview/unsupported_worker_rng")
		return
	_thread = Thread.new()
	if _thread.start(TurnForecast.run_prepared.bind(prepared), Thread.PRIORITY_LOW) != OK:
		_thread = null
		prepared.consumed = true
		_immediate = TurnForecast.rejected(&"preview/worker_unavailable")

func take_finished() -> TurnForecast:
	if _immediate != null:
		var result := _immediate
		_immediate = null
		return result
	if _thread == null or _thread.is_alive(): return null
	var result := _thread.wait_to_finish() as TurnForecast
	_thread = null
	return result

func close() -> void:
	if _thread != null: _thread.wait_to_finish()
	_thread = null
	_immediate = null
