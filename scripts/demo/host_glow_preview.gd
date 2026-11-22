extends Control
class_name HostGlowPreview

var skin: CharacterSkinDefinition
var style: Dictionary = {}
var elapsed: float = 0.0

func configure(class_id: StringName, skin_id: StringName, appearance: Dictionary) -> void:
	skin = CharacterSkinCatalog.definition(class_id,skin_id)
	style = appearance.duplicate(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed += delta
	if style.get("flicker","soft") == "soft": queue_redraw()

func _draw() -> void:
	if skin == null: return
	var points := HostGlowAppearance.eyes(skin.id,skin.still)
	var full_origin := Vector2(8,12)
	# Авторская фигура art_trial_unit.tscn использует масштаб тела 0.8 при zoom100%.
	var scale_value: float = skin.texture_scale * 0.8 * (0.9 if skin.class_id == &"archer" else 1.0)
	draw_texture_rect(skin.still,Rect2(full_origin,skin.still.get_size()*scale_value),false)
	HostGlowAppearance.paint(self,points,style,elapsed,full_origin,scale_value)
	var face_origin := Vector2(154,12)
	var face := Rect2(105,55,64,64)
	draw_texture_rect_region(skin.still,Rect2(face_origin,Vector2(192,192)),face)
	HostGlowAppearance.paint(self,points,style,elapsed,face_origin-face.position*3.0,3.0)
