extends Control
class_name BattleDemoBoard

@export var authored_layout: bool = false

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cancel_requested()
signal displayed_unit_hovered(unit_id: int)

const CYAN := Color("65dfcc")
const GOLD := Color("f7c97d")
const MUTED := Color("a5b3c5")
var session: BattleDemoSession
var execution_pending: bool = false
@export var camera_controls_enabled: bool = false
var forecast_wheel_handler: Callable
var camera_view := BattleBoardCamera.new()
var _camera_dragging: bool = false
var _camera_gesture_active: bool = false
var _camera_press_position: Vector2 = Vector2.ZERO
var _camera_last_position: Vector2 = Vector2.ZERO
var _camera_max_displacement: float = 0.0
var _camera_reset: Button
var _camera_layout_size := Vector2.ZERO
var attack_mode: bool = false
var retreat_mode: bool = false
var summoning_mode: bool = false
var raising_mode: bool = false
var environment_mode: bool = false
var elemental_mode: bool = false
var inspected_id: int = UnitId.NONE
var displayed_selected_id: int = UnitId.NONE
var acting_id: int = UnitId.NONE
var hovered_unit_id: int = UnitId.NONE
var compact_forecast: BattleForecastCard
var hover_cell := Vector2i(-1, -1)
var grid_config := IsoGridConfig.new()
var _reachable: Dictionary = {}
var inspection_cells: Dictionary = {}
var reaction_zone_cells: Array[Vector2i] = []
var action_areas: Array[Dictionary] = []
var area_preview_owner: int = UnitId.NONE
const ALLY_AREA := Color("64cb8c")
const ENEMY_AREA := Color("e97979")
var cover_target_ids: Array[int] = []
var sneak_threat_ids: Array[int] = []
var forecast: AttackForecast
var move_forecast: MoveForecast
var move_forecast_pending: bool = false
var pending_move_path: Array[Vector2i] = []
var _path: Array[Vector2i] = []
var _tiles: Node2D
var _entities: Node2D
var _overlay: Node2D
var _ghosts: Node2D
var _numbers: Node2D
var _impacts: Node2D
var _pending_strikes: Dictionary = {}
var _action_offsets: Dictionary = {}
var _falling: Dictionary = {}
var _fallen_ids: Dictionary = {}
var _shown_board: BattleBoard
var _tile_visuals: Array[BattleDemoIsoVisual] = []
var _entity_visuals: Array[BattleDemoIsoVisual] = []
const DEFAULT_TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/placeholder_tile.tscn")
var _terrain_visuals: Dictionary[Vector3i, BattleDemoIsoVisual] = {}
var _terrain_board_id: int = 0
var _terrain_size: Vector2i = Vector2i.ZERO
var _terrain_scene: PackedScene
var _unit_visuals: Dictionary[int, BattleManagedUnitVisual] = {}
var _unit_board_id: int = 0
var _unit_session_id: int = 0
var _unit_size: Vector2i = Vector2i.ZERO
var _unit_scene: PackedScene
var _terrain_screen_transform := Transform2D.IDENTITY
var _visual_lifecycle: Dictionary[String, int] = {
	"terrain_created": 0, "terrain_retired": 0,
	"environment_created": 0, "environment_retired": 0,
	"unit_created": 0, "unit_retired": 0,
}
var _view_width: int = 0
var _view_height: int = 0
var _view_heights: PackedInt32Array = PackedInt32Array()
var _view_terrain: PackedByteArray = PackedByteArray()
var _view_units: Array[Dictionary] = []
var _view_actor_classes: Dictionary = {}
var _view_visual_classes: Dictionary[int, StringName] = {}
var _view_fires: Array[Dictionary] = []
var _view_hazards: Dictionary = {}
var _view_corpses: Array[Dictionary] = []
var _view_collapse: Array[Vector2i] = []
const DEFAULT_ENVIRONMENT_SCENE: PackedScene = preload("res://scenes/demo/visuals/environment_overlay.tscn")
var environment_visual_scene: PackedScene = DEFAULT_ENVIRONMENT_SCENE
var _environment_visuals: Dictionary = {}
var _environment_scene: PackedScene
var _field_presentation := BattleFieldPresentation.new()
var _warning_phase: float = 0.0
## Сменяемая временная фигура; будущая сцена может использовать AnimationPlayer/AnimatedSprite2D.
@export var unit_visual_scene: PackedScene = preload("res://scenes/demo/visuals/placeholder_unit.tscn")
@export var tile_visual_scene: PackedScene = DEFAULT_TILE_SCENE
const MOVE_SEGMENT_SECONDS: float = 0.08
const FORCED_MOVE_SEGMENT_SECONDS: float = 0.10
const STRIKE_WINDUP_SECONDS: float = 0.10
const STRIKE_LUNGE_SECONDS: float = 0.025
const STRIKE_LUNGE_DISTANCE: float = 32.0
const POUNCE_PREPARE_SECONDS: float = 0.10
const POUNCE_JUMP_SECONDS: float = 0.12
const POUNCE_PREPARE_DISTANCE: float = -10.0
const POUNCE_CONTACT_DISTANCE: float = 32.0
const POUNCE_PREPARE_LIFT: float = 3.0
const POUNCE_JUMP_ARC_HEIGHT: float = 18.0
const HIT_STOP_SECONDS: float = 0.035
const STRIKE_RECOVERY_SECONDS: float = 0.20
const NORMAL_RECOIL_DISTANCE: float = 18.0
const CRITICAL_RECOIL_DISTANCE: float = 24.0
const CRITICAL_SHAKE_DISTANCE: float = 8.0
const CRITICAL_SHAKE_CYCLES: float = 3.0
const SHOT_WINDUP_SECONDS: float = 0.10
const OBSTACLE_APPROACH_SECONDS: float = 0.07
const OBSTACLE_HOLD_SECONDS: float = 0.05
const OBSTACLE_RECOVERY_SECONDS: float = 0.20
var number_scene: PackedScene = preload("res://scenes/demo/visuals/result_number.tscn")
var impact_scene: PackedScene = preload("res://scenes/demo/visuals/hit_impact.tscn")
var projectile_scene: PackedScene = preload("res://scenes/demo/visuals/shot_projectile.tscn")
var mage_scene: PackedScene = preload("res://scenes/demo/visuals/mage_delivery.tscn")
var support_effect_scene: PackedScene = preload("res://scenes/demo/visuals/support_effect.tscn")
var reaction_scene: PackedScene = preload("res://scenes/demo/visuals/reaction_cue.tscn")
const REACTION_CUE_SECONDS: float = 0.18
var _reaction_cues: Array[BattlePresentationReaction] = []
var _mage_effect: BattlePresentationMage
var _mage_target_id: int = UnitId.NONE
var _mage_target_cell: Vector2i = Vector2i(-1, -1)
var _mage_spell_id: StringName = &""
var _mage_recoil_direction: Vector2 = Vector2.ZERO
var _mage_dying: bool = false
var _support_effect: BattleSupportEffect
var _support_kind: StringName = &""
var _support_actor_id: int = UnitId.NONE
var _support_target_cell: Vector2i = Vector2i(-1, -1)
var _support_target_id: int = UnitId.NONE
var _support_started: bool = false

func show_presentation_state(value: Dictionary) -> void:
	clear_presentation_effects()
	_field_presentation.clear()
	action_areas.assign(value.get("action_areas", []).duplicate(true))
	area_preview_owner = UnitId.NONE
	_view_width = int(value.get("width", 0))
	_view_height = int(value.get("height", 0))
	_view_heights = value.get("heights", PackedInt32Array()).duplicate()
	_view_terrain = value.get("terrain", PackedByteArray()).duplicate()
	_view_units.clear()
	for row: Dictionary in value.get("units", {}).values():
		var view := BattleUnitView.new()
		view.id = row.id
		view.debug_name = row.name
		view.faction = int(row.faction) as Faction.Type
		view.alive = row.alive
		view.hp = row.hp
		view.hp_max = row.hp_max
		view.balance = row.balance
		view.balance_max = row.balance_max
		_view_units.append({"unit": view, "cell": row.cell, "selected": view.id == displayed_selected_id,
			"attack_range": float(row.get("attack_range", 1.0)),
			"shield": row.get("shield", {}).duplicate(true), "pending": bool(row.get("pending", false)),
			"raised_shield": row.get("raised_shield", {}).duplicate(true),
			"inspected": false, "show_rear": false, "armor": row.armor.duplicate(true),
			"statuses": BattleStatusPresentation.entries(row), "resources": _presentation_resources(row),
			"reaction_view": row.get("reaction_view", {}).duplicate(true)})
	_view_fires.assign(value.get("fires", []).duplicate(true))
	_view_hazards = value.get("hazards", {}).duplicate(true)
	_view_corpses.assign(value.get("corpses", []).duplicate(true))
	_view_collapse.assign(value.get("collapse", {}).get("marked", []).duplicate(true))
	_reachable.clear()
	inspection_cells.clear()
	reaction_zone_cells.clear()
	cover_target_ids.clear()
	sneak_threat_ids.clear()
	_path.clear()
	_rebuild_visuals()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

static func presentation_status(row: Dictionary) -> String:
	return BattleStatusPresentation.summary(BattleStatusPresentation.entries(row))

