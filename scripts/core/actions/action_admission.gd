extends RefCounted
class_name ActionAdmission

## Допуск корня вызывается только после захвата busy у очереди и контекста.
## Не исполняет команду и не распределяет IDs; порядок отказов значим для API.
var accepted: Command = null
var reason: StringName = &""

static func check(command: Command, context: ActionContext, max_commands: int, max_events: int, max_depth: int) -> ActionAdmission:
	var result := ActionAdmission.new()
	if max_commands < 1 or max_commands > 4096 or max_events < 1 or max_events > 8192 or max_depth < 1 or max_depth > 64:
		result.reason = &"invalid_limits"
	elif context.get_state() == null or context.get_rng() == null or context.get_sink() == null:
		result.reason = &"invalid_context"
	elif command == null:
		result.reason = &"unknown_command"
	else:
		result.accepted = command.copy_for_queue()
		if result.accepted == null:
			result.reason = &"unknown_command"
		else:
			var capture := ItemSimulationSnapshot.capture(context.get_state(), context.get_unsupported_runtime_ids())
			if capture.code != ItemSnapshotResult.Code.OK:
				result.reason = &"BUSY" if capture.code == ItemSnapshotResult.Code.SNAPSHOT_BUSY else StringName(capture.reason)
			elif result.accepted is AttackCommand and (result.accepted as AttackCommand).is_reaction():
				result.reason = &"reaction/internal_attack"
			elif result.accepted is ReactionStopCommand:
				result.reason = &"reaction/internal_stop"
			elif result.accepted is AttackHitCommand:
				result.reason = &"attack/internal_hit"
			elif result.accepted is ArtifactHitEffectCommand or result.accepted is ArtifactFormationCommand or result.accepted is ArtifactRepairCommand:
				result.reason = &"artifact/internal_command"
			elif result.accepted is MoveFallCommand:
				result.reason = &"move/internal_fall"
			elif result.accepted is ArmorEndBattleCommand:
				result.reason = &"armor/internal_expiry"
			elif result.accepted is BleedingApplyCommand or result.accepted is BleedingTickCommand or result.accepted is BleedingMovementCommand or result.accepted is ElementalTickCommand or result.accepted is StatusTurnUnitCommand:
				result.reason = &"bleeding/internal_command"
			elif result.accepted is ControlExpireCommand or result.accepted is ControlApplyCommand:
				result.reason = &"control/internal_command"
			elif result.accepted is EnvironmentCommand:
				result.reason = &"environment/internal_command"
			elif result.accepted is HazardCommand or result.accepted is HazardTurnCommand or result.accepted is AcidCommand:
				result.reason = &"hazard/internal_command"
			elif result.accepted is CollapseCellCommand:
				result.reason = &"collapse/internal_command"
			elif result.accepted is DeathCommand and ((result.accepted as DeathCommand)._has_spatial_binding or (result.accepted as DeathCommand)._spatial_binding != null):
				result.reason = &"move/internal_death"
			elif result.accepted is MoveCommand and (result.accepted as MoveCommand)._is_continuation():
				result.reason = &"move/internal_continuation"
			elif result.accepted is BalanceCommand:
				result.reason = &"balance/internal_command"
			elif result.accepted is PushChainCommand:
				result.reason = &"chain/internal_command"
			elif result.accepted is PushCommand:
				result.reason = &"push/internal_command"
			elif result.accepted is PushDamageCommand:
				result.reason = &"push/internal_damage"
			elif result.accepted is CollisionDamageCommand:
				result.reason = &"push/internal_collision"
			else: result.reason = result.accepted.validate(context)
	if result.reason == &"" and not AbilityCatalog.attack_references_valid(context): result.reason = &"ability/attack_catalog"
	if result.reason == &"" and not MageDeckRules.references_valid(context): result.reason = &"deck/attack_catalog"
	if result.reason == &"" and context.get_state().artifacts != null and not BattleArtifactRules.references_valid(context): result.reason = &"artifact/attack_catalog"
	if result.reason == &"" and context.get_state().abilities != null and result.accepted.get_script() in [AttackCommand, MoveCommand, GuardCommand, RaiseShieldsCommand, RestoreArmorCommand, RaiseCorpseCommand, ElementalCastCommand, UseHealingItemCommand, UseSummoningItemCommand, MageCastCommand]:
		var descriptor := result.accepted.get_ability_definition(context)
		var registered := context.get_state().abilities.definition(descriptor.ability_id) if descriptor != null else null
		if descriptor == null or registered == null or descriptor.to_dict() != registered.to_dict(): result.reason = &"ability/unregistered_action"
	return result
