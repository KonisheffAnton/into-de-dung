extends SceneTree

var passed: int = 0
var failed: int = 0
var hub: HeroHubScreen
var page: HubSectionPage
var save_path: String
var settings_path: String

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CHARACTER SKINS HUB: " + label)

func _run() -> void:
	var suffix := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	save_path = "user://character-skins-hub-%s.save" % suffix
	settings_path = "user://character-skins-hub-%s.cfg" % suffix
	var profile := HeroHubState.create(73191, 3)
	if not profile.party.is_empty():
		(profile.heroes[profile.party[0]] as HeroProgression).class_id = &"shieldbearer"
	if not profile.candidates.is_empty(): profile.candidates[0].class_id = &"shieldbearer"
	_check(HeroHubStore.write_run(save_path, profile).is_empty(), "fixture profile saved")
	var profile_bytes := FileAccess.get_file_as_bytes(save_path)
	var baseline := profile.to_dict()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = save_path
	hub.skin_settings_path = settings_path
	viewport.add_child(hub)
	await _settle()
	page = hub.get_node("ExpeditionDashboard/SectionPages/MercenariesPage") as HubSectionPage
	hub._on_hub_tab_requested(&"mercenaries")
	await _settle()
	var choice := page._slot("skin_choice") as OptionButton
	_check(choice != null and choice.visible and not choice.disabled and choice.item_count == 2, "shieldbearer selection offers two skins")
	_check(StringName(choice.get_item_metadata(choice.selected)) == &"watch_shield", "default skin resolves to watch shield")
	var choices := choice.item_count
	choice.item_selected.emit(1)
	await _settle()
	_check(hub.skin_settings.selections.get(&"shieldbearer", &"") == &"grey_bastion", "dropdown routes and publishes selected skin")
	var persisted := CharacterSkinSettings.new()
	persisted.read_file(settings_path)
	_check(persisted.selections.get(&"shieldbearer", &"") == &"grey_bastion", "selection persists outside profile storage")
	var absolute_settings := ProjectSettings.globalize_path(settings_path)
	_check(DirAccess.rename_absolute(absolute_settings, absolute_settings + ".bak") == OK, "simulate interrupted settings replacement")
	var recovered := CharacterSkinSettings.new()
	recovered.read_file(settings_path)
	_check(recovered.selections[&"shieldbearer"] == &"grey_bastion", "valid backup preserves selected skin without main file")
	var invalid_settings := ConfigFile.new()
	invalid_settings.set_value("format", "version", 999)
	_check(invalid_settings.save(settings_path) == OK, "write unsupported settings schema fixture")
	recovered.read_file(settings_path)
	_check(recovered.selections[&"shieldbearer"] == &"grey_bastion", "invalid main uses valid backup")
	DirAccess.remove_absolute(absolute_settings)
	_check(DirAccess.rename_absolute(absolute_settings + ".bak", absolute_settings) == OK, "restore test settings")
	_check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(save_path) == profile_bytes, "skin choice leaves profile and its RNG bytes unchanged")
	var selected_texture: Texture2D = CharacterSkinCatalog.definition(&"shieldbearer", &"grey_bastion").still
	_check((page._slot("hero_portrait") as TextureRect).texture == selected_texture, "mercenary detail portrait follows selected skin")
	var dashboard_cards := hub._dashboard._hero_cards
	var dashboard_portrait := dashboard_cards.get_child(0).get_node("Content/Portrait") as TextureRect
	_check(dashboard_portrait.texture == selected_texture, "dashboard party portrait follows the same class skin")
	_check(HubSkeletonCard.hero_texture(&"shieldbearer", &"unknown") == CharacterSkinCatalog.definition(&"shieldbearer", &"watch_shield").still, "unknown skin falls back within class")
	_check(choice.item_count == choices, "render does not duplicate skin options")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var captures := "user://character-skins-captures"
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
		_check(viewport.get_texture().get_image().save_png(captures.path_join("hub-skin-choice.png")) == OK, "save actual hub skin selector render")

	var old_skin: StringName = hub.skin_settings.selections[&"shieldbearer"]
	hub.run.phase = "expedition"
	hub._on_skin_selection_requested(&"shieldbearer", &"watch_shield")
	_check(hub.skin_settings.selections[&"shieldbearer"] == old_skin, "expedition phase refuses skin change")
	hub.run.phase = "battle"
	hub._on_skin_selection_requested(&"shieldbearer", &"watch_shield")
	_check(hub.skin_settings.selections[&"shieldbearer"] == old_skin, "battle phase refuses skin change")
	hub.run.phase = "hub"
	var blocked_file := settings_path + ".blocker"
	var blocker := FileAccess.open(blocked_file, FileAccess.WRITE)
	if blocker != null: blocker.store_string("file blocks directory")
	if blocker != null: blocker.close()
	hub.skin_settings_path = blocked_file + "/child/settings.cfg"
	hub._on_skin_selection_requested(&"shieldbearer", &"watch_shield")
	_check(hub.skin_settings.selections[&"shieldbearer"] == old_skin, "write failure keeps the previous selected skin")
	_check((page._slot("skin_notice") as Label).visible and (page._slot("skin_notice") as Label).text.begins_with("Облик не изменён"), "write failure is visible in the mercenary detail panel")
	hub.skin_settings_path = settings_path

	var fighter := profile.candidates[0]
	var original_candidate_class := fighter.class_id
	fighter.class_id = &"fighter"
	page._profile = profile
	page.character_skins = hub.skin_settings.selections.duplicate()
	page._on_selected("candidate:%d" % fighter.id)
	_check(choice.visible and choice.disabled and choice.item_count == 1, "single-skin class shows a disabled choice")
	fighter.class_id = &"rogue"
	page._render_skin_choice(fighter)
	_check(choice.visible and choice.disabled and choice.item_count == 1
		and StringName(choice.get_item_metadata(0)) == &"short_cape", "Rogue exposes its selected model02")
	_check(CharacterSkinCatalog.normalized({&"rogue": &"missing"})[&"rogue"] == &"short_cape"
		and recovered.selections[&"rogue"] == &"short_cape", "missing or unknown Rogue cosmetic resolves without profile migration")
	_check(HubSkeletonCard.hero_texture(&"rogue") == CharacterSkinCatalog.definition(&"rogue").still,
		"Rogue hub portrait uses the same selected model as the battle")
	fighter.class_id = &"mage"
	page._on_selected("candidate:%d" % fighter.id)
	var mage_definition := CharacterSkinCatalog.definition(&"mage", &"star_hood")
	var skin_rng_state := hub.run.rng_state
	var expedition_rng_state := hub.run.expedition_rng_state
	_check(choice.visible and choice.disabled and choice.item_count == 1
		and StringName(choice.get_item_metadata(0)) == &"star_hood",
		"Mage exposes its sole registered skin as a disabled choice")
	_check(mage_definition != null
		and (page._slot("hero_portrait") as TextureRect).texture == mage_definition.still
		and HubSkeletonCard.hero_texture(&"mage") == mage_definition.still,
		"Mage detail and hub portraits use the same selected still")
	var mage_default := CharacterSkinCatalog.normalized({})[&"mage"]
	var mage_unknown := CharacterSkinCatalog.normalized({&"mage": &"missing"})[&"mage"]
	_check(mage_default == &"star_hood" and mage_unknown == &"star_hood",
		"missing and unknown Mage cosmetics normalize to its default skin")
	fighter.class_id = &"archer"
	page._on_selected("candidate:%d" % fighter.id)
	var archer_definition := CharacterSkinCatalog.definition(&"archer", &"silver_ranger")
	_check(choice.visible and choice.disabled and choice.item_count == 1
		and StringName(choice.get_item_metadata(0)) == &"silver_ranger",
		"Archer exposes its sole registered skin as a disabled choice")
	_check(archer_definition != null
		and (page._slot("hero_portrait") as TextureRect).texture == archer_definition.still
		and HubSkeletonCard.hero_texture(&"archer") == archer_definition.still,
		"Archer detail and hub portraits use the same selected still")
	var archer_default := CharacterSkinCatalog.normalized({})[&"archer"]
	var archer_unknown := CharacterSkinCatalog.normalized({&"archer": &"missing"})[&"archer"]
	_check(archer_default == &"silver_ranger" and archer_unknown == &"silver_ranger",
		"missing and unknown Archer cosmetics normalize to its default skin")
	_check(hub.run.to_dict() == baseline and hub.run.rng_state == skin_rng_state
		and hub.run.expedition_rng_state == expedition_rng_state
		and FileAccess.get_file_as_bytes(save_path) == profile_bytes,
		"Mage and Archer skin normalization leaves profile, RNG and saved bytes unchanged")
	fighter.class_id = original_candidate_class
	page._on_selected("candidate:%d" % fighter.id)
	_check(profile.to_dict() == baseline, "temporary cosmetic portrait fixture restores the candidate profile")

	hub._start_battle()
	await _settle()
	_check(hub.battle_view != null, "existing battle start path still launches")
	if hub.battle_view != null:
		_check(hub.battle_view.character_skins.get(&"shieldbearer", &"") == &"grey_bastion", "battle receives the same selected per-class skin")

	viewport.queue_free()
	await process_frame
	for path: String in [save_path, save_path + ".bak", save_path + ".tmp", settings_path, settings_path + ".bak", settings_path + ".tmp", blocked_file]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CHARACTER SKINS HUB RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _settle() -> void:
	for unused: int in 4: await process_frame
