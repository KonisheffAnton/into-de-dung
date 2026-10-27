extends Control
class_name HeroHubScreen

@export var save_path: String = "user://hero-hub-v1.save"
@export var expedition_mode: bool = false
@export var mage_deck_mode: bool = false
var deck_editing: bool = false
var deck_draft: Array = []
var _base_deck_expected: Dictionary = {}
var _base_deck_candidate: HeroHubState

var run: HeroHubState
var selected_hero_id: int = 0
var pending_delta: Array[int] = [0, 0, 0, 0, 0]
var battle_view: HeroHubBattleView
var _battle_bundle: Dictionary = {}
var _pending_save: HeroHubState
var _storage_error: String = ""
var _message: String = ""
var _root_panel: Control
var _content: VBoxContainer
var _pages: Dictionary[String, VBoxContainer] = {}
var _page_host: VBoxContainer
var _start_button: Button
var _dashboard: ExpeditionDashboard
var _hub_management: bool = false
var _hub_tab: StringName = &"expedition"

func _ready() -> void:
	_root_panel = $Panel
	_dashboard = $ExpeditionDashboard
	_dashboard.start_requested.connect(_start_battle)
	_dashboard.manage_requested.connect(_open_hub_management)
	_dashboard.tab_requested.connect(_on_hub_tab_requested)
	_dashboard.hire_requested.connect(_on_mercenary_hire_requested)
	_dashboard.party_requested.connect(_on_mercenary_party_requested)
	_dashboard.equipment_requested.connect(_on_smith_equipment_requested)
	_dashboard.allocation_requested.connect(_on_mercenary_allocation_requested)
	_dashboard.deck_action_requested.connect(_base_deck_action.bind(&"deck"))
	($Panel/Column/Header/DashboardBack as Button).pressed.connect(_return_hub_dashboard)
	_page_host = $Panel/Column/HeroHubScroll/Content/Pages
	for child: Node in _page_host.get_children():
		_pages[String(child.name)] = child as VBoxContainer
		_page_host.remove_child(child)
	_start_button = _page("BasePage").get_node("Footer/Start") as Button
	var save_existed := FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")
	var loaded := HeroHubStore.read_run(save_path,mage_deck_mode)
	run = loaded.get("run") as HeroHubState
	_storage_error = String(loaded.get("error", ""))
	if run != null and not save_existed and _storage_error.is_empty():
		# Первый профиль сразу фиксируется, чтобы кандидаты и стартовый отряд не менялись после перезапуска.
		selected_hero_id = run.party[0] if not run.party.is_empty() else 0
		_commit(run)
		return
	if run != null and not run.heroes.is_empty():
		selected_hero_id = int(run.heroes.keys()[0])
		if not run.party.is_empty(): selected_hero_id = run.party[0]
	_render()

func _process(_delta: float) -> void:
	if battle_view == null or battle_view.is_execution_pending() or _pending_save != null:
		return
	var outcome := HeroHubBattleFactory.outcome(_battle_bundle)
	if outcome.is_empty():
		return
	if run.phase == "expedition":
		var transition := ExpeditionTransitions.apply(run, "outcome", outcome)
		if transition.is_ok(): _commit(transition.profile)
		else:
			_storage_error = "Исход не прошёл проверку: " + transition.reason
			_clear_battle(); _render()
		return
	var candidate := _copy_run()
	if candidate == null or not candidate.finish_battle(int(outcome.get("serial", -1)), bool(outcome.get("victory", false)), outcome.get("hp", {}), outcome.get("gear", {})):
		_storage_error = "Результат боя не прошёл проверку. Исход сохранён в текущей контрольной точке."
		_clear_battle()
		_render()
		return
	_commit(candidate)

func _exit_tree() -> void:
	_clear_battle()
	# Неактивные страницы временно вне дерева, но принадлежат этому экрану.
	for page: VBoxContainer in _pages.values():
		if page.get_parent() == null: page.free()
	_pages.clear()

func _copy_run() -> HeroHubState:
	return HeroHubState.from_dict(run.to_dict()) if run != null else null

