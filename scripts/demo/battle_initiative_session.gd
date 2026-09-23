extends BattleTacticalSession
class_name BattleInitiativeSession

## Изолированный эксперимент хранит инициативу только в runtime-сессии.
var individual_turns: bool = true
var current_actor_id: int = UnitId.NONE
var turn_order_ids: Array[int] = []
var turn_index: int = 0
var _round_roster: Array[int] = []
var _ai_actions: int = 0
var _ai_actor_id: int = UnitId.NONE

func reset() -> void:
	var mode := individual_turns
	super.reset()
	individual_turns = mode
	var values: Array[float] = [60.0, 50.0, 40.0, 30.0, 20.0, 10.0]
	for index in range(mini(units.size(), values.size())):
		units[index].stats.set_base_value(StatTypes.StatType.INITIATIVE, values[index])
	_round_roster.clear()
	turn_order_ids.clear()
	turn_index = 0
	_ai_actions = 0
	_ai_actor_id = UnitId.NONE
	current_actor_id = UnitId.NONE
	if individual_turns:
		flow_log.clear()
		_begin_round(false)

func current_actor() -> UnitState:
	if not individual_turns or phase in [Phase.VICTORY, Phase.DEFEAT, Phase.MUTUAL_DESTRUCTION, Phase.FAULTED]: return null
	var actor := board.get_unit_by_id(current_actor_id) if board != null else null
	return actor if actor != null and actor.is_alive() else null

func can_player_act() -> bool:
	if not individual_turns: return super.can_player_act()
	var actor := current_actor()
	return _available() and phase == Phase.PLAYER_TURN and actor != null and actor.faction == Faction.Type.PLAYER and selected_id == current_actor_id

func select_unit(id: int) -> bool:
	if not individual_turns: return super.select_unit(id)
	var actor := current_actor()
	if not _available() or phase != Phase.PLAYER_TURN or actor == null or actor.faction != Faction.Type.PLAYER or actor.id != id: return false
	selected_id = id
	return true

func selected_unit() -> UnitState:
	if not individual_turns: return super.selected_unit()
	if not can_player_act() or selected_id != current_actor_id: return null
	return current_actor()

func _submit(command: Command) -> ActionReceipt:
	var actor := current_actor() if individual_turns else null
	if individual_turns and actor == null:
		return _reject(&"battle/input_locked")
	var receipt := super._submit(command)
	if board != null: units = board.get_all_units()
	if individual_turns: _check_individual_outcome()
	return receipt

func _check_outcome() -> void:
	if not individual_turns:
		super._check_outcome()
		return
	_check_individual_outcome()

func _check_individual_outcome() -> void:
	if context == null: return
	# Итоги и переходы состава считаются только после полного опустошения очереди.
	if context.is_busy(): return
	if context.is_faulted():
		_set_terminal(Phase.FAULTED, "Бой остановлен из-за ошибки. Начните заново.")
		return
	if phase not in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]: return
	var players := living_ids(Faction.Type.PLAYER)
	var enemies := living_ids(Faction.Type.ENEMY)
	if players.is_empty() and enemies.is_empty(): _set_terminal(Phase.MUTUAL_DESTRUCTION, "Обе команды погибли. Бой окончен.")
	elif enemies.is_empty(): _set_terminal(Phase.VICTORY, "Победа! Все противники повержены.")
	elif players.is_empty(): _set_terminal(Phase.DEFEAT, "Поражение. Ваша команда погибла.")
	elif current_actor() == null:
		_advance_actor()

func end_player_turn() -> bool:
	if not individual_turns: return super.end_player_turn()
	if not can_player_act(): return false
	_check_individual_outcome()
	if not can_player_act(): return false
	_advance_actor()
	return phase not in [Phase.VICTORY, Phase.DEFEAT, Phase.MUTUAL_DESTRUCTION, Phase.FAULTED]

func step_enemy() -> ActionReceipt:
	if not individual_turns: return super.step_enemy()
	_check_individual_outcome()
	var actor := current_actor()
	if actor == null or actor.faction != Faction.Type.ENEMY or not _available(): return null
	if _ai_actor_id != actor.id:
		_ai_actor_id = actor.id
		_ai_actions = 0
	if _ai_actions >= 2:
		_advance_actor()
		return null
	var intent := BattleDemoBT.new().decide(self, actor)
	if intent == null or intent.kind == BattleAIIntent.Kind.WAIT:
		_advance_actor()
		return null
	var command: Command
	if intent.kind == BattleAIIntent.Kind.SUMMON:
		command = item_command(actor.id, intent.item_id, intent.cell)
	elif intent.kind == BattleAIIntent.Kind.MOVE:
		command = MoveCommand.new(actor.id, intent.path, context.get_revision())
	else:
		var target := board.get_unit_by_id(intent.target_id)
		if target == null or not target.is_alive() or not actor.is_hostile_to(target):
			_advance_actor()
			return null
		command = AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", context.get_revision())
	_ai_actions += 1
	var receipt := _submit(command)
	if current_actor_id == actor.id and (receipt.status != ActionReceipt.APPLIED or intent.kind in [BattleAIIntent.Kind.ATTACK, BattleAIIntent.Kind.SUMMON]): _advance_actor()
	return receipt

func _begin_round(increment: bool) -> void:
	if increment: round_number += 1
	var living: Array[UnitState] = []
	for unit in board.get_all_units():
		if unit.is_alive(): living.append(unit)
	var strategy := SimpleInitiativeStrategy.new()
	turn_order_ids.clear()
	for unit in strategy.compute_order(living): turn_order_ids.append(unit.id)
	_round_roster = turn_order_ids.duplicate()
	turn_index = 0
	_ai_actor_id = UnitId.NONE
	_ai_actions = 0
	_advance_actor(false)

func _advance_actor(advance: bool = true) -> void:
	if phase in [Phase.VICTORY, Phase.DEFEAT, Phase.MUTUAL_DESTRUCTION, Phase.FAULTED]: return
	if advance: turn_index += 1
	while turn_index < _round_roster.size():
		var id := _round_roster[turn_index]
		var actor := board.get_unit_by_id(id)
		if actor != null and actor.is_alive():
			current_actor_id = id
			selected_id = id if actor.faction == Faction.Type.PLAYER else UnitId.NONE
			phase = Phase.PLAYER_TURN if actor.faction == Faction.Type.PLAYER else Phase.ENEMY_TURN
			flow_log.append("Раунд %d · Ход: %s" % [round_number, actor.debug_name])
			_ai_actor_id = UnitId.NONE
			if not _refill_actor(actor): return
			return
		# Умерший участник остаётся в замороженном составе раунда, но пропускается.
		turn_index += 1
	_begin_round(true)

func _refill_actor(actor: UnitState) -> bool:
	_transitioning = true
	var receipt := super._submit(BattleTurnRefill.new([actor.id], context.get_revision(), actor.faction))
	_transitioning = false
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось начать ход. Начните заново.")
		return false
	if board != null: units = board.get_all_units()
	return true

func phase_text() -> String:
	if not individual_turns: return super.phase_text()
	if phase == Phase.PLAYER_TURN or phase == Phase.ENEMY_TURN:
		var actor := current_actor()
		return "Раунд %d · Ход: %s" % [round_number, actor.debug_name if actor != null else ""]
	return super.phase_text()
