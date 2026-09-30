extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE ARTIFACT SNAPSHOT: " + label)

func _run() -> void:
	var session := _player_session()
	if session == null:
		print("BATTLE ARTIFACT SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var definitions := _definition_catalog(session)
	_test_legacy(session, definitions)
	_test_artifact_snapshot(session, definitions)
	_test_bad_values(session)
	_test_guard(session)
	session.close()
	print("BATTLE ARTIFACT SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_legacy(session: BattleCoreReactionsSession, definitions: Dictionary) -> void:
	check(session.state.artifacts == null, "artifact capability is absent by default")
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot.to_dict().schema_version == 7 and captured.snapshot.to_dict().scope == ItemSimulationSnapshot.SCOPE_V7, "artifactless ability snapshot remains v7")
	if captured.snapshot == null:
		return
	var raw := captured.snapshot.to_dict()
	var decoded := ItemSimulationSnapshot.from_dict(raw)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_values() == captured.snapshot.canonical_values(), "legacy v7 canonical form remains unchanged")
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state.artifacts == null, "legacy v7 restore has no artifact capability")
	if restored.state != null: ForecastSimulation.close(restored.state)

func _test_artifact_snapshot(session: BattleCoreReactionsSession, definitions: Dictionary) -> void:
	var heroes := session.living_ids(Faction.Type.PLAYER)
	heroes.sort()
	check(heroes.size() == 3, "fixture has three permanent heroes")
	if heroes.size() != 3:
		return
	var value := {"schema": 1, "heroes": heroes, "mages": [heroes[2]], "attacks": [], "equipped": [
		{"id": 41, "unit_id": heroes[0], "slot": 1, "definition": "spark", "version": 1, "stacks": 2},
		{"id": 42, "unit_id": heroes[1], "slot": 2, "definition": "blood", "version": 1, "stacks": 1}
	], "formation_serials": [0, 0]}
	for hero_id: int in heroes:
		value["attacks"].append({"unit_id": hero_id, "attack_id": "demo_strike"})
	var artifacts := BattleArtifactState.from_dict(value)
	check(artifacts != null and artifacts.references_valid(session.board) and artifacts.stacks(heroes[0], "spark") == 2 and artifacts.ordinary(heroes[1], &"demo_strike"), "strict runtime capability resolves hero references")
	session.state.artifacts = artifacts
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot.to_dict().schema_version == 8 and captured.snapshot.to_dict().scope == ItemSimulationSnapshot.SCOPE_V8, "artifact capture emits v8")
	if captured.snapshot == null:
		return
	var raw := captured.snapshot.to_dict()
	check(raw.has("artifacts") and raw.has("summons") and raw.has("abilities") and raw.has("environment"), "v8 carries artifact DTO and v7 optional capabilities")
	var saved_abilities := session.state.abilities
	session.state.abilities = null
	var without_abilities := ItemSimulationSnapshot.capture(session.state, [])
	check(without_abilities.code == ItemSnapshotResult.Code.OK and not without_abilities.snapshot.to_dict().has("abilities"), "v8 permits absent abilities capability")
	session.state.abilities = saved_abilities
	var decoded := ItemSimulationSnapshot.from_dict(raw)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_values() == captured.snapshot.canonical_values(), "v8 capture, restore codec, and canonical form agree")
	var first := decoded.snapshot.instantiate(definitions)
	var second := decoded.snapshot.instantiate(definitions)
	check(first.code == ItemSnapshotResult.Code.OK and second.code == ItemSnapshotResult.Code.OK and first.state.artifacts.to_dict() == raw.artifacts, "v8 instantiates full artifact value state")
	if first.state == null or second.state == null:
		return
	first.state.artifacts.equipped[0]["stacks"] = 3
	first.state.artifacts.formation_serials[0] = 2
	check(second.state.artifacts.to_dict() == raw.artifacts and captured.snapshot.to_dict() == raw, "restored artifact mutations do not leak into snapshots or sibling restores")
	raw.artifacts.equipped[0]["stacks"] = 1
	check(captured.snapshot.to_dict().artifacts.equipped[0].stacks == 2, "returned snapshot dictionary is deeply isolated")
	ForecastSimulation.close(first.state); ForecastSimulation.close(second.state)