func _commit(candidate: HeroHubState) -> void:
	var error := HeroHubStore.write_run(save_path, candidate)
	if not error.is_empty():
		_pending_save = candidate
		_storage_error = error
		if battle_view != null:
			battle_view.set_process(false)
			battle_view.hide()
		_render()
		return
	if run != null and run.phase != "hub" and candidate.phase == "hub":
		# Новый выход завершён: после отчёта встречаем игрока на главной странице хаба.
		_hub_management = false
		_hub_tab = &"expedition"
	if run != null and run.heroes.has(selected_hero_id) and candidate.heroes.has(selected_hero_id):
		var previous: HeroProgression = run.heroes[selected_hero_id]
		var updated: HeroProgression = candidate.heroes[selected_hero_id]
		# Второе представление не должно применить старый черновик поверх уже сохранённого развития.
		if previous.allocated != updated.allocated: pending_delta = [0, 0, 0, 0, 0]
	if candidate == _base_deck_candidate:
		# Оба редактора используют один черновик; отказ записи оставляет его до retry.
		deck_editing = false
		deck_draft.clear()
		_base_deck_expected.clear()
		_base_deck_candidate = null
	run = candidate
	_pending_save = null
	_storage_error = ""
	_message = "Профиль сохранён."
	_clear_battle()
	_render()

func _retry_save() -> void:
	if _pending_save != null:
		_commit(_pending_save)

func _mutate(method: StringName, args: Array = []) -> void:
	if run == null or _pending_save != null or not _storage_error.is_empty() or battle_view != null:
		return
	var candidate := _copy_run()
	if candidate == null:
		_message = "Не удалось скопировать профиль."
		_render()
		return
	var result: Variant = candidate.callv(method, args)
	if not (result is bool and result):
		_message = "Действие недоступно: проверьте отряд, очки и золото."
		_render()
		return
	if method == &"start_battle":
		_commit(candidate)
		return
	_message = "Изменения сохранены."
	if method == &"set_mage_base": _base_deck_candidate = candidate
	_commit(candidate)

func _start_battle() -> void:
	if deck_editing:
		_message = "Сохраните или отмените состав колоды перед выходом."
		_render(); return
	if expedition_mode:
		_expedition_action("start")
		return
	if run == null or run.party.is_empty() or _pending_save != null or not _storage_error.is_empty():
		return
	var candidate := _copy_run()
	if candidate == null or not candidate.start_battle():
		_message = "Нужен хотя бы один герой в отряде."
		_render()
		return
	_commit(candidate)

static func _is_first_expedition_run(candidate: HeroHubState) -> bool:
	if candidate == null or candidate.phase != "expedition" or candidate.expedition == null or candidate.expedition.phase != "battle": return false
	var node := candidate.expedition.current_node()
	return not node.is_empty() and int(node.get("layer", -1)) == 0

func _configure_first_room_art(target_battle: HeroHubBattleView, candidate: HeroHubState) -> bool:
	if target_battle == null or not _is_first_expedition_run(candidate): return false
	var board := target_battle.get_node_or_null("BattleHUD/Margin/Column/Content/Left/Field/Board") as BattleDemoBoard
	if board == null: return false
	board.tile_visual_scene = load("res://scenes/demo/visuals/dungeon_comparison_tile.tscn") as PackedScene
	board.environment_visual_scene = load("res://scenes/demo/visuals/dungeon_room_environment.tscn") as PackedScene
	return board.tile_visual_scene != null and board.environment_visual_scene != null

func _begin_battle() -> void:
	if run == null or (run.phase != "battle" and (run.expedition == null or run.expedition.phase != "battle")):
		_render()
		return
	_battle_bundle = HeroHubBattleFactory.create(run)
	if _battle_bundle.is_empty() or not _battle_bundle.has("session"):
		_storage_error = "Не удалось собрать бой из сохранённого отряда и экипировки."
		_render()
		return
	battle_view = (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	battle_view.expedition_battle = run.phase == "expedition"
	_configure_first_room_art(battle_view, run)
	battle_view.supplied_session = _battle_bundle["session"]
	battle_view.return_requested.connect(_on_battle_return)
	battle_view.restart_requested.connect(_restart_checkpoint)
	battle_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_view)

func _on_battle_return() -> void:
	# Результат берётся только из терминального состояния сессии, никакого ручного исхода UI нет.
	if battle_view != null and not battle_view.is_execution_pending():
		_process(0.0)

func _restart_checkpoint() -> void:
	if _pending_save != null or not _storage_error.is_empty() or run == null or battle_view == null:
		return
	var current_battle := run.phase == "battle" or (run.phase == "expedition" and run.expedition != null and run.expedition.phase == "battle")
	if not current_battle or not battle_view.can_restart_checkpoint(): return
	# Run остаётся неизменной контрольной точкой начала этой комнаты; runtime создастся заново из неё.
	_clear_battle()
	_render()

