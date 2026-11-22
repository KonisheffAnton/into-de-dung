extends RefCounted
class_name HeroHubBattleFactory

const SICK_HOBGOBLIN: SickHobgoblinDefinition = preload("res://resources/enemies/sick_hobgoblin.tres")

const TAMED_TROGLODYTE: TamedTroglodyteDefinition = preload("res://resources/enemies/tamed_troglodyte.tres")

static func create(run: HeroHubState) -> Dictionary:
	if run == null or HeroHubState.from_dict(run.to_dict()) == null: return {}
	var expedition := run.phase == "expedition" and run.expedition != null and run.expedition.phase == "battle"
	var deck: bool = expedition and run.expedition.is_deck()
	if run.phase != "battle" and not expedition: return {}
	var node: Dictionary = run.expedition.current_node() if expedition else {}
	var showcase_layout: bool = expedition and int(node.get("layer", -1)) == 0
	var opening: Dictionary = run.expedition.plan.content.opening if deck and run.expedition.plan.opening and node.layer == 0 else {}
	var encounter := ExpeditionCatalog.encounter(node.kind if expedition else "battle",node.variant if expedition else 0)
	if encounter == null: return {}
	var enemy_count := encounter.enemy_cells.size()
	var enemy_hp := encounter.enemy_hp
	var enemy_strength := encounter.enemy_strength
	var session := BattleCoreReactionsSession.new(false)
	var board_size: Vector2i = BiomeShowcaseLayout.SIZE if showcase_layout else Vector2i(8, 8)
	session.board = BattleBoard.new(board_size.x, board_size.y)
	var showcase_classes := ClassShowcaseRoster.enemies(run)
	# Новый вид дополняет обзор классов; старые каталоги и сохранённый план не мигрируем.
	var add_hobgoblin: bool = run.hero_catalog_version >= 4
	var add_troglodyte: bool = (run.phase == "battle" or showcase_layout) and run.hero_catalog_version >= 4 and not showcase_classes.is_empty()
	var enemy_cells: Array[Vector2i] = []
	for index: int in enemy_count:
		enemy_cells.append(ExpeditionOpening.cell(opening.enemies[index].cell) if not opening.is_empty() else encounter.enemy_cells[index])
	if not showcase_classes.is_empty():
		enemy_count = showcase_classes.size() + (1 if add_hobgoblin else 0) + (1 if add_troglodyte else 0)
		enemy_cells = ClassShowcaseRoster.cells(enemy_cells, enemy_count, opening, board_size)
		if enemy_cells.size() < enemy_count:
			session.close(); return {}
	if add_troglodyte:
		enemy_cells[-1] = _nearby_troglodyte_cell(enemy_cells, opening, board_size, run.party.size())
	var hero_units: Dictionary = {}
	var gear_items: Dictionary = {}
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	var definitions: Array[AttackDefinition] = []
	var ordinary := _attack(&"demo_strike")
	ordinary.damage_components.append(_fire(2))
	definitions.append(ordinary)
	var entangle := _attack(&"entangling_strike")
	entangle.entangle_on_physical_hp = true
	definitions.append(entangle)
	var stunning := _attack(&"stunning_strike")
	stunning.stun_on_physical_hp = true
	definitions.append(stunning)
	for reaction_id: StringName in [&"opportunity_strike", &"counter_strike"]:
		var reaction := _attack(reaction_id)
		reaction.reaction_strike = true
		reaction.chain_push = false
		reaction.critical_on_control = false
		definitions.append(reaction)
	definitions.append(WarriorKit.definition(WarriorKit.CLEAVE))
	definitions.append(WarriorKit.definition(WarriorKit.KICK))
	for index: int in range(run.party.size() + enemy_count):
		var hero: HeroProgression = run.heroes[run.party[index]] if index < run.party.size() else null
		var enemy_index := index - run.party.size()
		var is_hobgoblin: bool = hero == null and add_hobgoblin and enemy_index == showcase_classes.size()
		var is_troglodyte: bool = hero == null and add_troglodyte and enemy_index == showcase_classes.size() + (1 if add_hobgoblin else 0)
		var enemy_data: Dictionary = opening.enemies[enemy_index] if hero == null and not is_hobgoblin and not is_troglodyte and not opening.is_empty() and enemy_index < opening.enemies.size() else {}
		var enemy_class: StringName = showcase_classes[enemy_index] if hero == null and not is_hobgoblin and not is_troglodyte and not showcase_classes.is_empty() else &""
		var enemy_definition := HeroCatalog.class_definition(enemy_class)
		var hero_class := HeroCatalog.class_definition(hero.class_id) if hero != null else null
		var enemy_balance := CharacterAttributeRules.balance_max(float(enemy_definition.base_attributes[2])) if enemy_definition != null else float(encounter.enemy_balance)
		var stats := StatsBag.from_base_values({
			StatTypes.StatType.HP_MAX: float(hero.max_hp() if hero != null else enemy_hp),
			StatTypes.StatType.ARMOR: 0.0,
			StatTypes.StatType.STRENGTH: float(3 if hero != null and hero.class_id != &"mage" else 0 if hero != null else enemy_strength),
			StatTypes.StatType.WEAPON_DAMAGE: 0.0 if hero != null else float(encounter.enemy_weapon_damage),
			StatTypes.StatType.IMPACT_POWER: 4.0 if hero != null else float(encounter.enemy_impact),
			StatTypes.StatType.BALANCE_MAX: float(hero.balance_max()) if hero != null else enemy_balance,
			StatTypes.StatType.MOVE_RANGE: hero.move_max() if hero != null else float(encounter.enemy_move),
			StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0,
			StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0,
			StatTypes.StatType.ATTACK_RANGE: float(hero_class.attack_range if hero != null else enemy_definition.attack_range if enemy_definition != null else encounter.enemy_range),
			StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: 0.0,
		})
		if is_troglodyte: stats = StatsBag.from_base_values(TAMED_TROGLODYTE.base_stats())
		if is_hobgoblin: stats = StatsBag.from_base_values(SICK_HOBGOBLIN.base_stats())
		if hero != null:
			var attributes := hero.attributes()
			var attribute_types := [StatTypes.StatType.POWER, StatTypes.StatType.DEXTERITY, StatTypes.StatType.ENDURANCE, StatTypes.StatType.INTELLECT, StatTypes.StatType.MASTERY]
			for attribute_index: int in attribute_types.size(): stats.set_base_value(attribute_types[attribute_index], float(attributes[attribute_index]))
		elif enemy_definition != null:
			# Возможности класса используют те же пять характеристик, без генерации нового героя/RNG.
			var attribute_types := [StatTypes.StatType.POWER, StatTypes.StatType.DEXTERITY, StatTypes.StatType.ENDURANCE, StatTypes.StatType.INTELLECT, StatTypes.StatType.MASTERY]
			for attribute_index: int in attribute_types.size(): stats.set_base_value(attribute_types[attribute_index], float(enemy_definition.base_attributes[attribute_index]))
		var cell := Vector2i(1, 2 + index) if hero != null else enemy_cells[enemy_index]
		var unit := UnitState.create(Faction.Type.PLAYER if hero != null else Faction.Type.ENEMY, cell, stats, hero.name if hero != null else "Дозорный %d" % (index - run.party.size() + 1))
		if is_troglodyte:
			unit.debug_name = TAMED_TROGLODYTE.display_name
			unit.archetype_id = TroglodyteKit.ID
		if is_hobgoblin: unit.debug_name = SICK_HOBGOBLIN.display_name
		unit.armor = ArmorState.new(); unit.armor.in_battle = false
		unit.armor.fractional = true
		unit.bleeding = BleedingState.new(); unit.bleeding.stacked = true
		unit.bleeding.authored = true
		unit.control = ControlState.new(); unit.elemental = ElementalState.new()
		unit.elemental.authored = true
		unit.combat_perks = CombatPerksState.new()
		if not enemy_data.is_empty():
			unit.debug_name = enemy_data.name
			unit.combat_perks.definition.tank_reactions = enemy_data.role == "guard"
			unit.combat_perks.definition.counterattack = enemy_data.role == "guard"
			unit.combat_perks.definition.stunning_strike = enemy_data.role == "guard"
			unit.combat_perks.definition.stun_immune = enemy_data.role == "shield"
			unit.combat_perks.definition.sneak_attack = enemy_data.role == "sneak"
			unit.bleeding.immune = enemy_data.role == "shield"
		if hero != null:
			unit.vitals.set_hp(hero.hp_current)
			unit.armor.natural.fire = int(hero.fire_resistance() * 100.0)
			unit.armor.natural.physical = int(hero.physical_resistance() * 100.0)
			unit.combat_perks.definition.tank_reactions = hero.class_id == &"warrior"
			unit.combat_perks.definition.counterattack = hero.class_id == &"warrior"
			unit.combat_perks.definition.stunning_strike = hero.class_id == &"warrior"
			unit.combat_perks.definition.sneak_attack = hero.class_id == &"rogue"
			if hero.class_id == &"fighter": unit.combat_perks.warrior = WarriorKit.make()
			if hero.class_id == &"shieldbearer":
				unit.combat_perks.definition.passive_opportunist = true
				unit.armor.raised_shield = RaisedShield.make()
			hero_units[hero.id] = unit.id
			var attack := _attack(MageDeckRules.hero_attack_id(unit.id))
			if hero.class_id == &"mage":
				var weapon := run.equipped(hero.id, "weapon")
				attack.damage_components.append(_fire(3 + (hero_class.weapon_damage if not weapon.is_empty() else 0)))
			definitions.append(attack)
			session.actor_loadouts[unit.id] = {"class_id":hero.class_id,"attack_id":attack.id}
			if hero.class_id in [&"shieldbearer", &"fighter"]: session.unit_visual_classes[unit.id] = hero.class_id
		elif enemy_data.is_empty() or enemy_data.role in ["guard", "shield"]:
			# Обычные бойцы, Страж и Щит получают только рисунок; Дозорный сохраняет свой вид.
			session.unit_visual_classes[unit.id] = &"warrior"
		if enemy_definition != null:
			ClassShowcaseRoster.apply_class(unit, enemy_class)
			unit.debug_name = "%s · противник %d" % [enemy_definition.display_name, enemy_index + 1]
			var attack := _attack(MageDeckRules.hero_attack_id(unit.id))
			if enemy_class == &"mage": attack.damage_components.append(_fire(enemy_definition.weapon_damage))
			definitions.append(attack)
			session.actor_loadouts[unit.id] = {"class_id":enemy_class, "attack_id":attack.id}
			session.unit_visual_classes[unit.id] = enemy_class
		if is_hobgoblin:
			# Собственная обычная атака не наследует огонь demo_strike или классовые приёмы.
			var attack := _attack(MageDeckRules.hero_attack_id(unit.id))
			definitions.append(attack)
			session.actor_loadouts[unit.id] = {"class_id":SICK_HOBGOBLIN.id, "attack_id":attack.id}
			session.unit_visual_classes[unit.id] = SICK_HOBGOBLIN.id
			unit.armor.natural.physical = int(CharacterAttributeRules.resistance_contribution(SICK_HOBGOBLIN.attributes[1]))
			unit.armor.natural.fire = int(CharacterAttributeRules.resistance_contribution(SICK_HOBGOBLIN.attributes[3]))
		if is_troglodyte:
			var attack := _attack(MageDeckRules.hero_attack_id(unit.id))
			definitions.append(attack)
			session.actor_loadouts[unit.id] = {"class_id":TroglodyteKit.ID, "attack_id":attack.id}
			session.unit_visual_classes[unit.id] = TroglodyteKit.ID
		unit.combat_perks.uses_bonus_actions = true
		unit.enable_action_resources(); unit.try_refill_turn_resources()
		session.board.add_unit(unit)
		session.units.append(unit)
		var owner := ItemOwnerState.new(unit)
		var inventory := InventoryState.new(owner)
		var equipped := EquipmentState.new(owner)
		owners.append(owner); inventories.append(inventory); equipment.append(equipped)
		if not enemy_data.is_empty() and enemy_data.armor > 0:
			var coat := ItemDef.new()
			coat.id = StringName("opening_armor_" + String(enemy_data.role))
			coat.display_name = "Броня противника"; coat.armor_max = enemy_data.armor
			if not equipped.equip(EquipmentState.EquipSlot.ARMOR, owner.create_item(coat)):
				session.close(); return {}
		if hero != null:
			for id: int in run.items:
				var record: Dictionary = run.items[id]
				if record.hero_id != hero.id: continue
				var item := owner.create_item(HeroGearCatalog.definition(record.definition))
				var slot := EquipmentState.EquipSlot.WEAPON if HeroGearCatalog.slot(record.definition) == "weapon" else EquipmentState.EquipSlot.ARMOR
				if item == null or not equipped.equip(slot, item):
					session.close(); return {}
				item.armor_remaining = record.remaining
				gear_items[id] = {"owner_id":unit.id,"item_id":item.get_item_instance_id()}
			var flask := ItemDef.new()
			flask.id = &"tactical_healing_flask"
			flask.display_name = "Походный флакон"
			flask.use_heal_amount = 4.0 + float(hero.attributes()[0])
			flask.max_charges = 1
			# Разные определения не делят ID: копии прогноза восстанавливают точную силу лечения.
			flask.id = StringName("hero_flask_%d" % unit.id)
			inventory.add_item(owner.create_item(flask))
		unit.armor.in_battle = true
	session.state = ItemSimulationState.new(session.board, owners, inventories, equipment)
	session.state.environment = CombatEnvironmentState.new()
	session.state.environment.status_effects = true
	session.state.environment.collapse = {"turn":0,"marked":[]}
	if not opening.is_empty():
		for tile: Dictionary in opening.terrain:
			session.board.set_terrain(ExpeditionOpening.cell(tile.cell), tile.type)
		for tile: Dictionary in opening.heights:
			session.board.set_height_steps(ExpeditionOpening.cell(tile.cell), tile.steps)
		for hazard: Dictionary in opening.hazards:
			session.state.environment.ignite(ExpeditionOpening.cell(hazard.cell), hazard.effect)
		session.state.environment.collapse = opening.collapse.duplicate(true)
	if showcase_layout:
		BiomeShowcaseLayout.apply(session.board, not opening.is_empty())
	if expedition and not deck:
		var artifacts := BattleArtifactState.new()
		for id: int in run.party:
			var unit_id: int = hero_units[id]
			artifacts.heroes.append(unit_id)
			if (run.heroes[id] as HeroProgression).class_id == &"mage": artifacts.mages.append(unit_id)
			artifacts.attacks[unit_id] = session.actor_loadouts[unit_id].attack_id
		for record: Dictionary in run.expedition.artifacts:
			if record.hero_id == 0: continue
			artifacts.equipped.append({"id":record.id,"unit_id":hero_units[record.hero_id],"slot":record.slot,"definition":record.definition,"version":1,"stacks":record.stacks})
		session.state.artifacts = artifacts
	if expedition:
		if node.modifier in ["spikes", "fire"]:
			for cell: Vector2i in encounter.hazard_cells:
				session.state.environment.fires.append({"id":session.state.environment.next_fire_id,"cell":cell,"damage":ExpeditionCatalog.SPIKE_DAMAGE if node.modifier == "spikes" else 0,"effect":"bleeding" if node.modifier == "spikes" else "burning"})
				session.state.environment.next_fire_id += 1
	var pairs: Array[Dictionary] = []
	if deck and not opening.is_empty(): BattleHazardSetup.opening(session)
	for actor: UnitState in session.units:
		for target: UnitState in session.units:
			if actor.id != target.id: pairs.append({"actor_unit_id":actor.id,"target_unit_id":target.id})
	var rules := AttackRules.new(session._unit_ids(), pairs, definitions)
	session.context = ActionContext.new(session.state, CombatRng.new(int(node.battle_seed) if expedition else 9101 + run.run_serial), ActionEventSink.new(), [], MoveRules.new(session._unit_ids(), 1, &"spatial_move_v1"), rules)
	session._queue = ActionQueue.new()
	var item_definitions: Dictionary = {}
	for owner: ItemOwnerState in owners: item_definitions.merge(owner._definitions, true)
	var ability_definitions := AbilityCatalog.build(rules, item_definitions, true)
	var has_raised_shield := false
	for unit: UnitState in session.units:
		if unit.armor != null and not unit.armor.raised_shield.is_empty():
			has_raised_shield = true
			break
	if has_raised_shield: ability_definitions.append(RaiseShieldsCommand.definition())
	session.state.abilities = BattleAbilityState.create(ability_definitions)
	if deck:
		session.state.abilities = BattleAbilityState.create_deck(ability_definitions,Faction.Type.ENEMY)
		session.state.deck = BattleDeckState.create(run.expedition.active_cards(),run.expedition.checkpoint.draw_seed)
		session.state.card_effects = BattleCardEffectState.new()
		session.state.card_effects.host_unit_id = hero_units[run.expedition.host_hero_id]
		session.board.get_unit_by_id(session.state.card_effects.host_unit_id).debug_name += " · носитель"
		for unit: UnitState in session.units:
			var attack_id: StringName = session.actor_loadouts[unit.id].attack_id if session.actor_loadouts.has(unit.id) else &"demo_strike"
			session.state.card_effects.ordinary_attacks.append({"unit_id":unit.id,"attack_id":String(attack_id)})
	session.phase = BattleTacticalSession.Phase.ENEMY_TURN
	session._enemy_ids = session.living_ids(Faction.Type.ENEMY)
	session._setup_revision = session.context.get_revision()
	session.flow_log = ["Расставьте отряд. Противник ходит первым; затем ваш отряд и окружение.", "Победа: каждому выжившему +100 опыта, каждому резервисту +10; +40 золота. Погибшие герои не возвращаются."]
	if expedition:
		var reward := ExpeditionCatalog.room(node.kind)
		session.flow_log[1] = "%s · встреча %d. Победа: выжившим +%d XP, резерву 10%%; добыча +%d золота." % [reward.title,int(node.variant) + 1,reward.xp,reward.gold]
		if not opening.is_empty():
			var opponents := "Страж, Щит, Дозорный"
			if not showcase_classes.is_empty():
				var names: PackedStringArray = []
				for class_id: StringName in showcase_classes: names.append(HeroCatalog.class_definition(class_id).display_name)
				if add_hobgoblin: names.append(SICK_HOBGOBLIN.display_name)
				if add_troglodyte: names.append(TAMED_TROGLODYTE.display_name)
				opponents = ", ".join(names)
			session.flow_log.append("Стартовая комната: %s; шипы, огонь, уступ, стена, пропасти и обрушение. После победы откроется выбор пути." % opponents)
	if rules.validate() != &"" or session.state.abilities == null or not session.begin_deployment() or ItemSimulationSnapshot.capture(session.state, []).code != ItemSnapshotResult.Code.OK:
		session.close(); return {}
	var bundle := {"session":session,"hero_units":hero_units,"gear_items":gear_items,"serial":run.expedition.battle_serial if expedition else run.run_serial}
	if expedition: bundle.merge({"run_id":run.expedition.run_id,"node_id":node.id})
	if deck: bundle["ruleset_id"] = ExpeditionRulesRegistry.DECK
	return bundle

