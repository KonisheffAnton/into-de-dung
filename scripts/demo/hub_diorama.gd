extends Control
class_name HubDiorama

@export var motion_enabled: bool = true
@export var figure_scale: float = 0.65
@onready var _figures: Control = $Figures
@onready var _motion: CheckButton = $Motion
var _skins: Array[CharacterSkinDefinition] = []
var _clock: float = 0.0

func _ready() -> void:
	_motion.set_pressed_no_signal(motion_enabled)
	_motion.toggled.connect(_on_motion_toggled)
	resized.connect(_layout_figures)
	_sync_motion()

func render_profile(profile: HeroHubState, selections: Dictionary) -> void:
	_skins.clear()
	while _figures.get_child_count() > profile.party.size():
		var removed := _figures.get_child(_figures.get_child_count() - 1)
		_figures.remove_child(removed)
		removed.queue_free()
	while _figures.get_child_count() < profile.party.size():
		var figure := Sprite2D.new()
		figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		figure.centered = false
		_figures.add_child(figure)
	for index: int in profile.party.size():
		var hero := profile.heroes.get(profile.party[index]) as HeroProgression
		var figure := _figures.get_child(index) as Sprite2D
		figure.set_meta(&"hero_id", profile.party[index])
		var skin: CharacterSkinDefinition = null
		if hero != null: skin = CharacterSkinCatalog.definition(hero.class_id, StringName(selections.get(hero.class_id, &"")))
		_skins.append(skin)
		figure.texture = skin.still if skin != null else HubSkeletonCard.hero_texture(hero.class_id) if hero != null else null
		figure.offset = -skin.anchor if skin != null else -Vector2(64.0, 104.0)
		figure.flip_h = skin != null and skin.source_facing_x < 0
		figure.scale = Vector2.ONE * figure_scale
	_layout_figures()
	_sync_motion()

func _layout_figures() -> void:
	if not is_node_ready(): return
	var count := _figures.get_child_count()
	var columns := mini(3, maxi(1, count))
	var rows := ceili(float(count) / columns)
	var spacing := minf(132.0, size.x / (columns + 0.3))
	for index: int in count:
		var row := index / columns
		var row_count := mini(columns, count - row * columns)
		var x := size.x * 0.5 + (index % columns - (row_count - 1) * 0.5) * spacing
		var y := size.y * 0.70 + (row - (rows - 1) * 0.5) * 126.0
		(_figures.get_child(index) as Sprite2D).position = Vector2(roundf(x), roundf(y))

func _on_motion_toggled(enabled: bool) -> void:
	motion_enabled = enabled
	_sync_motion()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready(): _sync_motion()

func _sync_motion() -> void:
	set_process(motion_enabled and is_visible_in_tree())
	if not is_node_ready() or motion_enabled: return
	for index: int in _skins.size():
		if _skins[index] != null: (_figures.get_child(index) as Sprite2D).texture = _skins[index].still

func _process(delta: float) -> void:
	# Локальные часы представления: скрытый экран не тикает и не читает боевую сессию/RNG.
	_clock = fmod(_clock + delta, 3600.0)
	for index: int in _skins.size():
		var skin := _skins[index]
		if skin == null or not skin.clip_valid(&"idle"): continue
		var frames := skin.animations
		var at := fmod(_clock + index * 0.7, skin.clip_duration(&"idle")) * frames.get_animation_speed(&"idle")
		var selected := 0
		for frame: int in frames.get_frame_count(&"idle"):
			at -= frames.get_frame_duration(&"idle", frame)
			selected = frame
			if at < 0.0: break
		(_figures.get_child(index) as Sprite2D).texture = frames.get_frame_texture(&"idle", selected)
