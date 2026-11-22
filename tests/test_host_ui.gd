extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var screen: HeroHubScreen
var captures: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST UI: " + label)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	var path := "user://host-ui-%d.save" % Time.get_ticks_usec()
	var packed := load("res://scenes/demo/hero_hub.tscn") as PackedScene
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	screen = packed.instantiate() as HeroHubScreen
	screen.save_path = path
	screen.mage_deck_mode = true
	screen.expedition_mode = true
	viewport.add_child(screen)
	await process_frame
	await process_frame
	_check(screen.run != null and screen.run.expedition == null and not screen.run.mage_deck.is_empty(), "authored hub loads fresh deck expedition profile")
	if screen.run == null:
		await _cleanup(path); quit(1); return
	var base_before: Array[String] = screen.run.mage_deck.base_types.duplicate()
	_check(base_before == ["card.fire","card.fire","card.heal","card.heal","card.shield","card.shield","card.summon","card.summon","card.wet","card.wet"], "fresh host profile retains default base deck")
	for card_id: String in ["card.binding_thread","card.light_step","card.poison"]:
		_check(MageCardCatalog.get_card(card_id) != null, "new card catalog definition " + card_id)
	screen._on_hub_tab_requested(&"deck")
	await process_frame
	var deck_page: HubDeckPage
	for node: Node in screen.find_children("*", "HubDeckPage", true, false):
		deck_page = node as HubDeckPage
		break
	var page_has_thread: bool = false; var page_has_light_step: bool = false; var page_has_poison: bool = false
	if deck_page != null:
		for card: MageCardDefinition in deck_page._catalog:
			if card.id == "card.binding_thread": page_has_thread = true
			if card.id == "card.light_step": page_has_light_step = true
			if card.id == "card.poison": page_has_poison = true
	_check(page_has_thread and page_has_light_step and page_has_poison, "deck page catalog exposes added cards")
	_check(screen.run.mage_deck.base_types == base_before, "catalog browse does not alter base deck")
	screen._on_hub_tab_requested(&"expedition")
	var source_before := screen.run.to_dict()
	var dashboard := screen.get_node("ExpeditionDashboard") as ExpeditionDashboard
	_check(dashboard._start_button.disabled and screen.run.mage_deck.host_hero_id == 0, "fresh profile requires explicit possession")
	_check(dashboard._launch_hint.text.contains("носителя") and dashboard._fix_button.visible, "start has a nearby choose-host action")
	await _capture("hub-unselected")
	dashboard._on_fix_issue()
	var dialog := dashboard._host_dialog
	_check(dialog.visible and dialog._heroes.get_child_count() == screen.run.party.size(), "dialog lists current party only")
	var selected_host: int = screen.run.party[1]
	(dialog._heroes.get_child(1) as Button).pressed.emit()
	_check(dialog._selected_id == selected_host and screen.run.to_dict() == source_before and HeroHubStore.read_run(path).run.to_dict() == source_before, "draft choice is presentation-only")
	_check(dialog._cards.text.contains("Пока нет"), "modal reports host cards absent from unchanged base deck")
	await _capture("possession-dialog")
	(dialog.get_node("Dialog/Content/Actions/Cancel") as Button).pressed.emit()
	_check(not dialog.visible and screen.run.to_dict() == source_before, "cancel leaves profile and save unchanged")
	dashboard.open_host_dialog()
	(dialog._heroes.get_child(1) as Button).pressed.emit()
	dialog._confirm.pressed.emit()
	_check(not dialog.visible and screen.run.mage_deck.host_hero_id == selected_host and not dashboard._start_button.disabled, "explicit confirmation persists host and enables start")
	_check(HeroHubStore.read_run(path).run.mage_deck.host_hero_id == selected_host, "confirmed host survives store roundtrip before departure")
	var hero_before: Dictionary = (screen.run.heroes[selected_host] as HeroProgression).to_dict()
	var rng_before: int = screen.run.rng_state
	dashboard._host_glow.pressed.emit()
	dialog._colors.select(2); dialog._forms.select(1); dialog._flicker.select(0); dialog._refresh()
	await _capture("glow-settings")
	dialog._confirm.pressed.emit()
	_check(screen.run.mage_deck.host_glow == {"color":"violet","form":"flame","flicker":"still"}, "glow customization saves independently")
	_check((screen.run.heroes[selected_host] as HeroProgression).to_dict() == hero_before and screen.run.rng_state == rng_before, "possession cosmetics preserve hero and RNG")
	var party_before: Array[int] = screen.run.party.duplicate()
	screen._on_dashboard_party_move(selected_host,0,party_before)
	_check(screen.run.party[0] == selected_host and screen.run.mage_deck.host_hero_id == selected_host, "reordering preserves carrier identity")
	await process_frame
	var squad := dashboard._hero_cards
	var badges: int = 0
	for badge: Node in squad.find_children("HostBadge", "TextureRect", true, false):
		if (badge as TextureRect).visible: badges += 1
	_check(badges == 1, "exactly one permanent carrier badge after reorder")
	for size_value: Vector2i in [Vector2i(1280,720),Vector2i(1600,900)]:
		viewport.size = size_value
		await process_frame; await process_frame
		_check(dashboard._start_button.get_global_rect().end.y <= float(size_value.y), "start remains in viewport at " + str(size_value))
		await _capture("hub-selected-%dx%d" % [size_value.x,size_value.y])
	viewport.size = Vector2i(1280,850)
	dashboard.open_host_dialog()
	var stale_party: Array[int] = screen.run.party.duplicate(); stale_party.reverse()
	screen._on_host_confirmed(selected_host,stale_party,selected_host,{"color":"blue","form":"glow","flicker":"soft"},false)
	_check(not dialog.visible and screen.run.mage_deck.host_glow.color == "violet", "stale modal rejects without overwriting settings")
	# Ошибка хранилища не публикует ни выбор, ни огонёк; retry пишет тот же кандидат.
	dashboard.open_host_dialog(true)
	dialog._colors.select(1); dialog._refresh()
	var old_settings: Dictionary = screen.run.mage_deck.duplicate(true)
	var blocker := FileAccess.open(path + ".block",FileAccess.WRITE)
	blocker.store_string("test-owned non-directory"); blocker.close()
	screen.save_path = path + ".block/save.dat"
	dialog._confirm.pressed.emit()
	_check(screen._pending_save != null and screen.run.mage_deck == old_settings, "write failure leaves confirmed source unchanged")
	screen.save_path = path
	screen._retry_save()
	_check(screen._pending_save == null and screen.run.mage_deck.host_glow.color == "blue", "retry saves appearance from retained candidate")
	# Окно показывает именно текущую базу: две карты добавлены явным выбором фикстуры.
	var with_cards := screen._copy_run()
	var card_types: Array = with_cards.mage_deck.base_types.duplicate()
	card_types[0] = "card.light_step"; card_types[1] = "card.binding_thread"
	_check(with_cards.set_mage_base(card_types), "explicit host-card base is valid")
	screen._commit(with_cards)
	dashboard.open_host_dialog()
	_check(dialog._cards.text.contains("Лёгкий шаг") and dialog._cards.text.contains("Связующая нить"), "modal shows both selected host cards")
	viewport.size = Vector2i(1024,720)
	await process_frame; await process_frame
	_check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses((dialog.get_node("Dialog") as Control).get_global_rect()), "both host cards fit modal at minimum game window")
	await _capture("possession-with-cards")
	dialog.close()
	viewport.size = Vector2i(1280,850)
	var invalid_source := HeroHubState.create(6671)
	invalid_source.enable_mage_deck()
	var invalid_before := invalid_source.to_dict()
	var invalid_transition := ExpeditionTransitions.apply(invalid_source,"start",{"host_hero_id":999999})
	_check(not invalid_transition.is_ok() and invalid_source.to_dict() == invalid_before, "host outside party rejected without profile mutation")
	screen._start_battle()
	await process_frame
	await process_frame
	_check(screen.run.expedition != null and screen.run.expedition.host_hero_id == selected_host, "start commits selected host")
	_check(screen.run.expedition.checkpoint.schema == 2 and screen.run.expedition.checkpoint.host_hero_id == selected_host, "selected host is in the saved checkpoint")
	_check(screen.battle_view != null and not screen._battle_bundle.is_empty(), "authored expedition creates real battle bundle")
	if screen.battle_view != null and not screen._battle_bundle.is_empty():
		var session: BattleCoreReactionsSession = screen._battle_bundle.session
		var hero_units: Dictionary = screen._battle_bundle.hero_units
		var host_unit_id: int = int(hero_units[selected_host])
		_check(session.state.card_effects.host_unit_id == host_unit_id, "factory maps selected hero to host unit")
		var other_id: int = int(screen.run.party[0]) if int(screen.run.party[0]) != selected_host else int(screen.run.party[1])
		_check(session.select_unit(int(hero_units[other_id])) and session.state.card_effects.host_unit_id == host_unit_id, "switching selected actor does not switch host")
		_check(HeroHubStore.read_run(path).run.expedition.host_hero_id == selected_host, "combat actor switch does not alter persisted host")
		var board := screen.battle_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board") as BattleDemoBoard
		_check(board.host_unit_id == host_unit_id and board.host_glow.color == "blue", "battle board receives detached host appearance")
		await _capture("host-in-battle")
	var saved_run := screen.run.to_dict()
	screen._clear_battle()
	viewport.remove_child(screen); screen.queue_free()
	await process_frame
	screen = packed.instantiate() as HeroHubScreen
	screen.save_path = path
	screen.mage_deck_mode = true
	screen.expedition_mode = true
	viewport.add_child(screen)
	await process_frame
	await process_frame
	_check(screen.run != null and screen.run.to_dict() == saved_run, "reopening same save restores host run")
	if screen.run != null and screen.battle_view != null:
		var reloaded_session: BattleCoreReactionsSession = screen._battle_bundle.session
		var reloaded_units: Dictionary = screen._battle_bundle.hero_units
		_check(reloaded_session.state.card_effects.host_unit_id == int(reloaded_units[selected_host]), "reloaded battle maps the same hero as host")
	await _cleanup(path)
	print("HOST UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	var image_value := viewport.get_texture().get_image()
	_check(image_value != null and image_value.save_png(captures.path_join(label + ".png")) == OK, "GPU capture " + label)

func _cleanup(path: String) -> void:
	if screen != null and is_instance_valid(screen):
		screen._clear_battle()
		if screen.get_parent() != null: screen.get_parent().remove_child(screen)
		screen.queue_free()
	if viewport != null and is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp", ".block"]:
		var absolute := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(absolute)
