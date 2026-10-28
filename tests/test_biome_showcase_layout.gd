extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BIOME SHOWCASE LAYOUT: " + label)

func run() -> void:
	var board := BattleBoard.new(BiomeShowcaseLayout.SIZE.x, BiomeShowcaseLayout.SIZE.y)
	var authored: Dictionary = ExpeditionOpening.values()
	for tile: Dictionary in authored.terrain:
		board.set_terrain(ExpeditionOpening.cell(tile.cell), int(tile.type) as TerrainType.Type)
	for tile: Dictionary in authored.heights:
		board.set_height_steps(ExpeditionOpening.cell(tile.cell), int(tile.steps))
	BiomeShowcaseLayout.apply(board, true)
	check(board.width == 24 and board.height == 16 and board.width * board.height == 384, "first room board dimensions")
	for chunk_index: int in range(BiomeShowcaseLayout.CHUNK_ORIGINS.size()):
		var origin: Vector2i = BiomeShowcaseLayout.CHUNK_ORIGINS[chunk_index]
		var wall := origin + Vector2i(3, 0)
		check(board.get_terrain(wall) == TerrainType.Type.WALL, "chunk ordinary wall " + str(wall))
		check(board.get_height_steps(origin + Vector2i(3, 3)) == 1, "chunk half ledge " + str(origin))
		check(board.get_height_steps(origin + Vector2i(4, 3)) == 2, "chunk full ledge " + str(origin))
		check(board.get_terrain(origin + Vector2i(2, 0)) == TerrainType.Type.FLOOR, "corridor remains walkable " + str(origin))
		if chunk_index > 0:
			check(board.get_terrain(origin + Vector2i(5, 6)) == TerrainType.Type.FLOOR and board.get_terrain(origin + Vector2i(6, 7)) == TerrainType.Type.FLOOR, "replica omits lethal terrain " + str(origin))
	check(board.get_terrain(Vector2i(5, 6)) == TerrainType.Type.HAZARD and board.get_terrain(Vector2i(6, 7)) == TerrainType.Type.VOID, "authored first chunk lethal geometry stays in place")
	var snapshot_result := SimulationSnapshot.capture_board(board, [])
	check(snapshot_result.code == BoardSnapshotResult.Code.OK, "board snapshot admitted")
	if snapshot_result.code == BoardSnapshotResult.Code.OK:
		var snapshot: SimulationSnapshot = snapshot_result.snapshot
		var copied := SimulationSnapshot.from_dict(snapshot.to_dict())
		var restored: BattleBoard = copied.snapshot.instantiate_board() if copied.code == BoardSnapshotResult.Code.OK else null
		check(restored != null and restored.width == 24 and restored.height == 16, "snapshot copy and restore dimensions")
		check(restored != null and restored.to_snapshot_dict() == board.to_snapshot_dict(), "snapshot copy and restore geometry")
	var empty_opening_board := BattleBoard.new(BiomeShowcaseLayout.SIZE.x, BiomeShowcaseLayout.SIZE.y)
	BiomeShowcaseLayout.apply(empty_opening_board, false)
	check(empty_opening_board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.FLOOR and empty_opening_board.get_height_steps(Vector2i(4, 3)) == 0, "legacy first chunk preserves original flat layout")
	check(empty_opening_board.get_terrain(Vector2i(11, 0)) == TerrainType.Type.WALL and empty_opening_board.get_height_steps(Vector2i(12, 3)) == 2, "legacy expansion adds safe samples outside original chunk")
	check(empty_opening_board.get_terrain(Vector2i(5, 6)) == TerrainType.Type.FLOOR and empty_opening_board.get_terrain(Vector2i(6, 7)) == TerrainType.Type.FLOOR, "empty opening contains no lethal terrain")

	var hub := HeroHubState.create(443)
	var legacy_hub := HeroHubState.from_dict(hub.to_dict())
	check(legacy_hub.start_battle(), "legacy battle starts before factory construction")
	var legacy_bundle := HeroHubBattleFactory.create(legacy_hub)
	check(not legacy_bundle.is_empty() and legacy_bundle.session.board.width == 8 and legacy_bundle.session.board.height == 8, "legacy battle keeps standard board")
	if not legacy_bundle.is_empty(): legacy_bundle.session.close()
	hub.enable_mage_deck()
	var started := ExpeditionTransitions.apply(hub, "start", {})
	check(started.is_ok(), "deck expedition starts")
	if started.is_ok():
		hub = started.profile
		var saved_profile := hub.to_dict()
		var first_unit_id := UnitId.get_counter()
		var bundle := HeroHubBattleFactory.create(hub)
		check(not bundle.is_empty() and bundle.session.board.width == 24 and bundle.session.board.height == 16, "first expedition factory builds expanded board")
		if not bundle.is_empty():
			check(bundle.session.board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.WALL and bundle.session.board.get_terrain(Vector2i(5, 6)) == TerrainType.Type.HAZARD and bundle.session.board.get_terrain(Vector2i(6, 7)) == TerrainType.Type.VOID, "authored first chunk geometry stays in place")
			check(bundle.session.state.environment.fire_at(Vector2i(3, 2)).effect == "bleeding" and bundle.session.state.environment.fire_at(Vector2i(4, 4)).effect == "burning", "authored first chunk hazards stay in place")
		check(hub.to_dict() == saved_profile, "factory leaves saved profile unchanged")
		if not bundle.is_empty():
			var state_snapshot := ItemSimulationSnapshot.capture(bundle.session.state, [])
			var battle_rng: Dictionary = (bundle.session as BattleCoreReactionsSession).context.get_rng().to_dict()
			var final_unit_id := UnitId.get_counter()
			bundle.session.close()
			UnitId.set_counter(first_unit_id)
			var replay_hub := HeroHubState.from_dict(saved_profile)
			var replay_bundle := HeroHubBattleFactory.create(replay_hub)
			var replay_snapshot: ItemSnapshotResult = ItemSimulationSnapshot.capture(replay_bundle.session.state, []) if not replay_bundle.is_empty() else null
			check(state_snapshot.code == ItemSnapshotResult.Code.OK and replay_snapshot != null and replay_snapshot.code == ItemSnapshotResult.Code.OK and state_snapshot.snapshot.to_dict() == replay_snapshot.snapshot.to_dict(), "restart recreates complete board snapshot")
			check(not replay_bundle.is_empty() and replay_bundle.session.context.get_rng().to_dict() == battle_rng, "restart preserves seeded battle RNG")
			if not replay_bundle.is_empty(): replay_bundle.session.close()
			UnitId.set_counter(final_unit_id)
		check_cross_chunk_move(HeroHubState.from_dict(saved_profile), [Vector2i(7, 7), Vector2i(8, 7)], "horizontal")
		check_cross_chunk_move(HeroHubState.from_dict(saved_profile), [Vector2i(7, 7), Vector2i(7, 8)], "vertical")
		check_collapse_beyond_eight(HeroHubState.from_dict(saved_profile))
		var outcome := ExpeditionTransitions.apply(hub, "outcome", successful_receipt(hub))
		check(outcome.is_ok(), "first room outcome advances expedition")
		if outcome.is_ok():
			hub = outcome.profile
			var reward := ExpeditionTransitions.apply(hub, "reward", {"index": -1})
			check(reward.is_ok(), "first room reward resolves")
			if reward.is_ok():
				hub = reward.profile
				var next_battle_id: int = 0
				for node_id: int in hub.expedition.available_nodes():
					var candidate: Dictionary = hub.expedition.plan.nodes[node_id - 1]
					if candidate.kind in ["battle", "elite", "final"]:
						next_battle_id = node_id
						break
				check(next_battle_id > 0, "next layer offers another battle")
				if next_battle_id > 0:
					var choice := ExpeditionTransitions.apply(hub, "choose", {"node": next_battle_id})
					check(choice.is_ok(), "nonfirst battle selected")
					if choice.is_ok():
						var next_bundle := HeroHubBattleFactory.create(choice.profile)
						check(not next_bundle.is_empty() and next_bundle.session.board.width == 8 and next_bundle.session.board.height == 8, "nonfirst expedition keeps standard board")
						if not next_bundle.is_empty(): next_bundle.session.close()
	var wrong_size := BattleBoard.new(8, 8)
	BiomeShowcaseLayout.apply(wrong_size, true)
	check(wrong_size.width == 8 and wrong_size.height == 8 and wrong_size.get_terrain(Vector2i(3, 0)) == TerrainType.Type.FLOOR, "adapter leaves legacy board untouched")
	print("BIOME SHOWCASE LAYOUT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check_cross_chunk_move(profile: HeroHubState, path: Array[Vector2i], label: String) -> void:
	var run := HeroHubState.from_dict(profile.to_dict())
	var bundle := HeroHubBattleFactory.create(run)
	if bundle.is_empty():
		check(false, label + " fixture battle exists")
		return
	var session: BattleCoreReactionsSession = bundle.session
	var actor: UnitState = null
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.PLAYER:
			actor = unit
			break
	check(actor != null, label + " player fixture exists")
	if actor != null:
		check(session.board.move_unit(actor, Vector2i(7, 7)), label + " actor positioned at seam")
		actor.move_points_left = float(actor.get_stat(StatTypes.StatType.MOVE_RANGE))
		var before := ItemSimulationSnapshot.capture(session.state, [])
		var rng_before := session.context.get_rng().to_dict()
		var command := MoveCommand.new(actor.id, path, session.context.get_revision())
		var preview := MoveForecast.build(session.context, session._queue, command)
		check(preview.status == ActionReceipt.APPLIED and session.board.occupant_at(path.back()) == null, label + " preview crosses seam without mutating live board")
		check(before.code == ItemSnapshotResult.Code.OK and before.snapshot.to_dict() == ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() and session.context.get_rng().to_dict() == rng_before, label + " preview preserves live state and RNG")
		var receipt := session._queue.submit(command, session.context)
		var after := ItemSimulationSnapshot.capture(session.state, [])
		check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, label + " live command matches preview events")
		check(after.code == ItemSnapshotResult.Code.OK and after.snapshot.to_dict() == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after, label + " live command matches preview state and RNG")
		check(actor.cell == path.back(), label + " actor reaches other side of seam")
	session.close()

