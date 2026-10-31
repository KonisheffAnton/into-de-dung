extends RefCounted

## Старые сценарии проверяют detached-расчёт; до прямых мутаций возвращаем live owner.
## Саму фазу lease и ввод внутри неё проверяет test_battle_forecast_preparation_ui.
static func settle(tree: SceneTree, demo: BattleDemo) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(demo) and (demo._forecast_preparation_worker.is_started() or demo._forecast_preparation_recovering) and Time.get_ticks_msec() < deadline:
		if demo._forecast_preparation_worker.is_started(): demo._poll_forecast_preparation()
		elif demo._forecast_preparation_recovering: demo._recover_forecast_input()
		await tree.create_timer(0.001).timeout
	assert(not is_instance_valid(demo) or not (demo._forecast_preparation_worker.is_started() or demo._forecast_preparation_recovering), "Forecast preparation did not return owner within timeout")
