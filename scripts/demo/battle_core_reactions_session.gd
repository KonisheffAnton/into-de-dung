extends BattleCoreCombinationSession
class_name BattleCoreReactionsSession

var stun_selected: bool = false

func _first_team() -> Faction.Type:
	return Faction.Type.ENEMY

func retreat_reason() -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER: return &"move/no_selected_unit"
	var reason := ControlRules.action_reason(actor, true)
	if reason != &"": return reason
	if actor.action_resources == null: return &"move/invalid_runtime"
	if actor.action_resources.get_main_left() < 1: return &"move/insufficient_main"
	if actor.move_points_left < 1.0: return &"move/insufficient_move"
	return &""

func retreat_to(cell: Vector2i) -> ActionReceipt:
	var reason := retreat_reason()
	if reason != &"": return _reject(reason)
	var path := path_to(cell)
	if path.size() < 2: return _reject(&"move/unreachable")
	return _submit(MoveCommand.new(selected_id, path, context.get_revision(), &"safe_retreat"))

func preview_retreat(cell: Vector2i) -> MoveForecast:
	return MoveForecast.build_prepared(prepare_retreat_forecast(cell))

func prepare_retreat_forecast(cell: Vector2i) -> ForecastSimulation.Prepared:
	var reason := retreat_reason()
	if reason != &"": return ForecastSimulation.Prepared.rejected(reason)
	var path := path_to(cell)
	if path.size() < 2: return ForecastSimulation.Prepared.rejected(&"move/unreachable")
	return ForecastSimulation.prepare(context, _queue, MoveCommand.new(selected_id, path, context.get_revision(), &"safe_retreat"))

func _command_for(id: int) -> AttackCommand:
	if not stun_selected: return super._command_for(id)
	var ordinary := super._command_for(id)
	if ordinary == null: return null
	return AttackCommand.new(ordinary.get_actor_unit_id(), ordinary.get_target_unit_id(), ordinary.get_expected_actor_cell(), ordinary.get_expected_target_cell(), &"stunning_strike", ordinary.get_expected_revision())

## Новый состав способностей использует весь прежний общий бой и его границы хода.
func reset() -> void:
	super.reset()
	state.environment.collapse = {"turn": 0, "marked": []}
	stun_selected = false
	for index: int in [0, 1, 2, 3, 4, 5]:
		var perks := CombatPerksState.new()
		perks.definition.tank_reactions = index in [0, 1]
		perks.definition.counterattack = index in [0, 1]
		perks.definition.sneak_attack = index in [2, 5]
		perks.definition.stunning_strike = index in [0, 1]
		perks.definition.stun_immune = index == 3
		perks.definition.entangle_immune = index == 4
		perks.reaction_left = 1 if perks.definition.tank_reactions else 0
		units[index].combat_perks = perks
	var rules := context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for source: AttackDefinition in rules._definitions:
		var definition := AttackRules._copy_definition(source)
		definition.chain_push = true
		definition.backstab_bonus_percent = 0
		definition.sneak_attack_enabled = true
		definitions.append(definition)
	# Обычное попадание сохраняет компоненты/политику D3; исключения реакции явные.
	var reaction := AttackRules._copy_definition(definitions[0])
	reaction.id = &"opportunity_strike"
	reaction.profile = AttackRules.ARMOR_PROFILE
	reaction.reaction_strike = true
	reaction.chain_push = false
	reaction.critical_on_control = false
	definitions.append(reaction)
	var counter := AttackRules._copy_definition(reaction)
	counter.id = &"counter_strike"
	definitions.append(counter)
	var stunning := AttackRules._copy_definition(definitions[0])
	stunning.id = &"stunning_strike"
	stunning.profile = AttackRules.ARMOR_PROFILE
	stunning.bleeding_policy = &""
	stunning.entangle_on_physical_hp = false
	stunning.stun_on_physical_hp = true
	definitions.append(stunning)
	context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	for index: int in flow_log.size():
		if flow_log[index].contains("в спину"):
			flow_log[index] = "Клинок Бора пробивает 50% физической базы сквозь броню. Щит сохраняет иммунитет к кровотечению; шипы на C4. Рей оглушён до конца вашего хода."
	flow_log.append("Бор и Дозорный: перк «Скрытая атака» даёт +50% физической базы, когда цели угрожают хотя бы двое. Направление спины больше не даёт бонуса.")
	flow_log.append("Астра и Страж владеют Оглушающим ударом; Щит защищён от оглушения, Рей — от пут. Способности контроля на второй странице действий.")
	flow_log.append("Оппортунист/Прикрытие/Контратака на второй странице. Стойка с режимом стоит 1 основное; три режима делят один заряд. Контратака отвечает после полного удара, если враг ещё в досягаемости; стойка сохраняется.")
	flow_log.append("Порядок раунда: противник → вы → окружение. Окружение случайно отмечает клетку, а отметку прошлого круга обрушает в пропасть. Первый ход окружения только предупреждает; оставшийся на клетке погибает.")

func _after_team_end(incoming: Faction.Type) -> bool:
	if incoming != Faction.Type.ENEMY or state.environment.collapse.is_empty(): return true
	_transitioning = true
	var receipt := _submit(CollapsePhaseCommand.new(context.get_revision()))
	turn_events.append_array(receipt.get_events())
	_transitioning = false
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось завершить ход окружения. Начните бой заново.")
		return false
	return phase in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]

func prepare_environment_forecast() -> ForecastSimulation.Prepared:
	if not can_player_act(): return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	if not BattleExecutionWorker.can_transfer(self): return ForecastSimulation.Prepared.rejected(&"collapse/unsupported_runtime")
	return ForecastSimulation.prepare(context, _queue, CollapsePhaseCommand.new(context.get_revision()))

func preview_environment() -> ForecastSimulation:
	return ForecastSimulation.run_prepared(prepare_environment_forecast())

func reaction_reason(mode: int, cover_id: int = 0) -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	var actor := selected_unit()
	if actor == null or actor.faction != Faction.Type.PLAYER: return &"guard/no_selected_unit"
	return GuardCommand.new(actor.id, context.get_revision(), mode, cover_id).validate(context)

func set_reaction_guard(mode: int, cover_id: int = 0) -> ActionReceipt:
	var reason := reaction_reason(mode, cover_id)
	if reason != &"": return _reject(reason)
	return _submit(GuardCommand.new(selected_id, context.get_revision(), mode, cover_id))

func preview_reaction_guard(mode: int, cover_id: int = 0) -> GuardForecast:
	var reason := reaction_reason(mode, cover_id)
	if reason != &"": return GuardForecast.rejected(reason)
	return GuardForecast.build(context, _queue, GuardCommand.new(selected_id, context.get_revision(), mode, cover_id))

func cover_targets() -> Array[int]:
	var result: Array[int] = []
	var actor := selected_unit()
	if not MeleeThreat.has_tank(actor): return result
	for unit: UnitState in board.get_all_units():
		if MeleeThreat.cover_eligible(context, actor, unit): result.append(unit.id)
	result.sort()
	return result

func reaction_zone(actor_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var actor := board.get_unit_by_id(actor_id)
	if not MeleeThreat.has_reactions(actor): return cells
	var reach := ActionHpExecutor._stat_value(actor, StatTypes.StatType.ATTACK_RANGE)
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			if board.is_terrain_walkable(cell) and AttackReachCheck.inspect_spatial_cells(board, actor.cell, actor.faction, cell, reach) == &"": cells.append(cell)
	return cells
