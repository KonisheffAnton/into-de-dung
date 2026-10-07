extends BattleDemoSession
class_name BattleTacticalSession

## Первый бой: границы командных ходов принадлежат runtime, а не выделению в UI.
enum Phase { PLAYER_TURN, ENEMY_TURN, VICTORY, DEFEAT, MUTUAL_DESTRUCTION, FAULTED, DEPLOYMENT }
var phase: Phase = Phase.PLAYER_TURN
var round_number: int = 1
var flow_log: Array[String] = []
var _enemy_ids: Array[int] = []
var _enemy_index: int = 0
var _enemy_actions: int = 0
var _transitioning: bool = false

func _first_team() -> Faction.Type:
	return Faction.Type.PLAYER

func _initial_phase() -> Phase:
	return Phase.ENEMY_TURN if _first_team() == Faction.Type.ENEMY else Phase.PLAYER_TURN

func _summoning_definition() -> ItemDef:
	var definition := ItemDef.new()
	definition.id = &"tactical_summoning_seal"
	definition.display_name = "Печать"
	definition.use_summon = true
	definition.max_charges = 2
	definition.summon_definition = SummonDefinition.new()
	return definition

func reset() -> void:
	super.reset()
	# Отдельный сценарий сохраняет прежние sandbox fixtures и формулы ядра.
	units[3].faction = Faction.Type.ENEMY
	units[5].debug_name = "Дозорный"
	for unit in units:
		if unit.faction != Faction.Type.PLAYER: continue
		var definition := ItemDef.new()
		definition.id = &"tactical_healing_flask"
		definition.display_name = "Флакон"
		definition.use_heal_amount = 12.0
		definition.max_charges = 2
		var owner := state.get_owner(unit.id)
		var item := owner.create_item(definition)
		for inventory in state.get_inventories():
			if inventory._state == owner: inventory.add_item(item)
	for unit in units:
		var definition := _summoning_definition()
		var owner := state.get_owner(unit.id)
		state.get_inventory(unit.id).add_item(owner.create_item(definition))
	phase = _initial_phase()
	round_number = 1
	_enemy_ids.clear()
	if phase == Phase.ENEMY_TURN: _enemy_ids = living_ids(Faction.Type.ENEMY)
	_enemy_index = 0
	_enemy_actions = 0
	_transitioning = false
	if phase == Phase.ENEMY_TURN: selected_id = UnitId.NONE
	flow_log = ["Раунд 1. Ход противника." if phase == Phase.ENEMY_TURN else "Раунд 1. Ваш ход: победите трёх противников."]

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

func click_attack(id: int) -> ActionReceipt:
	return BattleClickAttack.execute(self, id)

func preview_move(cell: Vector2i) -> MoveForecast:
	if not can_player_act(): return MoveForecast.rejected(&"battle/input_locked")
	return super.preview_move(cell)

func prepare_move_forecast(cell: Vector2i) -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	return super.prepare_move_forecast(cell)

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

func prepare_attack_forecast(id: int) -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	var target := board.get_unit_by_id(id)
	if target != null and target.faction == Faction.Type.PLAYER: return ForecastSimulation.Prepared.rejected(&"battle/friendly_target")
	return super.prepare_attack_forecast(id)

func guard_reason() -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER: return &"guard/no_selected_unit"
	return GuardCommand.new(actor.id, context.get_revision()).validate(context)

func guard_selected() -> ActionReceipt:
	var reason := guard_reason()
	if reason != &"": return _reject(reason)
	return _submit(GuardCommand.new(selected_id, context.get_revision()))

func raise_shields_reason() -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	return RaiseShieldsCommand.new(selected_id, context.get_revision()).validate(context)

func raise_shields() -> ActionReceipt:
	var reason := raise_shields_reason()
	if reason != &"": return _reject(reason)
	return _submit(RaiseShieldsCommand.new(selected_id, context.get_revision()))