func _clear_battle() -> void:
	if battle_view != null:
		battle_view._join_execution()
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	if not _battle_bundle.is_empty():
		var session: Variant = _battle_bundle.get("session")
		if session != null:
			session.call("close")
	_battle_bundle.clear()

func _page(key: String) -> VBoxContainer:
	return _pages[key]

func _show_page(key: String) -> VBoxContainer:
	for child: Node in _page_host.get_children():
		_page_host.remove_child(child)
	var page := _page(key)
	HubUI.clear_dynamic(page)
	_page_host.add_child(page)
	page.show()
	_content = page
	return page

func _render() -> void:
	_sync_base_deck_draft()
	_dashboard.hide()
	_root_panel.show()
	($Panel/Column/Header/DashboardBack as Button).hide()
	var scroll := $Panel/Column/HeroHubScroll as ScrollContainer
	var scroll_offset := scroll.scroll_vertical
	if battle_view != null:
		_clear_battle()
	if run != null:
		if run.phase == "expedition" and not run.party.has(selected_hero_id): selected_hero_id = run.party[0]
		var selected: HeroProgression = run.heroes.get(selected_hero_id)
		if selected == null or selected.hp_current <= 0.0:
			selected_hero_id = 0
			for id: int in run.heroes:
				var candidate: HeroProgression = run.heroes[id]
				if candidate.hp_current > 0.0:
					selected_hero_id = id
					break
	var title := HubUI.text(self, ^"Panel/Column/Header/HubTitle", "intoDeDung · Поход" if run != null and run.phase == "expedition" else "intoDeDung · Хаб героев")
	if run != null and run.phase == "hub" and deck_editing: title.text = "Колода мага · %d/10" % deck_draft.size()
	var wallet := $Panel/Column/Header/HubWallet as Label
	wallet.visible = run != null
	if run != null:
		var wallet_text := "Золото: %d" % run.gold
		if run.phase == "expedition" and run.expedition != null:
			wallet_text = "Золото похода: %d · В хабе: %d" % [run.expedition.gold, run.gold]
		wallet.text = "%s · Эссенция: %d · Очки: %d (%d доступно)" % [wallet_text, run.essence, run.achievements.total_points, run.achievements.available_points]
	var last_result := $Panel/Column/HeroHubScroll/Content/LastResult as Label
	var message := $Panel/Column/HeroHubScroll/Content/Message as Label
	last_result.hide()
	message.hide()
	scroll.set_deferred("scroll_vertical", scroll_offset)
	if not _storage_error.is_empty() or run == null:
		var error_page := _show_page("ErrorPage")
		HubUI.text(error_page, ^"Error", "Сохранение недоступно: " + _storage_error if not _storage_error.is_empty() else "Профиль не загружен. Сохранение не изменено.")
		HubUI.bind(error_page, ^"retry_save", _retry_save).visible = _pending_save != null
		return
	if run.battle_report.get("open", false):
		_show_page("ReportPage")
		PostBattlePanel.render(self)
		return
	last_result.text = run.last_result
	last_result.visible = run.phase != "expedition"
	if run.phase == "battle" or (run.phase == "expedition" and run.expedition.phase == "battle"):
		for child: Node in _page_host.get_children(): _page_host.remove_child(child)
		_begin_battle()
		return
	if run.phase == "expedition":
		_show_page("ExpeditionPage")
		ExpeditionHubPanel.render(self)
		return
	message.text = _message
	message.visible = not _message.is_empty()
	if not _hub_management:
		var launch_hint := "Состав готов. Можно отправляться."
		if run.party.is_empty(): launch_hint = "Добавьте хотя бы одного героя в отряд."
		elif deck_editing: launch_hint = "Сохраните или отмените изменения в разделе «Колода»."
		_dashboard.render_profile(run, expedition_mode, _hub_tab, not run.party.is_empty() and not deck_editing, launch_hint, deck_editing, deck_draft)
		_root_panel.hide()
		_dashboard.show()
		return
	($Panel/Column/Header/DashboardBack as Button).show()
	_show_page("BasePage")
	_hub_content()

func _can_navigate_hub() -> bool:
	return run != null and run.phase == "hub" and not run.battle_report.get("open", false) and _pending_save == null and _storage_error.is_empty()

func _open_hub_management() -> void:
	if not _can_navigate_hub(): return
	_hub_management = true
	_render()

func _return_hub_dashboard() -> void:
	if not _can_navigate_hub(): return
	# Возврат меняет только представление: черновик колоды остаётся у владельца хаба.
	_hub_management = false
	_hub_tab = &"expedition"
	_render()

