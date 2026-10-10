extends BattleTacticalSession
class_name BattleArmorSession

## Отдельный игровой сценарий — явный адаптер из прежних определений, без миграции ARMOR.
func reset() -> void:
	super.reset()
	for unit: UnitState in units:
		unit.armor = ArmorState.new()
		unit.armor.in_battle = false
		var owner := state.get_owner(unit.id)
		for slot: EquipmentState.EquipSlot in [EquipmentState.EquipSlot.ARMOR, EquipmentState.EquipSlot.TRINKET]:
			var definition := ItemDef.new()
			definition.id = &"armor_coat" if slot == EquipmentState.EquipSlot.ARMOR else &"armor_bracer"
			definition.display_name = "Кольчуга" if slot == EquipmentState.EquipSlot.ARMOR else "Наручи"
			definition.armor_max = 60 if slot == EquipmentState.EquipSlot.ARMOR else 40
			state.get_equipment(unit.id).equip(slot, owner.create_item(definition))
		_equip_scenario_weapon(unit)
		unit.armor.in_battle = true
	# Страж начинает с четвертью комплекта: первый прогноз показывает обе ветви.
	for item: ItemInstance in state.get_owner(units[1].id)._items.values():
		if item.get_definition().armor_max > 0: item.armor_remaining = int(item.get_definition().armor_max / 4)
	var definition := AttackDefinition.new()
	definition.id = &"demo_strike"
	definition.profile = AttackRules.ARMOR_PROFILE
	definition.damage_components = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "flame_rune", "factor_num": 1, "factor_den": 1}]
	var pairs: Array[Dictionary] = []
	for actor: UnitState in units:
		for target: UnitState in units:
			if actor != target: pairs.append({"actor_unit_id": actor.id, "target_unit_id": target.id})
	context._attack_rules = AttackRules.new(_unit_ids(), pairs, [definition])
	context._rng = CombatRng.new(913)
	flow_log = ["Броня: физический удар и огненная руна. Наведите на цель в режиме атаки, чтобы увидеть расход брони и HP."]

func _equip_scenario_weapon(_unit: UnitState) -> void:
	pass

func summoning_reason() -> StringName:
	return &"armor/summon_unsupported"

func supports_summoning() -> bool:
	return false

func restore_armor_reason() -> StringName:
	if not can_player_act() or selected_unit() == null: return &"battle/input_locked"
	return RestoreArmorCommand.new(selected_id, 20, context.get_revision()).validate(context)

func restore_selected_armor() -> ActionReceipt:
	var reason := restore_armor_reason()
	if reason != &"": return _reject(reason)
	return _submit(RestoreArmorCommand.new(selected_id, 20, context.get_revision()))

func preview_restore_armor() -> ForecastSimulation:
	var reason := restore_armor_reason()
	if reason != &"": return ForecastSimulation.rejected(reason)
	return ForecastSimulation.run(context, _queue, RestoreArmorCommand.new(selected_id, 20, context.get_revision()))

func prepare_restore_armor_forecast() -> ForecastSimulation.Prepared:
	if not can_player_act() or selected_unit() == null: return ForecastSimulation.Prepared.rejected(&"battle/input_locked")
	return prepare_action_forecast(RestoreArmorCommand.new(selected_id, 20, context.get_revision()))
