extends Control

@export var save_path: String = "user://hero-hub-v1.save"
@export var mage_deck_mode: bool = true

func _ready() -> void:
	var continue_button: Button = $CenterContainer/VBoxContainer/continue_game
	continue_button.pressed.connect(_open_hub)

func _open_hub() -> void:
	for child: Node in get_children(): remove_child(child); child.queue_free()
	var hub: HeroHubScreen = load("res://scenes/demo/hero_hub.tscn").instantiate() as HeroHubScreen
	hub.name = "ExpeditionHub"; hub.expedition_mode = true; hub.save_path = save_path
	hub.mage_deck_mode = mage_deck_mode
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(hub)
