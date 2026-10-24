extends Control
class_name HubSectionPage

signal manage_requested
signal hire_requested(candidate_id: int)
signal party_requested(hero_id: int, join_party: bool)
signal equipment_requested(item_id: int, hero_id: int, equip_item: bool)
signal allocation_requested(hero_id: int, expected: Dictionary, delta: Array[int])

@export var section_id: StringName = &"mercenaries"

const RESERVE_PAGE_SIZE: int = 3
const ITEMS_PAGE_SIZE: int = 6
var _profile: HeroHubState
var _selected_hero_id: int = 0
var _selected_candidate: bool = true
var _selected_item_id: int = 0
var _reserve_page: int = 0
var _items_page: int = 0
var _school_index: int = 0
var _skill_index: int = -1
var _development: HubHeroDevelopment = HubHeroDevelopment.new()

func _ready() -> void:
	_connect_controls()

func render_profile(profile: HeroHubState) -> void:
	_profile = profile
	if profile == null: return
	_connect_controls()
	match section_id:
		&"mercenaries":
			_render_mercenaries()
			_development.render(self, profile)
		&"smith": HubSmithPresenter.render(self, profile)
		&"schools": _render_schools()

func _connect_controls() -> void:
	for child: Node in find_children("*", "", true, false):
		if child is HubSkeletonCard:
			var card := child as HubSkeletonCard
			if not card.selected.is_connected(_on_selected): card.selected.connect(_on_selected)
		elif child is Button and child.has_meta(&"hub_action"):
			var button := child as Button
			var callback := _on_action.bind(String(child.get_meta(&"hub_action")))
			if not button.pressed.is_connected(callback): button.pressed.connect(callback)

func _slot(key: String) -> Node:
	# Метаданные переживают переименование/перемещение; отсутствие элемента допустимо.
	for child: Node in find_children("*", "", true, false):
		if String(child.get_meta(&"hub_slot", "")) == key: return child
	return null

func _text(key: String, value: String) -> void:
	var label := _slot(key) as Label
	if label != null: label.text = value

func _portrait(key: String, texture: Texture2D) -> void:
	var control := _slot(key) as TextureRect
	if control != null: control.texture = texture

func _action_enabled(action: String, enabled: bool) -> void:
	for child: Node in find_children("*", "Button", true, false):
		if String(child.get_meta(&"hub_action", "")) == action: (child as Button).disabled = not enabled

func _action_button(action: String) -> Button:
	for child: Node in find_children("*", "Button", true, false):
		if String(child.get_meta(&"hub_action", "")) == action: return child as Button
	return null

func _render_hero_slot(slot: String, hero: HeroProgression, candidate: bool = false) -> void:
	var card := _slot(slot) as HubSkeletonCard
	if card == null: return
	if hero == null:
		card.render_card("", "—")
		return
	var definition := HeroCatalog.class_definition(hero.class_id)
	var key := ("candidate:" if candidate else "hero:") + str(hero.id)
	card.render_card(key, definition.display_name, "Ур. %d" % hero.level(), "", HubSkeletonCard.hero_texture(hero.class_id))
	card.tooltip_text = hero.name

func _reserve_ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in _profile.heroes:
		var hero: HeroProgression = _profile.heroes[id]
		if not _profile.party.has(id) and hero.hp_current > 0.0: result.append(id)
	return result

func _selected_hero() -> HeroProgression:
	if not _selected_candidate: return _profile.heroes.get(_selected_hero_id) as HeroProgression
	for hero: HeroProgression in _profile.candidates:
		if hero.id == _selected_hero_id: return hero
	return null

