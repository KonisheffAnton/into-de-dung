extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SICK HOBGOBLIN: " + label)

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return {"state": capture.snapshot.to_dict(), "rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(), "admission": SummonAdmission.values(session.context)}

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1100, 380)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var profile := HeroHubState.create(91821, 4)
	check(profile.start_battle(), "current profile enters battle")
	var saved := profile.to_dict()
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "factory supplies new enemy")
	if bundle.is_empty(): quit(1); return
	var session := bundle.session as BattleCoreReactionsSession
	var hob: UnitState = null
	var target: UnitState = null
	for unit: UnitState in session.units:
		if session.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"sick_hobgoblin": hob = unit
		if unit.faction == Faction.Type.PLAYER and target == null: target = unit
	check(hob != null and target != null and session.units.size() == 7, "two monsters supplement five classes")
	if hob == null or target == null: session.close(); quit(1); return
	check(hob.faction == Faction.Type.ENEMY and hob.debug_name == "Нездоровый хоб-гоблин", "enemy name and faction")
	check(hob.vitals.get_hp() == 24.0 and hob.get_stat(StatTypes.StatType.MOVE_RANGE) == 3.0
		and hob.get_stat(StatTypes.StatType.BALANCE_MAX) == 4.0, "health24 movement3 balance4 follow attributes")
	check(hob.get_stat(StatTypes.StatType.STRENGTH) == 3.0 and hob.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 2.0
		and hob.get_stat(StatTypes.StatType.IMPACT_POWER) == 2.0 and hob.get_stat(StatTypes.StatType.ATTACK_RANGE) == 1.0, "plain adjacent physical attack")
	for field: StringName in [&"sneak_attack", &"tank_reactions", &"stunning_strike", &"stun_immune", &"entangle_immune", &"counterattack", &"burning_bypass_hp_gate", &"passive_opportunist"]:
		check(not bool(hob.combat_perks.definition.get(field)), "no perk " + String(field))
	check(hob.combat_perks.warrior.is_empty() and hob.armor.raised_shield.is_empty()
		and not hob.bleeding.immune and session.state.get_owner(hob.id)._items.is_empty(), "no class kit, immunity or armor items")
	check(not HeroCatalog.class_ids(4).has(&"sick_hobgoblin")
		and not CharacterSkinCatalog.normalized({}).has(&"sick_hobgoblin"), "monster never becomes a recruitable hero or saved cosmetic")
	check(profile.to_dict() == saved, "factory preserves profile and stored plan")
	check(session.start_battle(), "real tactical battle starts")
	for index: int in session.units.size():
		var unit: UnitState = session.units[index]
		var parking := Vector2i(index, 7)
		session.board.set_terrain(parking, TerrainType.Type.FLOOR)
		check(session.board.move_unit(unit, parking), "park via board")
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(4, 3)]:
		session.board.set_terrain(cell, TerrainType.Type.FLOOR)
		session.board.set_height_steps(cell, 0)
	check(session.board.move_unit(hob, Vector2i(3, 3)) and session.board.move_unit(target, Vector2i(4, 3)), "adjacent melee fixture")
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1000.0)
	target.vitals.set_hp(100.0)
	target.vitals.set_balance(0.0)
	target.armor.natural.physical = 0
	target.armor.natural.fire = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	var intent := BattleDemoBT.new().decide(session, hob)
	var attack_id := MageDeckRules.hero_attack_id(hob.id)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.attack_definition_id == attack_id,
		"BT selects only the ordinary monster attack")
	var attack := session.context.get_attack_rules().get_definition(attack_id)
	check(attack != null and attack.damage_components.is_empty() and not attack.entangle_on_physical_hp
		and not attack.stun_on_physical_hp, "definition has no fire or control rider")
	var command := AttackCommand.new(hob.id, target.id, hob.cell, target.cell, attack_id, session.context.get_revision())
	var original := _snapshot(session)
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(session.context, session._queue, command)
	check(_snapshot(session) == original and UnitId.get_counter() == ids, "preview preserves live state and IDs")
	var receipt := session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.APPLIED and receipt.status == preview.status
		and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "real ordinary attack matches preview events")
	check(_snapshot(session) == {"state": preview.snapshot_after, "rng": preview.rng_after,
		"counters": preview.counters_after, "admission": preview.admission_after}, "full preview/live parity")
	check(is_equal_approx(target.vitals.get_hp(), 95.0) and hob.action_resources.get_main_left() == 0,
		"one main action deals exactly five physical damage without extra fire")
	await _test_visuals(session, hob.id)
	session.close()
	viewport.queue_free()
	await process_frame
	print("SICK HOBGOBLIN RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _visual(id: int, kind: StringName, side: Faction.Type, position: Vector2) -> BattleCharacterSkinVisual:
	var visual := UNIT_SCENE.instantiate() as BattleCharacterSkinVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.show_ground_shadow = false
	viewport.add_child(visual)
	var statuses: Array[Dictionary] = []
	var values := {"cell": Vector2i(1, 1), "half_steps": 0,
		"unit": {"id": id, "faction": int(side), "name": String(kind), "alive": true,
			"hp": 24.0, "hp_max": 24.0, "balance": 0.0, "balance_max": 4.0},
		"visual_class_id": kind, "visual_skin_id": CharacterSkinCatalog.resolve_id(kind),
		"selected": false, "inspected": false, "hovered": false, "acting": false,
		"forecast_entry": {}, "show_rear": false, "summon_pending": false,
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {},
		"reaction_view": {}, "action_resources_view": {}, "status_entries": statuses}
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	check(visual.apply_view(values, config), "visual accepts selected skin")
	visual.position = position
	visual.set_process(false)
	return visual

func _start_roar(visual: BattleCharacterSkinVisual) -> void:
	visual.reset_view_pose()
	for tick: int in 220:
		if visual._skin_ambient_elapsed >= 0.0: break
		visual._process(0.1)
	visual.set_process(false)
	check(visual._skin_ambient_elapsed >= 0.0, "cosmetic roar begins after quiet delay")

func _test_visuals(session: BattleCoreReactionsSession, unit_id: int) -> void:
	var before := _snapshot(session)
	var ids := UnitId.get_counter()
	var board := BattleDemoBoard.new()
	board.unit_visual_scene = UNIT_SCENE
	board.size = Vector2(1100, 380)
	board.session = session
	viewport.add_child(board)
	board.refresh()
	var retained := board._presentation_visual(unit_id) as BattleCharacterSkinVisual
	check(retained != null and retained.skin_definition != null, "real factory board binds monster skin")
	if retained != null:
		retained.set_process(false)
		retained._process(2.0)
		var wait_before := retained._skin_ambient_wait
		board.refresh()
		check(board._presentation_visual(unit_id) == retained and retained._skin_ambient_wait == wait_before, "refresh preserves partial first wait")
		_start_roar(retained)
		retained._process(1.12)
		var roar_before := retained._skin_ambient_elapsed
		board.size += Vector2(10, 5)
		board._rescale_layout()
		check(retained._skin_ambient_elapsed == roar_before, "resize preserves in-flight roar")
		retained._process(3.0)
		board.refresh()
		retained._process(6.1)
		check(not retained._skin_ambient_first and retained._skin_ambient_elapsed < 0.0, "refresh does not reset repeat interval to six seconds")
		var repeated_roar := false
		for tick: int in 170:
			retained._process(0.1)
			if retained._skin_ambient_elapsed >= 0.0:
				repeated_roar = true
				break
		check(repeated_roar, "roar repeats after eighteen idle seconds and any secondary tail")
		retained.set_process(false)
	board.queue_free()
	await process_frame
	var visual := _visual(unit_id, &"sick_hobgoblin", Faction.Type.ENEMY, Vector2(350, 200))
	var warrior := _visual(99191, &"fighter", Faction.Type.PLAYER, Vector2(120, 200))
	var sprite := visual.class_still_sprite()
	var definition := visual.skin_definition
	check(definition != null and definition.id == &"sick_hobgoblin" and definition.ambient_buff_interval == 18.0,
		"correct enemy resource with cosmetic interval")
	check(visual.get_authored_facing_x() == -1 and sprite.scale == Vector2(-0.5, 0.5), "enemy faces left with authored anchor")
	check(is_equal_approx(visual.get_unit_art_scale(), warrior.get_unit_art_scale())
		and visual.get_unit_pick_rect() == Rect2(-31, -55, 62, 58), "no scale compensation enlarges the small source")
	check(definition.still.get_image().get_used_rect().size.y < warrior.skin_definition.still.get_image().get_used_rect().size.y * 0.7,
		"native silhouette remains roughly two thirds of Warrior")
	_start_roar(visual)
	visual._process(1.12)
	visual.set_process(false)
	check(sprite.texture == definition.animations.get_frame_texture(&"buff", 16), "roar uses selected frame16")
	var phase := visual._skin_ambient_elapsed
	visual.sync_scene_art()
	visual.set_process(false)
	check(visual._skin_ambient_elapsed == phase and sprite.texture == definition.animations.get_frame_texture(&"buff", 16), "sync preserves cosmetic phase")
	visual._process(3.0)
	visual.set_process(false)
	check(visual._skin_ambient_elapsed < 0.0 and sprite.texture is AtlasTexture
		and (sprite.texture as AtlasTexture).atlas.resource_path.ends_with("/idle.png"), "roar naturally returns to main idle")
	var saw_secondary := false
	for tick: int in 700:
		visual._process(0.1)
		saw_secondary = saw_secondary or visual.skin_clock.secondary
	visual.set_process(false)
	check(saw_secondary, "rare idle2 remains reachable beside roar")
	for property: StringName in [&"frozen", &"stunned", &"summon_pending", &"ambient_animation_paused"]:
		_start_roar(visual)
		visual.set(property, true)
		visual.sync_scene_art()
		check(visual._skin_ambient_elapsed < 0.0, "roar cancels for " + String(property))
		visual.set(property, false)
		visual.sync_scene_art()
	_start_roar(visual)
	visual.action_offset = Vector2(3, 0)
	visual.sync_scene_art()
	check(visual._skin_ambient_elapsed < 0.0, "ordinary attack movement cancels roar")
	visual.action_offset = Vector2.ZERO
	_start_roar(visual)
	visual.sample_death(1.0)
	check(visual._skin_ambient_elapsed < 0.0 and sprite.texture == definition.animations.get_frame_texture(&"death", 32), "death interrupts roar and holds closed-eye final pose")
	visual.reset_view_pose()
	visual.set_process(false)
	check(_snapshot(session) == before and UnitId.get_counter() == ids, "idle/roar/death presentation changes no state, RNG, actions or IDs")
	if DisplayServer.get_name() != "headless":
		var roar := _visual(99192, &"sick_hobgoblin", Faction.Type.ENEMY, Vector2(580, 200))
		roar.sample_buff(1.12)
		roar.set_process(false)
		var dead := _visual(99193, &"sick_hobgoblin", Faction.Type.ENEMY, Vector2(810, 200))
		dead.sample_death(1.0)
		dead.set_process(false)
		for entry: Dictionary in [{"name":"Воин", "x":70}, {"name":"Хоб-гоблин · idle3", "x":280}, {"name":"Рык", "x":550}, {"name":"Смерть1", "x":760}]:
			var label := Label.new()
			label.text = entry.name
			label.position = Vector2(entry.x, 225)
			viewport.add_child(label)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var directory := "user://sick-hobgoblin-captures"
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--captures="): directory = argument.trim_prefix("--captures=")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		check(not image.is_empty() and image.save_png(directory.path_join("hobgoblin-selected-in-game.png")) == OK, "GPU renders selected clips beside Warrior")
	visual.retire_view()
	check(visual._skin_ambient_elapsed < 0.0 and visual._skin_owner == UnitId.NONE, "pool retirement clears ambient state")