func prepare_raise_shields_forecast() -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	return ForecastSimulation.prepare(context, _queue, RaiseShieldsCommand.new(selected_id, context.get_revision()))

func preview_guard() -> GuardForecast:
	var reason := guard_reason()
	if reason != &"": return GuardForecast.rejected(reason)
	return GuardForecast.build(context, _queue, GuardCommand.new(selected_id, context.get_revision()))

func prepare_guard_forecast(mode: int = CombatPerksState.Mode.NONE, cover_id: int = 0) -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER: return ForecastSimulation.Prepared.rejected(&"guard/no_selected_unit")
	var command_mode := -1 if mode == CombatPerksState.Mode.NONE else mode
	return ForecastSimulation.prepare(context, _queue, GuardCommand.new(actor.id, context.get_revision(), command_mode, cover_id))

func healing_item() -> ItemInstance:
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER or state == null: return null
	var owner := state.get_owner(actor.id)
	if owner == null or owner.is_closed(): return null
	for item: ItemInstance in owner.get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if item.get_definition_id() == &"tactical_healing_flask": return item
	return null

func healing_reason() -> StringName:
	return _item_reason(healing_item(), ItemUseAction.Kind.HEAL_SELF)

func healing_hint_reason() -> StringName:
	return _item_reason(healing_item(), ItemUseAction.Kind.HEAL_SELF, Vector2i(-1, -1), true)

func use_healing_item() -> ActionReceipt:
	return _use_item(healing_item(), ItemUseAction.Kind.HEAL_SELF)

func preview_healing_item() -> ItemUseForecast:
	return _preview_item(healing_item(), ItemUseAction.Kind.HEAL_SELF)

func preview_summoning_item(cell: Vector2i) -> ItemUseForecast:
	return _preview_item(summoning_item(), ItemUseAction.Kind.SUMMON_ADJACENT, cell)

func prepare_item_forecast(kind: ItemUseAction.Kind, cell: Vector2i = Vector2i(-1, -1)) -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	var item := healing_item() if kind == ItemUseAction.Kind.HEAL_SELF else summoning_item()
	if item == null: return ForecastSimulation.Prepared.rejected(&"item/not_owned")
	var action := item.get_use_action()
	if action == null or action.get_kind() != kind: return ForecastSimulation.Prepared.rejected(&"item/not_usable")
	# Снимок проверяется при отделении; полная команда — на копии в рабочем потоке.
	return ForecastSimulation.prepare(context, _queue, action.create_command(selected_id, item.get_item_instance_id(), context.get_revision(), cell))

func _preview_item(item: ItemInstance, kind: ItemUseAction.Kind, cell: Vector2i = Vector2i(-1, -1)) -> ItemUseForecast:
	# Допуск совпадает с кликом, но отказ прогноза не заменяет последний live receipt.
	var reason := _item_reason(item, kind, cell)
	if reason != &"": return ItemUseForecast.rejected(reason)
	return ItemUseForecast.build(context, _queue, item_command(selected_id, item.get_item_instance_id(), cell))

func _item_reason(item: ItemInstance, kind: ItemUseAction.Kind, cell: Vector2i = Vector2i(-1, -1), hint_only: bool = false) -> StringName:
	# Порядок ходов остаётся у session; описание действия знает только допуск команды.
	if not can_player_act(): return &"battle/input_locked"
	if item == null: return &"item/not_owned"
	var action := item.get_use_action()
	if action == null or action.get_kind() != kind: return &"item/not_usable"
	if hint_only: return action.hint_reason(context, selected_id, item.get_item_instance_id(), cell)
	return action.availability_reason(context, selected_id, item.get_item_instance_id(), cell)

func _use_item(item: ItemInstance, kind: ItemUseAction.Kind, cell: Vector2i = Vector2i(-1, -1)) -> ActionReceipt:
	var reason := _item_reason(item, kind, cell)
	if reason != &"": return _reject(reason)
	return _submit(item_command(selected_id, item.get_item_instance_id(), cell))

