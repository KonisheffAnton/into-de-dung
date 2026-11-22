extends Command
class_name AbilityBoundaryCommand

var operation: StringName
var team: int
var serial: int
var revision: int
func _init(op: StringName = &"", side: int = 0, turn: int = 0, rev: int = 0) -> void:
	operation = op; team = side; serial = turn; revision = rev
func get_kind() -> StringName: return &"ability_boundary"
func copy_for_queue() -> Command: return AbilityBoundaryCommand.new(operation, team, serial, revision)
func projected_after(context: ActionContext) -> Dictionary:
	if context == null or context.get_state() == null or context.get_state().abilities == null or context.get_revision() != revision: return {}
	if operation == &"start" and context.get_state().deck != null and not context.get_state().deck.mulligan_done: return {}
	return context.get_state().abilities.boundary(operation, team, serial)

func projected_deck(context: ActionContext) -> Dictionary:
	var state := context.get_state()
	if state.deck == null: return {}
	if operation == &"end" and team == Faction.Type.PLAYER: return state.deck.draw().get("after",{})
	return state.deck.to_dict()

func projected_effects(context: ActionContext) -> Dictionary:
	var state := context.get_state()
	if state.card_effects == null: return {}
	if operation != &"end": return state.card_effects.to_dict()
	var units: Array[int] = []
	for unit: UnitState in state.get_board().get_all_units():
		if unit.faction == team: units.append(unit.id)
	return state.card_effects.expire(serial,units).get("after",{})
func validate(context: ActionContext) -> StringName:
	return &"ability/invalid_boundary" if projected_after(context).is_empty() else &""
func execute(context: ActionContext) -> CommandStepResult:
	var after := projected_after(context)
	if after.is_empty(): return CommandStepResult.faulted(&"ability/invalid_boundary")
	var state := context.get_state()
	var expiry_host: UnitState = null
	var expiry_units: Array[UnitState] = []
	if operation == &"end" and team == Faction.Type.PLAYER and state.card_effects != null and state.card_effects.light_step_serial == serial and serial > 0:
		expiry_host = state.get_board().get_unit_by_id(state.card_effects.host_unit_id)
		if expiry_host != null and expiry_host.is_alive(): expiry_units.append(expiry_host)
	var guard := SpatialRules.capture_guard(context, expiry_units, [], {})
	if guard == null: return CommandStepResult.faulted(&"ability/invalid_runtime")
	guard = guard.ability_phase(after)
	var events: Array[Dictionary] = []
	if state.deck != null:
		var deck_after := projected_deck(context)
		var effects_after := projected_effects(context)
		if deck_after.is_empty() or effects_after.is_empty(): return CommandStepResult.faulted(&"deck/invalid_boundary")
		guard = guard.deck_phase(deck_after,effects_after)
		if deck_after != state.deck.to_dict(): events.append(MageDeckChangeCommand.changed(state.deck.to_dict(),deck_after,"draw"))
		state.card_effects.apply_values(effects_after); state.deck.apply_values(deck_after)
	if not expiry_units.is_empty():
		var spent := minf(2.0, expiry_host.move_points_left)
		guard = guard.debit(expiry_host.id, 0, spent)
		expiry_host.move_points_left -= spent
	context.get_state().abilities.apply_values(after)
	if not guard.check(context): return CommandStepResult.faulted(&"ability/checkpoint")
	return CommandStepResult.applied(events, [], [], null, true)
