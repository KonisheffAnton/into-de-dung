extends BattleBleedingSession
class_name D4BattleSession

## Проекция постоянных вещей в существующий бой; пассивное хранение остаётся снаружи.
var hero_units: Dictionary = {}
var projected_items: Dictionary = {}

func configure(run: D4RunState) -> bool:
	if run == null or run.phase != D4RunState.BATTLE or D4RunState.from_dict(run.to_dict()) == null: return false
	close()
	hero_units.clear()
	projected_items.clear()
	board = BattleBoard.new(8, 8)
	_configure_map()
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	var cells: Array[Vector2i] = [Vector2i(0,2), Vector2i(2,5), Vector2i(5,6)]
	for hero: Dictionary in run.heroes:
		var stats := _demo_stats()
		stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0)
		var unit := UnitState.create(Faction.Type.PLAYER, cells[int(hero.id)-1], stats, hero.name)
		unit.vitals.set_hp(hero.hp)
		# Загрузка на границе боя не порождает событий смерти или предметных реакций.
		unit.vitals._is_alive = hero.hp > 0
		_prepare_unit(unit, owners, inventories, equipment)
		hero_units[hero.id] = unit
		var owner: ItemOwnerState = owners.back()
		for record: Dictionary in run.items:
			if record.place != "equipped" or record.hero != hero.id: continue
			var item := owner.create_item(D4Catalog.definition(record.kind))
			item.armor_remaining = record.armor
			item.armor_origin_owner = 1
			item.armor_origin_item = record.id
			if not equipment.back().equip(record.slot, item):
				_cleanup_failed(owners, inventories, equipment)
				return false
			projected_items[record.id] = item
		unit.armor.in_battle = true
	var enemy_cells: Array[Vector2i] = [Vector2i(4,2), Vector2i(3,5), Vector2i(6,6)]
	if run.encounter == 2: enemy_cells = [Vector2i(3,2), Vector2i(3,4), Vector2i(6,5)]
	for index: int in 3:
		var unit := UnitState.create(Faction.Type.ENEMY, enemy_cells[index], _demo_stats(), ["Страж", "Щит", "Дозорный"][index])
		_prepare_unit(unit, owners, inventories, equipment)
		unit.bleeding.immune = index == 1
		var owner: ItemOwnerState = owners.back()
		for kind: String in ["coat", "bracer"]:
			var item := owner.create_item(D4Catalog.definition(kind))
			equipment.back().equip(D4Catalog.slot(kind), item)
		unit.armor.in_battle = true
	state = ItemSimulationState.new(board, owners, inventories, equipment)
	var ordinary := AttackDefinition.new()
	ordinary.id = &"demo_strike"
	ordinary.profile = AttackRules.ARMOR_PROFILE
	ordinary.bleeding_policy = &"physical_hp"
	ordinary.damage_components = [{"type":"fire", "policy":"standard", "numerator":10, "denominator":1, "source":"flame_rune", "factor_num":1, "factor_den":1}]
	var rune: AttackDefinition = ordinary.duplicate(true)
	rune.id = &"blood_rune"
	rune.bleeding_policy = &"bypass_hp_gate"
	var pairs: Array[Dictionary] = []
	for actor: UnitState in units:
		for target: UnitState in units:
			if actor != target: pairs.append({"actor_unit_id":actor.id, "target_unit_id":target.id})
	context = ActionContext.new(state, CombatRng.new(913 + run.encounter), ActionEventSink.new(), [], MoveRules.new(_unit_ids(), 1, &"spatial_move_v1"), AttackRules.new(_unit_ids(), pairs, [ordinary, rune]))
	_queue = ActionQueue.new()
	phase = Phase.PLAYER_TURN
	round_number = 1
	selected_id = living_ids(Faction.Type.PLAYER)[0]
	_enemy_ids.clear()
	_enemy_index = 0
	_enemy_actions = 0
	_transitioning = false
	rune_selected = false
	turn_events.clear()
	flow_log = ["Бой %d из 2. Вещи в рюкзаках не дают бонусов. Отправка — только в комнате между боями." % run.encounter]
	return true

func _prepare_unit(unit: UnitState, owners: Array[ItemOwnerState], inventories: Array[InventoryState], equipment: Array[EquipmentState]) -> void:
	unit.armor = ArmorState.new()
	unit.armor.in_battle = false
	unit.bleeding = BleedingState.new()
	unit.enable_action_resources()
	if unit.is_alive(): unit.try_refill_turn_resources()
	board.add_unit(unit)
	units.append(unit)
	var owner := ItemOwnerState.new(unit)
	owners.append(owner)
	inventories.append(InventoryState.new(owner))
	equipment.append(EquipmentState.new(owner))

func _cleanup_failed(owners: Array[ItemOwnerState], inventories: Array[InventoryState], equipment: Array[EquipmentState]) -> void:
	state = ItemSimulationState.new(board, owners, inventories, equipment)
	close()

func outcome_data() -> Dictionary:
	if context == null or context.is_busy() or context.is_faulted() or phase not in [Phase.VICTORY, Phase.DEFEAT, Phase.MUTUAL_DESTRUCTION]: return {}
	var hp: Dictionary = {}
	var armor: Dictionary = {}
	for id: int in hero_units:
		var unit: UnitState = hero_units[id]
		hp[id] = int(unit.vitals.get_hp()) if unit.is_alive() else 0
	for id: int in projected_items: armor[id] = (projected_items[id] as ItemInstance).armor_remaining
	return {"victory":phase == Phase.VICTORY, "hp":hp, "armor":armor}

func close() -> void:
	super.close()
	hero_units.clear()
	projected_items.clear()
