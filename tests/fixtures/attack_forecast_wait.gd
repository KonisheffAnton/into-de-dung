extends RefCounted

## Старые UI-сценарии ждут готового результата, не завися от скорости CPU/кадра.
static func settle(tree: SceneTree, demo: BattleDemo) -> void:
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(tree, demo)
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(demo) and demo._attack_forecast_pending and Time.get_ticks_msec() < deadline:
		# Некоторые fixtures останавливают AI через set_process(false).
		demo._process_attack_forecast()
		await tree.create_timer(0.001).timeout
	assert(not is_instance_valid(demo) or not demo._attack_forecast_pending, "Attack forecast did not finish within timeout")
