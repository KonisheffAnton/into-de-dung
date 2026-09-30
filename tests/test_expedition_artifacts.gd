extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL EXPEDITION ARTIFACTS: " + label)

func _run() -> void:
	_spark_and_exclusions()
	_production_mage()
	_runes()
	_ice_gate()
	_harvest()
	_formation()
	await _workers()
	print("EXPEDITION ARTIFACTS RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func fixture(effects: Array[String], mage: bool = false) -> BattleCoreReactionsSession:
	var profile := HeroHubState.create(338)
	if mage: profile.party = [4,2,3]
	profile.start_battle()
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(),"fixture factory")
	if bundle.is_empty(): return null
	var s: BattleCoreReactionsSession = bundle.session
	s.start_battle(); s._enemy_index = s._enemy_ids.size(); s.step_enemy()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN,"fixture real player boundary")
	s.state.environment.fires.clear(); s.state.environment.collapse = {"turn":0,"marked":[]}
	for index: int in s.units.size():
		var unit := s.units[index]
		check(s.board.move_unit(unit,Vector2i(index,0)),"park")
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX,100.0); unit.vitals._hp = 100.0
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
		unit.armor.natural = {"physical":0,"fire":0}
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	s.board.move_unit(s.units[0],Vector2i(2,3)); s.board.move_unit(s.units[3],Vector2i(3,3))
	s.selected_id = s.units[0].id
	var artifacts := BattleArtifactState.new()
	for index: int in 3:
		var unit := s.units[index]
		artifacts.heroes.append(unit.id); artifacts.attacks[unit.id] = s.actor_loadouts[unit.id].attack_id
		if s.actor_loadouts[unit.id].class_id == &"mage": artifacts.mages.append(unit.id)
	for index: int in effects.size():
		artifacts.equipped.append({"id":index + 1,"unit_id":s.units[0].id,"slot":index + 1,"definition":effects[index],"version":1,"stacks":3 if effects[index] == "spark" else 1})
	s.state.artifacts = artifacts
	check(BattleArtifactRules.references_valid(s.context),"fixture valid capability")
	return s

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var value := ItemSimulationSnapshot.capture(s.state,[])
	check(value.code == ItemSnapshotResult.Code.OK,"capture " + value.reason)
	return value.snapshot.to_dict() if value.snapshot != null else {}

func attack(s: BattleCoreReactionsSession, definition: StringName = &"") -> AttackCommand:
	return AttackCommand.new(s.units[0].id,s.units[3].id,s.units[0].cell,s.units[3].cell,s.actor_loadouts[s.units[0].id].attack_id if definition == &"" else definition,s.context.get_revision())

