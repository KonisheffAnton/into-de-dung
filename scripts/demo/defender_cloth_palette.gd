class_name DefenderClothPalette
extends RefCounted

const MASKS: Texture2D = preload("res://assets/art_presets/trials/defender_cloth_v1/cloth_masks.svg")
const LABELS: Array[String] = ["Исходная", "Бордовая", "Синяя", "Лесная", "Охра", "Сливовая", "Серая"]
const SHADOWS: Array[Color] = [Color("595a2f"), Color("633440"), Color("354e70"), Color("36553f"), Color("765432"), Color("574165"), Color("495461")]
const LIGHTS: Array[Color] = [Color("858241"), Color("a55b66"), Color("6087b0"), Color("65815b"), Color("b38d51"), Color("9477a0"), Color("86929b")]


static func count() -> int:
	return LABELS.size()


static func valid_index(index: int) -> int:
	return index if index >= 0 and index < count() else 0


static func label(index: int) -> String:
	return LABELS[valid_index(index)]


static func mask_slot(texture: Texture2D) -> int:
	if texture == null: return -1
	var path := texture.resource_path
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		if atlas.atlas != null and atlas.atlas.resource_path == "res://assets/art_presets/trials/defender_field_v1/defender_new.png" \
			and atlas.region == Rect2(89, 206, 1034, 966): return 0
		return -1
	var folders: Array[String] = ["defender_idle_v1/vertical", "defender_idle_v1/sway", "defender_buff_v1", "defender_death_v1"]
	var offsets: Array[int] = [1, 13, 25, 58]
	var lengths: Array[int] = [12, 12, 33, 33]
	for clip: int in folders.size():
		var prefix := "res://assets/art_presets/trials/%s/frame-" % folders[clip]
		if not path.begins_with(prefix): continue
		var suffix := path.trim_prefix(prefix)
		var frame := suffix.trim_suffix(".png").to_int()
		if suffix == "%02d.png" % frame and frame >= 1 and frame <= lengths[clip]:
			return offsets[clip] + frame - 1
	return -1


static func mask_origin(slot: int) -> Vector2:
	return Vector2((slot % 10) * 128, (slot / 10) * 128)


static func apply(material: ShaderMaterial, index: int, slot: int) -> void:
	var selected := valid_index(index)
	material.set_shader_parameter("cloth_enabled", selected != 0 and slot >= 0)
	material.set_shader_parameter("cloth_masks", MASKS)
	material.set_shader_parameter("cloth_mask_origin", mask_origin(maxi(0, slot)))
	material.set_shader_parameter("cloth_shadow", SHADOWS[selected])
	material.set_shader_parameter("cloth_light", LIGHTS[selected])
