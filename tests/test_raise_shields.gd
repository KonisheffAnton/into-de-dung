extends SceneTree

var passed: int = 0
var failed: int = 0

class PacketHit extends DamageCommand:
	func _init(hit: DamageRequest = null) -> void: super(hit)
	func get_kind() -> StringName: return &"raised_shield_test_hit"
	func copy_for_queue() -> Command: return PacketHit.new(request.copy())
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(context: ActionContext) -> CommandStepResult:
		var target := context.get_state().get_board().get_unit_by_id(request.target_unit_id)
		var guard := SpatialRules.capture_guard(context, [target], [target.cell], {target.id: [StatTypes.StatType.HP_MAX]})
		return ArmorHitExecutor.execute(request, guard, context).result

class MultiHit extends Command:
	var target_id: int
	var count: int
	var physical: int
	var fire: int
	var source_kind: StringName
	func _init(id: int = 0, hits: int = 1, p: int = 20, f: int = 10, kind: StringName = &"attack") -> void:
		target_id = id; count = hits; physical = p; fire = f; source_kind = kind
	func get_kind() -> StringName: return &"raised_shield_test_multi"
	func copy_for_queue() -> Command: return MultiHit.new(target_id, count, physical, fire, source_kind)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(context: ActionContext) -> CommandStepResult:
		var target := context.get_state().get_board().get_unit_by_id(target_id)
		var children: Array[Command] = []
		for i: int in count:
			var raw: Array[Dictionary] = [{"type":"physical","policy":"standard","source":"base","numerator":physical,"denominator":1}, {"type":"fire","policy":"standard","source":"fire","numerator":fire,"denominator":1}]
			var hit := ArmorAttack.request(target_id, raw, DamageSource.new(source_kind, 0, target.cell))
			hit.attack_group_id = context.damage_attack_group()
			children.append(PacketHit.new(hit))
		return CommandStepResult.applied([], children)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL RAISE SHIELDS: " + label)

func fixture() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	if s.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		s._enemy_index = s._enemy_ids.size(); s.step_enemy()
	s.selected_id = s.living_ids(Faction.Type.PLAYER)[0]
	for unit: UnitState in s.units:
		if not unit.is_alive(): continue
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.vitals.set_hp(80.0)
		unit.armor.natural = {"physical":0,"fire":0}
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	var actor := s.selected_unit()
	actor.combat_perks.definition = CombatPerksDefinition.new()
	actor.combat_perks.definition.passive_opportunist = true
	actor.combat_perks.uses_bonus_actions = true
	actor.armor.raised_shield = RaisedShield.make()
	s.state.abilities.catalog.append(RaiseShieldsCommand.definition())
	s.state.abilities.catalog.sort_custom(func(a: AbilityDefinition,b: AbilityDefinition) -> bool: return String(a.ability_id)<String(b.ability_id))
	return s

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var value := ItemSimulationSnapshot.capture(s.state, [])
	check(value.code == ItemSnapshotResult.Code.OK, "snapshot valid: " + value.reason)
	return value.snapshot.to_dict() if value.snapshot != null else {}

func submit(s: BattleCoreReactionsSession, c: Command) -> ActionReceipt:
	var r := s._queue.submit(c,s.context)
	check(r.status == ActionReceipt.APPLIED, "%s applied: %s %s" % [c.get_kind(),r.status,r.reason])
	return r

func advance(s: BattleCoreReactionsSession) -> void:
	for operation: StringName in [&"close",&"end",&"begin"]:
		var clock := s.state.abilities
		submit(s,AbilityBoundaryCommand.new(operation,clock.team,clock.serials[clock.team],s.context.get_revision()))
	var clock := s.state.abilities
	submit(s,BattleTurnRefill.new(s.living_ids(clock.team),s.context.get_revision(),clock.team))
	submit(s,AbilityBoundaryCommand.new(&"open",clock.team,clock.serials[clock.team],s.context.get_revision()))

