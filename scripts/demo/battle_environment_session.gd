extends BattleBleedingSession
class_name BattleEnvironmentSession

## Авторская сцена D5 не изменяет профиль и контрольные точки забега D4.
func reset() -> void:
	super.reset()
	state.environment = CombatEnvironmentState.new()
	state.environment.ignite(Vector2i(5, 2))
	state.environment.ignite(Vector2i(1, 1))
	# Готовое тело позволяет проверить поднятие до первого убийства; запись создаётся
	# тем же событием смерти, что и в настоящем бою, с отдельным unit ID.
	var fallen := UseSummoningItemCommand.make_helper(UseSummoningItemCommand.next_id(board), Faction.Type.NEUTRAL, Vector2i(0, 3), "")
	fallen.debug_name = "Павший разведчик"
	fallen.armor = ArmorState.new()
	fallen.bleeding = BleedingState.new()
	var owner := ItemOwnerState.new(fallen)
	state._owners.append(owner)
	state._inventories.append(InventoryState.new(owner))
	state._equipment.append(EquipmentState.new(owner))
	board.add_unit(fallen)
	_queue.submit(DeathCommand.new(fallen.id, DamageSource.new(&"cell", 0, fallen.cell)), context)
	units = board.get_all_units()
	flow_log = ["Шипы: 8 урона при входе и толчке, с учётом брони. Выбор персонажа и конец хода шипы не запускают.", "Поднимите тело рядом с Астрой: 1 основное, 16 HP, помощник действует со следующего хода команды. Клетки с шипами и занятые клетки не подходят."]

func raise_cells() -> Array[Vector2i]:
	return _raise_cells(false)

func raise_hint_cells() -> Array[Vector2i]:
	return _raise_cells(true)

func _raise_cells(hint_only: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var actor := selected_unit()
	if actor == null or state.environment == null: return result
	for record: Dictionary in state.environment.to_dict()["corpses"]:
		var command := RaiseCorpseCommand.new(actor.id, record["id"], context.get_revision())
		var reason := command.hint_reason(context) if hint_only else command.validate(context)
		if reason == &"" and not result.has(record["cell"]): result.append(record["cell"])
	return result

func raise_reason() -> StringName:
	return _raise_reason(false)

func raise_hint_reason() -> StringName:
	return _raise_reason(true)

func _raise_reason(hint_only: bool) -> StringName:
	if not can_player_act() or selected_unit() == null: return &"battle/input_locked"
	if state.is_summon(selected_id): return &"summon/helper_cannot_summon"
	if state.active_summon(selected_id) != null: return &"summon/active_helper"
	if selected_unit().action_resources.get_main_left() < 1: return &"item/insufficient_main"
	return &"" if not _raise_cells(hint_only).is_empty() else &"environment/no_corpse"

func raise_corpse(cell: Vector2i) -> ActionReceipt:
	if not can_player_act() or selected_unit() == null: return _reject(&"battle/input_locked")
	var command := _raise_command(cell)
	if command != null: return _submit(command)
	return _reject(&"environment/no_corpse")

func preview_raise_corpse(cell: Vector2i) -> RaiseCorpseForecast:
	if not can_player_act() or selected_unit() == null: return RaiseCorpseForecast.rejected(&"battle/input_locked")
	var command := _raise_command(cell)
	if command == null: return RaiseCorpseForecast.rejected(&"environment/no_corpse")
	return RaiseCorpseForecast.build(context, _queue, command)

func prepare_raise_corpse_forecast(cell: Vector2i) -> ForecastSimulation.Prepared:
	if not can_player_act() or selected_unit() == null: return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	var command := _raise_command(cell)
	if command == null: return ForecastSimulation.Prepared.rejected(&"environment/no_corpse")
	return ForecastSimulation.prepare(context, _queue, command)

func _raise_command(cell: Vector2i) -> RaiseCorpseCommand:
	if state == null or state.environment == null: return null
	# Один выбор тела сохраняет прежний min-ID порядок для preview и настоящего клика.
	for record: Dictionary in state.environment.corpses_at(cell):
		if record["creature_kind"] == "humanoid":
			return RaiseCorpseCommand.new(selected_id, record["id"], context.get_revision())
	return null