func _render_mercenaries() -> void:
	# После успешной публикации найма прежний ID переходит из списка кандидатов в героев.
	var hired_selection := _selected_candidate and _profile.heroes.has(_selected_hero_id)
	if hired_selection:
		_selected_candidate = false
	_text("candidate_count", "Доступные наёмники · %d" % _profile.candidates.size())
	for index: int in 4:
		_render_hero_slot("candidate_%d" % index, _profile.candidates[index] if index < _profile.candidates.size() else null, true)
	_text("party_count", "%d/%d" % [_profile.party.size(), HeroHubState.MAX_PARTY])
	for index: int in HeroHubState.MAX_PARTY:
		_render_hero_slot("party_%d" % index, _profile.heroes.get(_profile.party[index]) if index < _profile.party.size() else null)
	var reserve := _reserve_ids()
	if hired_selection:
		var hired_reserve_index := reserve.find(_selected_hero_id)
		if hired_reserve_index >= 0: _reserve_page = floori(float(hired_reserve_index) / float(RESERVE_PAGE_SIZE))
	_reserve_page = clampi(_reserve_page, 0, maxi(0, (reserve.size() - 1) / RESERVE_PAGE_SIZE))
	_text("reserve_count", "Резерв · %d" % reserve.size())
	_text("reserve_page", "%d / %d" % [_reserve_page + 1, maxi(1, ceili(float(reserve.size()) / RESERVE_PAGE_SIZE))])
	_action_enabled("reserve_prev", _reserve_page > 0)
	_action_enabled("reserve_next", (_reserve_page + 1) * RESERVE_PAGE_SIZE < reserve.size())
	for slot: int in RESERVE_PAGE_SIZE:
		var index := _reserve_page * RESERVE_PAGE_SIZE + slot
		_render_hero_slot("reserve_%d" % slot, _profile.heroes.get(reserve[index]) if index < reserve.size() else null)
	var hero := _selected_hero()
	if hero == null:
		_selected_candidate = not _profile.candidates.is_empty()
		if _selected_candidate: hero = _profile.candidates[0]
		elif not _profile.heroes.is_empty(): hero = _profile.heroes.values()[0] as HeroProgression
		_selected_hero_id = hero.id if hero != null else 0
	if hero == null:
		_text("hero_title", "Выберите героя")
		_text("hero_detail", "Нет доступных героев")
		_portrait("hero_portrait", null)
		_update_mercenary_action(null)
		return
	_text("hero_title", hero.name)
	_portrait("hero_portrait", HubSkeletonCard.hero_texture(hero.class_id))
	var attrs := hero.attributes()
	var location := "Кандидат" if _selected_candidate else ("В отряде" if _profile.party.has(hero.id) else "В резерве")
	_text("hero_detail", "%s · ур. %d\nHP %.0f/%.0f\nМощь %d · Ловкость %d\nВыносливость %d\nИнтеллект %d · Мастерство %d" % [location, hero.level(), hero.hp_current, hero.max_hp(), attrs[0], attrs[1], attrs[2], attrs[3], attrs[4]])
	_update_mercenary_action(hero)

func _update_mercenary_action(hero: HeroProgression) -> void:
	var action_button := _action_button("mercenary_action")
	# Кнопка и подпись независимы: удаление одной не останавливает обновление другой.
	var action_text := "Нанять бесплатно" if _selected_candidate else "В отряд"
	var available := false
	var hint := ""
	if _profile.phase != "hub":
		hint = "Действие доступно только в хабе"
	elif _selected_candidate:
		if hero == null or not _profile.candidates.has(hero): hint = "Выберите доступного кандидата"
		elif _profile.heroes.size() >= HeroHubState.MAX_ROSTER: hint = "Достигнут предел состава: %d героев" % HeroHubState.MAX_ROSTER
		elif _profile.items.size() + 2 > HeroHubState.MAX_ITEMS: hint = "На складе нужны 2 свободных места для комплекта новичка"
		elif _profile.next_id >= 1000000000: hint = "Достигнут предел найма в этом профиле"
		else: available = true
	else:
		var current: HeroProgression = _profile.heroes.get(_selected_hero_id) as HeroProgression
		if current == null or current.hp_current <= 0.0:
			hint = "Выберите живого героя"
		elif _profile.party.has(current.id):
			action_text = "В резерв"
			available = true
		else:
			if _profile.party.size() >= HeroHubState.MAX_PARTY: hint = "Отряд заполнен: максимум %d героя" % HeroHubState.MAX_PARTY
			else: available = true
	if action_button != null:
		action_button.text = action_text
		action_button.disabled = not available
	if hint.is_empty():
		hint = "Бесплатно · новый герой появится в резерве" if _selected_candidate else "Перевод без стоимости"
	_text("mercenary_hint", hint)

