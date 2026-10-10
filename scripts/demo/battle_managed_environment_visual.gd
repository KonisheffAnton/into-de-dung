class_name BattleManagedEnvironmentVisual
extends BattleEnvironmentVisual

var _view_initialized: bool = false
var view_apply_count: int = 0


func apply_view(values: Dictionary) -> bool:
	var spikes: bool = values["spikes"]
	var burning: bool = values["burning"]
	var warning: bool = values["warning"]
	var corpses: Array[Dictionary] = values["corpses"]
	var acid: bool = values["acid"]
	var floor_plate: bool = values["floor_trap"]
	var wall_direction: Vector2i = values["wall_direction"]
	var armed: bool = values["armed"]
	if _view_initialized and has_spikes == spikes and has_burning_fallback == burning \
		and is_warning == warning and corpse_records == corpses and acid_pool == acid \
		and floor_trap == floor_plate and wall_trap_direction == wall_direction \
		and trap_armed == armed:
		return false
	configure(spikes, burning, warning, corpses, acid, floor_plate, wall_direction, armed)
	_view_initialized = true
	view_apply_count += 1
	return true


func reset_view_pose() -> void:
	# Сбрасываются только временные семплы, чтобы постоянные свойства сцены пережили повторное использование.
	if collapse_progress != -1.0:
		collapse_progress = -1.0
	if hazard_progress != -1.0:
		hazard_progress = -1.0
	if trap_progress != -1.0:
		trap_progress = -1.0


func retire_view() -> void:
	reset_view_pose()
	# configure владеет глубокой копией, поэтому очистка не затрагивает переданные вызывающим данные.
	corpse_records.clear()
	_view_initialized = false


func sync_view_transform() -> void:
	pass
