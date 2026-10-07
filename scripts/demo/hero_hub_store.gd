extends RefCounted
class_name HeroHubStore

const MAX_BYTES: int = 1048576

## Файл содержит только значения; повреждённый профиль никогда не заменяется новым молча.
static func read_run(path: String, deck_mode: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"): return {"run":null, "error":"Сохранение прервано. Сохранена резервная копия: " + path + ".bak"}
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var fresh := HeroHubState.create(rng.seed, 2 if deck_mode else 1)
		if deck_mode: fresh.enable_mage_deck()
		return {"run":fresh, "error":""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"run":null, "error":"Не удалось открыть сохранение."}
	if file.get_length() > MAX_BYTES or file.get_length() < 1: return {"run":null, "error":"Неверный размер сохранения."}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var envelope: Variant = bytes_to_var(bytes)
	if not envelope is Dictionary or envelope.keys().size() != 3 or envelope.get("format") not in ["hero-hub-v1","hero-hub-v2","hero-hub-v3","hero-hub-v4","hero-hub-v5"] or not envelope.get("payload") is PackedByteArray or not envelope.get("sha256") is String:
		return {"run":null, "error":"Неизвестный формат сохранения."}
	var payload: PackedByteArray = envelope.payload
	if _digest(payload) != envelope.sha256: return {"run":null, "error":"Сохранение повреждено; контрольная сумма не совпала."}
	var decoded: Variant = bytes_to_var(payload)
	var schemas := {"hero-hub-v1":1,"hero-hub-v2":2,"hero-hub-v3":3,"hero-hub-v4":4,"hero-hub-v5":5}
	if not decoded is Dictionary or decoded.get("schema") != schemas[envelope.format]: return {"run":null,"error":"Версия профиля не совпадает с форматом файла."}
	var expedition: Variant = decoded.get("expedition")
	if expedition is Dictionary and expedition.get("plan") is Dictionary and not ExpeditionRulesRegistry.matches_content(expedition.plan.get("content"),expedition.get("schema") == 3,expedition.plan.get("schema") == 3):
		return {"run":null,"error":"Сохранённый поход использует другую версию или параметры каталога. Файл сохранён без изменений."}
	var run := HeroHubState.from_dict(decoded)
	var migrated: bool = decoded.schema < 3
	if run != null and deck_mode and decoded.schema < 4:
		run.enable_mage_deck(); migrated = true
	return {"run":run, "error":"" if run != null else "Сохранение не соответствует правилам хаба.","migrated":migrated}

static func write_run(path: String, run: HeroHubState) -> String:
	if run == null or HeroHubState.from_dict(run.to_dict()) == null: return "Состояние хаба не прошло проверку."
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: return "Не удалось создать папку сохранения."
	var payload := var_to_bytes(run.to_dict())
	var format := "hero-hub-v5" if run.hero_catalog_version == 2 else ("hero-hub-v4" if not run.mage_deck.is_empty() else "hero-hub-v3")
	var bytes := var_to_bytes({"format":format, "payload":payload, "sha256":_digest(payload)})
	if bytes.size() > MAX_BYTES: return "Превышен размер сохранения."
	var temp := absolute + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return "Не удалось записать временный файл сохранения."
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return "Запись сохранения не завершена."
	var backup := absolute + ".bak"
	var existed := FileAccess.file_exists(absolute)
	if existed:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return "Не удалось обновить резервную копию."
		if DirAccess.rename_absolute(absolute, backup) != OK: return "Не удалось подготовить замену сохранения."
	if DirAccess.rename_absolute(temp, absolute) != OK:
		if existed: DirAccess.rename_absolute(backup, absolute)
		return "Не удалось заменить сохранение."
	if existed: DirAccess.remove_absolute(backup)
	return ""

static func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