static func _presentation_resources(row: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["main", "bonus", "move", "reaction"]:
		if row.has(key): result[key] = row[key]
	return result

func clear_presentation_effects() -> void:
	_clear_layer(_ghosts)
	_reaction_cues.clear()
	if _mage_target_id != UnitId.NONE: _set_action_offset(_mage_target_id, Vector2.ZERO)
	if is_instance_valid(_mage_effect):
		remove_child(_mage_effect)
		_mage_effect.free()
	_mage_effect = null
	_mage_target_id = UnitId.NONE
	_mage_target_cell = Vector2i(-1, -1)
	_mage_spell_id = &""
	_mage_recoil_direction = Vector2.ZERO
	_mage_dying = false
	if is_instance_valid(_support_effect):
		remove_child(_support_effect)
		_support_effect.free()
	_support_effect = null
	_support_kind = &""
	_support_actor_id = UnitId.NONE
	_support_target_cell = Vector2i(-1, -1)
	_support_target_id = UnitId.NONE
	_support_started = false

func clear_strike_poses() -> void:
	_pending_strikes.clear()
	_action_offsets.clear()
	for visual: BattleDemoIsoVisual in _entity_visuals: visual.action_offset = Vector2.ZERO

func clear_presentation_feedback() -> void:
	clear_presentation_effects()
	clear_strike_poses()
	_field_presentation.clear()
	_rebuild_visuals()
	_clear_layer(_numbers)
	_clear_layer(_impacts)

static func _strike_key(event: Dictionary) -> String:
	return "%d:%d" % [int(event.get("root_id", 0)), int(event.get("event_seq", 0))]

func _strike_direction(event: Dictionary) -> Vector2:
	var from: Vector2i = event.actor_cell
	var to: Vector2i = event.target_cell
	return IsoGridUtils.grid_direction_to_screen(to - from, grid_config.tile_size)

func _set_action_offset(id: int, offset: Vector2) -> void:
	_action_offsets[id] = offset
	var visual := _presentation_visual(id)
	if visual != null: visual.action_offset = offset * grid_config.tile_size.x / 128.0

func _obstacle_direction(event: Dictionary) -> Vector2:
	var from_cell: Vector2i = event.get("from_cell", Vector2i.ZERO)
	var attempted_cell: Vector2i = event.get("attempted_cell", from_cell)
	var delta := attempted_cell - from_cell
	return IsoGridUtils.grid_direction_to_screen(delta, grid_config.tile_size)

func _obstacle_participant_alive(id: int) -> bool:
	for row: Dictionary in _view_units:
		var unit := row.get("unit") as BattleUnitView
		if unit != null and unit.id == id:
			return unit.alive and _presentation_visual(id) != null
	return false

func _obstacle_approach(progress: float, event: Dictionary) -> void:
	var target_id := int(event.get("target_unit_id", UnitId.NONE))
	if not _obstacle_participant_alive(target_id): return
	_set_action_offset(target_id, _obstacle_direction(event) * 28.0 * clampf(progress, 0.0, 1.0))

func _obstacle_recovery(progress: float, event: Dictionary) -> void:
	var amount := clampf(progress, 0.0, 1.0)
	var direction := _obstacle_direction(event)
	var recovery_curve := cos(amount * TAU) * pow(1.0 - amount, 2.0)
	var target_id := int(event.get("target_unit_id", UnitId.NONE))
	if _obstacle_participant_alive(target_id):
		# Затухающая отдача остаётся только в рисунке тела и точно сходит к нулю.
		_set_action_offset(target_id, direction * 28.0 * recovery_curve)
	if event.get("kind") == &"collision":
		var blocker_id := int(event.get("blocker_unit_id", UnitId.NONE))
		if _obstacle_participant_alive(blocker_id):
			_set_action_offset(blocker_id, direction * 10.0 * recovery_curve)
	if amount >= 1.0:
		if _obstacle_participant_alive(target_id): _set_action_offset(target_id, Vector2.ZERO)
		if event.get("kind") == &"collision":
			var final_blocker_id := int(event.get("blocker_unit_id", UnitId.NONE))
			if _obstacle_participant_alive(final_blocker_id): _set_action_offset(final_blocker_id, Vector2.ZERO)

func _obstacle_impact(event: Dictionary) -> void:
	var direction := _obstacle_direction(event)
	var target_id := int(event.get("target_unit_id", UnitId.NONE))
	if _obstacle_participant_alive(target_id):
		var impact := impact_scene.instantiate() as BattlePresentationImpact
		_impacts.add_child(impact)
		impact.set_meta("obstacle_contact", true)
		impact.set_meta("cell", event.get("from_cell", Vector2i.ZERO))
		impact.set_meta("anchor", direction * 38.0 + Vector2(0.0, -18.0))
		impact.set_meta("impact_scale", 1.0)
		_place_impacts()
		impact.start(Color("ffd08a"))
	if event.get("kind") == &"collision":
		var blocker_id := int(event.get("blocker_unit_id", UnitId.NONE))
		if _obstacle_participant_alive(blocker_id):
			_set_action_offset(blocker_id, direction * 10.0)

func _strike_pose(distance: float, event: Dictionary) -> void:
	_set_action_offset(int(event.actor_unit_id), _strike_direction(event) * distance)

func _pounce_prepare(progress: float, event: Dictionary) -> void:
	var amount := clampf(progress, 0.0, 1.0)
	var offset := _strike_direction(event) * lerpf(0.0, POUNCE_PREPARE_DISTANCE, amount)
	offset += Vector2(0.0, POUNCE_PREPARE_LIFT * amount)
	_set_action_offset(int(event.actor_unit_id), offset)

func _pounce_jump(progress: float, event: Dictionary) -> void:
	var amount := clampf(progress, 0.0, 1.0)
	if amount >= 1.0:
		# Контакт должен совпасть с прежним выпадом без остатка от lift по вертикали.
		_set_action_offset(int(event.actor_unit_id), _strike_direction(event) * POUNCE_CONTACT_DISTANCE)
		return
	var offset := _strike_direction(event) * lerpf(POUNCE_PREPARE_DISTANCE, POUNCE_CONTACT_DISTANCE, amount * amount)
	offset += Vector2(0.0, POUNCE_PREPARE_LIFT * (1.0 - amount) - POUNCE_JUMP_ARC_HEIGHT * sin(PI * amount))
	_set_action_offset(int(event.actor_unit_id), offset)

static func _impact_recoil(progress: float) -> float:
	if progress <= 0.0 or progress >= 1.0: return 0.0
	if progress <= 0.2: return sin((progress / 0.2) * PI * 0.5)
	var fade_progress := (progress - 0.2) / 0.8
	return cos(fade_progress * TAU) * pow(1.0 - fade_progress, 2.0)

func _hit_recovery(progress: float, strike: Dictionary, dying: bool) -> void:
	var amount := clampf(progress, 0.0, 1.0)
	_strike_pose((0.0 if strike.get("presentation_ranged", false) else STRIKE_LUNGE_DISTANCE) * pow(1.0 - amount, 3.0), strike)
	var recoil := _strike_direction(strike) * _impact_recoil(amount) * NORMAL_RECOIL_DISTANCE
	if bool(strike.get("modifiers", {}).get("critical", false)):
		if amount <= 0.0 or amount >= 1.0:
			recoil = Vector2.ZERO
		else:
			var direction := _strike_direction(strike)
			var perpendicular := Vector2(-direction.y, direction.x)
			# Критический удар заметнее, но толчок остаётся только на рисунке тела.
			var shake := sin(amount * PI * CRITICAL_SHAKE_CYCLES * 2.0) * pow(1.0 - amount, 2.0)
			recoil = direction * _impact_recoil(amount) * CRITICAL_RECOIL_DISTANCE
			recoil += perpendicular * shake * CRITICAL_SHAKE_DISTANCE
	_set_action_offset(int(strike.target_unit_id), recoil)
	if dying:
		_field_presentation.sample_death(progress, self, int(strike.target_unit_id))

func _is_ranged_strike(event: Dictionary) -> bool:
	# Дальность приходит из отделённого кадра; соседство не превращает стрелка в бойца ближнего боя.
	for row: Dictionary in _view_units:
		if row.unit.id == int(event.actor_unit_id) and float(row.get("attack_range", 1.0)) > 1.0: return true
	return (event.actor_cell as Vector2i).distance_squared_to(event.target_cell) > 1

static func _shot_flight_seconds(event: Dictionary) -> float:
	var delta: Vector2i = event.target_cell - event.actor_cell
	return clampf(0.10 + 0.025 * float(absi(delta.x) + absi(delta.y) - 1), 0.10, 0.24)

static func _shot_arc_height(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var delta := to_cell - from_cell
	var distance := float(absi(delta.x) + absi(delta.y))
	# Дальние дуги растут быстрее длины пути; предел удерживает заглушку в пределах поля.
	return minf(180.0, 12.0 * distance + 2.0 * distance * distance)

func _effect_anchor(id: int) -> Vector2:
	var visual := _presentation_visual(id)
	var anchor := visual.get_node_or_null("ArtRoot/EffectAnchor") as Node2D if visual != null else null
	return anchor.position if anchor != null else Vector2(0, -18)

func _prepare_projectile(event: Dictionary) -> BattlePresentationProjectile:
	var projectile := projectile_scene.instantiate() as BattlePresentationProjectile
	_ghosts.add_child(projectile)
	projectile.set_meta("from_cell", event.actor_cell)
	projectile.set_meta("to_cell", event.target_cell)
	projectile.set_meta("from_anchor", _effect_anchor(int(event.actor_unit_id)) - _strike_direction(event) * 8.0)
	projectile.set_meta("to_anchor", _effect_anchor(int(event.target_unit_id)))
	projectile.set_meta("progress", 0.0)
	return projectile

func _place_projectiles() -> void:
	if _ghosts == null: return
	for child: Node in _ghosts.get_children():
		var projectile := child as BattlePresentationProjectile
		if projectile == null: continue
		var art_scale := grid_config.tile_size.x / 128.0
		var from := _world_cell_center(projectile.get_meta("from_cell")) + (projectile.get_meta("from_anchor") as Vector2) * art_scale
		var to := _world_cell_center(projectile.get_meta("to_cell")) + (projectile.get_meta("to_anchor") as Vector2) * art_scale
		var arc_height := _shot_arc_height(projectile.get_meta("from_cell"), projectile.get_meta("to_cell")) * art_scale
		projectile.sample(from, to, float(projectile.get_meta("progress")), art_scale, arc_height)

func _shot_flight(progress: float, event: Dictionary, projectile: BattlePresentationProjectile) -> void:
	if not is_instance_valid(projectile): return
	projectile.visible = true
	projectile.set_meta("progress", progress)
	_place_projectiles()
	_strike_pose(-8.0 * (1.0 - progress), event)

func _hit_impact(event: Dictionary, tint: Color) -> void:
	var visual := _presentation_visual(int(event.target_unit_id))
	if visual == null: return
	var impact := impact_scene.instantiate() as BattlePresentationImpact
	_impacts.add_child(impact)
	var anchor := visual.get_node_or_null("ArtRoot/EffectAnchor") as Node2D
	impact.set_meta("impact_scale", 0.85)
	impact.set_meta("cell", _view_unit_cell(int(event.target_unit_id)))
	impact.set_meta("anchor", anchor.position if anchor != null else Vector2(0, -18))
	_place_impacts()
	impact.start(tint)

func _place_impacts() -> void:
	if _impacts == null: return
	for impact: Node2D in _impacts.get_children():
		var anchor: Vector2 = impact.get_meta("anchor")
		impact.position = _world_cell_center(impact.get_meta("cell")) + anchor * grid_config.tile_size.x / 128.0
		impact.scale = Vector2.ONE * grid_config.tile_size.x / 128.0 * float(impact.get_meta("impact_scale", 0.7))

func _matching_strike(events: Array, step: Dictionary) -> Dictionary:
	if step.get("kind") != &"attack_hit": return {}
	for event: Dictionary in events:
		if event.get("kind") not in [&"damaged", &"healed", &"armor_changed", &"hit_resolved"]: continue
		# Mandatory attack_hit наследует parent_event_seq=0, а не event_seq атаки.
		# Связываем только следующий шаг attack_hit того же root и тех же участников.
		for strike: Dictionary in _pending_strikes.values():
			if event.get("root_id") == strike.root_id and int(step.get("command_seq", 0)) == int(strike.command_seq) + 1 and event.get("source", {}).get("kind") == &"attack" and event.get("actor_unit_id") == strike.actor_unit_id and event.get("target_unit_id") == strike.target_unit_id:
				return strike
	return {}

## Числа создаются на той же атомарной границе, что HP/броня поля и HUD.
func finish_presentation_frame(events: Array, step: Dictionary = {}, before: Dictionary = {}, after: Dictionary = {}) -> void:
	var strike := _matching_strike(events, step)
	for feedback: Dictionary in BattleReactionPresentation.feedback(events, step, before, after):
		_add_result_number(int(feedback.id), String(feedback.text), Color("93dce9"), &"reaction")
	var numbered: Dictionary = {}
	for event: Dictionary in events:
		var status_feedback := BattleStatusPresentation.event_feedback(event)
		if not status_feedback.is_empty(): _add_result_number(int(event.get("target_unit_id", 0)), status_feedback, Color("ffd08a"), &"status")
		var kind := StringName(event.get("kind", &""))
		var target := int(event.get("target_unit_id", 0))
		var text := ""
		var tint := Color("f29b9b")
		if kind in [&"damaged", &"healed"] and float(event.get("amount", 0.0)) > 0.0:
			text = ("−" if kind == &"damaged" else "+") + ("%.1f HP" % float(event.amount))
			if kind == &"healed": tint = Color("65dfcc")
			elif not strike.is_empty() and bool(strike.get("modifiers", {}).get("critical", false)): text = "КРИТ · " + text
		elif kind == &"shield_changed":
			text = "Щит −%d" % int(event.absorbed) if int(event.absorbed) > 0 else "Щит %d" % int(event.after.get("hp", 0))
			tint = Color("71cefa")
		elif kind == &"armor_changed":
			var delta := 0.0
			for change: Dictionary in event.get("grants", []) + event.get("items", []):
				delta += float(change.after) - float(change.before)
			if not is_zero_approx(delta): text = ("+" if delta > 0.0 else "−") + ("%.1f броня" % absf(delta))
			tint = Color("8dcaff")
		if not text.is_empty():
			_add_result_number(target, text, tint)
			numbered[target] = true
	for event: Dictionary in events:
		if event.get("kind") == &"hit_resolved" and not numbered.has(int(event.target_unit_id)):
			_add_result_number(int(event.target_unit_id), "0 · без урона", Color("d6dfeb"))
			numbered[int(event.target_unit_id)] = true
	_show_consequence_feedback(BattleConsequenceFeedback.entries(events, before, after), int(events[0].get("root_id", 0)) if not events.is_empty() else 0)
	# Командный refill остаётся кадром значений без боевого импакта/HP-события.
	if step.get("kind") == &"battle_turn_refill" and step.get("status") == &"APPLIED":
		_show_consequence_feedback(BattleConsequenceFeedback.recovery_entries(before, after), 0)
	# FAULTED attack_hit без результата снимает замах без выдуманного попадания.
	if step.get("kind") == &"attack_hit": clear_strike_poses()

func _show_consequence_feedback(entries: Array[Dictionary], root_id: int) -> void:
	var grouped: Dictionary = {}
	for entry: Dictionary in entries:
		var id := int(entry.unit_id)
		if not grouped.has(id): grouped[id] = {}
		var parts: Dictionary = grouped[id]
		var kind := StringName(entry.kind)
		parts[kind] = String(parts[kind]) + "\n" + String(entry.text) if parts.has(kind) else String(entry.text)
	for id: int in grouped:
		var parts: Dictionary = {}
		# Один блок причин на фигуру: исходный пробой остаётся рядом с последующим упором.
		for number: BattlePresentationNumber in _numbers.get_children():
			if number.feedback_kind == &"consequence" and int(number.get_meta("unit_id", 0)) == id:
				if int(number.get_meta("root_id", -1)) == root_id: parts = number.get_meta("parts").duplicate(true)
				_numbers.remove_child(number)
				number.queue_free()
		parts.merge(grouped[id], true)
		var texts: PackedStringArray = []
		for kind: StringName in [&"armor", &"balance", &"push"]:
			if parts.has(kind): texts.append(String(parts[kind]).replace(" · ", "\n").replace("Столкновение: ", "Столкновение:\n"))
		var tint := Color("8dcaff") if parts.size() == 1 and parts.has(&"armor") else Color("f7c97d")
		var number := _add_result_number(id, "\n".join(texts), tint, &"consequence")
		if number != null:
			number.set_meta("root_id", root_id)
			number.set_meta("parts", parts)

func begin_presentation_frame(events: Array) -> void:
	set_acting_unit(UnitId.NONE)
	for event: Dictionary in events:
		var actor_id := int(event.get("actor_unit_id", UnitId.NONE))
		if _view_unit_cell(actor_id).x >= 0:
			set_acting_unit(actor_id)
			break
	# Следующее действие участника убирает прежнюю причину до движения/замаха.
	# Числа результата привязаны к месту прошлого удара и сохраняют свой срок R05.
	for event: Dictionary in events:
		var root_id := int(event.get("root_id", 0))
		var participants: Array[int] = []
		for field: String in ["actor_unit_id", "target_unit_id", "from_unit_id", "blocker_unit_id"]:
			if event.has(field): participants.append(int(event[field]))
		for number: BattlePresentationNumber in _numbers.get_children():
			if number.feedback_kind == &"consequence" and int(number.get_meta("root_id", -1)) != root_id and int(number.get_meta("unit_id", 0)) in participants:
				_numbers.remove_child(number)
				number.queue_free()

func _add_result_number(id: int, text: String, tint: Color, feedback_kind: StringName = &"result") -> BattlePresentationNumber:
	var cell := _view_unit_cell(id)
	if cell.x < 0: return null
	var number := number_scene.instantiate() as BattlePresentationNumber
	number.feedback_kind = feedback_kind
	_numbers.add_child(number)
	number.set_meta("cell", cell)
	number.set_meta("unit_id", id)
	var visual := _presentation_visual(id)
	var anchor := visual.get_node_or_null("ArtRoot/LabelAnchor") as Node2D if visual != null else null
	number.set_meta("anchor", anchor.position if anchor != null else Vector2(0, -48))
	if feedback_kind == &"consequence":
		number.rise = 0.0
		number._label.add_theme_font_size_override("font_size", 16)
		number.set_meta("anchor", Vector2(0, 35))
		var leader := Line2D.new()
		leader.name = "Leader"
		leader.width = 1.0
		leader.default_color = Color(tint, 0.55)
		leader.z_index = -1
		number.add_child(leader)
	number.start(text, tint)
	_place_result_numbers()
	return number

func _place_result_numbers() -> void:
	if _numbers == null: return
	var occupied: Array[Rect2] = []
	var ordered: Array[Node] = []
	for number: BattlePresentationNumber in _numbers.get_children():
		if number.feedback_kind != &"consequence": ordered.append(number)
	for number: BattlePresentationNumber in _numbers.get_children():
		if number.feedback_kind == &"consequence": ordered.append(number)
	for number: BattlePresentationNumber in ordered:
		if number.is_queued_for_deletion(): continue
		var anchor: Vector2 = number.get_meta("anchor")
		var point := _world_cell_center(number.get_meta("cell")) + anchor * grid_config.tile_size.x / 128.0
		# Резервируем весь путь подписи: старое число не налетает на новое при подъёме.
		var dimensions := number._label.size
		var consequence := number.feedback_kind == &"consequence"
		if consequence: point.y += dimensions.y
		var bounds := Rect2(point - Vector2(dimensions.x * 0.5, dimensions.y + number.rise), dimensions + Vector2(0, number.rise)).grow(3.0)
		var collision := true
		while collision:
			collision = false
			for prior: Rect2 in occupied:
				if bounds.intersects(prior):
					point.y = prior.end.y + dimensions.y + 4.0 if consequence else prior.position.y - 4.0
					bounds.position.y = point.y - dimensions.y - number.rise - 3.0
					collision = true
					break
		number.position = point
		occupied.append(bounds)
		if consequence:
			var leader := number.get_node("Leader") as Line2D
			leader.points = PackedVector2Array([_world_cell_center(number.get_meta("cell")) + Vector2(0, 18) * grid_config.tile_size.x / 128.0 - point, Vector2(0, -dimensions.y - 2)])

func _presentation_visual(id: int) -> BattleDemoIsoVisual:
	for visual: BattleDemoIsoVisual in _entity_visuals:
		if visual.unit != null and visual.unit.id == id: return visual
	return null

func _presentation_motion(progress: float, id: int, from: Vector2i, to: Vector2i) -> void:
	# Поиск текущего узла сохраняет Tween при rebuild/resize; ссылки на runtime здесь нет.
	var visual := _presentation_visual(id)
	if visual == null: return
	visual.half_steps = 0
	var origin := IsoGridUtils.grid_to_screen(from, grid_config, 0)
	var destination := IsoGridUtils.grid_to_screen(to, grid_config, 0)
	var foot := origin.lerp(destination, progress)
	# Обе поверхности сегмента должны оставаться под стопами и между центрами.
	# Смещаем только ключ сортировки; стены следующего ряда остаются впереди.
	visual.position = Vector2(foot.x, maxf(origin.y, destination.y) - 0.25)
	visual.presentation_offset = foot - visual.position
	visual.presentation_lift = -0.5 * lerpf(_view_height_steps(from), _view_height_steps(to), progress) * grid_config.height_step
	_sort_visuals()
	if progress >= 1.0:
		# После сегмента возвращаем обычную глубину клетки до дальнейших эффектов шага.
		visual.position = destination
		visual.presentation_offset = Vector2.ZERO
		_sort_visuals()
		for row: Dictionary in _view_units:
			if row.unit.id == id: row.cell = to

func _presentation_pulse(progress: float, id: int, dying: bool, falling: bool) -> void:
	var visual := _presentation_visual(id)
	if visual == null: return
	if dying:
		visual.modulate.a = 1.0 - progress
		if falling: visual.fall_drop = progress * grid_config.tile_size.y * 1.4
	else:
		visual.modulate = Color.WHITE.lerp(Color("ffd07a"), sin(progress * PI) * 0.8)

func _presentation_badge(event: Dictionary) -> void:
	clear_presentation_effects()
	var id := int(event.get("target_unit_id", 0))
	var cell: Vector2i = event.get("cell", _view_unit_cell(id))
	if cell.x < 0: return
	# Внутри одного шага moved может уже сдвинуть фигуру до died/control_changed.
	var visual := _presentation_visual(id)
	var anchor := visual.position + visual.get_visual_offset() if visual != null else _world_cell_center(cell)
	var label := Label.new()
	label.text = _presentation_caption(event)
	label.add_theme_color_override("font_color", Color("fff2bd"))
	label.add_theme_color_override("font_shadow_color", Color("101522"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = anchor + Vector2(-35, -72)
	_ghosts.add_child(label)
	if event.get("kind") in [&"attacked", &"opportunity_attacked", &"counterattacked"]:
		var from: Vector2i = event.get("actor_cell", cell)
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color("ffd07a")
		line.points = PackedVector2Array([_world_cell_center(from) + Vector2(0, -20), anchor + Vector2(0, -20)])
		_ghosts.add_child(line)

static func _presentation_caption(event: Dictionary) -> String:
	match StringName(event.get("kind", &"")):
		&"damaged": return "−%.1f HP" % float(event.amount)
		&"healed": return "+%.1f HP" % float(event.amount)
		&"armor_changed": return "БРОНЯ"
		&"attacked": return "УДАР"
		&"opportunity_attacked", &"counterattacked", &"reaction_used": return "РЕАКЦИЯ"
		&"died": return "ПАДЕНИЕ" if event.get("source", {}).get("kind") == &"fall" else "ГИБЕЛЬ"
		&"shield_changed": return "ЩИТ"
		&"mage_cast", &"mage_card_play": return "МАГ"
		&"elemental_cast", &"elemental_changed", &"control_changed", &"bleeding_changed": return "СОСТОЯНИЕ"
		&"summoned", &"corpse_raised": return "ПРИЗЫВ"
		&"mage_summoned": return "ПОДНЯТИЕ" if int(event.get("corpse_id", 0)) > 0 else "ПРИЗЫВ"
		&"support_collapsed": return "ОБВАЛ"
		&"fell": return "ПАДЕНИЕ"
		&"guarded": return "ЗАЩИТА"
	return ""

func animate_presentation_frame(events: Array, step: Dictionary = {}) -> Tween:
	var mage_frame := _matching_mage_cast(events, step)
	if not mage_frame.is_empty(): return _animate_mage_frame(events, mage_frame)
	var support_frame := _matching_support_action(events, step)
	if not support_frame.is_empty(): return _animate_support_action(support_frame)
	var tween := create_tween()
	var visible_event := false
	var strike := _matching_strike(events, step)
	var consequence_pulses: Dictionary = {}
	var reaction_cues := BattleReactionPresentation.cues(events, step)
	# Исторический источник тика может указывать на прежнюю клетку: подсвечиваем
	# только реальное исполнение опасности, а не любой урон с таким source.
	var hazard := BattleFieldPresentation.hazard_cell(events, _view_fires) if step.get("kind") == &"fire_entry" else Vector2i(-1, -1)
	var trap_event := BattleFieldPresentation.trap_event(events) if step.get("kind") in [&"hazard_contact", &"hazard_trigger"] else {}
	var trap_cell: Vector2i = trap_event.get("cell", Vector2i(-1, -1))
	if trap_cell.x >= 0:
		var trap_kind: String = String(trap_event.get("trap_kind", "floor"))
		var trap_direction: Vector2i = trap_event.get("direction", Vector2i.ZERO)
		tween.tween_method(_field_presentation.sample_trap.bind(self, trap_cell, trap_kind, trap_direction), 0.0, 1.0, BattleFieldPresentation.SPIKE_EXTEND_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Шипы остаются поднятыми во время урона/смерти и публикации чисел.
		# Втягивание принадлежит отдельному хвосту уже опубликованного кадра.
		visible_event = true
	if hazard.x >= 0:
		tween.tween_method(_field_presentation.sample_cell.bind(self, hazard, &"hazard"), 0.0, 1.0, BattleFieldPresentation.HAZARD_SECONDS)
		visible_event = true
	var falling_ids: Array[int] = []
	for event: Dictionary in events:
		if event.get("kind") == &"fell": falling_ids.append(int(event.target_unit_id))
	if not strike.is_empty():
		for cue: Dictionary in strike.get("presentation_cues", []):
			var effect := _make_reaction_cue(cue)
			_sample_reaction_cue(1.0, effect)
		var impact_tint := Color("f29b9b") if events.any(func(e: Dictionary) -> bool: return e.get("kind") == &"damaged") else (Color("8dcaff") if events.any(func(e: Dictionary) -> bool: return e.get("kind") == &"armor_changed") else Color("d6dfeb"))
		tween.tween_callback(_hit_impact.bind(strike, impact_tint))
		tween.tween_interval(HIT_STOP_SECONDS)
		var dying := events.any(func(e: Dictionary) -> bool: return e.get("kind") == &"died" and e.get("target_unit_id") == strike.target_unit_id)
		tween.tween_method(_hit_recovery.bind(strike, dying), 0.0, 1.0, STRIKE_RECOVERY_SECONDS)
		visible_event = true
	for event: Dictionary in events:
		var kind := StringName(event.get("kind", &""))
		var id := int(event.get("target_unit_id", 0))
		if kind == &"support_collapsed":
			tween.tween_method(_field_presentation.sample_cell.bind(self, event.cell, &"collapse"), 0.0, 1.0, BattleFieldPresentation.COLLAPSE_SECONDS)
			visible_event = true
			continue
		if kind == &"fell":
			tween.tween_method(_field_presentation.sample_fall.bind(self, id, event.from_cell, event.attempted_cell, true), 0.0, 1.0, BattleFieldPresentation.FALL_SECONDS)
			visible_event = true
			continue
		if kind == &"died":
			if id in falling_ids or not strike.is_empty(): continue
			var cell := _view_unit_cell(id)
			var origin: Vector2i = event.get("source", {}).get("origin_cell", cell)
			if event.get("source", {}).get("kind") in [&"fall", &"cell"] and _view_terrain_at(origin) in [TerrainType.Type.VOID, TerrainType.Type.HAZARD]:
				# moved и died могут находиться в одном кадре: падение начинается
				# после уже показанного сдвига, а не повторяет его из старой клетки.
				for prior: Dictionary in events:
					if prior == event: break
					if prior.get("kind") == &"moved" and int(prior.get("target_unit_id", 0)) == id: cell = prior.to_cell
				tween.tween_method(_field_presentation.sample_fall.bind(self, id, cell, origin, true), 0.0, 1.0, BattleFieldPresentation.FALL_SECONDS)
			else:
				tween.tween_method(_field_presentation.sample_death.bind(self, id), 0.0, 1.0, BattleFieldPresentation.DEATH_SECONDS)
			visible_event = true
			continue
		# Расход уже объяснён единственным клипом действия; это не ещё одно попадание.
		if kind == &"reaction_used" or (kind == &"shield_changed" and not strike.is_empty()): continue
		if kind == &"guarded" and not reaction_cues.is_empty():
			for cue: Dictionary in reaction_cues:
				if cue.kind == &"guard": _append_reaction_cue(tween, cue)
			visible_event = true
			continue
		if kind in [&"push_blocked", &"collision"]:
			var obstacle_event := event.duplicate(true)
			tween.tween_method(_obstacle_approach.bind(obstacle_event), 0.0, 1.0, OBSTACLE_APPROACH_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tween.tween_callback(_obstacle_impact.bind(obstacle_event))
			tween.tween_interval(OBSTACLE_HOLD_SECONDS)
			tween.tween_method(_obstacle_recovery.bind(obstacle_event), 0.0, 1.0, OBSTACLE_RECOVERY_SECONDS)
			visible_event = true
			continue
		if kind in [&"balance_changed", &"balance_broken", &"chain_link"]:
			# Изменение и пробой одного balance — один импульс, без обещания сдвига.
			if not consequence_pulses.has(id):
				tween.tween_method(_presentation_pulse.bind(id, false, false), 0.0, 1.0, 0.16)
				consequence_pulses[id] = true
				visible_event = true
			continue
		if kind in [&"bleeding_changed", &"elemental_changed", &"control_changed"]:
			# Название изменения публикуется вместе с after; до него — только короткий импульс.
			if hazard.x < 0:
				tween.tween_method(_presentation_pulse.bind(id, false, false), 0.0, 1.0, 0.16)
				visible_event = true
			continue
		if kind == &"died" and not strike.is_empty(): continue
		if kind in [&"attacked", &"opportunity_attacked", &"counterattacked"]:
			clear_strike_poses()
			var start := event.duplicate(true)
			start["presentation_ranged"] = _is_ranged_strike(event)
			# Класс берётся только из снимка боя, чтобы playback не читал session во время worker.
			start["presentation_pounce"] = not bool(start.presentation_ranged) and _view_actor_classes.get(int(event.actor_unit_id), &"") == &"rogue"
			start["presentation_cues"] = reaction_cues.duplicate(true)
			_pending_strikes[_strike_key(event)] = start
			for cue: Dictionary in reaction_cues:
				if cue.kind in [&"opportunist", &"counterattack"]: _append_reaction_cue(tween, cue)
			for cue: Dictionary in reaction_cues:
				if cue.kind == &"cover": _append_reaction_cue(tween, cue)
			if start.presentation_ranged:
				var projectile := _prepare_projectile(start)
				tween.tween_method(_strike_pose.bind(start), 0.0, -8.0, SHOT_WINDUP_SECONDS)
				tween.tween_method(_shot_flight.bind(start, projectile), 0.0, 1.0, _shot_flight_seconds(start))
			else:
				if bool(start.presentation_pounce):
					tween.tween_method(_pounce_prepare.bind(start), 0.0, 1.0, POUNCE_PREPARE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
					tween.tween_method(_pounce_jump.bind(start), 0.0, 1.0, POUNCE_JUMP_SECONDS)
				else:
					tween.tween_method(_strike_pose.bind(start), 0.0, -10.0, STRIKE_WINDUP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
					tween.tween_method(_strike_pose.bind(start), -10.0, STRIKE_LUNGE_DISTANCE, STRIKE_LUNGE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			visible_event = true
			continue
		if kind in [&"damaged", &"healed", &"armor_changed", &"hit_resolved"]:
			# Несколько технических записей попадания не создают повторную отдачу.
			if strike.is_empty() and hazard.x < 0 and event.get("source", {}).get("kind") != &"fall" and kind in [&"damaged", &"healed"]:
				tween.tween_method(_presentation_pulse.bind(id, false, false), 0.0, 1.0, 0.16)
				visible_event = true
			continue
		if kind == &"moved":
			var path: Array = event.get("transit_path", [event.from_cell, event.get("to_cell", event.get("attempted_cell", event.from_cell))])
			# Добровольный путь ощущается отзывчивее; толчки и падения сохраняют прежний темп.
			var segment_seconds: float = MOVE_SEGMENT_SECONDS if event.get("movement_kind", &"") in [&"voluntary", &"safe_retreat"] else FORCED_MOVE_SEGMENT_SECONDS
			for index in range(1, path.size()):
				if _is_presentation_drop(path[index - 1], path[index]):
					tween.tween_method(_field_presentation.sample_fall.bind(self, id, path[index - 1], path[index], false), 0.0, 1.0, BattleFieldPresentation.FALL_SECONDS)
					tween.tween_method(_field_presentation.sample_land.bind(self, id), 0.0, 1.0, BattleFieldPresentation.LAND_SECONDS)
				elif event.get("movement_kind", &"") in [&"voluntary", &"safe_retreat"]:
					tween.tween_method(_presentation_motion.bind(id, path[index - 1], path[index]), 0.0, 1.0, segment_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				else:
					tween.tween_method(_presentation_motion.bind(id, path[index - 1], path[index]), 0.0, 1.0, segment_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			visible_event = true
		elif not _presentation_caption(event).is_empty():
			tween.tween_callback(_presentation_badge.bind(event.duplicate(true)))
			var dying := kind == &"died"
			var falling: bool = dying and event.get("source", {}).get("kind") == &"fall"
			tween.tween_method(_presentation_pulse.bind(id, dying, falling), 0.0, 1.0, 0.3 if dying else 0.16)
			visible_event = true
	if not visible_event: tween.tween_interval(0.035)
	return tween

func animate_trap_retraction(event: Dictionary) -> Tween:
	var cell: Vector2i = event.cell
	var kind: String = String(event.trap_kind)
	var direction: Vector2i = event.direction
	# show_presentation_state пересобрал позы: восстанавливаем укол по событию,
	# сохраняя атомарную публикацию HP, тела и чисел до паузы чтения результата.
	_field_presentation.sample_trap(1.0, self, cell, kind, direction)
	var tween := create_tween()
	tween.tween_interval(BattleFieldPresentation.SPIKE_HOLD_SECONDS)
	tween.tween_method(_field_presentation.sample_trap.bind(self, cell, kind, direction), 1.0, 0.0, BattleFieldPresentation.SPIKE_RETRACT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return tween

func _is_presentation_drop(from: Vector2i, to: Vector2i) -> bool:
	return _view_terrain_at(to) == TerrainType.Type.FLOOR and _view_height_steps(from) > _view_height_steps(to)

func _make_reaction_cue(cue: Dictionary) -> BattlePresentationReaction:
	var effect := reaction_scene.instantiate() as BattlePresentationReaction
	_ghosts.add_child(effect)
	effect.set_meta("cue", cue.duplicate(true))
	_reaction_cues.append(effect)
	_sample_reaction_cue(0.0, effect)
	return effect

func _append_reaction_cue(tween: Tween, cue: Dictionary) -> void:
	var effect := _make_reaction_cue(cue)
	effect.visible = false
	tween.tween_method(_sample_reaction_cue.bind(effect), 0.0, 1.0, REACTION_CUE_SECONDS)

func _sample_reaction_cue(progress: float, effect: BattlePresentationReaction) -> void:
	if not is_instance_valid(effect): return
	var cue: Dictionary = effect.get_meta("cue")
	effect.visible = true
	effect.sample(cue.kind, cue.title, progress, _reaction_anchor(int(cue.actor_id)), _reaction_anchor(int(cue.target_id)))

func _reaction_anchor(id: int) -> Vector2:
	var visual := _presentation_visual(id)
	if visual == null: return _world_cell_center(_view_unit_cell(id))
	return visual.position + visual.get_visual_offset() + _effect_anchor(id) * grid_config.tile_size.x / 128.0

func _place_reaction_cues() -> void:
	for effect: BattlePresentationReaction in _reaction_cues:
		if is_instance_valid(effect) and effect.visible: _sample_reaction_cue(effect.progress, effect)

func _matching_mage_cast(events: Array, step: Dictionary) -> Dictionary:
	if step.get("kind") not in [&"mage_cast", &"mage_card_play"]: return {}
	for event: Dictionary in events:
		var source: Dictionary = event.get("source", {})
		if event.get("kind") not in [&"mage_cast", &"mage_card_played"] or int(event.get("actor_unit_id", -1)) != 0: continue
		if int(event.get("command_seq", -1)) != int(step.get("command_seq", -2)): continue
		if event.get("kind") == &"mage_card_played":
			var card := MageCardCatalog.get_card(String(event.get("type_id","")))
			if step.get("kind") == &"mage_card_play" and card != null and card.effect.begins_with("mage.") and source.get("kind") == &"mage" and source.get("source_instance_id") == card.source_id(): return event
			continue
		var spell := _mage_visual_spell(event)
		var expected_source := AbilityDefinition.mage_source_id(spell) if spell in [&"mage.fire", &"mage.heal", &"mage.test_heal", &"mage.test_summon", &"mage.test_raise", &"mage.shield"] else 0
		if expected_source == 0 or source.get("kind") != &"mage" or int(source.get("source_instance_id", 0)) != expected_source: continue
		return event
	return {}

func _mage_visual_spell(cast: Dictionary) -> StringName:
	if cast.get("kind") == &"mage_card_played":
		var card := MageCardCatalog.get_card(String(cast.get("type_id","")))
		return StringName(card.effect) if card != null else &""
	return StringName(cast.get("spell_id", &""))

func _mage_result_matches(event: Dictionary, cast: Dictionary) -> bool:
	var source: Dictionary = event.get("source", {})
	var target_matches := int(event.get("target_unit_id", -1)) == int(cast.get("target_unit_id", -2))
	if AbilityDefinition.is_cell_spell(_mage_visual_spell(cast)):
		var same_spell: bool = event.get("card_type_id") == cast.get("type_id") if cast.get("kind") == &"mage_card_played" else event.get("spell_id") == cast.get("spell_id")
		var same_target: bool = event.get("cell") == cast.get("target_cell") if cast.get("kind") == &"mage_card_played" else int(event.get("anchor_unit_id", event.get("owner_unit_id", -1))) == int(cast.get("target_unit_id", -2))
		target_matches = event.get("kind") == &"mage_summoned" and same_spell and same_target
	return event.get("root_id") == cast.get("root_id") and int(event.get("command_seq", -1)) == int(cast.get("command_seq", -2)) and target_matches and source.get("kind") == &"mage" and int(source.get("source_instance_id", 0)) == int(cast.get("source", {}).get("source_instance_id", -1))

func _animate_mage_frame(events: Array, cast: Dictionary) -> Tween:
	var target_id := int(cast.get("target_unit_id", UnitId.NONE))
	var spell := _mage_visual_spell(cast)
	var contact_kind := &"healed" if spell in [&"mage.heal", &"mage.test_heal"] else &""
	var confirms_contact := false
	_mage_dying = false
	_mage_target_cell = Vector2i(-1, -1)
	for event: Dictionary in events:
		if not _mage_result_matches(event, cast): continue
		if AbilityDefinition.is_cell_spell(spell) and event.get("kind") == &"mage_summoned":
			confirms_contact = true
			_mage_target_cell = event.cell
			_support_kind = &"mage_raise" if int(event.get("corpse_id", 0)) > 0 else &"mage_summon"
			_support_actor_id = UnitId.NONE
			_support_target_id = int(event.get("target_unit_id", UnitId.NONE))
		if spell in [&"mage.heal", &"mage.test_heal"] and event.get("kind") == contact_kind: confirms_contact = true
		if spell == &"mage.shield" and event.get("kind") == &"shield_changed": confirms_contact = true
		if spell == &"mage.fire" and event.get("kind") in [&"hit_resolved", &"damaged", &"healed", &"armor_changed"]: confirms_contact = true
		if spell == &"mage.fire" and event.get("kind") == &"died": _mage_dying = true
	_clear_layer(_ghosts)
	_mage_target_id = target_id
	_mage_spell_id = spell
	_mage_effect = mage_scene.instantiate() as BattlePresentationMage
	_mage_effect.show_target = not AbilityDefinition.is_cell_spell(spell) or confirms_contact
	add_child(_mage_effect)
	_mage_effect.z_index = RenderLayers.z_index_for(RenderLayers.Layer.VFX_OVERLAY) + 1
	_update_mage_geometry()
	var tween := create_tween()
	tween.tween_method(_sample_mage.bind(&"prepare"), 0.0, 1.0, 0.10)
	# Без подтверждённого появления prefix не знает целевую клетку и не выдумывает её.
	if AbilityDefinition.is_cell_spell(spell) and not confirms_contact: return tween
	tween.tween_method(_sample_mage.bind(&"delivery"), 0.0, 1.0, 0.22)
	if confirms_contact:
		if AbilityDefinition.is_cell_spell(spell):
			_create_support_effect(_support_kind, UnitId.NONE, _mage_target_cell, int(cast.get("target_unit_id", UnitId.NONE)))
			_support_started = false
			_support_effect.visible = false
			tween.tween_callback(_begin_support_contact)
			tween.tween_method(_sample_support.bind(&"contact"), 0.0, 1.0, 0.20)
		tween.tween_callback(_mage_contact.bind(cast, spell))
		tween.tween_method(_sample_mage.bind(&"contact"), 0.0, 1.0, 0.20)
	return tween

func _sample_mage(progress: float, phase: StringName) -> void:
	if is_instance_valid(_mage_effect): _update_mage_geometry(phase, progress)
	if phase == &"contact" and _mage_spell_id == &"mage.fire":
		_set_action_offset(_mage_target_id, _mage_recoil_direction * 7.0 * sin(progress * PI) * (1.0 - progress))
		if _mage_dying:
			_field_presentation.sample_death(progress, self, _mage_target_id)

func _matching_support_action(events: Array, step: Dictionary) -> Dictionary:
	var kind := StringName(step.get("kind", &""))
	var command_seq := int(step.get("command_seq", -1))
	var root_id := -1
	for event: Dictionary in events:
		if int(event.get("command_seq", -2)) == command_seq:
			var event_root := int(event.get("root_id", -1))
			if event_root < 1 or (root_id >= 0 and root_id != event_root): return {}
			root_id = event_root
	if root_id < 0: return {}
	if kind == &"raise_corpse":
		for event: Dictionary in events:
			if event.get("kind") == &"corpse_raised" and int(event.get("root_id", -2)) == root_id and int(event.get("command_seq", -2)) == command_seq:
				return {"kind": &"character_raise", "actor_id": int(event.actor_unit_id), "target_id": int(event.target_unit_id), "cell": event.cell}
		return {}
	if kind != &"use_healing_item" and kind != &"use_summoning_item": return {}
	var used: Dictionary = {}
	for event: Dictionary in events:
		if event.get("kind") == &"item_used" and int(event.get("root_id", -2)) == root_id and int(event.get("command_seq", -2)) == command_seq:
			used = event
			break
	if used.is_empty(): return {}
	var actor_id := int(used.get("actor_unit_id", UnitId.NONE))
	if kind == &"use_healing_item":
		if int(used.get("target_unit_id", UnitId.NONE)) != actor_id: return {}
		var healed := false
		for event: Dictionary in events:
			var source: Dictionary = event.get("source", {})
			if event.get("kind") == &"healed" and int(event.get("root_id", -2)) == root_id and int(event.get("command_seq", -2)) == command_seq and int(event.get("target_unit_id", UnitId.NONE)) == actor_id and source.get("kind") == &"item" and int(source.get("source_instance_id", -1)) == int(used.get("item_instance_id", -2)):
				healed = true
				break
		if not healed: return {}
		return {"kind": &"item_potion", "actor_id": actor_id, "target_id": actor_id, "cell": _view_unit_cell(actor_id)}
	for event: Dictionary in events:
		if event.get("kind") == &"summoned" and int(event.get("root_id", -2)) == root_id and int(event.get("command_seq", -2)) == command_seq and int(event.get("actor_unit_id", UnitId.NONE)) == actor_id and int(event.get("item_instance_id", -1)) == int(used.get("item_instance_id", -2)):
			return {"kind": &"item_seal", "actor_id": actor_id, "target_id": int(event.target_unit_id), "cell": event.cell}
	return {}

func _animate_support_action(frame: Dictionary) -> Tween:
	_create_support_effect(StringName(frame.kind), int(frame.actor_id), frame.cell, int(frame.target_id))
	var tween := create_tween()
	tween.tween_method(_sample_support.bind(&"prepare"), 0.0, 1.0, 0.10)
	tween.tween_method(_sample_support.bind(&"delivery"), 0.0, 1.0, 0.22)
	tween.tween_method(_sample_support.bind(&"contact"), 0.0, 1.0, 0.20)
	return tween

func _create_support_effect(kind: StringName, actor_id: int, cell: Vector2i, target_id: int) -> void:
	if is_instance_valid(_support_effect):
		remove_child(_support_effect)
		_support_effect.free()
	_support_kind = kind
	_support_actor_id = actor_id
	_support_target_cell = cell
	_support_target_id = target_id
	_support_effect = support_effect_scene.instantiate() as BattleSupportEffect
	add_child(_support_effect)
	_support_effect.z_index = RenderLayers.z_index_for(RenderLayers.Layer.VFX_OVERLAY) + 2
	_support_started = kind in [&"item_potion", &"item_seal", &"character_raise"]
	_sample_support(0.0, &"prepare")

func _begin_support_contact() -> void:
	_support_started = true
	if is_instance_valid(_support_effect): _support_effect.visible = true
	_sample_support(0.0, &"contact")

func _sample_support(progress: float, phase: StringName) -> void:
	if not _support_started or not is_instance_valid(_support_effect): return
	var source := Vector2(20.0, 52.0) if _support_kind in [&"mage_summon", &"mage_raise"] else _support_anchor(_support_actor_id)
	var target := world_to_view(_world_cell_center(_support_target_cell))
	if _support_kind == &"item_potion": target = source
	_support_effect.sample(_support_kind, phase, progress, source, target)

func _support_anchor(unit_id: int) -> Vector2:
	var visual := _presentation_visual(unit_id)
	if visual == null: return world_to_view(_world_cell_center(_view_unit_cell(unit_id)))
	return world_to_view(visual.position + visual.get_visual_offset())

func _update_mage_geometry(phase: StringName = &"prepare", progress: float = 0.0) -> void:
	if not is_instance_valid(_mage_effect): return
	var source_point := Vector2(20.0, 52.0)
	var visual := _presentation_visual(_mage_target_id)
	var anchor := visual.get_node_or_null("ArtRoot/EffectAnchor") as Node2D if visual != null else null
	var world_point := _world_cell_center(_view_unit_cell(_mage_target_id)) + ((anchor.position if anchor != null else Vector2(0, -18)) * grid_config.tile_size.x / 128.0)
	if _mage_target_cell.x >= 0: world_point = _world_cell_center(_mage_target_cell)
	_mage_effect.spell_id = _mage_spell_id
	_mage_effect.sample(phase, progress, source_point, world_to_view(world_point))

func _mage_contact(cast: Dictionary, spell: StringName) -> void:
	var target_id := int(cast.get("target_unit_id", UnitId.NONE))
	var visual := _presentation_visual(target_id)
	if visual != null and spell == &"mage.fire":
		_mage_recoil_direction = (world_to_view(_world_cell_center(_view_unit_cell(target_id))) - Vector2(20, 52)).normalized()
	if spell == &"mage.fire": _hit_impact(cast, Color("ffb35c"))

static func has_presentation_animation(events: Array) -> bool:
	for event: Dictionary in events:
		if event.get("kind", &"") in [&"moved", &"fell", &"hit_resolved", &"balance_changed", &"balance_broken", &"chain_link", &"push_blocked", &"collision", &"trap_fired"] or not _presentation_caption(event).is_empty(): return true
	return false

func _ready() -> void:
	if not authored_layout:
		custom_minimum_size = Vector2(520, 520)
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
	_tiles = _layer("TilesLayer", RenderLayers.Layer.TILES)
	_entities = _layer("EntitiesLayer", RenderLayers.Layer.ENTITIES)
	_entities.y_sort_enabled = true
	_ghosts = _layer("FallingFigures", RenderLayers.Layer.VFX_OVERLAY)
	_impacts = _layer("HitImpacts", RenderLayers.Layer.VFX_OVERLAY)
	_numbers = _layer("ResultNumbers", RenderLayers.Layer.VFX_OVERLAY)
	_overlay = _layer("PathOverlay", RenderLayers.Layer.UI_PREVIEW)
	_overlay.draw.connect(_draw_overlay)
	compact_forecast = get_node_or_null("CompactForecast") as BattleForecastCard
	if compact_forecast == null:
		compact_forecast = BattleForecastCard.new()
		compact_forecast.name = "CompactForecast"
		add_child(compact_forecast)
	mouse_exited.connect(_clear_hover)
	if camera_controls_enabled: _build_camera_controls()
	_rescale_layout()
	_apply_camera()

func _build_camera_controls() -> void:
	var controls := get_node_or_null("CameraControls") as HBoxContainer
	if controls == null:
		controls = (load("res://scenes/demo/battle/camera_controls.tscn") as PackedScene).instantiate() as HBoxContainer
		add_child(controls)
	controls.z_index = RenderLayers.z_index_for(RenderLayers.Layer.UI_PREVIEW) + 1
	_camera_reset = controls.get_node("ResetCamera") as Button
	_camera_reset.pressed.connect(reset_camera)
	(controls.get_node("ZoomOut") as Button).pressed.connect(func() -> void: zoom_camera(camera_view.zoom / 1.1, size * 0.5))
	(controls.get_node("ZoomIn") as Button).pressed.connect(func() -> void: zoom_camera(camera_view.zoom * 1.1, size * 0.5))

func world_to_view(point: Vector2) -> Vector2:
	return camera_view.world_to_view(point)

func view_to_world(point: Vector2) -> Vector2:
	return camera_view.view_to_world(point)

func cell_center(cell: Vector2i) -> Vector2:
	return world_to_view(_world_cell_center(cell))

func zoom_camera(value: float, anchor: Vector2) -> void:
	camera_view.zoom_at(value, anchor)
	_apply_camera()

func pan_camera(delta: Vector2) -> void:
	camera_view.pan(delta)
	_apply_camera()

func reset_camera() -> void:
	_cancel_camera_gesture()
	camera_view.reset()
	_apply_camera()

func _cancel_camera_gesture() -> void:
	_camera_gesture_active = false
	_camera_dragging = false
	_camera_press_position = Vector2.ZERO
	_camera_last_position = Vector2.ZERO
	_camera_max_displacement = 0.0

func _apply_camera() -> void:
	# Меняется только canvas-преобразование: текущие Tween и показанные узлы живут дальше.
	for layer: Node2D in [_tiles, _entities, _ghosts, _impacts, _numbers, _overlay]:
		if layer != null: layer.transform = camera_view.get_transform()
	if _camera_reset != null: _camera_reset.text = "%d%%" % roundi(camera_view.zoom * 100.0)
	if compact_forecast != null: compact_forecast.place(self)
	_update_mage_geometry(_mage_effect.phase if is_instance_valid(_mage_effect) else &"prepare", _mage_effect.progress if is_instance_valid(_mage_effect) else 0.0)
	_sample_support(_support_effect.progress if is_instance_valid(_support_effect) else 0.0, _support_effect.phase if is_instance_valid(_support_effect) else &"prepare")
	queue_redraw()

func _camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Прогноз получает прежнюю прокрутку первым; Ctrl явно выбирает камеру.
			if (not camera_controls_enabled or not button.ctrl_pressed) and forecast_wheel_handler.is_valid() and bool(forecast_wheel_handler.call(event)): return true
			if not camera_controls_enabled: return false
			var ticks := clampf(button.factor if button.factor > 0.0 else 1.0, 0.05, 8.0)
			zoom_camera(camera_view.zoom * pow(1.1, ticks if button.button_index == MOUSE_BUTTON_WHEEL_UP else -ticks), button.position)
			return true
		if camera_controls_enabled and button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_camera_gesture_active = true
				_camera_dragging = false
				_camera_press_position = button.global_position
				_camera_last_position = button.global_position
				_camera_max_displacement = 0.0
			return true
	elif camera_controls_enabled and event is InputEventMouseMotion and _camera_gesture_active:
		return true
	return false

func _input(event: InputEvent) -> void:
	if not camera_controls_enabled or not _camera_gesture_active: return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var position := motion.global_position
		_camera_max_displacement = maxf(_camera_max_displacement, position.distance_to(_camera_press_position))
		if not _camera_dragging and _camera_max_displacement >= 6.0:
			_camera_dragging = true
			# Первый заметный сдвиг применяет весь путь с точки нажатия, даже если был jitter.
			pan_camera(position - _camera_press_position)
		elif _camera_dragging:
			pan_camera(position - _camera_last_position)
		_camera_last_position = position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		var should_cancel := not _camera_dragging
		_cancel_camera_gesture()
		# Сигнал выдаётся на отпускании в глобальном input, чтобы клик снаружи доски тоже завершал жест ровно один раз.
		if should_cancel: cancel_requested.emit()

func _layer(label: String, layer: RenderLayers.Layer) -> Node2D:
	var result := Node2D.new()
	result.name = label
	result.z_index = RenderLayers.z_index_for(layer)
	add_child(result)
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _rescale_layout()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]: _cancel_camera_gesture()

func refresh() -> void:
	if execution_pending: return
	var live_board: BattleBoard = session.board if session != null else null
	if live_board != _shown_board:
		reset_camera()
		clear_presentation_feedback()
		_clear_falls()
		_fallen_ids.clear()
		_shown_board = live_board
	_capture_board_view(live_board)
	inspection_cells.clear()
	var inspected := session.board.get_unit_by_id(inspected_id) if session != null and session.board != null else null
	var inspecting_enemy := inspected != null and inspected.is_alive() and inspected.faction == Faction.Type.ENEMY and session is BattleTacticalSession and (session as BattleTacticalSession).can_player_act()
	if inspecting_enemy:
		# Следующий ход ещё не пополнял врага: показываем полную будущую дальность.
		var finder := GridPathfinder.new()
		finder.configure(session.board.get_bounds(), session.board.make_spatial_data_provider(inspected), 1, &"spatial_move_v1")
		inspection_cells = finder.get_reachable_cells(inspected.cell, inspected.get_stat(StatTypes.StatType.MOVE_RANGE))
		_reachable = {}
	else:
		inspected_id = UnitId.NONE
		_reachable = session.reachable_cells() if session != null else {}
	# Состояние ограничивает добровольный путь, но не выбор персонажа и не толчки.
	if inspected != null and ControlRules.action_reason(inspected, true) != &"": inspection_cells.clear()
	if session != null and session.selected_unit() != null and ControlRules.action_reason(session.selected_unit(), true) != &"": _reachable.clear()
	if retreat_mode and (not session is BattleCoreReactionsSession or (session as BattleCoreReactionsSession).retreat_reason() != &""): _reachable.clear()
	if summoning_mode and session is BattleTacticalSession:
		_reachable = {}
		for cell in (session as BattleTacticalSession).summoning_cells(): _reachable[cell] = 0.0
	if raising_mode and session is BattleEnvironmentSession:
		_reachable = {}
		for cell in (session as BattleEnvironmentSession).raise_hint_cells(): _reachable[cell] = 0.0
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying():
		_reachable = (session as BattleCoreCombinationSession).deployment_cells()
	_refresh_path()
	_rebuild_visuals()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

func refresh_forecast() -> void:
	if execution_pending: return
	# Наведение меняет только прогноз: сохраняем узлы доски и уже найденную доступность.
	_refresh_path()
	for visual: BattleDemoIsoVisual in _entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT and visual.unit != null:
			visual.forecast_entry = _forecast_entry(visual.unit.id)
			visual.queue_redraw()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

func reachable_cells() -> Dictionary:
	return inspection_cells if inspected_id != UnitId.NONE else _reachable

func _world_cell_center(cell: Vector2i) -> Vector2:
	var steps := _view_height_steps(cell)
	return IsoGridUtils.grid_to_screen(cell, grid_config, 0) - Vector2(0, float(steps) * 0.5 * grid_config.height_step)

func cell_at(point: Vector2) -> Vector2i:
	if execution_pending or _view_width <= 0 or _view_height <= 0: return Vector2i(-1, -1)
	point = view_to_world(point)
	# Те же поверхности, но в обратном порядке их фактической отрисовки.
	for i in range(_entity_visuals.size() - 1, -1, -1):
		if _entity_visuals[i].contains_point(point): return _entity_visuals[i].grid_anchor
	for i in range(_tile_visuals.size() - 1, -1, -1):
		if _tile_visuals[i].contains_point(point): return _tile_visuals[i].grid_anchor
	return Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
	if _camera_input(event):
		accept_event()
		return
	if execution_pending:
		# Осмотр использует только опубликованные значения и экранные фигуры.
		if event is InputEventMouseMotion:
			displayed_unit_hovered.emit(displayed_unit_at(event.position))
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT: displayed_unit_hovered.emit(displayed_unit_at(event.position))
			accept_event()
		return
	if event is InputEventMouseMotion:
		displayed_unit_hovered.emit(displayed_unit_at(event.position))
		var cell := cell_at((event as InputEventMouseMotion).position)
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
			if _overlay != null: _overlay.queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(button.position)
			if cell.x >= 0: cell_clicked.emit(cell)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			cancel_requested.emit()
			accept_event()

func _clear_hover() -> void:
	displayed_unit_hovered.emit(UnitId.NONE)
	hover_cell = Vector2i(-1, -1)
	cell_hovered.emit(hover_cell)
	refresh_forecast()
	if _overlay != null: _overlay.queue_redraw()

func displayed_unit_at(point: Vector2) -> int:
	point = view_to_world(point)
	_sort_visuals()
	for index in range(_entity_visuals.size() - 1, -1, -1):
		var visual := _entity_visuals[index]
		if not visual.contains_point(point): continue
		return visual.unit.id if visual.unit != null else UnitId.NONE
	return UnitId.NONE

func set_acting_unit(id: int) -> void:
	acting_id = id
	for visual: BattleDemoIsoVisual in _entity_visuals:
		visual.acting = visual.unit != null and visual.unit.alive and visual.unit.id == id
		visual.queue_redraw()

func set_hovered_unit(id: int) -> void:
	hovered_unit_id = id
	for visual: BattleDemoIsoVisual in _entity_visuals:
		visual.hovered = visual.unit != null and visual.unit.alive and visual.unit.id == id
		visual.queue_redraw()

func displayed_names() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in _view_units: result[row.unit.id] = row.unit.debug_name
	return result

func displayed_unit_summary(unit_id: int) -> String:
	for row: Dictionary in _view_units:
		var value: BattleUnitView = row.unit
		if value.id != unit_id: continue
		var summary := "%s · HP %.1f/%.1f · броня %.1f" % [value.debug_name, value.hp, value.hp_max, float(row.armor.get("current", 0))]
		if unit_id == displayed_selected_id: summary = "Выбран · " + summary
		if unit_id == acting_id: summary = "Действует · " + summary
		if not value.alive: summary += " · погиб"
		var states := BattleStatusPresentation.summary(row.get("statuses", [])) if value.alive else ""
		return summary + ("\n" + states if not states.is_empty() else "")
	return "Наведите на фигуру для осмотра."

func displayed_unit_details(unit_id: int) -> String:
	for row: Dictionary in _view_units:
		var value: BattleUnitView = row.unit
		if value.id != unit_id: continue
		if not value.alive: return "%s · погиб" % value.debug_name
		var lines: PackedStringArray = ["%s · HP %.1f/%.1f" % [value.debug_name, value.hp, value.hp_max],
			"Броня %.1f/%.1f · запас равновесия %s" % [float(row.armor.get("current", 0)), float(row.armor.get("maximum", 0)), BattleBalanceDisplay.value_text(value.balance, value.balance_max)]]
		if value.balance_max <= 0.0:
			lines.append("Невосприимчив к потере равновесия.")
		else:
			lines.append("Полная шкала означает устойчивость. Воздействие тратит запас.")
			lines.append("После пробоя запас вновь полный.")
			lines.append("В начале своего командного хода восстанавливается до 1 ед. равновесия.")
			if value.balance >= value.balance_max:
				lines.append("Запас исчерпан; пробой проверяется при следующем воздействии. При переполненном нарушении запас может оставаться нулевым.\nСнижение порога само по себе не вызывает сдвиг.")
		var resources: Dictionary = row.get("resources", {})
		if not resources.is_empty():
			lines.append("Действия: основное %d · доп. %d · движение %.1f" % [int(resources.get("main", 0)), int(resources.get("bonus", 0)), float(resources.get("move", 0))])
		lines.append(BattleStatusPresentation.details(row.get("statuses", [])))
		if bool(row.get("raised_shield", {}).get("active", false)): lines.append("Поднять щиты: блок 90% прямого урона первой атаки; до следующего своего хода.")
		var reaction_details := BattleReactionPresentation.details(row.get("reaction_view", {}), displayed_names())
		if not reaction_details.is_empty(): lines.append(reaction_details)
		return "\n".join(lines)
	return "Наведите на фигуру для осмотра."

func _refresh_path() -> void:
	if execution_pending: return
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying():
		_path.clear()
		return
	_path.clear()
	if move_forecast_pending:
		# Маршрут запроса виден сразу, но не обещает пройти опасные клетки до конца.
		_path = pending_move_path.duplicate()
		return
	if move_forecast != null:
		# После прерывания не рисуем непроходимый остаток как будущий ход.
		if move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]: _path = move_forecast.traversed_path.duplicate()
		return
	if session != null and not attack_mode and not summoning_mode and not raising_mode and not elemental_mode and inspected_id == UnitId.NONE and _reachable.has(hover_cell): _path = session.path_to(hover_cell)

func _rescale_layout() -> void:
	if _camera_layout_size != Vector2.ZERO: camera_view.recenter_after_resize(_camera_layout_size * 0.5, size * 0.5)
	_camera_layout_size = size
	var base_size := IsoGridConfig.DEFAULT_TILE_SIZE
	var factor := 1.0 if camera_controls_enabled else maxf(0.1, minf((size.x - 64) / (base_size.x * 8.0), (size.y - 108) / (base_size.y * 8.0 + 32.0)))
	# Базовая геометрия в камере остаётся читаемой независимо от размера поля.
	grid_config.tile_size = base_size * factor
	grid_config.height_step = 32 * factor
	grid_config.origin_offset = Vector2(size.x * 0.5, size.y * 0.5 - grid_config.tile_size.y * 3.5)
	# Более высокий ромб требует запаса сверху для стартовых фигур при 100%.
	# Это постоянное кадрирование: resize и ручная камера сохраняют прежние преобразования.
	if camera_controls_enabled: grid_config.origin_offset.y += grid_config.tile_size.x * 0.5
	if is_inside_tree():
		if not execution_pending: _clear_falls()
		_rebuild_visuals()
		_place_result_numbers()
		_place_impacts()
		_place_projectiles()
		_place_reaction_cues()
		_apply_camera()
		queue_redraw()
		if _overlay != null: _overlay.queue_redraw()

func _clear_layer(layer: Node2D) -> void:
	if layer == null: return
	for child in layer.get_children():
		layer.remove_child(child)
		child.queue_free()

func _rebuild_visuals() -> void:
	if _entities == null: return
	_tile_visuals.clear()
	_entity_visuals.clear()
	_clear_layer(_tiles)
	_prepare_terrain_rebuild()
	if _view_width <= 0 or _view_height <= 0: return
	var cells: Array[Vector2i] = []
	for y in _view_height:
		for x in _view_width: cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.y < b.y))
	for cell in cells:
		var steps := _view_height_steps(cell)
		var terrain := _view_terrain_at(cell)
		var floor_visual := _terrain_visual(cell, steps, false)
		var burning := false
		for fire: Dictionary in _view_fires:
			if fire.get("cell", Vector2i(-1, -1)) == cell and String(fire.get("effect", "bleeding")) == "burning": burning = true
		# Видимые поверхности всех высот сортируются вместе: ближний пол закрывает
		# дальнюю грань уступа. Разделение по высоте на два слоя ломает это перекрытие.
		_attach_visual(floor_visual)
		_apply_terrain_view(floor_visual, cell, steps, false, terrain == TerrainType.Type.VOID,
			not attack_mode and not elemental_mode and _reachable.has(cell),
			inspected_id != UnitId.NONE and inspection_cells.has(cell), burning)
		_add_environment_visual(floor_visual, cell)
		if terrain == TerrainType.Type.WALL:
			var wall := _terrain_visual(cell, steps, true)
			_attach_visual(wall)
			_apply_terrain_view(wall, cell, steps, true)
	for row: Dictionary in _view_units:
		var unit: BattleUnitView = row["unit"]
		var unit_cell: Vector2i = row["cell"]
		if not _unit_row_visible(row): continue
		var visual: BattleDemoIsoVisual = _unit_visuals.get(unit.id)
		if visual == null:
			visual = _make_visual(unit_cell, _view_height_steps(unit_cell), BattleDemoIsoVisual.Role.UNIT)
			_visual_lifecycle.unit_created += 1
			if visual is BattleManagedUnitVisual: _unit_visuals[unit.id] = visual
		if visual is BattleManagedUnitVisual:
			_attach_visual(visual)
			var managed := visual as BattleManagedUnitVisual
			managed.reset_view_pose()
			managed.apply_view(_unit_view_values(row), grid_config)
			var offset := (_action_offsets.get(unit.id, Vector2.ZERO) as Vector2) * grid_config.tile_size.x / 128.0
			if visual.action_offset != offset: visual.action_offset = offset
			continue
		# Не принявшая lifecycle сцена сохраняет прежний путь полной пересборки.
		visual.unit = unit
		visual.visual_class_id = _view_visual_classes.get(unit.id, &"")
		visual.selected = bool(row["selected"]) and unit.alive
		visual.inspected = bool(row["inspected"]) and unit.alive
		visual.hovered = unit.id == hovered_unit_id and unit.alive
		visual.acting = unit.id == acting_id and unit.alive
		visual.forecast_entry = _forecast_entry(unit.id)
		visual.show_rear = bool(row["show_rear"])
		visual.armor_values = (row["armor"] as Dictionary).duplicate(true)
		visual.shield_view = row.get("shield", {}).duplicate(true)
		visual.raised_shield_view = row.get("raised_shield", {}).duplicate(true)
		visual.summon_pending = bool(row.get("pending", false))
		visual.status_entries.assign(row.get("statuses", []).duplicate(true))
		visual.reaction_view = row.get("reaction_view", {}).duplicate(true)
		visual.action_resources_view = (row.get("resources", {}) as Dictionary).duplicate(true)
		visual.status_text = BattleStatusPresentation.summary(visual.status_entries)
		visual.frozen = BattleStatusPresentation.has(visual.status_entries, "frozen")
		visual.stunned = BattleStatusPresentation.has(visual.status_entries, "stunned")
		visual.entangled = BattleStatusPresentation.has(visual.status_entries, "entangled")
		_attach_visual(visual)
		visual.sync_scene_art()
		visual.action_offset = (_action_offsets.get(unit.id, Vector2.ZERO) as Vector2) * grid_config.tile_size.x / 128.0
	_sort_visuals()
	_field_presentation.restore(self)

func _unit_row_visible(row: Dictionary) -> bool:
	var unit: BattleUnitView = row["unit"]
	if environment_mode and not unit.alive: return false
	return unit.alive or (not _fallen_ids.has(unit.id) and _view_terrain_at(row["cell"]) not in [TerrainType.Type.VOID, TerrainType.Type.HAZARD])

func _unit_view_values(row: Dictionary) -> Dictionary:
	var unit: BattleUnitView = row["unit"]
	return {"cell": row["cell"], "half_steps": _view_height_steps(row["cell"]),
		"unit": {"id": unit.id, "faction": int(unit.faction), "name": unit.debug_name,
			"alive": unit.alive, "hp": unit.hp, "hp_max": unit.hp_max,
			"balance": unit.balance, "balance_max": unit.balance_max},
		"visual_class_id": _view_visual_classes.get(unit.id, &""),
		"selected": bool(row["selected"]) and unit.alive,
		"inspected": bool(row["inspected"]) and unit.alive,
		"hovered": unit.id == hovered_unit_id and unit.alive,
		"acting": unit.id == acting_id and unit.alive,
		"forecast_entry": _forecast_entry(unit.id), "show_rear": bool(row["show_rear"]),
		"armor_values": row["armor"], "shield_view": row.get("shield", {}),
		"raised_shield_view": row.get("raised_shield", {}),
		"summon_pending": bool(row.get("pending", false)),
		"status_entries": row.get("statuses", []), "reaction_view": row.get("reaction_view", {}),
		"action_resources_view": row.get("resources", {})}

func _retain_unit_visuals(retained: Dictionary[int, bool]) -> void:
	var board_id := _shown_board.get_instance_id() if _shown_board != null else 0
	# Во время worker runtime закрыт для UI; resize использует прежнюю область владения.
	var session_id := session.get_instance_id() if session != null else _unit_session_id
	var dimensions := Vector2i(_view_width, _view_height)
	if board_id != _unit_board_id or session_id != _unit_session_id or dimensions != _unit_size or unit_visual_scene != _unit_scene:
		for visual: BattleManagedUnitVisual in _unit_visuals.values(): _retire_unit_visual(visual)
		_unit_visuals.clear()
	_unit_board_id = board_id
	_unit_session_id = session_id
	_unit_size = dimensions
	_unit_scene = unit_visual_scene
	var visible_ids: Dictionary[int, bool] = {}
	for row: Dictionary in _view_units:
		if _unit_row_visible(row): visible_ids[(row["unit"] as BattleUnitView).id] = true
	for id: int in _unit_visuals.keys():
		var visual := _unit_visuals[id]
		if not visible_ids.has(id) or not is_instance_valid(visual) or visual.is_queued_for_deletion() or visual.get_parent() != _entities:
			_retire_unit_visual(visual)
			_unit_visuals.erase(id)
		else:
			retained[visual.get_instance_id()] = true

func _retire_unit_visual(visual: BattleDemoIsoVisual) -> void:
	if not is_instance_valid(visual): return
	_visual_lifecycle.unit_retired += 1
	if visual is BattleManagedUnitVisual: (visual as BattleManagedUnitVisual).retire_view()
	if visual.get_parent() != null: visual.get_parent().remove_child(visual)
	visual.queue_free()

func _prepare_terrain_rebuild() -> void:
	var board_id := _shown_board.get_instance_id() if _shown_board != null else 0
	var dimensions := Vector2i(_view_width, _view_height)
	if board_id != _terrain_board_id or dimensions != _terrain_size or tile_visual_scene != _terrain_scene:
		_terrain_visuals.clear()
	_terrain_board_id = board_id
	_terrain_size = dimensions
	_terrain_scene = tile_visual_scene
	var retained: Dictionary[int, bool] = {}
	for key: Vector3i in _terrain_visuals.keys():
		var visual := _terrain_visuals[key]
		var cell := Vector2i(key.x, key.y)
		if not is_instance_valid(visual) or visual.is_queued_for_deletion() or visual.get_parent() != _entities or (key.z == 1 and _view_terrain_at(cell) != TerrainType.Type.WALL):
			_terrain_visuals.erase(key)
		else:
			retained[visual.get_instance_id()] = true
	var preserve_overlays := environment_visual_scene == _environment_scene
	for cell: Vector2i in _environment_visuals.keys():
		var overlay := _environment_visuals[cell] as BattleEnvironmentVisual
		var parent := overlay.get_parent() as BattleDemoIsoVisual if is_instance_valid(overlay) else null
		if not preserve_overlays or not overlay is BattleManagedEnvironmentVisual or parent == null or not retained.has(parent.get_instance_id()) or overlay.is_queued_for_deletion():
			_retire_environment_visual(cell)
	_environment_scene = environment_visual_scene
	_retain_unit_visuals(retained)
	for child: Node in _entities.get_children():
		if retained.has(child.get_instance_id()): continue
		if child is BattleDemoIsoVisual and (child as BattleDemoIsoVisual).role != BattleDemoIsoVisual.Role.UNIT:
			_visual_lifecycle.terrain_retired += 1
			if child is BattleTerrainVisual: (child as BattleTerrainVisual).retire_view()
		elif child is BattleDemoIsoVisual:
			_retire_unit_visual(child as BattleDemoIsoVisual)
			continue
		_entities.remove_child(child)
		child.queue_free()

func visual_lifecycle_counts() -> Dictionary:
	return _visual_lifecycle.duplicate()

func _terrain_visual(cell: Vector2i, steps: int, wall: bool) -> BattleDemoIsoVisual:
	var role := BattleDemoIsoVisual.Role.WALL if wall else (BattleDemoIsoVisual.Role.PLATFORM if steps > 0 else BattleDemoIsoVisual.Role.FLOOR)
	var key := Vector3i(cell.x, cell.y, 1 if wall else 0)
	var visual := _terrain_visuals.get(key) as BattleDemoIsoVisual
	if visual == null:
		visual = _make_visual(cell, steps, role)
		_visual_lifecycle.terrain_created += 1
		# Наследование — явное принятие lifecycle; имя/путь PackedScene не участвуют.
		if visual is BattleTerrainVisual: _terrain_visuals[key] = visual
	return visual

func _apply_terrain_view(visual: BattleDemoIsoVisual, cell: Vector2i, steps: int, wall: bool,
		void_surface: bool = false, can_reach: bool = false, in_enemy_range: bool = false, burning: bool = false) -> void:
	var role := BattleDemoIsoVisual.Role.WALL if wall else (BattleDemoIsoVisual.Role.PLATFORM if steps > 0 else BattleDemoIsoVisual.Role.FLOOR)
	if visual is BattleTerrainVisual:
		var managed := visual as BattleTerrainVisual
		managed.reset_view_pose()
		managed.apply_view({"cell": cell, "role": role, "half_steps": steps,
			"is_void": void_surface, "reachable": can_reach, "enemy_range": in_enemy_range,
			"burning": burning}, grid_config)
	else:
		# Legacy-сцены остаются свежими; контракт допуска нового арта их отклоняет.
		visual.grid_config = grid_config
		visual.role = role
		visual.half_steps = steps
		visual.set_grid_anchor(cell)
		visual.burning = burning
		visual.is_void = void_surface
		visual.reachable = can_reach
		visual.enemy_range = in_enemy_range
		visual.sync_scene_art()

func _attach_visual(visual: BattleDemoIsoVisual) -> void:
	if visual.get_parent() == null: _entities.add_child(visual)
	# При равной глубине picking и Y-sort должны видеть прежний порядок клеток,
	# даже если стена появилась позже соседнего сохранённого узла.
	var index := _entity_visuals.size()
	if visual.get_index() != index: _entities.move_child(visual, index)
	_entity_visuals.append(visual)

func _add_environment_visual(floor_visual: BattleDemoIsoVisual, cell: Vector2i, force: bool = false) -> void:
	if _view_terrain_at(cell) != TerrainType.Type.FLOOR:
		_retire_environment_visual(cell)
		return
	var corpses: Array[Dictionary] = []
	for corpse: Dictionary in _view_corpses:
		if corpse.cell == cell: corpses.append(corpse)
	var spikes := false
	for fire: Dictionary in _view_fires:
		if fire.cell == cell and fire.get("effect", "bleeding") != "burning": spikes = true
	var warning := cell in _view_collapse
	var acid: bool = cell in _view_hazards.get("acid", [])
	var trap := _trap_at_cell(cell)
	# Активная поза просит overlay повторно после rebuild, поэтому держим его до restore.
	var has_presentation_pose := _field_presentation.cells.has(cell)
	if not force and not has_presentation_pose and not spikes and not floor_visual.burning and not warning and corpses.is_empty() and not acid and trap.is_empty():
		_retire_environment_visual(cell)
		return
	var overlay := _environment_visuals.get(cell) as BattleEnvironmentVisual
	if not is_instance_valid(overlay) or overlay.is_queued_for_deletion() or overlay.get_parent() != floor_visual:
		_retire_environment_visual(cell)
		overlay = environment_visual_scene.instantiate() as BattleEnvironmentVisual
		floor_visual.add_child(overlay)
		_environment_visuals[cell] = overlay
		_visual_lifecycle.environment_created += 1
	if overlay is BattleManagedEnvironmentVisual:
		(overlay as BattleManagedEnvironmentVisual).reset_view_pose()
	else:
		if overlay.collapse_progress != -1.0: overlay.collapse_progress = -1.0
		if overlay.hazard_progress != -1.0: overlay.hazard_progress = -1.0
		if overlay.trap_progress != -1.0: overlay.trap_progress = -1.0
	var overlay_position := floor_visual.get_visual_offset() + Vector2(0, 0.5)
	var overlay_scale := Vector2.ONE * grid_config.tile_size.x / 128.0
	if overlay.position != overlay_position: overlay.position = overlay_position
	if overlay.scale != overlay_scale: overlay.scale = overlay_scale
	var burning_fallback := floor_visual.burning and tile_visual_scene == null
	var floor_trap := String(trap.get("kind", "")) == "floor"
	var direction: Vector2i = trap.get("direction", Vector2i.ZERO)
	var armed := bool(trap.get("armed", false))
	if overlay is BattleManagedEnvironmentVisual:
		(overlay as BattleManagedEnvironmentVisual).apply_view({"spikes": spikes, "burning": burning_fallback,
			"warning": warning, "corpses": corpses, "acid": acid, "floor_trap": floor_trap,
			"wall_direction": direction, "armed": armed})
	else:
		overlay.configure(spikes, burning_fallback, warning, corpses, acid, floor_trap, direction, armed)
	if overlay.warning_phase != _warning_phase: overlay.warning_phase = _warning_phase

func _retire_environment_visual(cell: Vector2i) -> void:
	var overlay := _environment_visuals.get(cell) as BattleEnvironmentVisual
	_environment_visuals.erase(cell)
	if not is_instance_valid(overlay): return
	_visual_lifecycle.environment_retired += 1
	if overlay is BattleManagedEnvironmentVisual: (overlay as BattleManagedEnvironmentVisual).retire_view()
	if overlay.get_parent() != null: overlay.get_parent().remove_child(overlay)
	overlay.queue_free()

func _trap_at_cell(cell: Vector2i) -> Dictionary:
	for trap: Dictionary in _view_hazards.get("traps", []):
		if trap.get("cell", Vector2i(-1, -1)) == cell:
			return {"kind": String(trap.get("kind", "")), "direction": trap.get("direction", Vector2i.ZERO), "armed": int(trap.get("armed_team", -1)) >= 0}
	return {}

func _ensure_environment_visual(cell: Vector2i) -> BattleEnvironmentVisual:
	if not _environment_visuals.has(cell):
		for visual: BattleDemoIsoVisual in _entity_visuals:
			if visual.grid_anchor == cell and visual.role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM]:
				_add_environment_visual(visual, cell, true)
				break
	return _environment_visuals.get(cell) as BattleEnvironmentVisual

func _process(delta: float) -> void:
	if not _terrain_visuals.is_empty():
		# Смена canvas/stretch не обязана прислать transform notification дочерним узлам.
		# Проверяем один transform доски, а авторские стыки обновляем только при его смене.
		var screen_transform := get_screen_transform()
		if screen_transform != _terrain_screen_transform:
			_terrain_screen_transform = screen_transform
			for visual: BattleTerrainVisual in _terrain_visuals.values():
				if is_instance_valid(visual): visual.sync_view_transform()
			for overlay: BattleEnvironmentVisual in _environment_visuals.values():
				if overlay is BattleManagedEnvironmentVisual:
					(overlay as BattleManagedEnvironmentVisual).sync_view_transform()
	_warning_phase = fmod(_warning_phase + delta * TAU / 1.8, TAU)
	for cell: Vector2i in _view_collapse:
		var overlay := _environment_visuals.get(cell) as BattleEnvironmentVisual
		if overlay != null: overlay.warning_phase = _warning_phase

func _sort_visuals() -> void:
	_entity_visuals.sort_custom(func(a: BattleDemoIsoVisual, b: BattleDemoIsoVisual) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.get_index() < b.get_index()))

func _make_visual(cell: Vector2i, steps: int, role: BattleDemoIsoVisual.Role) -> BattleDemoIsoVisual:
	var visual: BattleDemoIsoVisual
	var source := unit_visual_scene if role == BattleDemoIsoVisual.Role.UNIT else tile_visual_scene
	if source != null:
		var candidate := source.instantiate()
		visual = candidate as BattleDemoIsoVisual
		if visual == null: candidate.free()
	if visual == null: visual = BattleDemoIsoVisual.new()
	visual.grid_config = grid_config
	visual.role = role
	visual.half_steps = steps
	visual.set_grid_anchor(cell)
	return visual

func _capture_board_view(board: BattleBoard) -> void:
	action_areas.assign(ActionPresentationState.capture_action_areas(session.state) if session is BattleCoreReactionsSession else [])
	_view_actor_classes.clear()
	_view_visual_classes.clear()
	if session is BattleCoreReactionsSession:
		_view_visual_classes.assign((session as BattleCoreReactionsSession).unit_visual_classes)
		for unit_id: Variant in (session as BattleCoreReactionsSession).actor_loadouts:
			var loadout: Variant = (session as BattleCoreReactionsSession).actor_loadouts[unit_id]
			if loadout is Dictionary:
				_view_actor_classes[int(unit_id)] = StringName(loadout.get("class_id", &""))
				# Отдельный рисунок класса не должен менять его игровой loadout.
				if not _view_visual_classes.has(int(unit_id)):
					_view_visual_classes[int(unit_id)] = StringName(loadout.get("class_id", &""))
	# Рендер и resize читают эту копию, чтобы worker не менял уже показанный кадр.
	_view_width = board.width if board != null else 0
	_view_height = board.height if board != null else 0
	_view_heights = PackedInt32Array()
	_view_terrain = PackedByteArray()
	_view_units.clear()
	_view_fires.clear()
	_view_hazards.clear()
	_view_corpses.clear()
	_view_collapse.clear()
	if board == null: return
	_view_heights.resize(_view_width * _view_height)
	_view_terrain.resize(_view_width * _view_height)
	for y in _view_height:
		for x in _view_width:
			var cell := Vector2i(x, y)
			var index := y * _view_width + x
			_view_heights[index] = board.get_height_steps(cell)
			_view_terrain[index] = board.get_terrain(cell)
	var selected_id := session.selected_id if session != null else UnitId.NONE
	displayed_selected_id = selected_id
	var source_units: Array[UnitState] = session.units if session != null else []
	for unit: UnitState in source_units:
		var value := BattleUnitView.capture(unit)
		if value == null: continue
		var armor: Dictionary = {}
		if unit.armor != null:
			var owner := session.state.get_owner(unit.id)
			if owner != null: armor = ArmorRuntime.totals(ArmorRuntime.capture(owner))
		_view_units.append({
			"unit": value, "cell": unit.cell, "selected": unit.id == selected_id,
			"inspected": unit.id == inspected_id,
			"show_rear": session is BattleControlSession or (session is BattleCoreCombinationSession and not session is BattleCoreReactionsSession),
			"armor": armor.duplicate(true),
			"shield": unit.armor.shield.duplicate(true) if unit.armor != null else {}, "pending": session.state.is_summon_pending(unit.id),
			"raised_shield": unit.armor.raised_shield.duplicate(true) if unit.armor != null else {},
			"reaction_view": ActionPresentationState.capture_reaction_view(session.state, unit),
			"statuses": BattleStatusPresentation.entries({
				"shield": unit.armor.shield.duplicate(true) if unit.armor != null else {},
				"bleeding": unit.bleeding.to_dict() if unit.bleeding != null else {},
				"elemental": unit.elemental.to_dict() if unit.elemental != null else {},
				"control": unit.control.to_dict() if unit.control != null else {}}),
			"resources": {"main": unit.action_resources.get_main_left() if unit.action_resources != null else 0,
				"bonus": unit.action_resources.get_bonus_left() if unit.action_resources != null else 0,
				"move": unit.move_points_left, "reaction": MeleeThreat.reaction_points(unit)},
		})
	var environment: CombatEnvironmentState = session.state.environment if session != null and session.state != null else null
	if environment != null:
		_view_fires = environment.fires.duplicate(true)
		_view_hazards = environment.hazards.duplicate(true)
		_view_corpses = environment.corpses.duplicate(true)
		_view_collapse.assign(environment.collapse.get("marked", []))

func _view_index(cell: Vector2i) -> int:
	return cell.y * _view_width + cell.x if cell.x >= 0 and cell.y >= 0 and cell.x < _view_width and cell.y < _view_height else -1

func _view_height_steps(cell: Vector2i) -> int:
	var index := _view_index(cell)
	return int(_view_heights[index]) if index >= 0 else 0

func _view_terrain_at(cell: Vector2i) -> TerrainType.Type:
	var index := _view_index(cell)
	return int(_view_terrain[index]) as TerrainType.Type if index >= 0 else TerrainType.Type.VOID

func _view_unit_cell(unit_id: int) -> Vector2i:
	for row: Dictionary in _view_units:
		var unit: BattleUnitView = row["unit"]
		if unit.id == unit_id: return row["cell"]
	return Vector2i(-1, -1)

func _draw() -> void:
	if _view_width <= 0 or _view_height <= 0: return
	draw_set_transform_matrix(camera_view.get_transform())
	var hh := grid_config.tile_size.y * 0.5
	var hw := grid_config.tile_size.x * 0.5
	for n in 8:
		draw_string(ThemeDB.fallback_font, IsoGridUtils.grid_to_screen(Vector2i(n, 0), grid_config, 0) + Vector2(5, -hh - 7), String.chr(65 + n), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		draw_string(ThemeDB.fallback_font, IsoGridUtils.grid_to_screen(Vector2i(0, n), grid_config, 0) + Vector2(-hw - 17, 4), str(n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)

func area_details(cell: Vector2i) -> String:
	var lines: PackedStringArray = []
	for area: Dictionary in action_areas:
		if not area.ready or (cell != area.origin and not area.cells.has(cell)): continue
		var mode := "Оппортунист: останавливает при выходе из зоны" if area.mode == CombatPerksState.Mode.OPPORTUNIST else "Контратака: отвечает на прямой ближний удар"
		lines.append("%s · %s · реакция готова" % [area.name, mode])
	return "\n".join(lines)

func _draw_action_areas() -> void:
	for area: Dictionary in action_areas:
		var preview: bool = area.owner_id == area_preview_owner
		if not area.ready and not preview: continue
		var color := ALLY_AREA if area.faction == Faction.Type.PLAYER else ENEMY_AREA
		for cell: Vector2i in area.cells:
			var center := _world_cell_center(cell)
			# Два вложенных контура оставляют различимыми перекрытия разных сторон.
			var inset := 0.42 if area.faction == Faction.Type.PLAYER else 0.48
			var half := grid_config.tile_size * inset
			var points := PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0), center + Vector2(0, half.y), center + Vector2(-half.x, 0), center + Vector2(0, -half.y)])
			if area.ready: _overlay.draw_colored_polygon(points, Color(color, 0.12))
			_overlay.draw_polyline(points, Color(color, 0.85 if preview else 0.6), 2.0 if preview else 1.5, true)
		var origin := _world_cell_center(area.origin)
		_overlay.draw_arc(origin, grid_config.tile_size.x * 0.27, 0, TAU, 32, color, 3.0, true)
		if area.cells.has(hover_cell):
			_overlay.draw_dashed_line(origin, _world_cell_center(hover_cell), color, 1.5, 5.0)

func _draw_cover_links() -> void:
	for row: Dictionary in _view_units:
		var view: Dictionary = row.get("reaction_view", {})
		if not row.unit.alive or int(view.get("mode", 0)) != CombatPerksState.Mode.COVER or not bool(view.get("ready", false)): continue
		var source := _reaction_anchor(int(row.unit.id))
		var target := _reaction_anchor(int(view.get("cover_target_id", 0)))
		_overlay.draw_line(source, target, Color("76d9f2", 0.45), 1.5, true)
		_overlay.draw_arc(target, 9.0, 0.0, TAU, 16, Color("76d9f2", 0.65), 1.5, true)

func _draw_overlay() -> void:
	_draw_cover_links()
	if _view_width <= 0 or _view_height <= 0: return
	var hw := grid_config.tile_size.x * 0.5
	var highlight_hh := grid_config.tile_size.y * 0.48
	var highlight_hw := grid_config.tile_size.x * 0.48
	_draw_action_areas()
	for cell: Vector2i in reaction_zone_cells:
		var center := _world_cell_center(cell)
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -highlight_hh), center + Vector2(highlight_hw, 0), center + Vector2(0, highlight_hh), center + Vector2(-highlight_hw, 0), center + Vector2(0, -highlight_hh)]), Color("a5b3c5", 0.35), 1.0, true)
	for id: int in cover_target_ids:
		var ally_cell := _view_unit_cell(id)
		if ally_cell.x < 0: continue
		var center := _world_cell_center(ally_cell)
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -highlight_hh), center + Vector2(highlight_hw, 0), center + Vector2(0, highlight_hh), center + Vector2(-highlight_hw, 0), center + Vector2(0, -highlight_hh)]), CYAN, 2.5, true)
	for id: int in sneak_threat_ids:
		var threat_cell := _view_unit_cell(id)
		if threat_cell.x < 0: continue
		var center := _world_cell_center(threat_cell)
		_overlay.draw_arc(center, grid_config.tile_size.x * 0.25, 0, TAU, 24, GOLD, 2.5, true)
	if _path.size() > 1:
		var points := PackedVector2Array()
		for cell in _path: points.append(_world_cell_center(cell))
		if move_forecast_pending:
			for i: int in range(1, points.size()):
				_overlay.draw_dashed_line(points[i - 1], points[i], MUTED, 2, 6)
		else:
			_overlay.draw_polyline(points, CYAN, 2, true)
	if _view_index(hover_cell) >= 0:
		var center := _world_cell_center(hover_cell)
		if _view_terrain_at(hover_cell) == TerrainType.Type.WALL: center.y -= grid_config.height_step
		var cell_hw := grid_config.tile_size.x * 0.48
		var hh := grid_config.tile_size.y * 0.48
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -hh), center + Vector2(cell_hw, 0), center + Vector2(0, hh), center + Vector2(-cell_hw, 0), center + Vector2(0, -hh)]), GOLD if attack_mode or elemental_mode or inspected_id != UnitId.NONE else (Color("f29b9b") if raising_mode else CYAN), 2, true)
	if move_forecast != null and move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		var after: Dictionary = move_forecast.units.get(move_forecast.actor_id, {}).get("after", {})
		if not after.is_empty():
			var endpoint := _world_cell_center(after["cell"])
			var color := CYAN if after["alive"] else Color("f29b9b")
			_overlay.draw_arc(endpoint, 10.0, 0, TAU, 24, color, 2.5, true)
	if forecast != null and forecast.status == &"APPLIED":
		var chain_preview := forecast.events.any(func(value: Dictionary) -> bool: return value.get("kind") == &"chain_link")
		for event_variant in forecast.events:
			var event := event_variant as Dictionary
			var kind := StringName(event.get("kind", &""))
			if kind not in [&"moved", &"push_blocked", &"collision", &"fell"]: continue
			var from_cell := Vector2i(-1, -1)
			if event.has("from_cell"): from_cell = event["from_cell"] as Vector2i
			var to_cell := from_cell
			if event.has("to_cell"): to_cell = event["to_cell"] as Vector2i
			elif event.has("attempted_cell"): to_cell = event["attempted_cell"] as Vector2i
			if _view_index(from_cell) < 0: continue
			var start := _world_cell_center(from_cell)
			var finish := _world_cell_center(to_cell) if _view_index(to_cell) >= 0 else start + IsoGridUtils.grid_to_screen(to_cell, grid_config, 0) - IsoGridUtils.grid_to_screen(from_cell, grid_config, 0)
			# Переданный импульс не означает движения промежуточного тела.
			if chain_preview and kind != &"moved":
				_overlay.draw_dashed_line(start, finish, Color("f7c97d"), 2.0, 5.0, true)
				if kind in [&"push_blocked", &"fell"]:
					_overlay.draw_line(finish - Vector2(5, 5), finish + Vector2(5, 5), Color("f29b9b"), 2, true)
					_overlay.draw_line(finish - Vector2(5, -5), finish + Vector2(5, -5), Color("f29b9b"), 2, true)
				continue
			_overlay.draw_line(start, finish, Color("f29b9b"), 3.0, true)
			var direction := (finish - start).normalized()
			_overlay.draw_line(finish, finish - direction.rotated(0.5) * 10.0, Color("f29b9b"), 3.0, true)
			_overlay.draw_line(finish, finish - direction.rotated(-0.5) * 10.0, Color("f29b9b"), 3.0, true)
			_overlay.draw_arc(finish, 6.0, 0, TAU, 16, Color("f29b9b"), 1.5, true)
			if kind in [&"push_blocked", &"collision"]:
				_overlay.draw_line(finish - Vector2(4, 4), finish + Vector2(4, 4), Color.WHITE, 2, true)
				_overlay.draw_line(finish - Vector2(4, -4), finish + Vector2(4, -4), Color.WHITE, 2, true)

