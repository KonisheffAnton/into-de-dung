extends RefCounted

## Ожидание ограничено, а выключенный процесс демо продвигает только worker прогноза.
static func settle(tree: SceneTree, demo: BattleDemo) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	for _frame: int in 600:
		if not is_instance_valid(demo) or not demo._action_forecast_pending: return
		if not demo.is_processing(): demo._process_action_forecast()
		if Time.get_ticks_msec() >= deadline: break
		await tree.create_timer(0.002).timeout
	assert(not is_instance_valid(demo) or not demo._action_forecast_pending, "Action forecast did not finish within timeout")
