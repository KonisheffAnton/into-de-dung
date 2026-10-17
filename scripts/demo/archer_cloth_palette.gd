class_name ArcherClothPalette
extends RefCounted

const MASKS: Texture2D = preload("res://assets/art_presets/trials/archer_cloth_v1/cloth_masks.svg")
const ROOT: String = "res://assets/art_presets/trials/archer_idle_v1/idle/"


static func mask_slot(texture: Texture2D) -> int:
	if texture == null or texture is AtlasTexture: return -1
	var path := texture.resource_path
	var prefix := ROOT + "frame-"
	if not path.begins_with(prefix): return -1
	var suffix := path.trim_prefix(prefix)
	var frame := suffix.trim_suffix(".png").to_int()
	if suffix != "%02d.png" % frame or frame < 1 or frame > 12: return -1
	return frame - 1


static func mask_origin(slot: int) -> Vector2:
	return DefenderClothPalette.mask_origin(slot)


static func apply(material: ShaderMaterial, index: int, slot: int) -> void:
	# Палитра повторяет выбор Defender, а отдельная маска захватывает только одежду Archer.
	DefenderClothPalette.apply(material, index, slot)
	material.set_shader_parameter("cloth_masks", MASKS)
