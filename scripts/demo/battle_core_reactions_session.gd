extends BattleCoreCombinationSession
class_name BattleCoreReactionsSession

var stun_selected: bool = false
var elemental_selected: StringName = &""
## Сессионная проекция классов не хранит ссылки на постоянных героев хаба.
var actor_loadouts: Dictionary = {}
## Назначение двух дополнительных кнопок образца; не часть D4-save.
var action_slot_overrides: Dictionary = {}

func visible_action_descriptors(available: Array[Dictionary]) -> Array[Dictionary]:
	var actor := selected_unit()
	var desired: Array = [&"entangling_strike", &"safe_retreat"]
	if MeleeThreat.has_tank(actor): desired = [&"opportunity_guard", &"stunning_strike"]
	elif MeleeThreat.has_counterattack(actor): desired = [&"counterattack_guard", &"safe_retreat"]
	elif actor_loadouts.get(selected_id, {}).get("class_id", &"") == &"mage": desired = [&"restore_armor", &"healing_item"]
	if action_slot_overrides.has(selected_id): desired = action_slot_overrides[selected_id]
	var result: Array[Dictionary] = []
	var seen: Array[StringName] = []
	for id: StringName in desired.slice(0, 2):
		if seen.has(id): continue
		seen.append(id)
		for descriptor: Dictionary in available:
			if descriptor.get("action_id", &"") == id:
				result.append(descriptor)
				break
	return result

func allows_loadout_action(action: StringName) -> bool:
	if not actor_loadouts.has(selected_id): return true
	var class_id: StringName = actor_loadouts[selected_id].class_id
	match action:
		&"blood_rune": return false
		&"entangling_strike": return class_id == &"archer"
		&"elemental", &"restore_armor": return class_id == &"mage"
	return true

func cast_reason(effect: StringName) -> StringName:
	if AbilityDefinition.mage_source_id(effect) > 0: return mage_reason(effect)
	if not allows_loadout_action(&"elemental"): return &"status/capability_required"
	if not can_player_act(): return &"battle/input_locked"
	var actor := selected_unit()
	if not ElementalRules.valid_unit(actor) or effect not in [&"burning", &"wet", &"freeze"]: return &"status/capability_required"
	var reason := ControlRules.action_reason(actor)
	if reason != &"": return reason
	return &"" if actor.action_resources != null and actor.action_resources.get_main_left() >= 1 else &"status/insufficient_main"

func cast_unit(id: int) -> ActionReceipt:
	if AbilityDefinition.mage_source_id(elemental_selected) > 0: return cast_mage_spell(elemental_selected, id)
	var reason := cast_reason(elemental_selected)
	if reason != &"": return _reject(reason)
	return _submit(ElementalCastCommand.new(selected_id, id, elemental_selected, context.get_revision()))

func prepare_cast_forecast(id: int) -> ForecastSimulation.Prepared:
	if AbilityDefinition.mage_source_id(elemental_selected) > 0: return prepare_mage_forecast(elemental_selected, id)
	var reason := cast_reason(elemental_selected)
	if reason != &"": return ForecastSimulation.Prepared.rejected(reason)
	return ForecastSimulation.prepare(context, _queue, ElementalCastCommand.new(selected_id, id, elemental_selected, context.get_revision()))

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
	if actor_loadouts.has(selected_id):
		var ordinary := super._command_for(id)
		if ordinary == null or rune_selected or (entangle_selected and not allows_loadout_action(&"entangling_strike")): return null
		var attack_id: StringName = actor_loadouts[selected_id].attack_id
		if stun_selected: attack_id = &"stunning_strike"
		elif entangle_selected: attack_id = &"entangling_strike"
		return AttackCommand.new(ordinary.get_actor_unit_id(), id, ordinary.get_expected_actor_cell(), ordinary.get_expected_target_cell(), attack_id, context.get_revision())
	if not stun_selected: return super._command_for(id)
	var ordinary := super._command_for(id)
	if ordinary == null: return null
	return AttackCommand.new(ordinary.get_actor_unit_id(), ordinary.get_target_unit_id(), ordinary.get_expected_actor_cell(), ordinary.get_expected_target_cell(), &"stunning_strike", ordinary.get_expected_revision())

## Новый состав способностей использует весь прежний общий бой и его границы хода.
func reset() -> void:
	actor_loadouts.clear()
	action_slot_overrides.clear()
	super.reset()
	state.environment.collapse = {"turn": 0, "marked": []}
	state.environment.status_effects = true
	for hazard: Dictionary in state.environment.fires: hazard["effect"] = "bleeding"
	state.environment.ignite(Vector2i(3, 2), "burning")
	for unit: UnitState in board.get_all_units():
		unit.elemental = ElementalState.new()
		if unit.control == null: unit.control = ControlState.new()
		unit.bleeding.stacked = true
	stun_selected = false
	elemental_selected = &""
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
	var item_definitions: Dictionary = {}
	for owner: ItemOwnerState in state.get_owners(): item_definitions.merge(owner._definitions, true)
	state.abilities = BattleAbilityState.create(AbilityCatalog.build(context.get_attack_rules(), item_definitions, true))
	if not deployment_enabled: state.abilities.apply_values(state.abilities.boundary(&"start", Faction.Type.ENEMY, 0))
	for index: int in flow_log.size():
		if flow_log[index].contains("в спину"):
			flow_log[index] = "Клинок Бора пробивает 50% физической базы сквозь броню. Щит сохраняет иммунитет к кровотечению; шипы на C4. Рей оглушён до конца вашего хода."
	flow_log.append("Бор и Дозорный: перк «Скрытая атака» даёт +50% физической базы, когда цели угрожают хотя бы двое. Направление спины больше не даёт бонуса.")
	flow_log.append("Астра и Страж владеют Оглушающим ударом; Щит защищён от оглушения, Рей — от пут. Назначенные способности персонажа слева.")
	flow_log.append("Режимы реакции назначаются в два дополнительных слота. Стойка с режимом стоит 1 основное; три режима делят один заряд. Контратака отвечает после полного удара, если враг ещё в досягаемости; стойка сохраняется.")
	flow_log.append("Порядок раунда: противник → вы → окружение. Окружение случайно отмечает клетку, а отметку прошлого круга обрушает в пропасть. Первый ход окружения только предупреждает; оставшийся на клетке погибает.")
	flow_log[0] = "Шипы: 8 физического урона и стак кровотечения при входе. Горящая земля D3: поджог при входе и в начале хода, без разового урона. Броня не мешает наложению клеткой."
	flow_log.append("Кровотечение: 1 за стак в начале хода, 2 за пройденную клетку; новое наложение обновляет 3 тика. Поджог снимает кровотечение; мокрый гасит поджог. Новые действия: Поджечь, Облить, Заморозить — 1 основное, дальность 3.")