func _item_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _profile.items: ids.append(id)
	ids.sort()
	return ids

func _render_schools() -> void:
	_text("school_title", "Школа %d" % (_school_index + 1))
	_text("skill_title", "Выберите узел" if _skill_index < 0 else "Узел %d" % (_skill_index + 1))
	_text("skill_detail", "Место для описания умения.\nСостав и связи ещё не выбраны.")
	for child: Node in find_children("*", "Button", true, false):
		var action := String(child.get_meta(&"hub_action", ""))
		if action.begins_with("school_"): (child as Button).set_pressed_no_signal(action == "school_%d" % _school_index)
		elif action.begins_with("skill_"): (child as Button).set_pressed_no_signal(action == "skill_%d" % _skill_index)

func _on_selected(key: String) -> void:
	var parts := key.split(":")
	if _profile == null or parts.size() != 2: return
	var previous_id := _selected_hero_id
	var previous_candidate := _selected_candidate
	match parts[0]:
		"hero", "candidate":
			_selected_candidate = parts[0] == "candidate"
			_selected_hero_id = int(parts[1])
		"item": _selected_item_id = int(parts[1])
	if section_id == &"mercenaries" and (previous_id != _selected_hero_id or previous_candidate != _selected_candidate):
		_development.close(self)
	render_profile(_profile)

func _on_action(action: String) -> void:
	if section_id == &"mercenaries" and _development.handle_action(self, _profile, action):
		if _profile != null: render_profile(_profile)
		return
	if action == "manage":
		manage_requested.emit()
		return
	if action == "mercenary_action":
		var action_button := _action_button(action)
		# Скрытая страница/кнопка не должна запускать действие через устаревший callback.
		if section_id != &"mercenaries" or not is_visible_in_tree() or action_button == null or not action_button.is_visible_in_tree() or _profile == null: return
		if _profile.phase != "hub": return
		if _selected_candidate:
			var candidate: HeroProgression = _selected_hero()
			if candidate == null or not _profile.candidates.has(candidate) or _profile.heroes.size() >= HeroHubState.MAX_ROSTER or _profile.items.size() + 2 > HeroHubState.MAX_ITEMS or _profile.next_id >= 1000000000: return
			hire_requested.emit(candidate.id)
		else:
			var current: HeroProgression = _profile.heroes.get(_selected_hero_id) as HeroProgression
			if current == null or current.hp_current <= 0.0 or not _profile.heroes.has(current.id): return
			var join_party := not _profile.party.has(current.id)
			if join_party and _profile.party.size() >= HeroHubState.MAX_PARTY: return
			party_requested.emit(current.id, join_party)
		return
	if section_id == &"smith" and HubSmithPresenter.handle_action(self, _profile, action):
		if _profile != null: render_profile(_profile)
		return
	match action:
		"items_prev": _items_page -= 1
		"items_next": _items_page += 1
		"reserve_prev": _reserve_page -= 1
		"reserve_next": _reserve_page += 1
	if action.begins_with("school_"):
		_school_index = clampi(int(action.trim_prefix("school_")), 0, 3)
		_skill_index = -1
	elif action.begins_with("skill_"): _skill_index = clampi(int(action.trim_prefix("skill_")), 0, 5)
	if _profile != null: render_profile(_profile)