func item_command(actor_id: int, item_id: int, cell: Vector2i = Vector2i(-1, -1)) -> Command:
	if context == null or state == null: return null
	var owner := state.get_owner(actor_id)
	var item: ItemInstance = owner._items.get(item_id) if owner != null and not owner.is_closed() else null
	var action := item.get_use_action() if item != null else null
	return action.create_command(actor_id, item_id, context.get_revision(), cell) if action != null else null

func _submit(command: Command) -> ActionReceipt:
	var receipt := super._submit(command)
	if board != null: units = board.get_all_units()
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
	if board == null: return ids
	for unit in board.get_all_units():
		if unit.is_alive() and unit.faction == faction: ids.append(unit.id)
	return ids

func end_player_turn() -> bool:
	if not can_player_act(): return false
	_check_outcome()
	if phase != Phase.PLAYER_TURN: return false
	if not _refill(Faction.Type.ENEMY): return false
	if _first_team() == Faction.Type.ENEMY: round_number += 1
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
			if _first_team() == Faction.Type.PLAYER: round_number += 1
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
	if intent.kind == BattleAIIntent.Kind.SUMMON:
		command = item_command(actor.id, intent.item_id, intent.cell)
	elif intent.kind == BattleAIIntent.Kind.GUARD:
		command = GuardCommand.new(actor.id, context.get_revision(), intent.reaction_mode, intent.target_id)
	elif intent.kind == BattleAIIntent.Kind.MOVE:
		command = MoveCommand.new(actor.id, intent.path, context.get_revision())
	else:
		var target := board.get_unit_by_id(intent.target_id)
		if target == null or not target.is_alive() or not actor.is_hostile_to(target):
			_next_enemy()
			return null
		command = AttackCommand.new(actor.id, target.id, actor.cell, target.cell, intent.attack_definition_id, context.get_revision())
	var receipt := _submit(command)
	if receipt.status != ActionReceipt.APPLIED or intent.kind in [BattleAIIntent.Kind.ATTACK, BattleAIIntent.Kind.SUMMON, BattleAIIntent.Kind.GUARD]: _next_enemy()
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

func summoning_item(actor_id: int = 0) -> ItemInstance:
	if state == null: return null
	var id := selected_id if actor_id == 0 else actor_id
	var owner := state.get_owner(id)
	if owner == null or owner.is_closed(): return null
	for item: ItemInstance in owner.get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if item.get_definition_id() == &"tactical_summoning_seal": return item
	return null

func supports_summoning() -> bool:
	return true

func summoning_cells(actor_id: int = 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not supports_summoning(): return cells
	var actor := board.get_unit_by_id(selected_id if actor_id == 0 else actor_id) if board != null else null
	if actor == null: return cells
	var item := summoning_item(actor_id)
	var action := item.get_use_action() if item != null else null
	if action == null: return cells
	for cell: Vector2i in action.target_cells(board, actor.cell):
		if state.environment == null or state.environment.fire_at(cell).is_empty(): cells.append(cell)
	return cells

func summoning_reason() -> StringName:
	var cells := summoning_cells()
	var cell := cells[0] if not cells.is_empty() else Vector2i(-1, -1)
	return _item_reason(summoning_item(), ItemUseAction.Kind.SUMMON_ADJACENT, cell)

func summoning_hint_reason() -> StringName:
	if not supports_summoning(): return summoning_reason()
	var cells := summoning_cells()
	var cell := cells[0] if not cells.is_empty() else Vector2i(-1, -1)
	return _item_reason(summoning_item(), ItemUseAction.Kind.SUMMON_ADJACENT, cell, true)

func use_summoning_item(cell: Vector2i) -> ActionReceipt:
	return _use_item(summoning_item(), ItemUseAction.Kind.SUMMON_ADJACENT, cell)
