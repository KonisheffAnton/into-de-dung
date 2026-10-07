extends SceneTree
## Production fixture с обычным _process и catalog2/deck; только в изолированной копии.
var demo: HeroHubBattleView
var publications: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func measure(label: String, hover: bool = false, trigger: Callable = Callable(), settle_ai: bool = false) -> void:
	var intervals: Array[float] = []
	var process_ms: Array[float] = []
	var input_ms: Array[float] = []
	var frame: int = 0
	while frame < 180 or (settle_ai and (demo.is_execution_pending() or demo.session == null or (demo.session as BattleCoreReactionsSession).phase == BattleTacticalSession.Phase.ENEMY_TURN)):
		assert(frame < 1800, "enemy turn did not finish")
		var start := Time.get_ticks_usec()
		if frame == 0 and trigger.is_valid(): trigger.call()
		if hover and frame % 6 == 0:
			var cell := Vector2i(1 + (frame / 6) % 5, 2)
			demo.board_view.hover_cell = cell
			demo._hover(cell)
		input_ms.append(float(Time.get_ticks_usec()-start)/1000.0)
		await process_frame
		intervals.append(float(Time.get_ticks_usec()-start)/1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		frame += 1
	print(JSON.stringify({"label":label,"frame_ms":intervals,"process_ms":process_ms,"input_ms":input_ms}))
func state_values() -> Dictionary:
	var s := demo.session
	return {"state": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters(), "admission": SummonAdmission.values(s.context)}

func run() -> void:
	var hub := HeroHubState.create(73191,2)
	hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub,"start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	var battle: BattleCoreReactionsSession = bundle.session
	assert(battle.confirm_mage_deployment())
	assert(battle.confirm_mage_mulligan([]).status == ActionReceipt.APPLIED)
	assert(battle.start_battle())
	if battle.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		battle._enemy_index = battle._enemy_ids.size()
		battle.step_enemy()
	battle.select_unit(bundle.hero_units[1])
	demo = (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	demo.supplied_session = battle
	root.add_child(demo)
	demo._presentation_player.frame_started.connect(func(frame: Dictionary) -> void: publications.append(frame.duplicate(true)))
	for i: int in 45: await process_frame
	var before := state_values()
	await measure("idle_processing_on")
	await measure("hover_processing_on", true)
	demo.board_view.hover_cell = Vector2i(-1,-1)
	demo._hover(Vector2i(-1,-1))
	for i: int in 45: await process_frame
	await measure("idle_after_hover")
	demo._action_bar_hovered(&"raise_shields")
	await measure("shield_preview")
	demo._hovered_bar_action = &""
	for i: int in 45: await process_frame
	demo.set_process(false)
	await measure("diagnostic_demo_process_off")
	demo.set_process(true)
	await measure("idle_processing_restored")
	assert(state_values() == before, "idle/hover changed live state")
	await measure("live_raise_shields", false, demo._action_bar_requested.bind(&"raise_shields"))
	await measure("end_turn_and_ai", false, demo.end_turn, true)
	print(JSON.stringify({"label": "parity", "before": before, "after": state_values(), "publications": publications}))
	demo.queue_free()
	await process_frame
	await process_frame
	print("PRODUCTION SMOOTHNESS DONE")
	quit()
