class_name CharacterSkinSettings
extends RefCounted

const DEFAULT_PATH := "user://character-skins-v1.cfg"
var selections: Dictionary[StringName, StringName] = CharacterSkinCatalog.normalized({})

func read_file(path: String = DEFAULT_PATH) -> void:
	selections = CharacterSkinCatalog.normalized({})
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("format", "version", 0) != 1:
		# Прерванная замена могла оставить только резервную копию: чтение не стирает выбор.
		config.clear()
		if config.load(path + ".bak") != OK or config.get_value("format", "version", 0) != 1: return
	var values: Dictionary = {}
	for class_id: StringName in selections:
		values[class_id] = config.get_value("skins", String(class_id), "")
	selections = CharacterSkinCatalog.normalized(values)

func choose(class_id: StringName, skin_id: StringName, path: String = DEFAULT_PATH) -> String:
	if not CharacterSkinCatalog.ids(class_id).has(skin_id): return "Этот облик недоступен классу."
	var candidate := selections.duplicate()
	candidate[class_id] = skin_id
	var config := ConfigFile.new()
	config.set_value("format", "version", 1)
	for key: StringName in candidate: config.set_value("skins", String(key), String(candidate[key]))
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	while not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		if FileAccess.file_exists(directory): return "Путь папки обликов занят файлом."
		var parent := directory.get_base_dir()
		if parent == directory: break
		directory = parent
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: return "Не удалось создать папку обликов."
	if config.save(absolute + ".tmp") != OK: return "Не удалось сохранить облик."
	# Публикация следует успешной записи; отказ не меняет текущий рисунок в хабе.
	var existed := FileAccess.file_exists(absolute)
	if existed:
		if FileAccess.file_exists(absolute + ".bak") and DirAccess.remove_absolute(absolute + ".bak") != OK: return "Не удалось обновить резервную копию обликов."
		if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK: return "Не удалось подготовить сохранение облика."
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		if existed and DirAccess.rename_absolute(absolute + ".bak", absolute) != OK:
			return "Не удалось заменить файл обликов; предыдущий выбор сохранён в резервной копии."
		return "Не удалось заменить сохранение облика."
	if existed: DirAccess.remove_absolute(absolute + ".bak")
	selections.assign(candidate)
	return ""
