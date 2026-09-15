extends BattleDemoSession
class_name BattleTacticalSession

## Первый бой: границы командных ходов принадлежат runtime, а не выделению в UI.
enum Phase { PLAYER_TURN, ENEMY_TURN, VICTORY, DEFEAT, MUTUAL_DESTRUCTION, FAULTED }
var phase: Phase = Phase.PLAYER_TURN
var round_number: int = 1
var flow_log: Array[String] = []
var _enemy_ids: Array[int] = []
var _enemy_index: int = 0
var _enemy_actions: int = 0
var _transitioning: bool = false

func reset() -> void:
	super.reset()
	# Отдельный сценарий сохраняет прежние sandbox fixtures и формулы ядра.
	units[3].faction = Faction.Type.ENEMY
	units[5].debug_name = "Дозорный"
	phase = Phase.PLAYER_TURN
	round_number = 1
	_enemy_ids.clear()
	_enemy_index = 0
	_enemy_actions = 0
	_transitioning = false
	flow_log = ["Раунд 1. Ваш ход: победите трёх противников."]

func _demo_stats() -> StatsBag:
	return StatsBag.from_base_values({
		StatTypes.StatType.HP_MAX: 32.0, StatTypes.StatType.ARMOR: 2.0,
		StatTypes.StatType.STRENGTH: 6.0, StatTypes.StatType.WEAPON_DAMAGE: 4.0,
		StatTypes.StatType.IMPACT_POWER: 5.0, StatTypes.StatType.BALANCE_MAX: 5.0,
		StatTypes.StatType.MOVE_RANGE: 5.0, StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0,
		StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0, StatTypes.StatType.ATTACK_RANGE: 1.0,
	})

func can_player_act() -> bool:
	return phase == Phase.PLAYER_TURN and _available()

func _available() -> bool:
	return context != null and not context.is_busy() and not context.is_faulted() and not _transitioning

func select_unit(id: int) -> bool:
	var unit := board.get_unit_by_id(id) if board != null else null
	return super.select_unit(id) if can_player_act() and unit != null and unit.faction == Faction.Type.PLAYER else false

func selected_unit() -> UnitState:
	return super.selected_unit() if can_player_act() else null

func move_to(cell: Vector2i) -> ActionReceipt:
	if not can_player_act(): return _reject(&"battle/input_locked")
	return super.move_to(cell)

func attack_unit(id: int) -> ActionReceipt:
	if not can_player_act(): return _reject(&"battle/input_locked")
	var target := board.get_unit_by_id(id)
	if target != null and target.faction == Faction.Type.PLAYER: return _reject(&"battle/friendly_target")
	return super.attack_unit(id)

func preview_attack(id: int) -> AttackForecast:
	if not can_player_act(): return AttackForecast.rejected(&"battle/input_locked")
	var target := board.get_unit_by_id(id)
	if target != null and target.faction == Faction.Type.PLAYER: return AttackForecast.rejected(&"battle/friendly_target")
	return super.preview_attack(id)

func guard_reason() -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER: return &"guard/no_selected_unit"
	return GuardCommand.new(actor.id, context.get_revision()).validate(context)

func guard_selected() -> ActionReceipt:
	var reason := guard_reason()
	if reason != &"": return _reject(reason)
	return _submit(GuardCommand.new(selected_id, context.get_revision()))

func _submit(command: Command) -> ActionReceipt:
	var receipt := super._submit(command)
	# События смерти ещё могут породить реакции; только вернувшийся receipt завершает действие.
	if context != null and not context.is_busy(): _check_outcome()
	return receipt

func _check_outcome() -> void:
	if context == null: return
	if context.is_faulted():
		_set_terminal(Phase.FAULTED, "Бой остановлен из-за ошибки. Начните заново.")
		return
	if phase not in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]: return
	var players := living_ids(Faction.Type.PLAYER)
	var enemies := living_ids(Faction.Type.ENEMY)
	if players.is_empty() and enemies.is_empty():
		_set_terminal(Phase.MUTUAL_DESTRUCTION, "Обе команды погибли. Бой окончен.")
	elif enemies.is_empty(): _set_terminal(Phase.VICTORY, "Победа! Все противники повержены.")
	elif players.is_empty(): _set_terminal(Phase.DEFEAT, "Поражение. Ваша команда погибла.")
	elif phase == Phase.PLAYER_TURN and super.selected_unit() == null:
		selected_id = players[0]

func _set_terminal(value: Phase, message: String) -> void:
	if phase == value: return
	phase = value
	selected_id = UnitId.NONE
	flow_log.append(message)

func living_ids(faction: Faction.Type) -> Array[int]:
	var ids: Array[int] = []
	for unit in units:
		if unit.is_alive() and unit.faction == faction: ids.append(unit.id)
	return ids

func end_player_turn() -> bool:
	if not can_player_act(): return false
	_check_outcome()
	if phase != Phase.PLAYER_TURN: return false
	if not _refill(Faction.Type.ENEMY): return false
	phase = Phase.ENEMY_TURN
	selected_id = UnitId.NONE
	_enemy_ids = living_ids(Faction.Type.ENEMY)
	_enemy_index = 0
	_enemy_actions = 0
	flow_log.append("Ход противника.")
	return true

func _refill(faction: Faction.Type) -> bool:
	_transitioning = true
	var receipt := super._submit(BattleTurnRefill.new(living_ids(faction), context.get_revision(), faction))
	_transitioning = false
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось начать ход. Начните бой заново.")
		return false
	return true

func step_enemy() -> ActionReceipt:
	if phase != Phase.ENEMY_TURN or not _available(): return null
	_check_outcome()
	if phase != Phase.ENEMY_TURN: return null
	if _enemy_index >= _enemy_ids.size():
		if _refill(Faction.Type.PLAYER):
			round_number += 1
			phase = Phase.PLAYER_TURN
			selected_id = living_ids(Faction.Type.PLAYER)[0]
			flow_log.append("Раунд %d. Ваш ход." % round_number)
		return null
	var actor := board.get_unit_by_id(_enemy_ids[_enemy_index])
	if actor == null or not actor.is_alive() or _enemy_actions >= 2:
		_next_enemy()
		return null
	var intent := BattleDemoBT.new().decide(self, actor)
	if intent == null or intent.kind == BattleAIIntent.Kind.WAIT:
		_next_enemy()
		return null
	_enemy_actions += 1
	var command: Command
	if intent.kind == BattleAIIntent.Kind.MOVE:
		command = MoveCommand.new(actor.id, intent.path, context.get_revision())
	else:
		var target := board.get_unit_by_id(intent.target_id)
		if target == null or not target.is_alive() or not actor.is_hostile_to(target):
			_next_enemy()
			return null
		command = AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", context.get_revision())
	var receipt := _submit(command)
	if receipt.status != ActionReceipt.APPLIED or intent.kind == BattleAIIntent.Kind.ATTACK: _next_enemy()
	return receipt

func _next_enemy() -> void:
	_enemy_index += 1
	_enemy_actions = 0

func phase_text() -> String:
	match phase:
		Phase.PLAYER_TURN: return "Раунд %d · Ваш ход" % round_number
		Phase.ENEMY_TURN: return "Раунд %d · Ход противника…" % round_number
		Phase.VICTORY: return "ПОБЕДА · Все противники повержены"
		Phase.DEFEAT: return "ПОРАЖЕНИЕ · Ваша команда погибла"
		Phase.MUTUAL_DESTRUCTION: return "БОЙ ОКОНЧЕН · Обе команды погибли"
	return "БОЙ ОСТАНОВЛЕН · Начните заново"
