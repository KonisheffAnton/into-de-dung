extends ScrollContainer
class_name HubSquadList

signal slot_selected(slot_index: int)
signal reorder_requested(hero_id: int, target_index: int, expected_party: Array[int])

const CARD: PackedScene = preload("res://scenes/demo/hub/squad_card.tscn")
@export var edge_zone: float = 40.0
@export var scroll_speed: float = 360.0
@export var insertion_color: Color = Color(0.96, 0.75, 0.33)
@onready var _cards: VBoxContainer = $Cards
@onready var _insertion: ColorRect = $DragLayer/Insertion
var _expected_party: Array[int] = []
var _indicator_y: float = -1.0
var _scroll_fraction: float = 0.0

func _ready() -> void:
	set_process(false)

func render_profile(profile: HeroHubState, skins: Dictionary) -> void:
	_expected_party = profile.party.duplicate()
	var count := profile.party.size() + (1 if profile.party.size() < HeroHubState.MAX_PARTY else 0)
	while _cards.get_child_count() > count:
		var removed := _cards.get_child(_cards.get_child_count() - 1)
		_cards.remove_child(removed)
		removed.queue_free()
	while _cards.get_child_count() < count:
		var added := CARD.instantiate() as HubSquadCard
		_cards.add_child(added)
		added.slot_selected.connect(_on_slot_selected)
		added.move_requested.connect(_on_keyboard_move)
		added.drop_check = _can_drop_global
		added.drop_request = _drop_global
	for index: int in count:
		var card := _cards.get_child(index) as HubSquadCard
		card.slot_index = index
		card.hero_id = profile.party[index] if index < profile.party.size() else 0
		var hero := profile.heroes.get(card.hero_id) as HeroProgression
		var title := card.get_node("Name") as Label
		var identity := card.get_node("Identity") as Label
		var state := card.get_node("State") as Label
		var portrait := card.get_node("Portrait") as TextureRect
		card.drag_context = {"kind": "hub_party", "list_id": get_instance_id(), "hero_id": card.hero_id, "expected": _expected_party.duplicate()}
		title.text = hero.name if hero != null else "Добавить героя"
		identity.text = ""
		state.text = ""
		var flame := card.get_node("HostBadge") as TextureRect
		flame.visible = false
		state.offset_left = 10.0
		portrait.texture = null
		if hero == null:
			card.tooltip_text = "Выбрать героя из своего отряда и резерва"
			continue
		var definition := HeroCatalog.class_definition(hero.class_id)
		identity.text = "%s · ур. %d" % [definition.display_name, hero.level()]
		portrait.texture = HubSkeletonCard.hero_texture(hero.class_id, StringName(skins.get(hero.class_id, &"")))
		var notices: Array[String] = []
		if int(profile.mage_deck.get("host_hero_id",0)) == hero.id:
			notices.append("Носитель")
			flame.visible = true
			state.offset_left = 29.0
		if hero.available_points() > 0: notices.append("+%d очк." % hero.available_points())
		state.text = " · ".join(notices)
		card.tooltip_text = "%s\n%s\n%s\nКлик: выбрать героя. Перетаскивание или Alt+↑/↓: порядок." % [hero.name, identity.text, state.text]

func focus_slot(index: int) -> void:
	if index < 0 or index >= _cards.get_child_count() or not is_visible_in_tree(): return
	var card := _cards.get_child(index) as Control
	ensure_control_visible(card)
	card.grab_focus()

func _on_slot_selected(index: int) -> void:
	if is_visible_in_tree(): slot_selected.emit(index)

func _on_keyboard_move(hero_id: int, direction: int) -> void:
	var index := _expected_party.find(hero_id)
	var target := index + direction
	if not is_visible_in_tree() or index < 0 or target < 0 or target >= _expected_party.size(): return
	reorder_requested.emit(hero_id, target, _expected_party.duplicate())
	call_deferred("focus_slot", target)

func _owns_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "hub_party" and data.get("list_id") == get_instance_id() and data.get("expected") == _expected_party and _expected_party.has(int(data.get("hero_id", 0)))

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _can_drop_global(get_global_rect().position + at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	_drop_global(get_global_rect().position + at_position, data)

func _can_drop_global(point: Vector2, data: Variant) -> bool:
	if not is_visible_in_tree() or not _owns_drag(data) or not get_global_rect().has_point(point): return false
	_insertion_boundary(point)
	return true

func _insertion_boundary(point: Vector2) -> int:
	var boundary := _expected_party.size()
	for index: int in _expected_party.size():
		var rect := (_cards.get_child(index) as Control).get_global_rect()
		if point.y < rect.get_center().y:
			boundary = index
			break
	var marker: float = 0.0
	if boundary < _expected_party.size(): marker = (_cards.get_child(boundary) as Control).get_global_rect().position.y - 3.0
	elif boundary > 0: marker = (_cards.get_child(boundary - 1) as Control).get_global_rect().end.y + 3.0
	_indicator_y = clampf(marker - get_global_rect().position.y, 2.0, size.y - 2.0)
	_insertion.color = insertion_color
	_insertion.position = get_global_rect().position + Vector2(3.0, _indicator_y - 1.5)
	_insertion.size = Vector2(maxf(1.0, size.x - 19.0), 3.0)
	_insertion.visible = true
	return boundary

func _drop_global(point: Vector2, data: Variant) -> void:
	if not _can_drop_global(point, data): return
	var source := _expected_party.find(int(data.hero_id))
	var boundary := _insertion_boundary(point)
	var target := clampi(boundary - (1 if source < boundary else 0), 0, _expected_party.size() - 1)
	if target != source: reorder_requested.emit(int(data.hero_id), target, _expected_party.duplicate())
	call_deferred("focus_slot", target)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN: set_process(true)
	elif what == NOTIFICATION_DRAG_END:
		set_process(false)
		_indicator_y = -1.0
		_scroll_fraction = 0.0
		if is_node_ready(): _insertion.hide()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		if is_node_ready(): _insertion.hide()
		if is_inside_tree() and _owns_drag(get_viewport().gui_get_drag_data()): get_viewport().gui_cancel_drag()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _owns_drag(get_viewport().gui_get_drag_data()):
		get_viewport().gui_cancel_drag()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _owns_drag(get_viewport().gui_get_drag_data()): return
	var pointer := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(pointer):
		_indicator_y = -1.0
		_insertion.hide()
		return
	var direction := 0.0
	if pointer.y < edge_zone: direction = -(1.0 - pointer.y / edge_zone)
	elif pointer.y > size.y - edge_zone: direction = 1.0 - (size.y - pointer.y) / edge_zone
	_scroll_fraction += direction * scroll_speed * delta
	var movement := int(_scroll_fraction)
	_scroll_fraction -= movement
	scroll_vertical += movement
	_insertion_boundary(get_global_mouse_position())
