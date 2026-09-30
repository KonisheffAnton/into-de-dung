extends RefCounted
class_name BattleArtifactRules

static func references_valid(context: ActionContext) -> bool:
	if context == null or context.get_state() == null: return false
	var state := context.get_state()
	var artifacts := state.artifacts
	if artifacts == null or artifacts.get_script() != BattleArtifactState or not BattleArtifactState.valid(artifacts.to_dict()) or not artifacts.references_valid(state.get_board()): return false
	var rules := context.get_attack_rules()
	if rules == null or rules.validate() != &"": return false
	for id: int in artifacts.heroes:
		if state.summon_owner_id(id) != 0: return false
		var definition := rules.get_definition(artifacts.attacks[id])
		if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or definition.reaction_strike or definition.entangle_on_physical_hp or definition.stun_on_physical_hp: return false
	return true

static func has_neighbour(state: ItemSimulationState, owner: UnitState) -> bool:
	for id: int in state.artifacts.heroes:
		var other := state.get_board().get_unit_by_id(id)
		if other == null or other == owner or not other.is_alive() or other.faction != owner.faction: continue
		var delta := other.cell - owner.cell
		if maxi(absi(delta.x), absi(delta.y)) == 1 and state.get_board().get_height_steps(owner.cell) == state.get_board().get_height_steps(other.cell): return true
	return false