func _forecast_entry(unit_id: int) -> Dictionary:
	if move_forecast != null and move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		return move_forecast.units.get(unit_id, {})
	if forecast == null or forecast.status != ActionReceipt.APPLIED: return {}
	var units: Dictionary = forecast.units
	var entry: Variant = units.get(unit_id, {})
	return entry as Dictionary if entry is Dictionary else {}

func animate_fall(unit: UnitState, origin: Vector2i, destination: Vector2i) -> void:
	if execution_pending or unit == null or _ghosts == null: return
	# Команда анимации приходит после завершения worker; отделяем значения до создания tween.
	var unit_view := BattleUnitView.capture(unit)
	if unit_view == null or _falling.has(unit_view.id): return
	# При вылете за границу ядро сохраняет последнюю клетку, но фигура уже упала.
	_fallen_ids[unit_view.id] = true
	_rebuild_visuals()
	var center := _world_cell_center(destination)
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	var mask := Polygon2D.new()
	mask.position = center
	mask.polygon = PackedVector2Array([Vector2(-hw, -160), Vector2(hw, -160), Vector2(hw, 0), Vector2(0, hh), Vector2(-hw, 0)])
	mask.color = Color.TRANSPARENT
	_ghosts.add_child(mask)
	var ghost := BattleDemoIsoVisual.new()
	ghost.grid_config = grid_config
	ghost.role = BattleDemoIsoVisual.Role.UNIT
	ghost.transient_label = unit_view.debug_name
	ghost.transient_tint = CYAN if unit_view.faction == Faction.Type.PLAYER else GOLD
	mask.add_child(ghost)
	ghost.position = _world_cell_center(origin) - center
	_falling[unit_view.id] = mask
	var tween := mask.create_tween()
	tween.tween_property(ghost, "position", Vector2.ZERO, 0.18)
	# После входа в провал передняя кромка скрывает нижнюю часть фигуры.
	tween.tween_callback(func() -> void:
		mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		mask.color = Color.WHITE)
	tween.tween_property(ghost, "fall_drop", grid_config.tile_size.y * 1.4, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ghost, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_fall.bind(unit_view.id, mask))

func is_fall_animating(unit_id: int) -> bool:
	return _falling.has(unit_id)

func _finish_fall(unit_id: int, mask: Polygon2D) -> void:
	_falling.erase(unit_id)
	if is_instance_valid(mask): mask.queue_free()

func _clear_falls() -> void:
	_falling.clear()
	_clear_layer(_ghosts)
