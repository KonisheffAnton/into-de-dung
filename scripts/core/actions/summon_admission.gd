extends RefCounted
class_name SummonAdmission

## Помощник наследует только существующие пары владельца, без расширения чужих правил.
static func extend(move: MoveRules, attack: AttackRules, id: int, owner_id: int, ready: bool) -> Dictionary:
	if move == null or attack == null or move.validate() != &"" or attack.validate() != &"": return {}
	var actors := attack._actors.duplicate()
	var pairs := attack._pairs.duplicate(true)
	var movers := move._admitted_unit_ids.duplicate()
	if ready:
		if not actors.has(id): actors.append(id)
		if move.allows(owner_id) and not movers.has(id): movers.append(id)
	for pair: Dictionary in attack._pairs:
		if pair["target_unit_id"] == owner_id and pair["actor_unit_id"] != id:
			_add_pair(pairs, pair["actor_unit_id"], id)
		if ready and pair["actor_unit_id"] == owner_id and pair["target_unit_id"] != id:
			_add_pair(pairs, id, pair["target_unit_id"])
	var new_move := MoveRules.new(movers, move.get_max_height_step(), move.get_profile())
	var new_attack := AttackRules.new(actors, pairs, attack._definitions)
	if new_move.validate() != &"" or new_attack.validate() != &"": return {}
	return {"move": new_move, "attack": new_attack}

static func _add_pair(pairs: Array[Dictionary], actor: int, target: int) -> void:
	var pair := {"actor_unit_id": actor, "target_unit_id": target}
	if not pairs.has(pair): pairs.append(pair)

static func values(context: ActionContext) -> Dictionary:
	var move := context.get_move_rules()
	var attack := context.get_attack_rules()
	if move == null or attack == null: return {}
	var definitions: Array[Dictionary] = []
	for definition in attack._definitions: definitions.append({"id": definition.id, "profile": definition.profile})
	return {"movers": move._admitted_unit_ids.duplicate(), "height": move.get_max_height_step(), "profile": move.get_profile(), "move_invalid": move._invalid, "actors": attack._actors.duplicate(), "pairs": attack._pairs.duplicate(true), "definitions": definitions, "attack_invalid": attack._invalid}