func _test_bad_values(session: BattleCoreReactionsSession) -> void:
	var valid_data: Dictionary = session.state.artifacts.to_dict()
	var live_artifacts: BattleArtifactState = session.state.artifacts
	var bad_attack_owner: int = live_artifacts.heroes[0]
	live_artifacts.attacks[bad_attack_owner] = 7
	check(live_artifacts.to_dict().is_empty(), "runtime integer attack reference is not coerced to a string")
	live_artifacts.attacks[bad_attack_owner] = StringName("demo_strike")
	live_artifacts.attacks[999999] = &"demo_strike"
	check(live_artifacts.to_dict().is_empty(), "runtime extra attack mapping is rejected")
	live_artifacts.attacks.erase(999999)
	check(BattleArtifactState.valid(live_artifacts.to_dict()), "restored runtime attack mapping validates")
	var bad := valid_data.duplicate(true)
	bad.mages = [999999]
	check(not BattleArtifactState.valid(bad), "mage must be a permanent hero")
	bad = valid_data.duplicate(true); bad.mages = [true]
	check(not BattleArtifactState.valid(bad), "bool is not a mage ID")
	bad = valid_data.duplicate(true); bad.mages.append(bad.mages[0])
	check(not BattleArtifactState.valid(bad), "duplicate mage rejected")
	bad = valid_data.duplicate(true)
	bad.heroes[1] = bad.heroes[0]
	check(not BattleArtifactState.valid(bad), "duplicate hero IDs rejected")
	bad = valid_data.duplicate(true)
	bad.equipped.append(bad.equipped[0].duplicate(true))
	check(not BattleArtifactState.valid(bad), "duplicate item ID rejected")
	bad = valid_data.duplicate(true)
	var duplicate_definition: Dictionary = bad.equipped[0].duplicate(true)
	duplicate_definition.id = 90
	duplicate_definition.slot = 3
	bad.equipped.append(duplicate_definition)
	check(not BattleArtifactState.valid(bad), "same artifact cannot occupy two slots on one hero")
	bad = valid_data.duplicate(true)
	bad.equipped[0].stacks = 4
	check(not BattleArtifactState.valid(bad), "out-of-cap stack rejected")
	bad = valid_data.duplicate(true)
	bad.equipped[0].definition = "unknown"
	check(not BattleArtifactState.valid(bad), "unknown artifact rejected")
	bad = valid_data.duplicate(true)
	bad.equipped[0].version = 2
	check(not BattleArtifactState.valid(bad), "unknown artifact version rejected")
	bad = valid_data.duplicate(true)
	var boolean_heroes: Array = []
	boolean_heroes.append_array(bad.heroes)
	boolean_heroes[0] = true
	bad["heroes"] = boolean_heroes
	check(not BattleArtifactState.valid(bad), "bool is not a hero ID")
	bad = valid_data.duplicate(true)
	bad.attacks[0].attack_id = ""
	check(not BattleArtifactState.valid(bad), "empty attack reference rejected")
	bad = valid_data.duplicate(true)
	bad.equipped[0].slot = true
	check(not BattleArtifactState.valid(bad), "bool is not an equipment slot")
	bad = valid_data.duplicate(true)
	bad.equipped[0].extra = 1
	check(not BattleArtifactState.valid(bad), "extra equipment fields rejected")
	var missing := valid_data.duplicate(true)
	var old_id: int = missing.heroes[0]
	missing.heroes[0] = 999999999
	missing.heroes.sort()
	for attack: Dictionary in missing.attacks:
		if attack.unit_id == old_id: attack.unit_id = 999999999
	for item: Dictionary in missing.equipped:
		if item.unit_id == old_id: item.unit_id = 999999999
	var missing_state := BattleArtifactState.from_dict(missing)
	check(BattleArtifactState.valid(missing), "missing board reference remains structurally valid DTO")
	check(missing_state != null and not missing_state.references_valid(session.board), "board member reference required")
	var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var malformed := snapshot.duplicate(true)
	malformed.artifacts.equipped[0].version = 3
	check(ItemSimulationSnapshot.from_dict(malformed).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "snapshot rejects malformed artifact DTO")
	malformed = snapshot.duplicate(true)
	var missing_id: int = malformed.artifacts.heroes[0]
	malformed.artifacts.heroes[0] = 999999999
	malformed.artifacts.heroes.sort()
	for attack: Dictionary in malformed.artifacts.attacks:
		if attack.unit_id == missing_id: attack.unit_id = 999999999
	for item: Dictionary in malformed.artifacts.equipped:
		if item.unit_id == missing_id: item.unit_id = 999999999
	check(ItemSimulationSnapshot.from_dict(malformed).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "snapshot rejects missing board hero reference")

func _test_guard(session: BattleCoreReactionsSession) -> void:
	var active_units: Array[UnitState] = []
	for unit: UnitState in session.board.get_all_units():
		if unit.is_alive(): active_units.append(unit)
	var guard := SpatialRules.capture_guard(session.context, active_units, [], {})
	check(guard != null and guard.check(session.context), "guard captures valid artifact references and values")
	if guard == null:
		return
	var after := session.state.artifacts.to_dict()
	after.formation_serials[0] = 1
	session.state.artifacts.formation_serials[0] = 1
	var phase_guard := guard.artifacts_phase(after)
	check(phase_guard.check(session.context), "formation serial advances through explicit artifact phase")
	session.state.artifacts.equipped[0]["stacks"] = 1
	check(not phase_guard.check(session.context), "guard detects nested artifact value mutation")
	session.state.artifacts = BattleArtifactState.from_dict(after)
	var fresh := SpatialRules.capture_guard(session.context, active_units, [], {})
	session.state.artifacts = null
	check(fresh != null and not fresh.check(session.context), "guard detects artifact capability reference replacement")

func _definition_catalog(session: BattleCoreReactionsSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _player_session() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	if session.phase != BattleTacticalSession.Phase.ENEMY_TURN or session.state.abilities == null:
		session.close()
		return null
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()
	return session if session.phase == BattleTacticalSession.Phase.PLAYER_TURN else null
