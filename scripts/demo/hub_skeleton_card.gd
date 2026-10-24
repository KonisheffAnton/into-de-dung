extends Button
class_name HubSkeletonCard

signal selected(key: String)

var selection_key: String = ""

func _ready() -> void:
	pressed.connect(_on_pressed)

func render_card(key: String, title: String, subtitle: String = "", detail: String = "", portrait: Texture2D = null) -> void:
	selection_key = key
	disabled = key.is_empty()
	# Узлы принадлежат сцене: обновляем данные, не возвращаем удалённые поля и их разметку.
	for child: Node in find_children("*", "", true, false):
		match String(child.get_meta(&"hub_field", "")):
			"title":
				if child is Label: (child as Label).text = title
			"subtitle":
				if child is Label: (child as Label).text = subtitle
			"detail":
				if child is Label: (child as Label).text = detail
			"portrait":
				if child is TextureRect: (child as TextureRect).texture = portrait

static func hero_texture(class_id: StringName) -> Texture2D:
	if class_id == &"mage": return load("res://assets/placeholder_battle/mage_card.svg") as Texture2D
	var path := "res://assets/ui/hub/%s_portrait.tres" % String(class_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _on_pressed() -> void:
	if not disabled and not selection_key.is_empty(): selected.emit(selection_key)
