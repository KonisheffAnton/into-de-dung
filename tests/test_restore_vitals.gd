extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scenarios: Array[Dictionary] = [
		{"label": "wounded above base", "hp": 17.0, "alive": true},
		{"label": "full HP", "hp": 20.0, "alive": true},
		{"label": "dead", "hp": 0.0, "alive": false},
	]
	for scenario: Dictionary in scenarios:
		_run_case(scenario)
	print("RESTORE VITALS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run_case(scenario: Dictionary) -> void:
	var label: String = str(scenario["label"])
	var expected_hp: float = float(scenario["hp"])
	var expected_alive: bool = bool(scenario["alive"])
	var source: _Fixture = _make_fixture(label, expected_hp, expected_alive)
	var signals := _SignalCounter.new()
	var hp_callback := Callable(signals, "on_hp_changed")
	var died_callback := Callable(signals, "on_died")
	source.unit.vitals.hp_changed.connect(hp_callback)
	source.unit.vitals.died.connect(died_callback)

	var captured: ItemSnapshotResult = ItemSimulationSnapshot.capture(source.state, [])
	_check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, label + ": snapshot capture")
	if captured.code != ItemSnapshotResult.Code.OK or captured.snapshot == null:
		source.unit.vitals.hp_changed.disconnect(hp_callback)
		source.unit.vitals.died.disconnect(died_callback)
		_cleanup(source.state)
		return
	var source_bytes: PackedByteArray = captured.snapshot.canonical_bytes()
	var first: ItemSnapshotResult = captured.snapshot.instantiate(_catalogue(source.definition))
	var second: ItemSnapshotResult = captured.snapshot.instantiate(_catalogue(source.definition))
	_check(first.code == ItemSnapshotResult.Code.OK and first.state != null, label + ": first restore")
	_check(second.code == ItemSnapshotResult.Code.OK and second.state != null, label + ": second restore")
	if first.state != null and second.state != null:
		var first_unit: UnitState = first.state.get_board().get_unit_by_id(source.unit.id)
		var second_unit: UnitState = second.state.get_board().get_unit_by_id(source.unit.id)
		_check(first_unit != null and second_unit != null, label + ": restored units exist")
		if first_unit != null and second_unit != null:
			_check(first_unit != second_unit and first_unit.vitals != second_unit.vitals, label + ": restore branches own separate UnitState and Vitals")
			_check(_unit_matches(first_unit, expected_hp, expected_alive), label + ": first HP, max HP, alive")
			_check(_unit_matches(second_unit, expected_hp, expected_alive), label + ": second HP, max HP, alive")
			_check(_has_single_active_hp_modifier(first.state, source.unit.id), label + ": first ledger restores one equipped +10 effect and max HP 20")
			_check(_has_single_active_hp_modifier(second.state, source.unit.id), label + ": second ledger restores one equipped +10 effect and max HP 20")
			_check(_canonical_matches(first.state, source_bytes), label + ": first canonical snapshot parity")
			_check(_canonical_matches(second.state, source_bytes), label + ": second canonical snapshot parity")
			if expected_alive:
				# Только живые ветки меняют HP: не создаём недопустимый dead-positive state.
				var changed_hp: float = expected_hp - 1.0
				first_unit.vitals.set_hp(changed_hp)
				_check(is_equal_approx(first_unit.vitals.get_hp(), changed_hp), label + ": changed restored HP")
				_check(is_equal_approx(second_unit.vitals.get_hp(), expected_hp), label + ": other restore keeps HP")
				_check(is_equal_approx(source.unit.vitals.get_hp(), expected_hp), label + ": source keeps HP")
				_check(_canonical_matches(second.state, source_bytes), label + ": untouched restore remains canonical")
			else:
				# Dead-state restore проверяется без мутации HP, чтобы не моделировать воскрешение.
				_check(not first_unit.is_alive() and not second_unit.is_alive(), label + ": both restored branches stay dead")
	_check(signals.hp_changed_count == 0 and signals.died_count == 0, label + ": capture and restore emit no source Vitals signals")
	_check(_canonical_matches(source.state, source_bytes), label + ": source remains canonical")
	# Подключиться к сигналам восстановленного Vitals до его конструктора нельзя;
	# поэтому этот тест не заявляет прямую проверку constructor-time сигналов.
	source.unit.vitals.hp_changed.disconnect(hp_callback)
	source.unit.vitals.died.disconnect(died_callback)
	if first.state != null: _cleanup(first.state)
	if second.state != null: _cleanup(second.state)
	_cleanup(source.state)