func restore_armor_reason() -> StringName:
	if not allows_loadout_action(&"restore_armor"): return &"status/capability_required"
	return super.restore_armor_reason()

func healing_item() -> ItemInstance:
	if not actor_loadouts.has(selected_id): return super.healing_item()
	var owner := state.get_owner(selected_id) if state != null else null
	if owner == null: return null
	for item: ItemInstance in owner.get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if String(item.get_definition_id()).begins_with("hero_flask_"): return item
	return null

func _check_outcome() -> void:
	super._check_outcome()
	if actor_loadouts.is_empty() or context == null or context.is_busy() or context.is_faulted(): return
	if phase not in [Phase.PLAYER_TURN, Phase.ENEMY_TURN, Phase.VICTORY]: return
	for id: int in actor_loadouts:
		var unit := board.get_unit_by_id(id)
		if unit != null and unit.is_alive(): return
	# Временный помощник не заменяет погибших постоянных участников похода.
	_set_terminal(Phase.DEFEAT, "Все наёмники погибли. Резерв остался в хабе.")

# Переход владеет вводом целиком, включая callbacks каждого корня.
func _refill(faction: Faction.Type) -> bool:
	if state.abilities == null: return super._refill(faction)
	if _transitioning: return false
	var outgoing := Faction.Type.PLAYER if faction == Faction.Type.ENEMY else Faction.Type.ENEMY
	if state.abilities.team != outgoing or state.abilities.stage != "active": return false
	_transitioning = true
	if not _ability_boundary(&"close"): return _transition_failed()
	if not _transition_root(ControlTurnEndCommand.new(outgoing, context.get_revision())): return _transition_failed()
	if not _ability_boundary(&"end"): return _transition_failed()
	if faction == Faction.Type.ENEMY and not state.environment.collapse.is_empty():
		if not _transition_root(CollapsePhaseCommand.new(context.get_revision())): return _transition_failed()
	if not _transition_root(BleedingTurnCommand.new(faction, context.get_revision())): return _transition_failed()
	if not _transition_root(BattleTurnRefill.new(living_ids(faction), context.get_revision(), faction)): return _transition_failed()
	if not _ability_boundary(&"begin"): return _transition_failed()
	phase = Phase.PLAYER_TURN if faction == Faction.Type.PLAYER else Phase.ENEMY_TURN
	if not _ability_boundary(&"open"): return _transition_failed()
	_transitioning = false
	return true

func _transition_failed() -> bool:
	_transitioning = false
	return false

func _transition_root(command: Command) -> bool:
	var receipt := _submit(command)
	turn_events.append_array(receipt.get_events())
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось завершить переход команд. Начните бой заново.")
		return false
	return phase in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]

func _ability_boundary(operation: StringName) -> bool:
	var ability := state.abilities
	return _transition_root(AbilityBoundaryCommand.new(operation, ability.team, ability.serials[ability.team], context.get_revision()))

func begin_deployment() -> bool:
	if not super.begin_deployment(): return false
	if state.abilities != null:
		state.abilities.serials = [0, 0]; state.abilities.ended = [0, 0]
		state.abilities.stage = "setup"; state.abilities.mage_allowed = false
	return true

func start_battle() -> bool:
	if not super.start_battle(): return false
	if state.abilities != null:
		var after := state.abilities.boundary(&"start", Faction.Type.ENEMY, 0)
		if after.is_empty(): return false
		state.abilities.apply_values(after)
	return true

func mage_reason(spell: StringName) -> StringName:
	if not can_player_act(): return &"battle/input_locked"
	var ability := state.abilities
	if ability == null or not BattleAbilityState.valid(ability.to_dict()): return &"mage/capability_required"
	if not ability.mage_allowed: return &"mage/window_closed"
	var definition := ability.definition(spell)
	if definition == null or AbilityDefinition.mage_source_id(spell) == 0: return &"mage/unknown_spell"
	if ability.remaining(spell) > 0: return &"mage/cooldown"
	return &"mage/insufficient_mana" if ability.mana < definition.mana_cost else &""

func cast_mage_spell(spell: StringName, target: int) -> ActionReceipt:
	var reason := mage_reason(spell)
	if reason != &"": return _reject(reason)
	return _submit(MageCastCommand.new(spell, target, context.get_revision()))

func prepare_mage_forecast(spell: StringName, target: int) -> ForecastSimulation.Prepared:
	var reason := mage_reason(spell)
	if reason != &"": return ForecastSimulation.Prepared.rejected(reason)
	return ForecastSimulation.prepare(context, _queue, MageCastCommand.new(spell, target, context.get_revision()))

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