func run() -> void:
	await activation_and_worker()
	packets_and_sources()
	cooldown_and_expiry()
	actual_attack_and_opportunist()
	refusals_and_fault_prefix()
	mage_and_periodic()
	print("RAISE SHIELDS RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func activation_and_worker() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var command := RaiseShieldsCommand.new(actor.id,s.context.get_revision())
	var forecast := ForecastSimulation.run(s.context,s._queue,command)
	check(forecast.status == ActionReceipt.APPLIED, "activation forecast")
	var worker := ActionForecastWorker.new()
	worker.start(ForecastSimulation.prepare(s.context,s._queue,command))
	var result: ForecastSimulation
	for i: int in 200:
		result = worker.take_finished()
		if result != null: break
		await process_frame
	worker.close()
	check(result != null and result.snapshot_after == forecast.snapshot_after and result.events == forecast.events, "worker activation parity")
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "preview leaves live state/counters/RNG untouched")
	var receipt := submit(s,command)
	check(snapshot(s) == forecast.snapshot_after and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "live activation exact parity")
	check(actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 1 and actor.armor.raised_shield.active and not actor.guard_stance, "only main spent; independent shield")
	check(s.raise_shields_reason() == &"raise_shields/already_active", "repeat refuses")
	var unchanged := snapshot(s)
	var repeated := s._queue.submit(RaiseShieldsCommand.new(actor.id,s.context.get_revision()),s.context)
	check(repeated.status == ActionReceipt.REJECTED and snapshot(s) == unchanged, "repeat preserves state")
	var capture := ItemSimulationSnapshot.capture(s.state,[])
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = owner._definitions[id].duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state.get_board().get_unit_by_id(actor.id).armor.raised_shield == actor.armor.raised_shield, "snapshot restores active shield and cooldown")
	if restored.state != null: ForecastSimulation.close(restored.state)
	s.close()

func packets_and_sources() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	var hp := actor.vitals.get_hp()
	submit(s,MultiHit.new(actor.id,1,0,0))
	check(actor.armor.raised_shield.active and actor.vitals.get_hp() == hp, "zero attack does not consume")
	for kind: StringName in [&"status",&"cell",&"collision",&"fall"]:
		submit(s,MultiHit.new(actor.id,1,2,0,kind))
		check(actor.armor.raised_shield.active, "nonattack preserves shield: " + String(kind))
	check(actor.vitals.get_hp() == hp-8.0,"nonattack damage is not reduced")
	hp = actor.vitals.get_hp()
	var receipt := submit(s,MultiHit.new(actor.id,2))
	check(actor.vitals.get_hp() == hp-6.0,"all direct hits/components of one application reduced")
	check(receipt.get_events().filter(func(e: Dictionary) -> bool: return e.kind == &"raised_shield_used").size()==1,"one consumption event")
	submit(s,MultiHit.new(actor.id,1,10,0))
	check(actor.vitals.get_hp() == hp-16.0,"next application unprotected")
	s.close()
	s = fixture(); actor = s.selected_unit()
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	actor.armor.shield = SpellShield.make(&"mage.shield",6,1)
	hp=actor.vitals.get_hp()
	submit(s,MultiHit.new(actor.id,1,20,0))
	check(actor.vitals.get_hp()==hp and not actor.armor.raised_shield.active and actor.armor.shield.is_empty(),"90 percent before mage absorption; shield spent despite zero HP loss")
	s.close()

func cooldown_and_expiry() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	var ready: int = actor.armor.raised_shield.ready_turn
	advance(s)
	check(actor.armor.raised_shield.active,"opposing turn does not expire shield")
	advance(s)
	check(not actor.armor.raised_shield.active and actor.armor.raised_shield.ready_turn==ready,"own start expires only protection")
	check(RaiseShieldsCommand.new(actor.id,s.context.get_revision()).validate(s.context)==&"raise_shields/cooldown","next complete own turn unavailable")
	advance(s); advance(s)
	check(RaiseShieldsCommand.new(actor.id,s.context.get_revision()).validate(s.context)==&"","following own turn available")
	s.close()

func actual_attack_and_opportunist() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x,y),TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x,y),0)
	for i: int in s.units.size():
		if s.units[i].is_alive(): s.board.move_unit(s.units[i],Vector2i(i,0))
	s.board.move_unit(actor,Vector2i(2,3))
	var enemy := s.board.get_unit_by_id(s.living_ids(Faction.Type.ENEMY)[0])
	s.board.move_unit(enemy,Vector2i(3,3))
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	var attack := AttackCommand.new(enemy.id,actor.id,enemy.cell,actor.cell,&"demo_strike",s.context.get_revision())
	var before := snapshot(s)
	var preview := ForecastSimulation.run(s.context,s._queue,attack)
	check(preview.status == ActionReceipt.APPLIED,"actual attack preview: "+String(preview.reason))
	check(snapshot(s)==before,"attack preview does not consume live shield")
	var receipt := submit(s,attack)
	check(snapshot(s)==preview.snapshot_after and receipt.get_events()==preview.events,"actual attack shield preview/live parity")
	check(not actor.armor.raised_shield.active,"ordinary attack consumes shield")
	# Прямой удар сохраняет толчок; новую проверку перехвата ставим в заведомую угрозу.
	s.board.move_unit(actor,Vector2i(2,3))
	s.board.move_unit(enemy,Vector2i(3,3))
	enemy.action_resources._set_for_refill(1,1)
	var retreat := submit(s,MoveCommand.new(enemy.id,[enemy.cell,Vector2i(4,3)],s.context.get_revision(),&"safe_retreat"))
	check(enemy.cell==Vector2i(4,3) and actor.action_resources.get_bonus_left()==1 and not retreat.get_events().any(func(e: Dictionary) -> bool: return e.kind==&"opportunity_attacked"),"safe retreat bypasses passive reaction")
	s.board.move_unit(enemy,Vector2i(3,3))
	check(MeleeThreat.threatens(s.context,actor,enemy),"test departure begins inside melee threat")
	var move := MoveCommand.new(enemy.id,[enemy.cell,Vector2i(4,3)],s.context.get_revision())
	var movement := s._queue.submit(move,s.context)
	check(movement.status==ActionReceipt.INTERRUPTED,"opportunity interrupts movement: "+String(movement.reason))
	check(movement.get_events().any(func(e: Dictionary) -> bool: return e.kind==&"opportunity_attacked"),"passive opportunity without stance")
	check(enemy.cell==Vector2i(3,3) and actor.action_resources.get_bonus_left()==0,"perceptible stop and bonus payment")
	s.close()

