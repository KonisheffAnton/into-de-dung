extends RefCounted

static func settle(tree: SceneTree, demo: BattleDemo) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(demo) and demo.is_execution_pending() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		await tree.create_timer(0.001).timeout
	assert(not is_instance_valid(demo) or not demo.is_execution_pending(), "Battle execution did not finish within timeout")
