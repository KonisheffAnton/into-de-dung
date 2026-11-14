extends Control
class_name HubPartyPicker

signal hero_selected(hero_id: int)
signal cancelled

const HERO_CARD_SCENE: PackedScene = preload("res://scenes/demo/hub/sections/roster_hero_card.tscn")

@onready var _dialog: PanelContainer = $Dialog
@onready var _heading: Label = $Dialog/Content/Content/HeadingRow/Heading
@onready var _slot_label: Label = $Dialog/Content/Content/SlotLabel
@onready var _close_button: Button = $Dialog/Content/Content/HeadingRow/CloseButton
@onready var _hero_grid: GridContainer = $Dialog/Content/Content/HeroScroll/HeroGrid

var _profile: HeroHubState
var _slot_index: int = -1
var _skins: Dictionary = {}
var _hero_cards: Dictionary[int, HubSkeletonCard] = {}

func _ready() -> void:
	visible = false
	_close_button.pressed.connect(_on_cancel_pressed)
	_close_button.accessibility_name = "Закрыть выбор героя"

func open_for(profile: HeroHubState, slot_index: int, skins: Dictionary) -> void:
	_profile = profile
	_slot_index = slot_index
	_skins = skins.duplicate()
	_rebuild_cards()
	visible = true
	if _hero_cards.has(_current_hero_id()):
		_hero_cards[_current_hero_id()].grab_focus()
	elif _hero_cards.size() > 0:
		var first_card: HubSkeletonCard = _hero_cards.values()[0] as HubSkeletonCard
		first_card.grab_focus()
	else:
		_close_button.grab_focus()

func close() -> void:
	visible = false
	_profile = null
	_hero_cards.clear()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_TAB, KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]:
		var key_event: InputEventKey = event as InputEventKey
		var backwards: bool = key_event.shift_pressed or key_event.keycode in [KEY_LEFT, KEY_UP]
		_focus_next_control(backwards)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var click_position: Vector2 = (event as InputEventMouseButton).position
	if not _dialog.get_global_rect().has_point(click_position):
		cancelled.emit()
		close()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		_on_cancel_pressed()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_node_ready():
		_profile = null
		_hero_cards.clear()

func _rebuild_cards() -> void:
	for child: Node in _hero_grid.get_children():
		_hero_grid.remove_child(child)
		child.queue_free()
	_hero_cards.clear()
	if _profile == null:
		_heading.text = "Выбор героя"
		_slot_label.text = "Нет доступных героев"
		return
	var current_id: int = _current_hero_id()
	var current_hero: HeroProgression = _profile.heroes.get(current_id) as HeroProgression
	_heading.text = "Выберите героя для места %d" % (_slot_index + 1)
	_slot_label.text = "Сейчас: %s" % current_hero.name if current_hero != null else "Текущее место свободно"
	var hero_ids: Array[int] = []
	for key: Variant in _profile.heroes.keys():
		var hero_id: int = int(key)
		var hero: HeroProgression = _profile.heroes.get(hero_id) as HeroProgression
		if hero != null and hero.hp_current > 0.0:
			hero_ids.append(hero_id)
	hero_ids.sort()
	for hero_id: int in hero_ids:
		var hero: HeroProgression = _profile.heroes[hero_id] as HeroProgression
		var card: HubSkeletonCard = HERO_CARD_SCENE.instantiate() as HubSkeletonCard
		card.custom_minimum_size = Vector2(160.0, 148.0)
		var class_definition: HeroClassDefinition = HeroCatalog.class_definition(hero.class_id)
		var class_display_name: String = class_definition.display_name if class_definition != null else String(hero.class_id)
		var membership: String = "Текущий герой" if hero_id == current_id else _membership_label(hero_id)
		card.render_card(str(hero_id), hero.name, "%s · ур. %d" % [class_display_name, hero.level()], membership, HubSkeletonCard.hero_texture(hero.class_id, StringName(_skins.get(hero.class_id, &""))))
		card.set_pressed_no_signal(hero_id == current_id)
		card.tooltip_text = "%s · %s · ур. %d\n%s" % [hero.name, class_display_name, hero.level(), membership]
		var title_label: Label = card.get_node("Title") as Label
		title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		title_label.clip_text = true
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.accessibility_name = "%s, %s" % [hero.name, membership]
		card.selected.connect(_on_card_selected.bind(hero_id))
		_hero_grid.add_child(card)
		_hero_cards[hero_id] = card

func _membership_label(hero_id: int) -> String:
	var party_index: int = _profile.party.find(hero_id)
	if party_index >= 0:
		return "Отряд, место %d" % (party_index + 1)
	return "В резерве"

func _current_hero_id() -> int:
	if _profile == null or _slot_index < 0 or _slot_index >= _profile.party.size():
		return 0
	return _profile.party[_slot_index]

func _on_card_selected(_key: String, hero_id: int) -> void:
	hero_selected.emit(hero_id)

func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()

func _focus_next_control(backwards: bool) -> void:
	var focusable: Array[Control] = []
	for hero_id: int in _hero_cards:
		focusable.append(_hero_cards[hero_id])
	focusable.append(_close_button)
	if focusable.is_empty():
		return
	var current_index: int = focusable.find(get_viewport().gui_get_focus_owner())
	var delta: int = -1 if backwards else 1
	var next_index: int = (current_index + delta + focusable.size()) % focusable.size()
	focusable[next_index].grab_focus()
