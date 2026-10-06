extends Control

static var _temporary_profile_counter: int = 0

@export var save_path: String = "user://hero-hub-v1.save"
@export var mage_deck_mode: bool = true
@export var temporary_profile: bool = true

var _owned_temporary_save_path: String = ""
var _hub_opened: bool = false

func _ready() -> void:
	var continue_button: Button = $CenterContainer/VBoxContainer/continue_game
	var profile_hint: Label = $CenterContainer/VBoxContainer/TestProfileHint
	if temporary_profile:
		_owned_temporary_save_path = _make_temporary_save_path()
		save_path = _owned_temporary_save_path
		continue_button.text = "Начать тест · хаб и поход"
		profile_hint.text = "Тестовый прогресс сбрасывается после выхода."
	else:
		continue_button.text = "Продолжить · хаб и поход"
		profile_hint.text = "Прогресс сохраняется между запусками."
	continue_button.pressed.connect(_open_hub)

func _make_temporary_save_path() -> String:
	var base_name: String = "user://hero-hub-playtest-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var counter: int = _temporary_profile_counter
	var candidate: String = "%s-%d.save" % [base_name, counter]
	while _temporary_profile_path_exists(candidate):
		counter += 1
		candidate = "%s-%d.save" % [base_name, counter]
	# Счётчик разводит меню, созданные в одном кадре до появления файла сохранения.
	_temporary_profile_counter = counter + 1
	return candidate

func _temporary_profile_path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")

func _exit_tree() -> void:
	if _owned_temporary_save_path.is_empty():
		return
	for path: String in [_owned_temporary_save_path, _owned_temporary_save_path + ".bak", _owned_temporary_save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if error != OK:
				push_warning("Не удалось удалить временный профиль плейтеста: %s (%s)" % [path, error_string(error)])

func _open_hub() -> void:
	if _hub_opened:
		return
	_hub_opened = true
	for child: Node in get_children(): remove_child(child); child.queue_free()
	var hub: HeroHubScreen = load("res://scenes/demo/hero_hub.tscn").instantiate() as HeroHubScreen
	hub.name = "ExpeditionHub"; hub.expedition_mode = true; hub.save_path = save_path
	hub.mage_deck_mode = mage_deck_mode
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(hub)