func _on_hub_tab_requested(tab_id: StringName) -> void:
	if not _can_navigate_hub() or not ExpeditionDashboard.TAB_IDS.has(tab_id): return
	if tab_id == &"deck" and (_hub_management or not _dashboard.is_visible_in_tree()): return
	_hub_tab = tab_id
	_hub_management = false
	_render()

func _can_change_mercenaries() -> bool:
	return _can_navigate_hub() and not _hub_management and _hub_tab == &"mercenaries" and _dashboard.is_visible_in_tree() and battle_view == null

func _sync_base_deck_draft() -> void:
	if run == null or run.phase != "hub": return
	if not deck_editing:
		_base_deck_expected.clear()
		return
	if _base_deck_expected.is_empty() and not run.mage_deck.is_empty():
		_base_deck_expected = run.mage_deck.duplicate(true)
	elif _base_deck_expected != run.mage_deck:
		# Публикация другого состава делает прежний черновик устаревшим для обоих представлений.
		deck_editing = false
		deck_draft.clear()
		_base_deck_expected.clear()

func _base_deck_action(action: String, type_id: String, surface: StringName) -> void:
	if not _can_navigate_hub() or battle_view != null or not is_visible_in_tree(): return
	if surface == &"deck":
		if _hub_management or _hub_tab != &"deck" or not _dashboard.is_visible_in_tree() or not _dashboard.deck_page_visible(): return
	elif surface == &"management":
		if not _hub_management or not _root_panel.is_visible_in_tree() or not _page("BasePage").is_visible_in_tree(): return
	else: return
	if action == "close":
		if surface == &"deck": _return_hub_dashboard()
		return
	if run.mage_deck.is_empty(): return
	var was_editing := deck_editing
	_sync_base_deck_draft()
	if was_editing and not deck_editing:
		_render()
		return
	if action == "edit":
		if deck_editing: return
		deck_editing = true
		deck_draft = run.mage_deck.base_types.duplicate()
		_base_deck_expected = run.mage_deck.duplicate(true)
	elif not deck_editing: return
	elif action == "cancel":
		deck_editing = false
		deck_draft.clear()
		_base_deck_expected.clear()
	elif action == "save":
		if not MageCardCatalog.valid_base(deck_draft): return
		_mutate(&"set_mage_base", [deck_draft.duplicate()])
		return
	elif action in ["plus", "minus"]:
		if MageCardCatalog.get_card(type_id) == null: return
		if action == "minus": deck_draft.erase(type_id)
		elif deck_draft.count(type_id) < 2: deck_draft.append(type_id)
	else: return
	_render()

func _on_mercenary_hire_requested(candidate_id: int) -> void:
	if not _can_change_mercenaries(): return
	# Индекс вычисляется по опубликованному профилю: старый ID не наймёт замену кандидата.
	for index: int in run.candidates.size():
		if run.candidates[index].id == candidate_id:
			_hire(index)
			return

func _on_mercenary_party_requested(hero_id: int, join_party: bool) -> void:
	if not _can_change_mercenaries() or not run.heroes.has(hero_id): return
	var hero: HeroProgression = run.heroes[hero_id]
	if hero.hp_current <= 0.0 or run.party.has(hero_id) == join_party: return
	if join_party and run.party.size() >= HeroHubState.MAX_PARTY: return
	_toggle_party(hero_id)

func _on_smith_equipment_requested(item_id: int, hero_id: int, equip_item: bool) -> void:
	if not _can_navigate_hub() or _hub_management or _hub_tab != &"smith" or not _dashboard.is_visible_in_tree() or battle_view != null: return
	if not run.items.has(item_id) or not run.heroes.has(hero_id): return
	var hero: HeroProgression = run.heroes[hero_id]
	if hero.hp_current <= 0.0: return
	var item: Dictionary = run.items[item_id]
	# Проверяем текущего владельца: старый запрос не снимет вещь с другого героя.
	if equip_item:
		if int(item.hero_id) != 0 or not HeroGearCatalog.allowed(String(item.definition), hero.class_id): return
		_equip(item_id, hero_id)
	else:
		if int(item.hero_id) != hero_id: return
		_unequip(item_id)

func _on_mercenary_allocation_requested(hero_id: int, expected: Dictionary, delta: Array[int]) -> void:
	if not _can_change_mercenaries() or not run.heroes.has(hero_id): return
	var hero: HeroProgression = run.heroes[hero_id]
	# Предпросмотр относится к точному герою; повторный или устаревший запрос не тратит очки снова.
	if hero.hp_current <= 0.0 or hero.to_dict() != expected: return
	_mutate(&"allocate", [hero_id, delta.duplicate()])

