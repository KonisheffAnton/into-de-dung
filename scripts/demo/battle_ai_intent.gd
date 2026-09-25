extends RefCounted
class_name BattleAIIntent

## Неизменяемое по смыслу решение: исполнитель повторно проверяет его на свежем контексте.
## Намерение не хранит UnitState, чтобы решение не удерживало устаревший runtime-объект.

enum Kind {
	WAIT,
	MOVE,
	ATTACK,
	SUMMON,
	GUARD,
}

var kind: Kind = Kind.WAIT
var actor_id: int = UnitId.NONE
var target_id: int = UnitId.NONE
var item_id: int = 0
var cell: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var reaction_mode: int = CombatPerksState.Mode.NONE


static func from_utility(actor: UnitState, action: AIAction, utility_path: Array[Vector2i] = []) -> BattleAIIntent:
	var result := BattleAIIntent.new()
	if actor == null or action == null:
		return result
	result.actor_id = actor.id
	match action.action_type:
		AIAction.Type.MOVE:
			if utility_path.size() >= 2 and utility_path[0] == actor.cell and utility_path[utility_path.size() - 1] == action.final_cell:
				result.kind = Kind.MOVE
				result.path = utility_path.duplicate()
		AIAction.Type.MOVE_AND_ATTACK:
			if action.target == null or not action.target.is_alive():
				return result
			if actor.cell == action.final_cell:
				result.kind = Kind.ATTACK
				result.target_id = action.target.id
			elif utility_path.size() >= 2 and utility_path[0] == actor.cell and utility_path[utility_path.size() - 1] == action.final_cell:
				result.kind = Kind.MOVE
				result.path = utility_path.duplicate()
	return result
