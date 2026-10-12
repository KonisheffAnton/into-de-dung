class_name RogueClothPalette
extends RefCounted

const MASKS: Texture2D = preload("res://assets/art_presets/trials/rogue_cloth_v1/cloth_masks.svg")
const ROOT: String = "res://assets/art_presets/trials/rogue_animations_v1/"


static func mask_slot(texture: Texture2D) -> int:
	if texture == null or texture is AtlasTexture: return -1
	var path := texture.resource_path
	if path == ROOT + "still.png": return 0
	var folders: Array[String] = ["idle", "buff", "death"]
	var offsets: Array[int] = [1, 13, 19]
	var lengths: Array[int] = [12, 6, 13]
	for clip: int in folders.size():
		var prefix := ROOT + folders[clip] + "/frame-"
		if not path.begins_with(prefix): continue
		var suffix := path.trim_prefix(prefix)
		var frame := suffix.trim_suffix(".png").to_int()
		if suffix == "%02d.png" % frame and frame >= 1 and frame <= lengths[clip]:
			return offsets[clip] + frame - 1
	return -1


static func mask_origin(slot: int) -> Vector2:
	return DefenderClothPalette.mask_origin(slot)


static func apply(material: ShaderMaterial, index: int, slot: int) -> void:
	# Общая гамма HUD, но отдельный атлас: кожа и кинжалы не принадлежат ткани.
	DefenderClothPalette.apply(material, index, slot)
	material.set_shader_parameter("cloth_masks", MASKS)
