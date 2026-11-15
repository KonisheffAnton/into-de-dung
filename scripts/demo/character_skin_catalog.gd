class_name CharacterSkinCatalog
extends RefCounted

const ROOT := "res://assets/art_presets/approved/character_skins_v1/"
static var _loaded: Dictionary[StringName, CharacterSkinDefinition] = {}

static func ids(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"shieldbearer": return [&"watch_shield", &"grey_bastion"]
		&"fighter": return [&"red_bastion"]
		&"rogue": return [&"short_cape"]
		&"mage": return [&"star_hood"]
		&"archer": return [&"silver_ranger"]
		&"sick_hobgoblin": return [&"sick_hobgoblin"]
	return []

static func resolve_id(class_id: StringName, requested: StringName = &"") -> StringName:
	var available := ids(class_id)
	if available.is_empty(): return &""
	return requested if available.has(requested) else available[0]

static func definition(class_id: StringName, requested: StringName = &"") -> CharacterSkinDefinition:
	var skin_id := resolve_id(class_id, requested)
	if skin_id == &"": return null
	if not _loaded.has(skin_id):
		var path := ROOT + String(skin_id) + "/skin.tres"
		if not ResourceLoader.exists(path): return null
		var resource := load(path) as CharacterSkinDefinition
		if resource == null or resource.id != skin_id or resource.class_id != class_id: return null
		# В кэш попадает целый облик: частичный пакет не должен скрывать рабочую fallback-модель.
		if resource.still == null: return null
		for animation: StringName in [&"idle", &"buff", &"death"]:
			if not resource.clip_valid(animation): return null
		if skin_id in [&"watch_shield", &"star_hood", &"silver_ranger", &"sick_hobgoblin"] and not resource.clip_valid(&"idle_secondary"):
			return null
		_loaded[skin_id] = resource
	return _loaded[skin_id]

static func normalized(values: Dictionary) -> Dictionary[StringName, StringName]:
	var result: Dictionary[StringName, StringName] = {}
	for class_id: StringName in [&"shieldbearer", &"fighter", &"rogue", &"mage", &"archer"]:
		var value: Variant = values.get(class_id, &"")
		result[class_id] = resolve_id(class_id, StringName(value) if value is String or value is StringName else &"")
	return result