func parity(s: BattleCoreReactionsSession, command: Command) -> ActionReceipt:
	var before := snapshot(s); var rng := s.context.get_rng().to_dict(); var counters := s.context.simulation_counters(); var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(s.context,s._queue,command)
	check(preview.status == ActionReceipt.APPLIED,"preview applies: " + String(preview.reason))
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and UnitId.get_counter() == ids,"preview isolated")
	var receipt := s._queue.submit(command,s.context)
	check(receipt.status == preview.status and receipt.reason == preview.reason and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps,"events/steps parity " + String(receipt.reason))
	check(snapshot(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after and s.context.simulation_counters() == preview.counters_after,"state/RNG/counters parity")
	return receipt

func fire_damage(receipt: ActionReceipt) -> int:
	var damage: int = 0
	for event: Dictionary in receipt.get_events():
		if event.kind == &"hit_resolved":
			for row: Dictionary in event.hit.rows:
				if row.type == &"fire": damage += row.hp_damage
	return damage

func _spark_and_exclusions() -> void:
	var s := fixture(["spark"])
	var receipt := parity(s,attack(s))
	check(fire_damage(receipt) == 6 and s.state.artifacts.stacks(s.units[0].id,"spark") == 3,"spark adds six permanent fire")
	s.close()
	s = fixture(["spark"])
	receipt = parity(s,attack(s,&"stunning_strike"))
	check(fire_damage(receipt) == 0,"special strike excludes spark")
	var rejected := s._queue.submit(ArtifactRepairCommand.new(s.units[0].id,1),s.context)
	check(rejected.status == ActionReceipt.REJECTED and rejected.reason == &"artifact/internal_command","internal artifact roots rejected")
	s.close()
	s = fixture(["spark","blood","ember"])
	receipt = parity(s,MageCastCommand.new(&"mage.fire",s.units[3].id,s.context.get_revision()))
	check(s.units[3].bleeding.stacks == 0 and s.units[3].elemental.burning_stacks == 0,"mage spell does not inherit rune triggers")
	s.close()
	s = fixture(["spark","harvest"],true)
	s.units[0].vitals._hp = 40.0
	s.units[3].vitals._hp = 1.0
	var base_fire: int = s.context.get_attack_rules().get_definition(s.actor_loadouts[s.units[0].id].attack_id).damage_components[0].numerator
	receipt = parity(s,attack(s))
	var artifact_fire: bool = false
	for event: Dictionary in receipt.get_events():
		if event.kind == &"hit_resolved":
			for row: Dictionary in event.hit.rows:
				if row.sources.has(&"artifact:spark"): artifact_fire = true
	check(not artifact_fire and fire_damage(receipt) == base_fire,"mage ordinary strike has no spark component")
	check(not s.units[3].is_alive() and s.units[0].vitals.get_hp() == 40.0,"mage ordinary kill does not trigger harvest")
	s.close()

func _production_mage() -> void:
	var profile := HeroHubState.create(338)
	profile.party = [4,2,3]
	profile = ExpeditionTransitions.apply(profile,"start").profile
	profile = ExpeditionTransitions.apply(profile,"choose",{"node":1}).profile
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(),"production expedition mage factory")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var mage_id: int = bundle.hero_units[4]
	check(session.state.artifacts.mages == [mage_id] and not session.state.artifacts.effect_allowed(mage_id,"spark") and not session.state.artifacts.effect_allowed(mage_id,"harvest"),"factory seals actual mage exclusions")
	check(session.state.artifacts.effect_allowed(mage_id,"ember"),"mage retains permitted rune effects")
	session.close()

func _runes() -> void:
	var s := fixture(["blood"])
	parity(s,attack(s)); check(s.units[3].bleeding.stacks == 1,"physical HP rune applies")
	s.close()
	s = fixture(["blood"]); s.units[3].bleeding.immune = true
	parity(s,attack(s)); check(s.units[3].bleeding.stacks == 0,"bleeding immunity")
	s.close()
	s = fixture(["spark","blood","ember"])
	var result := parity(s,attack(s))
	check(s.units[3].bleeding.stacks == 0 and s.units[3].elemental.burning_stacks == 1,"ember clears earlier blood")
	var order: Array[StringName] = []
	for event: Dictionary in result.get_events():
		if event.kind in [&"bleeding_changed",&"elemental_changed"]: order.append(event.kind)
	check(order == [&"bleeding_changed",&"elemental_changed",&"bleeding_changed"],"blood then ember clearing order")
	s.close()
	s = fixture(["blood","ember","ice"],true); s.units[3].elemental.wet_turns = 3
	parity(s,attack(s)); check(s.units[3].elemental.wet_turns == 0 and s.units[3].elemental.frozen_turns == 0,"ember consumes wet before ice attempts")
	s.close()

func _ice_gate() -> void:
	for wet: bool in [false,true]:
		var s := fixture(["ice"]); s.units[3].elemental.wet_turns = 3 if wet else 0
		parity(s,attack(s))
		check(s.units[3].elemental.frozen_turns == (1 if wet else 0) and s.units[3].elemental.wet_turns == 0,"ice does not wet dry targets")
		s.close()
	for percent: int in [49,50]:
		var s := fixture(["ice"])
		var target := s.units[3]; target.elemental.wet_turns = 3
		var definition := ItemDef.new(); definition.id = &"test_ice_armor"; definition.armor_max = 100
		var owner := s.state.get_owner(target.id)
		target.armor.in_battle = false
		var item := owner.create_item(definition)
		check(s.state.get_equipment(target.id).equip(EquipmentState.EquipSlot.ARMOR,item),"ice gate armor")
		item.armor_remaining = percent; target.armor.in_battle = true
		parity(s,attack(s))
		check(target.elemental.frozen_turns == (1 if percent == 49 else 0),"gate before hit at %d%%" % percent)
		s.close()
	var s := fixture(["ice"]); s.units[3].elemental.frozen_turns = 1
	parity(s,attack(s)); check(s.units[3].elemental.frozen_turns == 2,"extend frozen")
	s.close()
	s = fixture(["ice"]); s.units[3].elemental.wet_turns = 3; s.units[3].elemental.freeze_immune = true
	parity(s,attack(s)); check(s.units[3].elemental.frozen_turns == 0,"freeze immunity")
	s.close()

