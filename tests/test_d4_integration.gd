extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL D4 INTEGRATION: " + label)

func _run() -> void:
	_projection()
	_storage()
	_parties()
	print("D4 INTEGRATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _projection() -> void:
	var run := D4RunState.new()
	# Один усиленный предмет на складе, другой в рюкзаке: оба остаются пассивными.
	run.start_run()
	run._add_item("keen_sword", "warehouse", 0, -1, 0)
	run._add_item("charm", "backpack", 1, -1, 0)
	var before := run.to_dict()
	var s := D4BattleSession.new()
	check(s.configure(run), "projection configured")
	var astra: UnitState = s.hero_units[1]
	check(astra.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 4 and astra.get_stat(StatTypes.StatType.STRENGTH) == 6, "only equipped bonuses apply")
	check(s.projected_items.size() == 9 and s.state.get_inventory(astra.id).size() == 0, "backpacks excluded from active ledger")
	var snap := ItemSimulationSnapshot.capture(s.state, [])
	check(snap.code == ItemSnapshotResult.Code.OK, "equipped projection captures existing schema")
	if snap.snapshot == null:
		s.close()
		return
	var enemy: UnitState = s.units[3]
	s.board.move_unit(astra, Vector2i(3,3))
	s.board.move_unit(enemy, Vector2i(4,3))
	s.select_unit(astra.id)
	var live_before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var rng_before := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var forecast := s.preview_attack(enemy.id)
	check(forecast.status == ActionReceipt.APPLIED, "D4 forecast supported")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == live_before and s.context.get_rng().to_dict() == rng_before and s.context.simulation_counters() == counters and run.to_dict() == before, "preview isolates battle and persistent storage")
	var receipt := s.attack_unit(enemy.id)
	check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "live forecast events and steps parity")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "live forecast snapshot RNG counters parity")
	check(run.to_dict() == before, "battle projection never mutates checkpoint")
	s.close()
	# Между боями погибли двое, броня оставшегося повреждена.
	var armor := _armor(run)
	armor[2] = 17
	check(run.apply_battle_result(true, {1:19, 2:0, 3:0}, armor), "victory commits persistent HP armor")
	run.collect_loot(1)
	run.send_item(1)
	run.continue_run()
	check(s.configure(run), "second encounter builds")
	astra = s.hero_units[1]
	check(s.living_ids(Faction.Type.PLAYER).size() == 1 and not (s.hero_units[2] as UnitState).is_alive(), "dead heroes stay dead between encounters")
	check(astra.vitals.get_hp() == 19 and astra.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 0 and (s.projected_items[2] as ItemInstance).armor_remaining == 17, "sent gear absent; HP and wear survive")
	check(astra.bleeding.ticks_left == 0 and not astra.guard_stance and astra.action_resources.get_main_left() == 1, "new encounter resets temporary state")
	s.close()

func _storage() -> void:
	var path := "user://d4-tests/integration-%d.save" % Time.get_ticks_usec()
	var run := D4RunState.new()
	check(D4RunStore.write_run(path, run).is_empty(), "initial atomic save")
	run.start_run()
	check(D4RunStore.write_run(path, run).is_empty(), "replace save with battle checkpoint")
	var restored: D4RunState = D4RunStore.read_run(path).run
	check(restored != null and restored.to_dict() == run.to_dict(), "disk roundtrip checkpoint exact")
	run.apply_battle_result(false, {1:0, 2:0, 3:0}, _armor(run))
	check(D4RunStore.write_run(path, run).is_empty(), "persist loss result")
	restored = D4RunStore.read_run(path).run
	check(restored != null and restored.to_dict() == run.to_dict(), "restored loss does not reroll")
	var old := FileAccess.get_file_as_bytes(path)
	check(not D4RunStore.write_run("user://d4-tests", run).is_empty() and FileAccess.get_file_as_bytes(path) == old, "write failure preserves existing checkpoint")
	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_buffer(var_to_bytes({"format":"d4-v1", "payload":var_to_bytes(run.to_dict()), "sha256":"bad"}))
	corrupt.close()
	var rejected := D4RunStore.read_run(path)
	check(rejected.run == null and not rejected.error.is_empty(), "corruption rejects without new profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://d4-tests.tmp"))

func _parties() -> void:
	for active: bool in [true, false]:
		var run := D4RunState.new()
		run.start_run()
		var s := D4BattleSession.new()
		check(s.configure(run), "full party configuration")
		_play(s, active)
		var result := s.outcome_data()
		print("D4 PARTY active=%s phase=%d round=%d" % [active, s.phase, s.round_number])
		check(not result.is_empty(), "full party reaches terminal")
		if not result.is_empty():
			check(run.apply_battle_result(result.victory, result.hp, result.armor), "real terminal accepted by run")
			check(D4RunState.from_dict(run.to_dict()) != null, "terminal persistent roundtrip")
			if active: check(result.victory, "active party wins first encounter")
			else: check(not result.victory, "passive party loses")
		if active and run.phase == D4RunState.LOOT:
			for hero: Dictionary in run.heroes:
				if hero.hp > 0:
					run.collect_loot(hero.id)
					break
			run.continue_run()
			check(s.configure(run), "full second party starts with carried state")
			_play(s, true)
			result = s.outcome_data()
			print("D4 SECOND phase=%d round=%d" % [s.phase, s.round_number])
			check(not result.is_empty(), "second party reaches outcome")
			if not result.is_empty():
				check(run.apply_battle_result(result.victory, result.hp, result.armor), "second outcome commits")
			s.close()
		else: s.close()

func _play(s: D4BattleSession, active: bool) -> void:
	var ai := BattleDemoBT.new()
	for _round: int in 60:
		if s.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if active:
			for id: int in s.living_ids(Faction.Type.PLAYER):
				if not s.select_unit(id): break
				for _action: int in 2:
					var actor := s.board.get_unit_by_id(id)
					if actor == null or not actor.is_alive(): break
					var intent := ai.decide(s, actor)
					if intent.kind == BattleAIIntent.Kind.WAIT: break
					var receipt: ActionReceipt
					if intent.kind == BattleAIIntent.Kind.ATTACK: receipt = s.attack_unit(intent.target_id)
					elif intent.kind == BattleAIIntent.Kind.MOVE and not intent.path.is_empty(): receipt = s.move_to(intent.path.back())
					else: break
					check(receipt.status == ActionReceipt.APPLIED, "legal player intent executes")
					if s.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if s.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		s.end_player_turn()
		for _step: int in 24:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			var receipt := s.step_enemy()
			if receipt != null: check(receipt.status == ActionReceipt.APPLIED, "legal enemy intent executes")

func _armor(run: D4RunState) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in run.items:
		if record.place == "equipped": result[record.id] = record.armor
	return result