static func outcome(bundle: Dictionary) -> Dictionary:
	if bundle.is_empty(): return {}
	var session: BattleCoreReactionsSession = bundle.session
	if session == null or not session._available() or session.context.is_faulted() or session.phase not in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]: return {}
	var hp: Dictionary = {}
	var gear: Dictionary = {}
	for id: int in bundle.hero_units:
		var unit := session.board.get_unit_by_id(bundle.hero_units[id])
		hp[id] = unit.vitals.get_hp() if unit != null and unit.is_alive() else 0.0
	for id: int in bundle.gear_items:
		var mapping: Dictionary = bundle.gear_items[id]
		var owner := session.state.get_owner(mapping.owner_id)
		var item: ItemInstance = owner._items.get(mapping.item_id) if owner != null else null
		if item == null: return {}
		gear[id] = item.armor_remaining
	var result := {"serial":bundle.serial,"victory":session.phase == BattleTacticalSession.Phase.VICTORY,"hp":hp,"gear":gear}
	if bundle.has("run_id"): result.merge({"run_id":bundle.run_id,"node_id":bundle.node_id})
	if bundle.has("ruleset_id"): result["ruleset_id"] = bundle.ruleset_id
	return result

static func _attack(id: StringName) -> AttackDefinition:
	var result := AttackDefinition.new()
	result.id = id; result.profile = AttackRules.ARMOR_PROFILE
	result.chain_push = true; result.critical_on_control = true; result.sneak_attack_enabled = true
	return result

