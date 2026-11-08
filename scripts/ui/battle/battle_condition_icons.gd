class_name BattleConditionIcons
extends RefCounted

const IDS: Array[StringName] = [
	&"bleeding",
	&"burning",
	&"poison",
	&"acid",
	&"stunned",
	&"entangled",
	&"frozen",
	&"wet",
	&"shield",
	&"raised_shield",
	&"opportunist",
	&"counterattack",
	&"cover",
	&"pending",
	&"fire_on_tile",
	&"acid_pool",
	&"spikes",
	&"corpse",
	&"collapse_warning",
	&"floor_trap",
	&"wall_trap",
	&"deep_acid",
	&"void",
	&"hazard",
]

const _ICON_ROOT: String = "res://assets/art_presets/approved/status_icons_silhouette_v1"
const _FRAMED_ROOT: String = "res://assets/art_presets/approved/status_icons_silhouette_v1/framed"

static var _texture_cache: Dictionary[String, Texture2D] = {}


static func texture(id: StringName, pixels: int = 16, framed: bool = true) -> Texture2D:
	if not IDS.has(id):
		return null
	var native_size: int = 16 if pixels <= 16 else 32
	var path: String = "%s/%d/%s.png" % [_FRAMED_ROOT if framed else _ICON_ROOT, native_size, String(id)]
	if _texture_cache.has(path):
		return _texture_cache[path]
	var loaded: Texture2D = load(path) as Texture2D
	if loaded != null:
		_texture_cache[path] = loaded
	return loaded


static func bbcode(id: StringName, pixels: int = 16) -> String:
	if not IDS.has(id):
		return ""
	var display_size: int = clampi(pixels, 16, 32)
	var native_size: int = 16 if display_size == 16 else 32
	var path: String = "%s/%d/%s.png" % [_FRAMED_ROOT, native_size, String(id)]
	return "[img=%dx%d]%s[/img]" % [display_size, display_size, path]


static func inline_icons(ids: Array[StringName], pixels: int = 16) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for id: StringName in ids:
		if seen.has(id):
			continue
		seen[id] = true
		var icon: String = bbcode(id, pixels)
		if not icon.is_empty():
			parts.append(icon)
	# Пробел отделяет соседние значки в BBCode и сохраняет читаемость строки.
	return " ".join(parts)
