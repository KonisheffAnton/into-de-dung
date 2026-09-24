extends BattleEnvironmentSession
class_name BattleCoreCombinationSession

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
	context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	flow_log.append("Бор на E4 несёт пробивающий клинок: 50% физической базы обходят броню; Щит сохраняет иммунитет к кровотечению. Бор бьёт его в спину и сдвигает на шипы C4. Рей оглушён до конца вашего хода.")
	flow_log.append("Контроль истекает в конце хода своей команды, затем кровотечение входящей команды исполняется до восстановления действий. Астра может поднять прежнее тело на A4.")

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
