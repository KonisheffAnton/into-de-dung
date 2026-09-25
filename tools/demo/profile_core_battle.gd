extends SceneTree

## Воспроизводимый CPU benchmark; времена не являются пороговым CI-тестом или FPS.
## Запуск: Godot --headless --path . --script tools/demo/profile_core_battle.gd
var demo: BattleDemo
var viewport: SubViewport
var s: BattleCoreCombinationSession
var _sample_label: String = ""

func _initialize() -> void:
	call_deferred("run")

func measure(label: String, body: Callable, count: int = 3) -> void:
	var values: Array[float] = []
	var last_result: Variant = null
	for i: int in count:
		var start := Time.get_ticks_usec()
		last_result = body.call()
		values.append(float(Time.get_ticks_usec() - start) / 1000.0)
	var row := {"label": label, "sample": _sample_label, "ms": values, "units": s.units.size()}
	if last_result is ActionReceipt:
		row["status"] = last_result.status
		row["reason"] = last_result.reason
	print(JSON.stringify(row))

func snapshot() -> ItemSnapshotResult:
	return ItemSimulationSnapshot.capture(s.state, [])

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	root.add_child(viewport)
	var scene := "res://scenes/demo/core_reactions_battle.tscn" if OS.get_cmdline_user_args().has("--reactions") else "res://scenes/demo/core_combination_battle.tscn"
	demo = (load(scene) as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	await process_frame; await process_frame
	demo.set_process(false)
	s = demo.session as BattleCoreCombinationSession
	await sample("initial")
	for turn: int in 3:
		measure("end_turn_" + str(turn), s.end_player_turn, 1)
		var times: Array[float] = []
		for action: int in 80:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			var start := Time.get_ticks_usec()
			s.step_enemy()
			times.append(float(Time.get_ticks_usec() - start) / 1000.0)
		print(JSON.stringify({"label":"enemy_steps_"+str(turn),"ms":times,"units":s.units.size()}))
		print(JSON.stringify({"label":"state_"+str(turn), "fingerprint": snapshot().snapshot.fingerprint(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}))
		if s.can_player_act(): await sample("round_"+str(turn+2))
	# Отдельная исходная партия для цены реального удара, без влияния на трассу ИИ.
	s.reset()
	s.select_unit(s.units[2].id)
	measure("live_attack", s.attack_unit.bind(s.units[3].id), 1)
	print(JSON.stringify({"label":"attack_state", "fingerprint": snapshot().snapshot.fingerprint(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}))
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	quit()

func sample(label: String) -> void:
	_sample_label = label
	print("SAMPLE " + label)
	s.select_unit(s.units[2].id)
	measure("snapshot", snapshot)
	measure("refresh", demo._refresh)
	measure("heal_reason", s.healing_reason)
	measure("summon_reason", s.summoning_reason)
	measure("restore_reason", s.restore_armor_reason)
	measure("raise_reason", s.raise_reason)
	measure("guard_reason", s.guard_reason)
	measure("reachable", s.reachable_cells)
	measure("guard_preview", s.preview_guard)
	measure("armor_preview", s.preview_restore_armor)
	measure("attack_preview", s.preview_attack.bind(s.units[3].id))
	measure("bt_decide", BattleDemoBT.new().decide.bind(s,s.units[3]))
	await process_frame; await process_frame