static func _fire(amount: int) -> Dictionary:
	return {"type":"fire","policy":"standard","numerator":amount,"denominator":1,"source":"hero_spell","factor_num":1,"factor_den":1}

static func _nearby_troglodyte_cell(cells: Array[Vector2i], opening: Dictionary, size: Vector2i, party_size: int) -> Vector2i:
	# Дополнительный монстр должен быть виден рядом с авторской группой, а не в дальнем углу большой карты.
	var reserved: Array[Vector2i] = []
	reserved.assign(cells.slice(0, cells.size() - 1))
	for index: int in party_size: reserved.append(Vector2i(1, 2 + index))
	var anchor := cells[0]
	var terrain := BattleBoard.new(size.x, size.y)
	for tile: Dictionary in opening.get("terrain", []):
		terrain.set_terrain(ExpeditionOpening.cell(tile.cell), int(tile.type) as TerrainType.Type)
	if size == BiomeShowcaseLayout.SIZE: BiomeShowcaseLayout.apply(terrain, not opening.is_empty())
	var hazards: Array[Vector2i] = []
	for hazard: Dictionary in opening.get("hazards", []): hazards.append(ExpeditionOpening.cell(hazard.cell))
	var available: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if terrain.get_terrain(cell) == TerrainType.Type.FLOOR and not hazards.has(cell): available.append(cell)
	available.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(a.x - anchor.x) + absi(a.y - anchor.y)
		var db := absi(b.x - anchor.x) + absi(b.y - anchor.y)
		if da != db: return da < db
		if a.y != b.y: return a.y > b.y
		return a.x < b.x)
	for cell: Vector2i in available:
		if not reserved.has(cell): return cell
	return cells[-1]