func _harvest() -> void:
	var s := fixture(["harvest"]); s.units[0].vitals._hp = 10.0; s.units[3].vitals._hp = 1.0
	parity(s,attack(s)); check(s.units[0].vitals.get_hp() == 14.0,"direct kill heals four")
	s.close()
	s = fixture(["harvest"]); s.units[0].vitals._hp = 10.0; s.units[3].vitals._hp = 20.0; s.units[3].elemental.frozen_turns = 1
	parity(s,attack(s)); check(not s.units[3].is_alive() and s.units[0].vitals.get_hp() == 14.0,"shatter direct kill heals")
	s.close()
	s = fixture(["harvest"]); s.units[0].vitals._hp = 10.0
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER,100.0)
	s.units[3].stats.set_base_value(StatTypes.StatType.BALANCE_MAX,1.0); s.units[3].vitals._balance = 1.0
	s.board.set_terrain(Vector2i(4,3),TerrainType.Type.VOID)
	parity(s,attack(s)); check(not s.units[3].is_alive() and s.units[0].vitals.get_hp() == 10.0,"fall kill does not heal")
	s.close()

func _formation() -> void:
	var s := fixture(["formation"])
	s.board.move_unit(s.units[1],Vector2i(1,3))
	var owner := s.state.get_owner(s.units[0].id)
	var armor: ItemInstance = null
	for item: ItemInstance in owner._items.values():
		if item.get_definition().armor_max > 0: armor = item
	var ability := s.state.abilities
	for op: StringName in [&"close",&"end",&"begin",&"open",&"close",&"end"]: ability.apply_values(ability.boundary(op,ability.team,ability.serials[ability.team]))
	var result := s._queue.submit(BleedingTurnCommand.new(Faction.Type.PLAYER,s.context.get_revision()),s.context)
	check(result.status == ActionReceipt.APPLIED and armor.armor_remaining == 4,"formation after status pass repairs four " + String(result.reason))
	s._queue.submit(BleedingTurnCommand.new(Faction.Type.PLAYER,s.context.get_revision()),s.context)
	check(armor.armor_remaining == 4,"formation once per team serial")
	s.close()
	s = fixture(["formation"])
	s.board.move_unit(s.units[1],Vector2i(1,3)); s.board.set_height_steps(Vector2i(1,3),2)
	check(not BattleArtifactRules.has_neighbour(s.state,s.units[0]),"different height excluded")
	s.close()

func _workers() -> void:
	var first_id := UnitId.get_counter()
	var s := fixture(["spark","blood","ember"])
	var preview := ForecastSimulation.run(s.context,s._queue,attack(s))
	var worker := AttackForecastWorker.new(); worker.start(ForecastSimulation.prepare(s.context,s._queue,attack(s)))
	var value: AttackForecast = null
	for unused: int in 1000:
		value = worker.take_finished()
		if value != null: break
		await process_frame
	check(value != null and value.snapshot_after == preview.snapshot_after and value.events == preview.events and value.steps == preview.steps and value.rng_after == preview.rng_after and value.counters_after == preview.counters_after,"action forecast worker parity")
	worker.close()
	var live := BattleExecutionWorker.new()
	check(live.start(s,&"attack_unit",[s.units[3].id]),"live worker admits artifact graph")
	var completed := live.take_finished(true)
	var receipt: ActionReceipt = completed.get("result")
	check(receipt != null and receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps and snapshot(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after and s.context.simulation_counters() == preview.counters_after,"live worker parity")
	s.close()
	UnitId.set_counter(first_id)
	s = fixture(["formation"])
	var before := snapshot(s)
	var forecast := TurnForecast.build(s)
	check(forecast.status == ActionReceipt.APPLIED and snapshot(s) == before,"turn forecast with artifacts isolated " + String(forecast.reason))
	s.end_player_turn()
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after,"turn forecast full state parity")
	s.close()
