extends SceneTree

const ACTION_LIMIT: int = 2400

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL HERO HUB PLAYTHROUGH: " + label)

func _run() -> void:
	_playthrough(false, "стартовый отряд")
	_playthrough(true, "отряд с магом")
	print("HERO HUB PLAYTHROUGH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _playthrough(include_mage: bool, label: String) -> void:
	var run := HeroHubState.create(4281 if include_mage else 4280)
	if include_mage:
		var mage_id := 0
		for id: int in run.heroes:
			if (run.heroes[id] as HeroProgression).class_id == &"mage": mage_id = id
		check(mage_id > 0 and run.party.size() == HeroHubState.MAX_PARTY, label + " mage exists and party is full")
		if mage_id <= 0 or run.party.is_empty(): return
		var removed_id: int = run.party.back()
		check(run.toggle_party(removed_id) and run.toggle_party(mage_id), label + " replace one starter with mage")
	var party_ids := run.party.duplicate()
	var experience_before: Dictionary = {}
	for id: int in run.heroes:
		experience_before[id] = (run.heroes[id] as HeroProgression).xp_tenths
	check(run.start_battle(), label + " hub checkpoint starts battle")
	var bundle := HeroHubBattleFactory.create(run)
	check(not bundle.is_empty(), label + " factory creates battle session")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	check(session.phase == BattleTacticalSession.Phase.DEPLOYMENT, label + " battle starts in deployment")
	check(session.start_battle(), label + " legal deployment placements start combat")
	var applied_attacks := 0
	var applied_moves := 0
	var enemy_steps := 0
	var completed_player_turns := 0
	var iterations := 0
	while iterations < ACTION_LIMIT and session.phase not in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION, BattleTacticalSession.Phase.FAULTED]:
		iterations += 1
		if session.context.is_faulted():
			break
		if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
			enemy_steps += 1
			session.step_enemy()
			continue
		if session.phase == BattleTacticalSession.Phase.PLAYER_TURN:
			for hero_id: int in party_ids:
				if session.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
				var unit_id: int = bundle.hero_units.get(hero_id, UnitId.NONE)
				var actions := _take_player_actions(session, unit_id)
				applied_attacks += int(actions.attack)
				applied_moves += int(actions.move)
			if session.phase == BattleTacticalSession.Phase.PLAYER_TURN:
				if session.end_player_turn(): completed_player_turns += 1
			continue
		check(false, label + " session entered unexpected phase %d" % session.phase)
		break
	var terminal := session.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]
	check(terminal, label + " reaches real terminal state before action limit (%d iterations)" % iterations)
	check(session.phase != BattleTacticalSession.Phase.FAULTED and not session.context.is_faulted(), label + " does not fault")
	check(enemy_steps > 0 and completed_player_turns > 0, label + " runs enemy AI and completed player turns")
	check(applied_attacks > 0 and applied_moves > 0, label + " applies legal attacks and path-based movement")
	if not terminal or session.phase == BattleTacticalSession.Phase.FAULTED:
		session.close()
		return
	var outcome := HeroHubBattleFactory.outcome(bundle)
	check(not outcome.is_empty() and int(outcome.serial) == int(bundle.serial), label + " factory publishes completed outcome")
	if outcome.is_empty():
		session.close()
		return
	check(outcome.victory, label + " wins the complete battle with normal commands")
	var committed := HeroHubState.from_dict(run.to_dict())
	check(committed != null and committed.finish_battle(outcome.serial, outcome.victory, outcome.hp, outcome.gear), label + " commits outcome to cloned profile")
	if committed == null:
		session.close()
		return
	check(committed.phase == "hub" and committed.run_serial == run.run_serial and committed.last_result != run.last_result, label + " checkpoint returns to hub with result")
	if outcome.victory:
		for hero_id: int in experience_before:
			if not committed.heroes.has(hero_id): continue
			var expected: int = int(experience_before[hero_id]) + (HeroHubState.VICTORY_XP * 10 if party_ids.has(hero_id) else HeroHubState.VICTORY_XP)
			check((committed.heroes[hero_id] as HeroProgression).xp_tenths == expected, label + " stores expected XP for hero %d" % hero_id)
	else:
		for hero_id: int in experience_before:
			if committed.heroes.has(hero_id) and not party_ids.has(hero_id):
				check((committed.heroes[hero_id] as HeroProgression).xp_tenths == int(experience_before[hero_id]), label + " defeat grants no reserve XP")
	var saved_result := committed.to_dict()
	check(HeroHubState.from_dict(saved_result) != null, label + " saved result passes profile validation")
	check(not committed.finish_battle(outcome.serial, outcome.victory, outcome.hp, outcome.gear) and committed.to_dict() == saved_result, label + " repeated terminal result cannot grant reward twice")
	var save_path := "user://hero-hub-playthrough-%d.save" % Time.get_ticks_usec()
	var write_error := HeroHubStore.write_run(save_path, committed)
	var restored := HeroHubStore.read_run(save_path)
	check(write_error.is_empty() and restored.get("error", "").is_empty() and restored.get("run") != null and restored.run.to_dict() == saved_result, label + " persists terminal result and XP")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	session.close()

func _take_player_actions(session: BattleCoreReactionsSession, unit_id: int) -> Dictionary:
	if unit_id == UnitId.NONE or not session.can_player_act() or not session.select_unit(unit_id):
		return {"attack":0, "move":0}
	var applied_attacks := 0
	var applied_moves := 0
	for attempt: int in 4:
		if not session.can_player_act(): break
		var actor := session.selected_unit()
		if actor == null or not actor.is_alive(): break
		if actor.action_resources != null and actor.action_resources.get_main_left() > 0:
			var target_id := _attackable_target(session)
			if target_id != UnitId.NONE:
				var attack := session.attack_unit(target_id)
				if attack != null and attack.status == ActionReceipt.APPLIED:
					applied_attacks += 1
					continue
		if actor.move_points_left > 0.0:
			var destination := _approach_cell(session, actor)
			if destination.x >= 0:
				var movement := session.move_to(destination)
				if movement != null and movement.status == ActionReceipt.APPLIED:
					applied_moves += 1
					continue
		break
	return {"attack":applied_attacks, "move":applied_moves}

func _attackable_target(session: BattleCoreReactionsSession) -> int:
	var enemies := session.living_ids(Faction.Type.ENEMY)
	enemies.sort()
	for target_id: int in enemies:
		var forecast := session.preview_attack(target_id)
		if forecast != null and forecast.status == ActionReceipt.APPLIED:
			return target_id
	return UnitId.NONE

func _approach_cell(session: BattleCoreReactionsSession, actor: UnitState) -> Vector2i:
	var enemies := session.living_ids(Faction.Type.ENEMY)
	if enemies.is_empty(): return Vector2i(-1, -1)
	var old_distance := _nearest_distance(session, actor.cell, enemies)
	var best_distance := old_distance
	var best_cell := Vector2i(-1, -1)
	for cell_value: Variant in session.reachable_cells():
		if typeof(cell_value) != TYPE_VECTOR2I: continue
		var cell: Vector2i = cell_value
		var path := session.path_to(cell)
		if path.size() < 2: continue
		var distance := _nearest_distance(session, cell, enemies)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	return best_cell

func _nearest_distance(session: BattleCoreReactionsSession, cell: Vector2i, enemies: Array[int]) -> int:
	var nearest := 1000
	for target_id: int in enemies:
		var target := session.board.get_unit_by_id(target_id)
		if target == null or not target.is_alive(): continue
		nearest = mini(nearest, absi(cell.x - target.cell.x) + absi(cell.y - target.cell.y))
	return nearest
