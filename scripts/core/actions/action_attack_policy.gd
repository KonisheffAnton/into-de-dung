extends RefCounted
class_name ActionAttackPolicy

## Состояние политики живёт ровно один submit; порядок drain остаётся у очереди.
var defer_item_reactions: bool = false
var _stances: Array[Dictionary] = []
var _root: Command
var _counter_considered: bool = false
var _extra_attacks_left: int = 0
var _equipment_owner: ItemOwnerState
var _equipment_items: Dictionary = {}
var _equipment_perks: Dictionary = {}

func _init(root: Command, context: ActionContext) -> void:
	_root = root
	if root is AttackCommand:
		var attacker := (root as AttackCommand).get_actor_unit_id()
		if not (root as AttackCommand).is_reaction() and not (root as AttackCommand).is_equipment_followup():
			_extra_attacks_left = AttackCommand.equipment_attack_count(context, attacker, (root as AttackCommand).get_attack_definition_id())
			if _extra_attacks_left > 0:
				_equipment_owner = context.get_state().get_owner(attacker)
				_equipment_items = _equipment_owner._items.duplicate()
				_equipment_perks = _equipment_values(_equipment_owner)
		var definition := context.get_attack_rules().get_definition((root as AttackCommand).get_attack_definition_id())
		defer_item_reactions = definition != null and (definition.bleeding_policy != &"" or definition.entangle_on_physical_hp or definition.stun_on_physical_hp or definition.chain_push)
		if context.get_state().artifacts != null and context.get_state().artifacts.ordinary(attacker,(root as AttackCommand).get_attack_definition_id()): defer_item_reactions = true
		# Срок отмены — весь каскад атаки, включая legacy balance/push и item-heal.
		for unit in context.get_state().get_board().get_all_units():
			_stances.append({"unit": unit, "expected": false if unit.id == attacker else unit.guard_stance})

func accept_cleared_stance(unit_id: int) -> void:
	for stance: Dictionary in _stances:
		if stance.unit.id == unit_id and not stance.unit.is_alive(): stance.expected = false

func stances_valid() -> bool:
	for stance: Dictionary in _stances:
		var unit: UnitState = stance["unit"]
		if unit.guard_stance != stance["expected"]: return false
	return true

func equipment_valid() -> bool:
	return _equipment_owner == null or (_equipment_owner._items == _equipment_items and _equipment_values(_equipment_owner) == _equipment_perks)

static func _equipment_values(owner: ItemOwnerState) -> Dictionary:
	var result: Dictionary = {}
	for id: int in owner._items:
		var item: ItemInstance = owner._items[id]
		if item == null or item._definition == null: return {"invalid": true}
		var definition: ItemDef = item._definition
		result[id] = [item, definition, owner._definitions.get(item.get_definition_id()), item._get_placement(), owner._placements.get(id), item.is_active(), definition.equipment_perks.duplicate()]
	return result

func finish_deferred_phase() -> bool:
	if not defer_item_reactions: return false
	defer_item_reactions = false
	return true

func take_counterattack(context: ActionContext) -> AttackCommand:
	# Единственный ответ принадлежит корню после полного drain его последствий.
	if _counter_considered: return null
	_counter_considered = true
	var counter := _counterattack_after(_root, context)
	if counter != null:
		var response := context.get_attack_rules().get_definition(counter.get_attack_definition_id())
		defer_item_reactions = response.bleeding_policy != &""
	return counter

func take_equipment_attack(context: ActionContext) -> AttackCommand:
	if _extra_attacks_left == 0: return null
	var attack := _root as AttackCommand
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(attack.get_actor_unit_id())
	var target := board.get_unit_by_id(attack.get_target_unit_id())
	# Каждый удар видит итог предыдущего каскада; погибшую/ушедшую цель не заменяем.
	if actor == null or target == null or not actor.is_alive() or not target.is_alive() or ControlRules.action_reason(actor) != &"":
		_extra_attacks_left = 0
		return null
	if AttackReachCheck.inspect_spatial(board, actor, target, actor.get_stat(StatTypes.StatType.ATTACK_RANGE)) != &"":
		_extra_attacks_left = 0
		return null
	_extra_attacks_left -= 1
	var next := AttackCommand.equipment_followup(actor, target, attack.get_attack_definition_id(), context.get_revision())
	var definition := context.get_attack_rules().get_definition(attack.get_attack_definition_id())
	defer_item_reactions = definition.bleeding_policy != &"" or definition.entangle_on_physical_hp or definition.stun_on_physical_hp or definition.chain_push
	if context.get_state().artifacts != null and context.get_state().artifacts.ordinary(actor.id, attack.get_attack_definition_id()): defer_item_reactions = true
	return next

static func _counterattack_after(root: Command, context: ActionContext) -> AttackCommand:
	if root.get_script() != AttackCommand or (root as AttackCommand).is_reaction(): return null
	var attack := root as AttackCommand
	var rules := context.get_attack_rules()
	var definition := rules.get_definition(attack.get_attack_definition_id())
	var response := rules.get_definition(&"counter_strike")
	# Только прямой weapon pipeline с явно заданным обычным ответом.
	if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or response == null or not response.reaction_strike: return null
	var board := context.get_state().get_board()
	var defender := board.get_unit_by_id(attack.get_target_unit_id())
	var attacker := board.get_unit_by_id(attack.get_actor_unit_id())
	if not MeleeThreat.reaction_ready(context, defender, CombatPerksState.Mode.COUNTERATTACK) or not MeleeThreat.threatens(context, defender, attacker): return null
	return AttackCommand.counterattack(defender, attacker, context.get_revision())