func check_collapse_beyond_eight(profile: HeroHubState) -> void:
	var run := HeroHubState.from_dict(profile.to_dict())
	var bundle := HeroHubBattleFactory.create(run)
	if bundle.is_empty():
		check(false, "collapse fixture battle exists")
		return
	var session: BattleCoreReactionsSession = bundle.session
	var far_cell := Vector2i(20, 12)
	session.state.environment.collapse = {"turn": 1, "marked": [far_cell]}
	var command := CollapsePhaseCommand.new(session.context.get_revision())
	var preview := ForecastSimulation.run(session.context, session._queue, command)
	var receipt := session._queue.submit(command, session.context)
	check(preview.status == ActionReceipt.APPLIED and preview.events.any(func(event: Dictionary) -> bool: return event.get("kind") == &"support_collapsed" and event.get("cell") == far_cell), "collapse forecast handles support beyond legacy board")
	check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "large-board collapse live result matches preview")
	check(session.board.get_terrain(far_cell) == TerrainType.Type.VOID and preview.snapshot_after == ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(), "large-board collapse mutates far cell deterministically")
	check(preview.rng_after == session.context.get_rng().to_dict() and preview.counters_after == session.context.simulation_counters(), "large-board collapse preserves preview/live RNG and counters")
	session.close()

func successful_receipt(hub: HeroHubState) -> Dictionary:
	var hp: Dictionary = {}
	var gear: Dictionary = {}
	for hero_id: int in hub.party:
		hp[hero_id] = float((hub.heroes[hero_id] as HeroProgression).max_hp())
	for item: Dictionary in hub.expedition.checkpoint.legacy_inputs.items:
		gear[item.id] = item.remaining
	return {"ruleset_id": ExpeditionRulesRegistry.DECK, "run_id": hub.expedition.run_id,
		"node_id": hub.expedition.current_node().id, "serial": hub.expedition.battle_serial,
		"victory": true, "hp": hp, "gear": gear}
