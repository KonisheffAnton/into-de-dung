extends Control
class_name ExpeditionDashboard

signal tab_requested(tab_id: StringName)
signal start_requested
signal manage_requested

const HERO_CARD: PackedScene = preload("res://scenes/demo/hub/dashboard_hero_card.tscn")
const TAB_IDS: Array[StringName] = [&"expedition", &"mercenaries", &"smith", &"schools"]
const CLASS_TEXTURES: Dictionary = {
	&"warrior": "res://assets/ui/hub/warrior_portrait.tres",
	&"shieldbearer": "res://assets/ui/hub/shieldbearer_portrait.tres",
	&"archer": "res://assets/ui/hub/archer_portrait.tres",
	&"rogue": "res://assets/ui/hub/rogue_portrait.tres",
	&"mage": "res://assets/placeholder_battle/mage_card.svg",
}

@onready var _tabs: Array[Button] = [
	$Layout/Tabs/TabExpedition,
	$Layout/Tabs/TabMercenaries,
	$Layout/Tabs/TabSmith,
	$Layout/Tabs/TabSchools,
]
@onready var _hero_cards: HBoxContainer = $Layout/Content/LeftColumn/PartyPanel/PartyContent/HeroCards
@onready var _party_count: Label = $Layout/Content/LeftColumn/PartyPanel/PartyContent/PartyHeader/PartyCount
@onready var _gold: Label = $Layout/Content/LeftColumn/ResourcesPanel/ResourcesContent/Gold
@onready var _essence: Label = $Layout/Content/LeftColumn/ResourcesPanel/ResourcesContent/Essence
@onready var _items: Label = $Layout/Content/LeftColumn/ResourcesPanel/ResourcesContent/Items
@onready var _reserve: Label = $Layout/Content/LeftColumn/ResourcesPanel/ResourcesContent/Reserve
@onready var _preparation_title: Label = $Layout/Content/PreparationPanel/PreparationContent/PreparationTitle
@onready var _route: Label = $Layout/Content/PreparationPanel/PreparationContent/Route
@onready var _party_summary: Label = $Layout/Content/PreparationPanel/PreparationContent/PartySummary
@onready var _deck_summary: Label = $Layout/Content/PreparationPanel/PreparationContent/DeckSummary
@onready var _launch_hint: Label = $Layout/Content/PreparationPanel/PreparationContent/LaunchHint
@onready var _start_button: Button = $Layout/Content/PreparationPanel/PreparationContent/StartJourney
@onready var _manage_button: Button = $Layout/Content/LeftColumn/PartyPanel/PartyContent/ManageParty

var _active_tab: StringName = &"expedition"

func _ready() -> void:
	for index: int in _tabs.size():
		_tabs[index].pressed.connect(_on_tab_pressed.bind(TAB_IDS[index]))
	_start_button.pressed.connect(_on_start_pressed)
	_manage_button.pressed.connect(_on_manage_pressed)

func render_profile(profile: HeroHubState, expedition: bool, tab: StringName, launch_enabled: bool, launch_hint: String) -> void:
	if profile == null:
		return
	_active_tab = tab if TAB_IDS.has(tab) else &"expedition"
	_render_tabs()
	_render_party(profile)
	_gold.text = "Золото   %d" % profile.gold
	_essence.text = "Эссенция   %d" % profile.essence
	_items.text = "Экипировка   %d" % profile.items.size()
	_reserve.text = "В резерве   %d" % _living_reserve_count(profile)
	var active_count: int = profile.party.size()
	_party_count.text = "%d/%d" % [active_count, HeroHubState.MAX_PARTY]
	_party_summary.text = "Отряд: %d/%d" % [active_count, HeroHubState.MAX_PARTY]
	_route.text = "7 комнат" if expedition else "1 бой"
	_deck_summary.text = _deck_summary_text(profile)
	_launch_hint.text = launch_hint
	_start_button.disabled = not launch_enabled
	if _active_tab == &"expedition":
		_preparation_title.text = "Подготовка к походу" if expedition else "Подготовка к бою"
		_route.visible = true
		_party_summary.visible = true
		_deck_summary.visible = true
		_launch_hint.visible = true
		_start_button.visible = true
		_manage_button.visible = true
	else:
		_render_placeholder_tab()

