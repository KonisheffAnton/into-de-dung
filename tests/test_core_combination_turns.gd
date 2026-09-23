extends SceneTree

const Session = preload("res://tests/fixtures/core_combination_session.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL K1 TURNS: " + label)

func _run() -> void:
	_team_and_ai()
	_lethal_boundary()
	print("CORE COMBINATION TURNS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _snapshot(s: D4BattleSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "capture " + capture.reason)
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func _seed_bleeding(unit: UnitState, source: UnitState) -> void:
	unit.bleeding.ticks_left = 2
	unit.bleeding.source = DamageSource.new(&"attack", 0, source.cell, source.id, source.id).to_dict()
	unit.bleeding.hit_id = "k1-start"

func _team_and_ai() -> void:
	var s := Session.new()
	check(s.build(), "supported fixture")
	var actor: UnitState = s.units[0]
	var target: UnitState = s.units[3]
	var ally: UnitState = s.units[2]
	var active_enemy: UnitState = s.units[4]
	target.control.stunned_turns = 1
	s.units[5].control.stunned_turns = 1
	active_enemy.control.entangled_turns = 1
	check(s.board.move_unit(active_enemy, Vector2i(5, 5)), "AI adjacent placement")
	ally.control.stunned_turns = 1
	ally.bleeding.immune = true
	_seed_bleeding(ally, target)
	ally.action_resources.try_spend_main(1)
	active_enemy.action_resources.try_spend_main(1)
	var attack := s.attack_unit(target.id)
	check(attack.status == ActionReceipt.APPLIED and target.bleeding.ticks_left == 2, "combined attack starts team test")
	check(target.cell == Vector2i(2, 3) and target.control.entangled_turns == 0 and target.control.stunned_turns == 1, "push removes only roots")
	check(actor.action_resources.get_main_left() == 0, "attack costs one main")
	var before := _snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	check(s.select_unit(ally.id) and s.select_unit(actor.id), "free team selection")
	check(_snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng, "selection preserves status resources RNG IDs")
	var target_hp := target.vitals.get_hp()
	var observations: Array[Dictionary] = []
	var observe := func(_old: float, _new: float) -> void:
		observations.append({"stun": ally.control.stunned_turns, "enemy_main": active_enemy.action_resources.get_main_left()})
	target.vitals.hp_changed.connect(observe)
	var boundary_root: int = s.context.simulation_counters()["next_root_id"]
	check(s.end_player_turn(), "end player turn")
	target.vitals.hp_changed.disconnect(observe)
	check(int(s.context.simulation_counters()["next_root_id"]) == boundary_root + 3, "one expiry, tick and refill submission")
	check(observations == [{"stun": 0, "enemy_main": 0}], "outgoing expiry then incoming tick before refill")
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN and target.bleeding.ticks_left == 1 and target.vitals.get_hp() == target_hp - 4, "one enemy tick; standing on spikes does not hit again")
	check(ally.bleeding.ticks_left == 2 and ally.control.stunned_turns == 0 and target.control.stunned_turns == 1, "only outgoing control and incoming bleeding change")
	check(active_enemy.action_resources.get_main_left() == 1 and actor.action_resources.get_main_left() == 0, "only incoming team refills")
	var player_observations: Array[Dictionary] = []
	var observe_player := func(_old: float, _new: float) -> void:
		if ally.bleeding.ticks_left == 1:
			player_observations.append({"main": ally.action_resources.get_main_left(), "stun": target.control.stunned_turns, "root": active_enemy.control.entangled_turns})
	ally.vitals.hp_changed.connect(observe_player)
	var attacks: Array[Dictionary] = []
	var receipts: int = 0
	for index: int in 24:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		var receipt := s.step_enemy()
		if receipt == null: continue
		receipts += 1
		check(receipt.status == ActionReceipt.APPLIED, "AI command admitted " + String(receipt.reason))
		for event: Dictionary in receipt.get_events():
			if event.get("kind") == &"attacked": attacks.append(event)
	ally.vitals.hp_changed.disconnect(observe_player)
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.round_number == 2, "real AI drains and returns turn")
	check(receipts == 1 and attacks.size() == 1, "stunned enemies wait; rooted adjacent enemy attacks")
	if attacks.size() == 1:
		check(int(attacks[0].get("actor_unit_id", 0)) == active_enemy.id, "actual attack belongs to permitted enemy")
	check(active_enemy.action_resources.get_main_left() == 0 and target.action_resources.get_main_left() == 1, "AI pays once, stunned enemy spends nothing")
	check(player_observations == [{"main": 0, "stun": 0, "root": 0}], "enemy expiry then player tick before refill")
	check(ally.bleeding.ticks_left == 1 and target.bleeding.ticks_left == 1, "one tick per incoming team")
	check(actor.action_resources.get_main_left() == 1 and ally.action_resources.get_main_left() == 1, "player refill once")
	check(s.boundary_receipts.size() == 4, "two expiry and two bleeding commands")
	check(int(s.context.simulation_counters()["next_root_id"]) == boundary_root + 6 + receipts, "one refill per boundary and only observed AI submissions")
	var expired_ids: Array[int] = []
	var tick_ids: Array[int] = []
	for receipt: ActionReceipt in s.boundary_receipts:
		for event: Dictionary in receipt.get_events():
			if event.get("kind") == &"control_changed": expired_ids.append(int(event["target_unit_id"]))
			if event.get("kind") == &"bleeding_changed": tick_ids.append(int(event["target_unit_id"]))
	check(expired_ids.size() == 4 and expired_ids.count(ally.id) == 1 and expired_ids.count(target.id) == 1 and expired_ids.count(active_enemy.id) == 1 and expired_ids.count(s.units[5].id) == 1, "control expires exactly once")
	check(tick_ids == [target.id, ally.id], "ticks ordered by incoming team")
	s.close()

