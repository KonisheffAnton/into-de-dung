extends Control
class_name HostPossessionDialog

signal confirmed(hero_id: int, expected_party: Array[int], expected_host: int, appearance: Dictionary, glow_only: bool)

@onready var _heading: Label = $Dialog/Content/Heading
@onready var _heroes: HBoxContainer = $Dialog/Content/Heroes
@onready var _preview: HostGlowPreview = $Dialog/Content/Body/PreviewColumn/Preview
@onready var _details: Label = $Dialog/Content/Body/DetailsColumn/Details
@onready var _cards: Label = $Dialog/Content/Body/DetailsColumn/Cards
@onready var _colors: OptionButton = $Dialog/Content/Settings/Color
@onready var _forms: OptionButton = $Dialog/Content/Settings/Form
@onready var _flicker: OptionButton = $Dialog/Content/Settings/Flicker
@onready var _confirm: Button = $Dialog/Content/Actions/Confirm
var _profile: HeroHubState
var _skins: Dictionary = {}
var _selected_id: int = 0
var _expected_party: Array[int] = []
var _expected_host: int = 0
var _glow_only: bool = false
const COLOR_IDS: Array[String] = ["amber","blue","violet","white"]
const FORM_IDS: Array[String] = ["glow","flame"]
const FLICKER_IDS: Array[String] = ["still","soft"]

func _ready() -> void:
	visible = false
	for label: String in ["Янтарный","Голубой","Фиолетовый","Белый"]: _colors.add_item(label)
	for label: String in ["Свечение глаз","Язычки пламени"]: _forms.add_item(label)
	for label: String in ["Без мерцания","Мягкое мерцание"]: _flicker.add_item(label)
	for picker: OptionButton in [_colors,_forms,_flicker]: picker.item_selected.connect(func(_index: int) -> void: _refresh())
	($Dialog/Content/Actions/Cancel as Button).pressed.connect(close)
	_confirm.pressed.connect(_on_confirm)

func open_for(profile: HeroHubState, skins: Dictionary, glow_only: bool = false) -> void:
	_profile = profile
	_skins = skins.duplicate()
	_expected_party = profile.party.duplicate()
	_expected_host = int(profile.mage_deck.get("host_hero_id",0))
	_selected_id = _expected_host
	_glow_only = glow_only
	if _selected_id == 0 and not profile.party.is_empty(): _selected_id = profile.party[0]
	var appearance: Dictionary = profile.mage_deck.host_glow
	_colors.select(COLOR_IDS.find(appearance.color))
	_forms.select(FORM_IDS.find(appearance.form))
	_flicker.select(FLICKER_IDS.find(appearance.flicker))
	_heading.text = "Огонёк мага" if glow_only else "Выберите носителя"
	_confirm.text = "Сохранить огонёк" if glow_only else "Вселиться"
	for child: Node in _heroes.get_children():
		_heroes.remove_child(child); child.queue_free()
	for id: int in profile.party:
		var hero: HeroProgression = profile.heroes[id]
		var button := Button.new()
		button.name = "Hero%d" % id
		button.text = hero.name
		button.icon = HubSkeletonCard.hero_texture(hero.class_id,StringName(skins.get(hero.class_id,&"")))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",54)
		button.custom_minimum_size = Vector2(0,68)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.disabled = glow_only and id != _selected_id
		button.pressed.connect(_choose.bind(id))
		button.set_meta(&"hero_id",id)
		_heroes.add_child(button)
	visible = true
	_refresh()
	_confirm.grab_focus()

func close() -> void:
	visible = false
	_profile = null

func _choose(id: int) -> void:
	_selected_id = id
	_refresh()

func _appearance() -> Dictionary:
	return {"color":COLOR_IDS[_colors.selected],"form":FORM_IDS[_forms.selected],"flicker":FLICKER_IDS[_flicker.selected]}

func _refresh() -> void:
	if _profile == null: return
	_confirm.disabled = not _profile.party.has(_selected_id)
	for child: Node in _heroes.get_children():
		(child as Button).set_pressed_no_signal(int(child.get_meta(&"hero_id")) == _selected_id)
	var hero := _profile.heroes.get(_selected_id) as HeroProgression
	if hero == null: return
	_preview.configure(hero.class_id,StringName(_skins.get(hero.class_id,&"")),_appearance())
	_details.text = "%s\n%s · уровень %d · HP %s" % [hero.name,HeroCatalog.class_definition(hero.class_id).display_name,hero.level(),str(hero.max_hp())]
	var lines: PackedStringArray = []
	for type_id: String in ["card.light_step","card.binding_thread"]:
		var count: int = _profile.mage_deck.base_types.count(type_id)
		if count == 0: continue
		var card := MageCardCatalog.get_card(type_id)
		lines.append("%s ×%d\n%s" % [card.name,count,card.description])
	_cards.text = "Карты носителя в вашей колоде:\n" + ("\n\n".join(lines) if not lines.is_empty() else "Пока нет. Добавьте их на странице «Колода».")

func _on_confirm() -> void:
	if _profile == null or _confirm.disabled: return
	confirmed.emit(_selected_id,_expected_party.duplicate(),_expected_host,_appearance(),_glow_only)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		# Модальное окно удерживает клавиатурный обход, не меняя фокус ОС.
		var controls: Array[Control] = []
		for child: Node in _heroes.get_children():
			if not (child as Button).disabled: controls.append(child as Control)
		controls.append_array([_colors,_forms,_flicker,$Dialog/Content/Actions/Cancel,_confirm])
		var index: int = controls.find(get_viewport().gui_get_focus_owner())
		var direction: int = -1 if event.shift_pressed else 1
		controls[posmod(index + direction,controls.size())].grab_focus()
		get_viewport().set_input_as_handled()
