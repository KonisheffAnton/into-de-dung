extends Control

@export var save_path: String = "user://hero-hub-v1.save"
@export var mage_deck_mode: bool = true

func _ready() -> void:
	var background := ColorRect.new(); background.color = Color("111a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	var column := VBoxContainer.new(); column.custom_minimum_size.x = 500; column.add_theme_constant_override("separation",24); center.add_child(column)
	var title := Label.new(); title.text = "intoDeDung"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",48); column.add_child(title)
	var subtitle := Label.new(); subtitle.text = "Соберите отряд. Выберите путь. Вернитесь с добычей."; subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; column.add_child(subtitle)
	var begin := Button.new(); begin.name = "continue_game"; begin.text = "Продолжить · хаб и поход"; begin.custom_minimum_size.y = 56; begin.pressed.connect(_open_hub); column.add_child(begin)

func _open_hub() -> void:
	for child: Node in get_children(): remove_child(child); child.queue_free()
	var hub := HeroHubScreen.new(); hub.name = "ExpeditionHub"; hub.expedition_mode = true; hub.save_path = save_path
	hub.mage_deck_mode = mage_deck_mode
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(hub)