func refusals_and_fault_prefix() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	for condition: String in ["stale","main","stunned","ownership"]:
		if condition=="main": actor.action_resources._set_for_refill(0,1)
		if condition=="stunned": actor.control.stunned_turns=1
		if condition=="ownership": actor.armor.raised_shield={}
		var before := snapshot(s)
		var rng := s.context.get_rng().to_dict()
		var counters := s.context.simulation_counters()
		var revision := s.context.get_revision()-1 if condition=="stale" else s.context.get_revision()
		var r := s._queue.submit(RaiseShieldsCommand.new(actor.id,revision),s.context)
		check(r.status==ActionReceipt.REJECTED and r.get_events().is_empty() and snapshot(s)==before and s.context.get_rng().to_dict()==rng and s.context.simulation_counters()==counters,"atomic refusal: "+condition)
		actor.action_resources._set_for_refill(1,1); actor.control.stunned_turns=0; actor.armor.raised_shield=RaisedShield.make()
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	actor.armor.shield=SpellShield.make(&"mage.shield",6,1)
	var corrupt := func(kind: StringName,_key: int,_old: int,_new: int) -> void:
		if kind==&"shield": actor.armor.natural.physical+=1
	actor.armor.changed.connect(corrupt)
	var hp := actor.vitals.get_hp()
	var fault := s._queue.submit(MultiHit.new(actor.id,1,100,0),s.context)
	actor.armor.changed.disconnect(corrupt)
	check(fault.status==ActionReceipt.FAULTED,"shield callback corruption faults")
	check(not actor.armor.raised_shield.active and actor.armor.shield.is_empty() and actor.vitals.get_hp()==hp,"fault preserves both consumed shields; HP not written")
	check(fault.get_events().any(func(e: Dictionary) -> bool: return e.kind==&"raised_shield_used") and fault.get_events().any(func(e: Dictionary) -> bool: return e.kind==&"shield_changed"),"fault receipt preserves consumed-shield prefix")
	s.close()

func mage_and_periodic() -> void:
	var s := fixture()
	var enemy := s.board.get_unit_by_id(s.living_ids(Faction.Type.ENEMY)[0])
	# Вражеский владелец даёт настоящую цель заклинанию верховного мага.
	enemy.armor.raised_shield=RaisedShield.activated(RaisedShield.make(),1)
	var before := snapshot(s)
	var preview := ForecastSimulation.run_prepared(s.prepare_mage_forecast(&"mage.fire",enemy.id))
	check(preview.status==ActionReceipt.APPLIED and snapshot(s)==before,"mage fire shield preview isolated")
	var fire := s.cast_mage_spell(&"mage.fire",enemy.id)
	check(fire.status==ActionReceipt.APPLIED and fire.get_events()==preview.events and snapshot(s)==preview.snapshot_after,"actual mage fire parity")
	check(not enemy.armor.raised_shield.active and fire.get_events().any(func(e: Dictionary) -> bool: return e.kind==&"raised_shield_used"),"actual mage fire consumes class shield")
	var actor := s.selected_unit()
	submit(s,RaiseShieldsCommand.new(actor.id,s.context.get_revision()))
	for unit: UnitState in s.units: unit.bleeding.stacked=true
	actor.elemental.burning_stacks=2; actor.elemental.burning_ticks=1
	actor.elemental.burning_source=DamageSource.new(&"mage",3,Vector2i(-1,-1),0,0).to_dict()
	var hp := actor.vitals.get_hp()
	submit(s,BleedingTurnCommand.new(actor.faction,s.context.get_revision()))
	check(actor.armor.raised_shield.active and actor.vitals.get_hp()==hp-2,"real mage-sourced burning does not consume or reduce")
	s.close()
