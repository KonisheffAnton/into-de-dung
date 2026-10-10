class_name BattleVisualSceneContract
extends RefCounted

## Проверка допуска пресета. Legacy fallback доски остаётся доступен,
## но не считается выполнением контракта нового арта.
static func validate(terrain_scene: PackedScene, environment_scene: PackedScene) -> Array[String]:
	var errors: Array[String] = []
	if terrain_scene == null:
		errors.append("Terrain preset requires a BattleTerrainVisual scene")
	else:
		var terrain := terrain_scene.instantiate()
		if not terrain is BattleTerrainVisual:
			errors.append("Terrain root must extend BattleTerrainVisual")
		terrain.free()
	if environment_scene == null:
		errors.append("Environment preset requires a BattleManagedEnvironmentVisual scene")
	else:
		var environment := environment_scene.instantiate()
		if not environment is BattleManagedEnvironmentVisual:
			errors.append("Environment root must extend BattleManagedEnvironmentVisual")
		environment.free()
	return errors

static func validate_unit(unit_scene: PackedScene) -> Array[String]:
	var errors: Array[String] = []
	if unit_scene == null:
		errors.append("Unit preset requires a BattleManagedUnitVisual scene")
	else:
		var unit := unit_scene.instantiate()
		if not unit is BattleManagedUnitVisual:
			errors.append("Unit root must extend BattleManagedUnitVisual")
		unit.free()
	return errors
