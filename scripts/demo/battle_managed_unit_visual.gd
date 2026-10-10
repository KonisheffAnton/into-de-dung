class_name BattleManagedUnitVisual
extends BattleDemoIsoVisual

var view_apply_count: int = 0
var _view_initialized: bool = false
var _view_tile_size: Vector2
var _view_height_step: float
var _view_origin_offset: Vector2
var _rest_modulate: Color = Color.WHITE
var _rest_modulate_captured: bool = false


func _ready() -> void:
	super._ready()
	_rest_modulate = modulate
	_rest_modulate_captured = true


func apply_view(values: Dictionary, config: IsoGridConfig) -> bool:
	var cell: Vector2i = values["cell"]
	var steps: int = values["half_steps"]
	var unit_values: Dictionary = values["unit"]
	var statuses: Array[Dictionary] = values["status_entries"]
	var next_visual_class: StringName = values["visual_class_id"]
	var next_forecast: Dictionary = values["forecast_entry"]
	var next_armor: Dictionary = values["armor_values"]
	var next_shield: Dictionary = values["shield_view"]
	var next_raised_shield: Dictionary = values["raised_shield_view"]
	var next_reaction: Dictionary = values["reaction_view"]
	var next_resources: Dictionary = values["action_resources_view"]
	var next_selected: bool = values["selected"]
	var next_inspected: bool = values["inspected"]
	var next_hovered: bool = values["hovered"]
	var next_acting: bool = values["acting"]
	var next_show_rear: bool = values["show_rear"]
	var next_summon_pending: bool = values["summon_pending"]
	var next_status_text := BattleStatusPresentation.summary(statuses)
	var next_frozen := BattleStatusPresentation.has(statuses, "frozen")
	var next_stunned := BattleStatusPresentation.has(statuses, "stunned")
	var next_entangled := BattleStatusPresentation.has(statuses, "entangled")
	var expected_position := IsoGridUtils.grid_to_screen(cell, config, 0)
	var geometry_changed := not _view_initialized or _view_tile_size != config.tile_size \
		or _view_height_step != config.height_step or _view_origin_offset != config.origin_offset
	var geometry_mismatch := role != Role.UNIT or half_steps != steps or grid_anchor != cell \
		or height_level != 0 or position != expected_position or grid_config == null \
		or grid_config.tile_size != config.tile_size or grid_config.height_step != config.height_step \
		or grid_config.origin_offset != config.origin_offset
	var anchor_pose_changed := role != Role.UNIT or grid_anchor != cell or height_level != 0 or position != expected_position
	var values_changed := not _view_initialized or not _unit_view_matches(unit, unit_values) or visual_class_id != next_visual_class \
		or selected != next_selected or inspected != next_inspected or hovered != next_hovered \
		or acting != next_acting or show_rear != next_show_rear or summon_pending != next_summon_pending \
		or forecast_entry != next_forecast or armor_values != next_armor or shield_view != next_shield \
		or raised_shield_view != next_raised_shield or reaction_view != next_reaction \
		or action_resources_view != next_resources or status_entries != statuses \
		or status_text != next_status_text or frozen != next_frozen or stunned != next_stunned or entangled != next_entangled
	var changed := geometry_changed or geometry_mismatch or values_changed
	grid_config = config
	if not changed: return false
	var view := _make_unit_view(unit_values)
	role = Role.UNIT
	half_steps = steps
	if anchor_pose_changed: set_grid_anchor(cell)
	unit = view
	visual_class_id = next_visual_class
	selected = next_selected
	inspected = next_inspected
	hovered = next_hovered
	acting = next_acting
	show_rear = next_show_rear
	summon_pending = next_summon_pending
	forecast_entry = next_forecast.duplicate(true)
	armor_values = next_armor.duplicate(true)
	shield_view = next_shield.duplicate(true)
	raised_shield_view = next_raised_shield.duplicate(true)
	reaction_view = next_reaction.duplicate(true)
	action_resources_view = next_resources.duplicate(true)
	status_entries.assign(statuses.duplicate(true))
	status_text = next_status_text
	frozen = next_frozen
	stunned = next_stunned
	entangled = next_entangled
	_view_tile_size = config.tile_size
	_view_height_step = config.height_step
	_view_origin_offset = config.origin_offset
	_view_initialized = true
	sync_scene_art()
	queue_redraw()
	view_apply_count += 1
	return true


func reset_view_pose() -> void:
	# Обычный кадр снимает только временные позы; авторский цвет нужен для повторного использования сцены.
	if action_offset != Vector2.ZERO: action_offset = Vector2.ZERO
	if presentation_lift != 0.0: presentation_lift = 0.0
	if presentation_offset != Vector2.ZERO: presentation_offset = Vector2.ZERO
	if fall_drop != 0.0: fall_drop = 0.0
	if landing_compression != 0.0: landing_compression = 0.0
	if death_progress != 0.0: death_progress = 0.0
	if transient_label != "": transient_label = ""
	if _rest_modulate_captured and modulate != _rest_modulate: modulate = _rest_modulate


func retire_view() -> void:
	reset_view_pose()
	unit = null
	forecast_entry.clear()
	armor_values.clear()
	shield_view.clear()
	raised_shield_view.clear()
	reaction_view.clear()
	action_resources_view.clear()
	status_entries.clear()
	status_text = ""
	visual_class_id = &""
	selected = false
	inspected = false
	hovered = false
	acting = false
	show_rear = false
	summon_pending = false
	frozen = false
	stunned = false
	entangled = false
	sync_scene_art()
	queue_redraw()
	grid_config = null
	_view_initialized = false


func _make_unit_view(values: Dictionary) -> BattleUnitView:
	var result := BattleUnitView.new()
	result.id = int(values["id"])
	result.faction = int(values["faction"]) as Faction.Type
	result.debug_name = String(values["name"])
	result.alive = bool(values["alive"])
	result.hp = float(values["hp"])
	result.hp_max = float(values["hp_max"])
	result.balance = float(values["balance"])
	result.balance_max = float(values["balance_max"])
	return result


func _unit_view_matches(current: BattleUnitView, values: Dictionary) -> bool:
	return current != null and current.id == int(values["id"]) \
		and int(current.faction) == int(values["faction"]) and current.debug_name == String(values["name"]) \
		and current.alive == bool(values["alive"]) and current.hp == float(values["hp"]) \
		and current.hp_max == float(values["hp_max"]) and current.balance == float(values["balance"]) \
		and current.balance_max == float(values["balance_max"])
