extends RefCounted
class_name HeroHubBattleFactory

static func create(run: HeroHubState) -> Dictionary:
	if run == null or HeroHubState.from_dict(run.to_dict()) == null: return {}
	var expedition := run.phase == "expedition" and run.expedition != null and run.expedition.phase == "battle"
	if run.phase != "battle" and not expedition: return {}
	var node: Dictionary = run.expedition.current_node() if expedition else {}
	var encounter := ExpeditionCatalog.encounter(node.kind if expedition else "battle",node.variant if expedition else 0)
	if encounter == null: return {}
	var enemy_count := encounter.enemy_cells.size()
	var enemy_hp := encounter.enemy_hp
	var enemy_strength := encounter.enemy_strength
	var session := BattleCoreReactionsSession.new(false)
	session.board = BattleBoard.new(8, 8)
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
	for index: int in range(run.party.size() + enemy_count):
		var hero: HeroProgression = run.heroes[run.party[index]] if index < run.party.size() else null
		var hero_class := HeroCatalog.class_definition(hero.class_id) if hero != null else null
		var stats := StatsBag.from_base_values({
			StatTypes.StatType.HP_MAX: float(hero.max_hp() if hero != null else enemy_hp),
			StatTypes.StatType.ARMOR: 0.0,
			StatTypes.StatType.STRENGTH: float(hero.attributes()[0] if hero != null and hero.class_id != &"mage" else 0 if hero != null else enemy_strength),
			StatTypes.StatType.WEAPON_DAMAGE: 0.0 if hero != null else float(encounter.enemy_weapon_damage),
			StatTypes.StatType.IMPACT_POWER: 4.0 if hero != null else float(encounter.enemy_impact),
			StatTypes.StatType.BALANCE_MAX: float(hero.balance_max() if hero != null else encounter.enemy_balance),
			StatTypes.StatType.MOVE_RANGE: hero.move_max() if hero != null else float(encounter.enemy_move),
			StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0,
			StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0,
			StatTypes.StatType.ATTACK_RANGE: float(hero_class.attack_range if hero != null else encounter.enemy_range),
			StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: 0.0,
		})
		var cell := Vector2i(1, 2 + index) if hero != null else encounter.enemy_cells[index - run.party.size()]
		var unit := UnitState.create(Faction.Type.PLAYER if hero != null else Faction.Type.ENEMY, cell, stats, hero.name if hero != null else "Дозорный %d" % (index - run.party.size() + 1))
		unit.armor = ArmorState.new(); unit.armor.in_battle = false
		unit.bleeding = BleedingState.new(); unit.bleeding.stacked = true
		unit.control = ControlState.new(); unit.elemental = ElementalState.new()
		unit.combat_perks = CombatPerksState.new()
		if hero != null:
			unit.vitals.set_hp(hero.hp_current)
			unit.armor.natural.fire = hero.fire_resistance()
			unit.combat_perks.definition.tank_reactions = hero.class_id == &"warrior"
			unit.combat_perks.definition.counterattack = hero.class_id == &"warrior"
			unit.combat_perks.definition.stunning_strike = hero.class_id == &"warrior"
			unit.combat_perks.definition.sneak_attack = hero.class_id == &"rogue"
			hero_units[hero.id] = unit.id
			var attack := _attack(StringName("hero_attack_%d" % unit.id))
			if hero.class_id == &"mage":
				var weapon := run.equipped(hero.id, "weapon")
				attack.damage_components.append(_fire(hero.attributes()[0] + (hero_class.weapon_damage if not weapon.is_empty() else 0)))
			definitions.append(attack)
			session.actor_loadouts[unit.id] = {"class_id":hero.class_id,"attack_id":attack.id}
		unit.combat_perks.uses_bonus_actions = true
		unit.enable_action_resources(); unit.try_refill_turn_resources()
		session.board.add_unit(unit)
		session.units.append(unit)
		var owner := ItemOwnerState.new(unit)
		var inventory := InventoryState.new(owner)
		var equipped := EquipmentState.new(owner)
		owners.append(owner); inventories.append(inventory); equipment.append(equipped)
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
	if expedition:
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
		if node.modifier in ["spikes", "fire"]:
			for cell: Vector2i in encounter.hazard_cells:
				session.state.environment.fires.append({"id":session.state.environment.next_fire_id,"cell":cell,"damage":ExpeditionCatalog.SPIKE_DAMAGE if node.modifier == "spikes" else 0,"effect":"bleeding" if node.modifier == "spikes" else "burning"})
				session.state.environment.next_fire_id += 1
	var pairs: Array[Dictionary] = []
	for actor: UnitState in session.units:
		for target: UnitState in session.units:
			if actor.id != target.id: pairs.append({"actor_unit_id":actor.id,"target_unit_id":target.id})
	var rules := AttackRules.new(session._unit_ids(), pairs, definitions)
	session.context = ActionContext.new(session.state, CombatRng.new(int(node.battle_seed) if expedition else 9101 + run.run_serial), ActionEventSink.new(), [], MoveRules.new(session._unit_ids(), 1, &"spatial_move_v1"), rules)
	session._queue = ActionQueue.new()
	var item_definitions: Dictionary = {}
	for owner: ItemOwnerState in owners: item_definitions.merge(owner._definitions, true)
	session.state.abilities = BattleAbilityState.create(AbilityCatalog.build(rules, item_definitions, true))
	session.phase = BattleTacticalSession.Phase.ENEMY_TURN
	session._enemy_ids = session.living_ids(Faction.Type.ENEMY)
	session._setup_revision = session.context.get_revision()
	session.flow_log = ["Расставьте отряд. Противник ходит первым; затем ваш отряд и окружение.", "Победа: каждому выжившему +100 опыта, каждому резервисту +10; +40 золота. Погибшие герои не возвращаются."]
	if expedition:
		var reward := ExpeditionCatalog.room(node.kind)
		session.flow_log[1] = "%s · встреча %d. Победа: выжившим +%d XP, резерву 10%%; добыча +%d золота." % [reward.title,int(node.variant) + 1,reward.xp,reward.gold]
	if rules.validate() != &"" or session.state.abilities == null or not session.begin_deployment() or ItemSimulationSnapshot.capture(session.state, []).code != ItemSnapshotResult.Code.OK:
		session.close(); return {}
	var bundle := {"session":session,"hero_units":hero_units,"gear_items":gear_items,"serial":run.expedition.battle_serial if expedition else run.run_serial}
	if expedition: bundle.merge({"run_id":run.expedition.run_id,"node_id":node.id})
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
	return result

static func _attack(id: StringName) -> AttackDefinition:
	var result := AttackDefinition.new()
	result.id = id; result.profile = AttackRules.ARMOR_PROFILE
	result.chain_push = true; result.critical_on_control = true; result.sneak_attack_enabled = true
	return result

static func _fire(amount: int) -> Dictionary:
	return {"type":"fire","policy":"standard","numerator":amount,"denominator":1,"source":"hero_spell","factor_num":1,"factor_den":1}
