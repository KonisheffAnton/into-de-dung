extends RefCounted
class_name ActionForecastWorker

## Один расчёт за раз; поток получает только detached Prepared, не session/UI.
var _thread: Thread
var _immediate: ForecastSimulation

func is_started() -> bool:
	return _thread != null or _immediate != null

func start(prepared: ForecastSimulation.Prepared) -> void:
	assert(not is_started())
	if prepared == null:
		_immediate = ForecastSimulation.rejected(&"preview/request_consumed")
		return
	if prepared.reason != &"":
		_immediate = ForecastSimulation.rejected(prepared.reason)
		return
	if prepared.command == null or prepared.command.get_script() not in [GuardCommand, UseHealingItemCommand, UseSummoningItemCommand, RaiseCorpseCommand, RestoreArmorCommand, CollapsePhaseCommand, ElementalCastCommand]:
		_immediate = ForecastSimulation.rejected(&"preview/unsupported_command")
		return
	if prepared.context == null or prepared.context.get_rng() == null:
		_immediate = ForecastSimulation.rejected(&"preview/context_copy_failed")
		return
	# Непроверенный RNG может содержать callbacks, небезопасные для фонового потока.
	if prepared.context.get_rng().get_script() not in [ActionRngPort, CombatRng]:
		_immediate = ForecastSimulation.rejected(&"preview/unsupported_worker_rng")
		return
	_thread = Thread.new()
	if _thread.start(ForecastSimulation.run_prepared.bind(prepared), Thread.PRIORITY_LOW) != OK:
		_thread = null
		_immediate = ForecastSimulation.rejected(&"preview/worker_unavailable")

func take_finished() -> ForecastSimulation:
	if _immediate != null:
		var result := _immediate
		_immediate = null
		return result
	if _thread == null or _thread.is_alive(): return null
	var result := _thread.wait_to_finish() as ForecastSimulation
	_thread = null
	return result

func close() -> void:
	# Даже отброшенный результат должен дождаться потока до освобождения владельца.
	if _thread != null: _thread.wait_to_finish()
	_thread = null
	_immediate = null
