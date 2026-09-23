extends RefCounted
class_name AttackModifiers

static func rear_offset(faction: Faction.Type) -> Vector2i:
	match faction:
		Faction.Type.PLAYER:
			return Vector2i(-1, 0)
		Faction.Type.ENEMY:
			return Vector2i(1, 0)
		_:
			return Vector2i.ZERO

static func is_backstab(actor_cell: Vector2i, target_cell: Vector2i, target_faction: Faction.Type) -> bool:
	var offset: Vector2i = rear_offset(target_faction)
	return offset != Vector2i.ZERO and actor_cell == target_cell + offset
