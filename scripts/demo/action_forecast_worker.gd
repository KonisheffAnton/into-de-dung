extends RefCounted
class_name ActionForecastWorker

## Один расчёт за раз; поток получает только detached Prepared, не session/UI.
var _thread: Thread
var _immediate: ForecastSimulation
var last_preparation: StringName = &"snapshot"

func is_started() -> bool:
	return _thread != null or _immediate != null

func start(prepared: ForecastSimulation.Prepared) -> void:
	assert(not is_started())
	prepared = ForecastSimulation.take_prepared(prepared)
	last_preparation = &"snapshot"
	if prepared == null:
		_immediate = ForecastSimulation.rejected(&"preview/request_consumed")
		return
	if prepared.reason != &"":
		_refuse(prepared, prepared.reason)
		return
	if prepared.command == null or prepared.command.get_script() not in [GuardCommand, RaiseShieldsCommand, UseHealingItemCommand, UseSummoningItemCommand, RaiseCorpseCommand, RestoreArmorCommand, CollapsePhaseCommand, ElementalCastCommand, MageCastCommand, PlayMageCardCommand, MageDeckChangeCommand, ConfirmMageMulliganCommand]:
		_refuse(prepared, &"preview/unsupported_command")
		return
	if prepared.context == null or prepared.context.get_rng() == null:
		_refuse(prepared, &"preview/context_copy_failed")
		return
	# Непроверенный RNG может содержать callbacks, небезопасные для фонового потока.
	if prepared.context.get_rng().get_script() not in [ActionRngPort, CombatRng]:
		_refuse(prepared, &"preview/unsupported_worker_rng")
		return
	if prepared.clone_requested:
		last_preparation = &"clone"
		var board := prepared.cloned_state.get_board() if prepared.cloned_state != null else null
		if board == null or not ForecastCloneGuard.is_safe([prepared], board):
			# Отказ переноса клона не отменяет допуск исходного снимка. Закрываем
			# только собственную копию и проверяем оставшийся fallback-пакет заново.
			if prepared.cloned_state != null: ForecastSimulation.close(prepared.cloned_state)
			prepared.cloned_state = null
			last_preparation = &"snapshot_fallback"
			if not ForecastCloneGuard.is_safe([prepared]):
				_refuse(prepared, &"preview/unsupported_worker_graph")
				return
	_thread = Thread.new()
	if _start_thread(prepared) != OK:
		_thread = null
		_refuse(prepared, &"preview/worker_unavailable")

func _start_thread(prepared: ForecastSimulation.Prepared) -> Error:
	# Точка проверки отказа ОС; живой код всегда запускает настоящий Thread.
	return _thread.start(ForecastSimulation.run_prepared.bind(prepared), Thread.PRIORITY_LOW)

func _refuse(prepared: ForecastSimulation.Prepared, reason: StringName) -> void:
	ForecastSimulation.discard_prepared(prepared)
	_immediate = ForecastSimulation.rejected(reason)

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