func _render_party(profile: HeroHubState) -> void:
	# Постоянные три слота не позволяют повторному render накапливать карточки и обработчики.
	while _hero_cards.get_child_count() < HeroHubState.MAX_PARTY:
		_hero_cards.add_child(HERO_CARD.instantiate())
	while _hero_cards.get_child_count() > HeroHubState.MAX_PARTY:
		var excess_card: Node = _hero_cards.get_child(_hero_cards.get_child_count() - 1)
		# Убираем узел сразу, чтобы очередь освобождения не оставляла его в контейнере до конца кадра.
		_hero_cards.remove_child(excess_card)
		excess_card.queue_free()
	for slot: int in HeroHubState.MAX_PARTY:
		var card := _hero_cards.get_child(slot) as PanelContainer
		var name_label := card.get_node("Content/Name") as Label
		var class_label := card.get_node("Content/Class") as Label
		var level_label := card.get_node("Content/Level") as Label
		var portrait := card.get_node("Content/Portrait") as TextureRect
		portrait.texture = null
		class_label.text = ""
		level_label.text = ""
		name_label.tooltip_text = ""
		if slot >= profile.party.size():
			name_label.text = "Свободное место"
			continue
		var hero_id: int = profile.party[slot]
		if not profile.heroes.has(hero_id):
			name_label.text = "Недоступный герой"
			continue
		var hero := profile.heroes[hero_id] as HeroProgression
		if hero == null:
			name_label.text = "Недоступный герой"
			continue
		var definition := HeroCatalog.class_definition(hero.class_id)
		name_label.text = definition.display_name if definition != null else String(hero.class_id)
		name_label.tooltip_text = hero.name
		class_label.text = ""
		level_label.text = "Ур. %d" % hero.level()
		if CLASS_TEXTURES.has(hero.class_id):
			portrait.texture = load(String(CLASS_TEXTURES[hero.class_id])) as Texture2D

func _living_reserve_count(profile: HeroHubState) -> int:
	var count: int = 0
	for hero_id: Variant in profile.heroes:
		if profile.party.has(int(hero_id)):
			continue
		var hero := profile.heroes[hero_id] as HeroProgression
		if hero != null and hero.hp_current > 0.0:
			count += 1
	return count

func _deck_summary_text(profile: HeroHubState) -> String:
	if profile.mage_deck.is_empty():
		return "Колода: Не используется"
	var base_types: Variant = profile.mage_deck.get("base_types", [])
	var count: int = base_types.size() if base_types is Array else 0
	return "Колода: %d карт" % count

func _render_tabs() -> void:
	for index: int in _tabs.size():
		_tabs[index].button_pressed = TAB_IDS[index] == _active_tab

func _render_placeholder_tab() -> void:
	_preparation_title.text = _tab_title(_active_tab)
	_route.visible = false
	_party_summary.visible = false
	_deck_summary.visible = false
	_launch_hint.visible = true
	_launch_hint.text = "Содержание этого раздела готовится."
	_start_button.visible = false
	_manage_button.visible = _active_tab == &"mercenaries"
	if _active_tab == &"mercenaries":
		_preparation_title.text = "Наёмники"
		_launch_hint.text = "Здесь можно управлять составом отряда."
	elif _active_tab == &"smith":
		_preparation_title.text = "Кузнец"
	elif _active_tab == &"schools":
		_preparation_title.text = "Школы"

func _tab_title(tab: StringName) -> String:
	match tab:
		&"mercenaries": return "Наёмники"
		&"smith": return "Кузнец"
		&"schools": return "Школы"
		_: return "Подготовка к походу"

func _on_tab_pressed(tab_id: StringName) -> void:
	tab_requested.emit(tab_id)

func _on_start_pressed() -> void:
	if _start_button.disabled:
		return
	start_requested.emit()

func _on_manage_pressed() -> void:
	manage_requested.emit()
