extends BattleEnvironmentSession
class_name BattleCoreCombinationSession

var entangle_selected: bool = false
var deployment_enabled: bool = false
var _setup_revision: int = -1

## Расстановка принадлежит сценарию: она не исполняет боевое перемещение/эффекты.
func begin_deployment() -> bool:
	if deployment_enabled or phase != Phase.PLAYER_TURN or context.get_revision() != _setup_revision or not _available(): return false
	deployment_enabled = true
	phase = Phase.DEPLOYMENT
	return true

func is_deploying() -> bool:
	return phase == Phase.DEPLOYMENT

func deployment_cells() -> Dictionary:
	var result: Dictionary = {}
	if not is_deploying() or board == null: return result
	for y: int in range(2, 6):
		for x: int in range(6):
			var cell := Vector2i(x, y)
			if board.is_in_bounds(cell) and board.is_terrain_walkable(cell) and not board.is_lethal(cell) and state.environment.fire_at(cell).is_empty():
				result[cell] = 0.0
	return result

func select_unit(id: int) -> bool:
	if not is_deploying(): return super.select_unit(id)
	var unit := board.get_unit_by_id(id)
	if not _available() or unit == null or not unit.is_alive() or unit.faction != Faction.Type.PLAYER: return false
	selected_id = id
	return true

func selected_unit() -> UnitState:
	if not is_deploying(): return super.selected_unit()
	return board.get_unit_by_id(selected_id) if board != null else null

func place_selected(cell: Vector2i) -> bool:
	if not is_deploying() or not _available(): return false
	var unit := selected_unit()
	if unit == null or not unit.is_alive() or unit.faction != Faction.Type.PLAYER or not deployment_cells().has(cell): return false
	if unit.cell == cell: return true
	if board.is_occupied(cell): return false
	return board.move_unit(unit, cell)

func start_battle() -> bool:
	if not is_deploying() or not _available(): return false
	var cells := deployment_cells()
	for id: int in living_ids(Faction.Type.PLAYER):
		var unit := board.get_unit_by_id(id)
		if not cells.has(unit.cell) or board.occupant_at(unit.cell) != unit: return false
	if ItemSimulationSnapshot.capture(state, []).code != ItemSnapshotResult.Code.OK: return false
	# Ресурсы и сроки уже заданы сценарием; повторное пополнение здесь меняло бы старт.
	phase = Phase.PLAYER_TURN
	flow_log.append("Расстановка завершена. Раунд 1: ваш ход.")
	return true

func phase_text() -> String:
	return "Расстановка · выберите союзника и свободную клетку в зоне" if is_deploying() else super.phase_text()

func summoning_reason() -> StringName:
	var cells := summoning_cells()
	var cell := cells[0] if not cells.is_empty() else Vector2i(-1, -1)
	return _item_reason(summoning_item(), ItemUseAction.Kind.SUMMON_ADJACENT, cell)

func supports_summoning() -> bool:
	return true

func _command_for(id: int) -> AttackCommand:
	if not entangle_selected: return super._command_for(id)
	var ordinary := super._command_for(id)
	if ordinary == null: return null
	return AttackCommand.new(ordinary.get_actor_unit_id(), ordinary.get_target_unit_id(), ordinary.get_expected_actor_cell(), ordinary.get_expected_target_cell(), &"entangling_strike", ordinary.get_expected_revision())

func _equip_scenario_weapon(unit: UnitState) -> void:
	if unit != units[2]: return
	# Сохраняем стартовый урон 4 после активации клинка, который добавляет ещё 4.
	unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	var definition := D4Catalog.definition("piercing_sword")
	var item := state.get_owner(unit.id).create_item(definition)
	if item == null or not state.get_equipment(unit.id).equip(EquipmentState.EquipSlot.WEAPON, item):
		push_error("K2 не удалось экипировать пробивающий клинок Бору")

## K2 соединяет прежние команды C1/D3/D5 в отдельном игровом сценарии.
func _configure_map() -> void:
	# Плоский участок отделяет сочетание контроля и шипов от прежнего уступа D2.
	pass

func reset() -> void:
	super.reset()
	entangle_selected = false
	var positions: Array[Vector2i] = [Vector2i(0, 2), Vector2i(5, 1), Vector2i(4, 3), Vector2i(3, 3), Vector2i(5, 5), Vector2i(5, 4)]
	for i: int in positions.size():
		var unit := units[i]
		unit.control = ControlState.new()
		if not board.move_unit(unit, positions[i]):
			push_error("K2 placement failed for unit %d" % unit.id)
	units[1].control.stunned_turns = 1
	units[3].control.entangled_turns = 1
	units[4].control.stunned_turns = 1
	state.environment.fires.clear()
	state.environment.ignite(Vector2i(2, 3))
	state.environment.ignite(Vector2i(1, 1))
	var rules := context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for id: StringName in [&"demo_strike", &"blood_rune"]:
		var definition := rules.get_definition(id)
		definition.backstab_bonus_percent = 50
		definition.critical_on_control = true
		definitions.append(definition)
	var entangling := AttackRules._copy_definition(definitions[0])
	entangling.id = &"entangling_strike"
	entangling.bleeding_policy = &""
	entangling.entangle_on_physical_hp = true
	definitions.append(entangling)
	context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	flow_log.append("Бор на E4 несёт пробивающий клинок: 50% физической базы обходят броню; Щит сохраняет иммунитет к кровотечению. Бор бьёт его в спину и сдвигает на шипы C4. Рей оглушён до конца вашего хода.")
	flow_log.append("Контроль истекает в конце хода своей команды, затем кровотечение входящей команды исполняется до восстановления действий. Астра может поднять прежнее тело на A4.")
	flow_log.append("Опутывающий удар — слот 7: путы после физического HP-урона и последствий удара, до конца ближайшего хода цели. Бор E5 → Дозорный F5: пробивание открывает наложение сквозь броню.")
	if deployment_enabled: phase = Phase.DEPLOYMENT
	_setup_revision = context.get_revision()

func _refill(faction: Faction.Type) -> bool:
	var outgoing := Faction.Type.PLAYER if faction == Faction.Type.ENEMY else Faction.Type.ENEMY
	_transitioning = true
	var expiry := _submit(ControlTurnEndCommand.new(outgoing, context.get_revision()))
	turn_events.append_array(expiry.get_events())
	_transitioning = false
	if expiry.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось завершить состояния хода. Начните бой заново.")
		return false
	# Даже успешная граница может завершить бой; следующий корень уже недопустим.
	if phase not in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]: return false
	return super._refill(faction)