func _hub_content() -> void:
	var page := _page("BasePage")
	_content = page.get_node("Deck") as VBoxContainer
	_content.visible = not run.mage_deck.is_empty()
	if _content.visible: MageDeckPanel.base_editor(self)
	_achievement_content()
	var party_row := page.get_node("Party") as HFlowContainer
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		var button := _button_for(party_row, ("✓ " if run.party.has(id) else "□ ") + hero.name, "party_%d" % id, _toggle_party.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HubUI.text(page, ^"Composition", "СОСТАВ · %d/%d · выбранный герой: %s" % [run.party.size(), HeroHubState.MAX_PARTY, _selected_name()])
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		var entry := HubUI.instance("hero_entry", page.get_node("Heroes"))
		var selected := " · выбран" if selected_hero_id == id else ""
		var choose := HubUI.bind(entry, ^"Select", _select_hero.bind(id))
		choose.text = "%s · %s · уровень %d · XP %d.%d · очки %d%s" % [hero.name, HeroCatalog.class_definition(hero.class_id).display_name, hero.level(), hero.xp_tenths / 10, hero.xp_tenths % 10, hero.available_points(), selected]
		HubUI.text(entry, ^"Detail", _hero_detail(hero))
	HubUI.text(page, ^"AllocationHeading", "ПРЕДВАРИТЕЛЬНЫЕ ОЧКИ · %s" % _selected_name())
	_content = page.get_node("Allocation") as VBoxContainer
	_allocation_controls()
	HubUI.text(page, ^"CandidatesHeading", "КАНДИДАТЫ · состав %d/%d · бесплатный найм, свойства показаны до найма" % [run.heroes.size(), HeroHubState.MAX_ROSTER])
	(page.get_node("StorageHint") as Control).visible = run.items.size() + 2 > HeroHubState.MAX_ITEMS
	for index: int in run.candidates.size():
		var candidate: HeroProgression = run.candidates[index]
		var entry := HubUI.instance("candidate_entry", page.get_node("Candidates"))
		HubUI.text(entry, ^"Detail", _hero_detail(candidate))
		var hire := HubUI.bind(entry, ^"Hire", _hire.bind(index))
		hire.name = "hire_%d" % index
		hire.disabled = run.heroes.size() >= HeroHubState.MAX_ROSTER or run.items.size() + 2 > HeroHubState.MAX_ITEMS
	HubUI.text(page, ^"EquipmentHeading", "СКЛАД ЭКИПИРОВКИ · всего вещей %d/%d" % [run.items.size(), HeroHubState.MAX_ITEMS])
	_equipment_controls()
	# Ссылка переживает смену runtime-имени, порядок элементов в редакторе свободен.
	var send := _start_button
	HubUI.bind(send.get_parent(), NodePath(send.name), _start_battle)
	send.name = "start_expedition" if expedition_mode else "start_battle"
	send.text = "Начать поход · 7 комнат" if expedition_mode else "Отправиться в настоящий бой"
	send.disabled = run.party.is_empty() or _pending_save != null

func _achievement_content() -> void:
	var section := _page("BasePage").get_node("Achievements")
	var achievements := run.achievements
	HubUI.text(section, ^"Title", "ДОСТИЖЕНИЯ · заработано %d очков · доступно %d" % [achievements.total_points, achievements.available_points])
	for definition: ProfileAchievementDefinition in ProfileAchievements.definitions():
		var count := achievements.count_for(definition.id)
		var unlocked := achievements.unlocked.has(String(definition.id))
		var entry := HubUI.instance("achievement_entry", section.get_node("Entries"))
		HubUI.text(entry, ^"Title", "%s · %s · %d/%d · %d очков" % ["✓" if unlocked else "○", definition.title, count, definition.goal, definition.points])
		HubUI.text(entry, ^"Description", definition.description)

func _hero_detail(hero: HeroProgression) -> String:
	var definition := HeroCatalog.class_definition(hero.class_id)
	var stats := hero.attributes()
	var is_candidate := not run.heroes.has(hero.id)
	var equipped_weapon := run.equipped(hero.id, "weapon") if not is_candidate else {}
	var weapon_damage := float(definition.weapon_damage) if is_candidate else (0.0 if equipped_weapon.is_empty() else _weapon_damage(String(equipped_weapon.definition), definition.weapon_damage))
	var equipped_armor := run.equipped(hero.id, "armor") if not is_candidate else {}
	var armor_text := "%d/%d" % [definition.armor_max, definition.armor_max] if is_candidate else ("%.1f/%d" % [float(equipped_armor.remaining), HeroGearCatalog.definition(String(equipped_armor.definition)).armor_max] if not equipped_armor.is_empty() else "0.0/0")
	var base_stats := "Мощь %d · Ловкость %d · Выносливость %d · Интеллект %d · Мастерство %d" % [stats[0], stats[1], stats[2], stats[3], stats[4]]
	var xp_text := "%d.%d опыта всего" % [hero.xp_tenths / 10, hero.xp_tenths % 10]
	var perk := HeroCatalog.perk_text(hero.perk)
	var weapon_name: String = {"warrior":"меч", "shieldbearer":"меч", "archer":"лук", "rogue":"кинжал", "mage":"посох"}.get(String(hero.class_id), "оружие класса")
	var abilities := definition.abilities_text
	if hero.class_id == &"mage": abilities += " Броня +20."
	abilities += " Общие действия: походный флакон (4 + Мощь), стойка." if hero.class_id == &"shieldbearer" else " Общие действия: походный флакон (4 + Мощь), общий отход и стойка."
	var allowed := "Оружие: только %s своего класса · доспехи: любое обычное имеющееся" % weapon_name
	return "%s\n%s\nУровень %d · %s · свободно очков: %d\nПерк: %s\nБазовые атрибуты: Мощь %d / Ловкость %d / Выносливость %d / Интеллект %d / Мастерство %d\nHP %.1f/%.1f · равновесие %d · движение %.0f · естественное сопротивление: физ. %.1f%% / огонь %.1f%%\n%s\nБроня надетого доспеха: %s · базовый урон оружия: %s\nСпособности: %s\nДопуски: %s" % [hero.name, base_stats, hero.level(), xp_text, hero.available_points(), perk, hero.base_attributes[0], hero.base_attributes[1], hero.base_attributes[2], hero.base_attributes[3], hero.base_attributes[4], hero.hp_current, hero.max_hp(), hero.balance_max(), hero.move_max(), hero.physical_resistance(), hero.fire_resistance(), _attribute_effects_text(hero), armor_text, String.num(weapon_damage).trim_suffix(".0"), abilities, allowed]

func _weapon_damage(key: String, fallback: int) -> float:
	var definition := HeroGearCatalog.definition(key)
	if definition == null: return float(fallback)
	if String(definition.id) == "weapon:mage": return float(fallback)
	for effect: ItemEffect in definition.effects:
		if effect is StatModifierEffect and (effect as StatModifierEffect).stat_type == StatTypes.StatType.WEAPON_DAMAGE:
			return (effect as StatModifierEffect).value
	return 0.0

func _allocation_controls() -> void:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	if hero == null:
		_text("Выберите героя для изменения характеристик.")
		return
	var attributes := ["Мощь", "Ловкость", "Выносливость", "Интеллект", "Мастерство"]
	var preview := HeroProgression.from_dict(hero.to_dict())
	var preview_ok := preview != null and _delta_sum() > 0 and preview.apply_allocation(pending_delta)
	var panel := HubUI.instance("allocation_panel", _content)
	for index: int in 5:
		var cell := HubUI.instance("attribute_entry", panel.get_node("Attributes"))
		HubUI.text(cell, ^"Title", attributes[index])
		HubUI.text(cell, ^"Controls/Value", "%d" % pending_delta[index])
		var minus := HubUI.bind(cell, ^"Controls/Minus", _change_delta.bind(index, -1))
		minus.name = "alloc_minus_%d" % index
		var plus := HubUI.bind(cell, ^"Controls/Plus", _change_delta.bind(index, 1))
		plus.name = "alloc_plus_%d" % index
		plus.disabled = hero.available_points() <= _delta_sum()
	HubUI.text(panel, ^"Current", "Сейчас %s" % _stat_preview(hero))
	if preview_ok: HubUI.text(panel, ^"Preview", "После применения: %s" % _allocation_delta_text(hero, preview))
	HubUI.bind(panel, ^"Actions/apply_allocation", _apply_allocation).disabled = not preview_ok
	HubUI.bind(panel, ^"Actions/cancel_allocation", _cancel_allocation)
	var reset := HubUI.bind(panel, ^"Actions/respec", _respec)
	reset.visible = run.phase == "hub"
	reset.text = "Перераспределить · %d золота" % HeroHubState.RESPEC_PRICE
	reset.disabled = hero.available_points() == hero.level() - 1 or run.gold < HeroHubState.RESPEC_PRICE

func _stat_preview(hero: HeroProgression) -> String:
	var attrs := hero.attributes()
	return "Мощь %d · Ловкость %d · Выносливость %d · Интеллект %d · Мастерство %d · HP %.1f/%.1f · HP макс. %.1f · равновесие %d · движение %.0f · физ. %.1f%% / огонь %.1f%% · %s · %s · флакон %d HP" % [attrs[0], attrs[1], attrs[2], attrs[3], attrs[4], hero.hp_current, hero.max_hp(), hero.max_hp(), hero.balance_max(), hero.move_max(), hero.physical_resistance(), hero.fire_resistance(), _attribute_effects_text(hero), _attack_base_text(hero), 4 + attrs[0]]

func _attribute_effects_text(hero: HeroProgression) -> String:
	var attrs := hero.attributes()
	return "Прямой урон ×%.2f · урон состояний ×%.2f · бонус позиции ×%.2f · крит ×%.2f" % [CharacterAttributeRules.power_multiplier(float(attrs[0])), CharacterAttributeRules.status_multiplier(float(attrs[3])), CharacterAttributeRules.position_bonus_multiplier(float(attrs[4])), CharacterAttributeRules.critical_multiplier(float(attrs[4]))]

func _allocation_delta_text(before: HeroProgression, after: HeroProgression) -> String:
	var old_stats := before.attributes()
	var new_stats := after.attributes()
	var labels: Array[String] = ["Мощь", "Ловкость", "Выносливость", "Интеллект", "Мастерство"]
	var parts: PackedStringArray = []
	for index: int in 5:
		parts.append("%s %d→%d (%+d)" % [labels[index], old_stats[index], new_stats[index], new_stats[index] - old_stats[index]])
	parts.append("HP %.1f→%.1f (%+.1f)" % [before.hp_current, after.hp_current, after.hp_current - before.hp_current])
	parts.append("макс. HP %.1f→%.1f (%+.1f)" % [before.max_hp(), after.max_hp(), after.max_hp() - before.max_hp()])
	parts.append("равновесие %d→%d (%+d)" % [before.balance_max(), after.balance_max(), after.balance_max() - before.balance_max()])
	parts.append("движение %.0f→%.0f (%+.0f)" % [before.move_max(), after.move_max(), after.move_max() - before.move_max()])
	parts.append("естественное сопротивление физ. %.1f→%.1f%% / огню %.1f→%.1f%%" % [before.physical_resistance(), after.physical_resistance(), before.fire_resistance(), after.fire_resistance()])
	parts.append("Прямой урон ×%.2f→%.2f · состояния ×%.2f→%.2f · бонус позиции ×%.2f→%.2f · крит ×%.2f→%.2f" % [CharacterAttributeRules.power_multiplier(float(old_stats[0])), CharacterAttributeRules.power_multiplier(float(new_stats[0])), CharacterAttributeRules.status_multiplier(float(old_stats[3])), CharacterAttributeRules.status_multiplier(float(new_stats[3])), CharacterAttributeRules.position_bonus_multiplier(float(old_stats[4])), CharacterAttributeRules.position_bonus_multiplier(float(new_stats[4])), CharacterAttributeRules.critical_multiplier(float(old_stats[4])), CharacterAttributeRules.critical_multiplier(float(new_stats[4]))])
	parts.append("%s→%s" % [_attack_base_text(before), _attack_base_text(after)])
	parts.append("флакон %d→%d HP" % [4 + before.attributes()[0], 4 + after.attributes()[0]])
	return " · ".join(parts)

func _attack_base_text(hero: HeroProgression) -> String:
	var class_definition := HeroCatalog.class_definition(hero.class_id)
	var weapon: Dictionary = run.equipped(hero.id, "weapon") if run != null and run.heroes.has(hero.id) else {}
	var weapon_value := 0.0 if weapon.is_empty() else _weapon_damage(String(weapon.definition), class_definition.weapon_damage)
	var attack_base := (3.0 + weapon_value) * CharacterAttributeRules.power_multiplier(float(hero.attributes()[0]))
	if hero.class_id == &"mage":
		return "огненная база %.1f (не урон по цели)" % attack_base
	return "база основной атаки %.1f (не урон по цели)" % attack_base

func _equipment_controls() -> void:
	var page := _page("BasePage")
	var selector := page.get_node("EquipmentSelector")
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		_button_for(selector, ("• " if selected_hero_id == id else "") + hero.name, "equipment_hero_%d" % id, _select_hero.bind(id))
	HubUI.text(page, ^"EquipmentSelected", "Экипировка героя: " + _selected_name())
	for item_id: int in run.items:
		var item: Dictionary = run.items[item_id]
		var definition := HeroGearCatalog.definition(String(item.definition))
		if definition == null: continue
		var owner := "на складе" if int(item.hero_id) == 0 else "надето на " + String((run.heroes[item.hero_id] as HeroProgression).name)
		var detail := " · броня %.1f/%d" % [float(item.remaining), definition.armor_max] if definition.armor_max > 0 else ""
		var row := HubUI.instance("equipment_entry", page.get_node("Equipment"))
		HubUI.text(row, ^"Detail", "%s #%d · %s%s" % [definition.display_name, item_id, owner, detail])
		var unequip := HubUI.bind(row, ^"Unequip", _unequip.bind(item_id))
		unequip.name = "unequip_%d" % item_id
		unequip.visible = selected_hero_id != 0 and int(item.hero_id) == selected_hero_id
		var equip := HubUI.bind(row, ^"Equip", _equip.bind(item_id, selected_hero_id))
		equip.name = "equip_%d" % item_id
		equip.visible = selected_hero_id != 0 and int(item.hero_id) == 0
		if equip.visible: equip.disabled = not HeroGearCatalog.allowed(String(item.definition), (run.heroes[selected_hero_id] as HeroProgression).class_id)
		var discard := HubUI.bind(row, ^"Discard", _discard.bind(item_id))
		discard.name = "discard_%d" % item_id
		discard.visible = int(item.hero_id) == 0

func _toggle_party(id: int) -> void:
	_mutate(&"toggle_party", [id])

func _hire(index: int) -> void:
	_mutate(&"hire", [index])

func _apply_allocation() -> void:
	if _delta_sum() <= 0: return
	var delta: Array[int] = pending_delta.duplicate()
	pending_delta = [0, 0, 0, 0, 0]
	if run.phase == "expedition":
		_expedition_action("allocate", {"hero":selected_hero_id,"delta":delta})
		return
	_mutate(&"allocate", [selected_hero_id, delta])

func _respec() -> void:
	pending_delta = [0, 0, 0, 0, 0]
	_mutate(&"respec", [selected_hero_id])

func _equip(item_id: int, hero_id: int) -> void:
	_mutate(&"equip", [item_id, hero_id])

func _unequip(item_id: int) -> void:
	_mutate(&"unequip", [item_id])

func _discard(item_id: int) -> void:
	_mutate(&"discard_item", [item_id])

func _change_delta(index: int, amount: int) -> void:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	if hero == null: return
	var next := pending_delta[index] + amount
	if next < 0 or _delta_sum() + amount > hero.available_points(): return
	var projected := HeroProgression.from_dict(hero.to_dict())
	if amount > 0:
		if projected.available_points() < _delta_sum() + 1: return
	pending_delta[index] = next
	_render()

func _cancel_allocation() -> void:
	pending_delta = [0, 0, 0, 0, 0]
	_render()

func _delta_sum() -> int:
	var result := 0
	for value: int in pending_delta: result += value
	return result

func _select_hero(id: int) -> void:
	selected_hero_id = id
	pending_delta = [0, 0, 0, 0, 0]
	_render()

func _selected_name() -> String:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	return hero.name if hero != null else "не выбран"

func _label(value: String, size: int = 16) -> Label:
	var scene := preload("res://scenes/demo/hub/text.tscn")
	var result := scene.instantiate() as Label
	result.set_meta(&"hub_dynamic", true)
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	return result

func _text(value: String, size: int = 16) -> void:
	_content.add_child(_label(value, size))

func _text_for_box(parent: Node, value: String, size: int = 16) -> void:
	parent.add_child(_label(value, size))

func _button_for(parent: Node, value: String, key: String, action: Callable) -> Button:
	var button := HubUI.instance("action_button", parent) as Button
	button.name = key
	button.text = value
	button.pressed.connect(action)
	return button

func _expedition_action(action: String, args: Dictionary = {}) -> void:
	if deck_editing and action != "deck_compose":
		_message = "Сохраните или отмените изменения состава."
		_render(); return
	if run == null or _pending_save != null or not _storage_error.is_empty() or battle_view != null: return
	var transition := ExpeditionTransitions.apply(run,action,args)
	if transition.is_ok(): _commit(transition.profile)
	else:
		_message = "Действие недоступно: " + transition.reason
		_render()