func _lethal_boundary() -> void:
	var s := Session.new()
	check(s.build(), "lethal fixture")
	var target: UnitState = s.units[3]
	for enemy: UnitState in [s.units[4], s.units[5]]:
		var death := s._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test", 0, enemy.cell)), s.context)
		check(death.status == ActionReceipt.APPLIED, "remove other enemy via command")
	target.vitals.set_hp(19)
	var attack := s.attack_unit(target.id)
	check(attack.status == ActionReceipt.APPLIED and target.is_alive() and target.vitals.get_hp() == 4 and target.bleeding.ticks_left == 2, "combined hit leaves last enemy for tick")
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN, "nonterminal after attack drain")
	var boundary_root: int = s.context.simulation_counters()["next_root_id"]
	check(not s.end_player_turn() and s.phase == BattleTacticalSession.Phase.VICTORY, "boundary death ends battle before refill or phase change")
	check(int(s.context.simulation_counters()["next_root_id"]) == boundary_root + 2, "terminal boundary submits expiry and tick without refill")
	check(not target.is_alive() and not s.board.is_occupied(target.cell) and s.state.environment.corpses_at(target.cell).size() == 1, "tick death frees cell and creates one corpse")
	var deaths: int = 0
	var bodies: int = 0
	for receipt: ActionReceipt in s.boundary_receipts:
		for event: Dictionary in receipt.get_events():
			if event.get("kind") == &"died": deaths += 1
			if event.get("kind") == &"corpse_created": bodies += 1
	check(deaths == 1 and bodies == 1 and target.bleeding.ticks_left == 1, "drained death exactly once with spent tick")
	check(not s.units[0].armor.in_battle and s.units[0].action_resources.get_main_left() == 0, "battle finalization preserves spent resources")
	var before := _snapshot(s)
	check(not s.end_player_turn() and s.step_enemy() == null and _snapshot(s) == before, "terminal boundary cannot run twice")
	s.close()