func _make_fixture(label: String, hp: float, alive: bool) -> _Fixture:
	var fixture := _Fixture.new()
	var stats := StatsBag.new()
	stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
	fixture.unit = UnitState.create(Faction.Type.PLAYER, Vector2i.ZERO, stats, label)
	var board := BattleBoard.new(1, 1)
	_check(board.add_unit(fixture.unit), label + ": source unit added to board")
	fixture.definition = ItemDef.new()
	fixture.definition.id = &"restore_vitals_hp_modifier"
	var effect := StatModifierEffect.new()
	effect.stat_type = StatTypes.StatType.HP_MAX
	effect.operation = StatModifier.Operation.ADD_FLAT
	effect.value = 10.0
	var effects: Array[ItemEffect] = [effect]
	fixture.definition.effects = effects
	var owner := ItemOwnerState.new(fixture.unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var item := owner.create_item(fixture.definition)
	_check(item != null and equipment.equip(EquipmentState.EquipSlot.TRINKET, item), label + ": HP modifier item equipped")
	if alive:
		fixture.unit.vitals.set_hp(hp)
	else:
		fixture.unit.vitals.apply_damage(fixture.unit.vitals.get_hp_max())
	var owners: Array[ItemOwnerState] = [owner]
	var inventories: Array[InventoryState] = [inventory]
	var equipment_facades: Array[EquipmentState] = [equipment]
	fixture.state = ItemSimulationState.new(board, owners, inventories, equipment_facades)
	_check(is_equal_approx(fixture.unit.get_stat(StatTypes.StatType.HP_MAX), 20.0), label + ": source max HP includes one modifier")
	_check(is_equal_approx(fixture.unit.vitals.get_hp(), hp) and fixture.unit.is_alive() == alive, label + ": source starts at requested state")
	return fixture

func _catalogue(definition: ItemDef) -> Dictionary:
	return {definition.id: definition.duplicate(true) as ItemDef}

func _unit_matches(unit: UnitState, hp: float, alive: bool) -> bool:
	return is_equal_approx(unit.vitals.get_hp(), hp) and is_equal_approx(unit.get_stat(StatTypes.StatType.HP_MAX), 20.0) and unit.is_alive() == alive

func _has_single_active_hp_modifier(state: ItemSimulationState, unit_id: int) -> bool:
	var owner: ItemOwnerState = state.get_owner(unit_id)
	var equipment: EquipmentState = state.get_equipment(unit_id)
	if owner == null or equipment == null:
		return false
	var item: ItemInstance = equipment.get_equipped(EquipmentState.EquipSlot.TRINKET)
	return item != null and item.is_active() and is_equal_approx(owner.get_owner().get_stat(StatTypes.StatType.HP_MAX), 20.0)

func _canonical_matches(state: ItemSimulationState, expected: PackedByteArray) -> bool:
	var result: ItemSnapshotResult = ItemSimulationSnapshot.capture(state, [])
	return result.code == ItemSnapshotResult.Code.OK and result.snapshot != null and result.snapshot.canonical_bytes() == expected

func _cleanup(state: ItemSimulationState) -> void:
	if state == null:
		return
	for inventory: InventoryState in state.get_inventories(): inventory.close()
	for equipment: EquipmentState in state.get_equipment_facades(): equipment.close()
	for owner: ItemOwnerState in state.get_owners(): owner.close()
	state.get_board().resize(0, 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL RESTORE VITALS: " + message)

class _Fixture extends RefCounted:
	var state: ItemSimulationState
	var definition: ItemDef
	var unit: UnitState

class _SignalCounter extends RefCounted:
	var hp_changed_count: int = 0
	var died_count: int = 0

	func on_hp_changed(_old_hp: float, _new_hp: float) -> void:
		hp_changed_count += 1

	func on_died() -> void:
		died_count += 1
