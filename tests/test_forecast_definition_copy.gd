extends SceneTree

const Fixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL FORECAST DEFINITION COPY: " + label)

func rejected(state: ItemSimulationState, label: String) -> void:
	var result := ForecastDefinitionCopy.copy_catalog(state)
	check(result.reason == &"preview/unsupported_definition_metadata" and result.definitions.is_empty(), label)

func set_bad_and_check(state: ItemSimulationState, root: Resource, key: StringName, value: Variant, label: String) -> void:
	root.set_meta(key, value)
	rejected(state, label)
	root.remove_meta(key)

func _run() -> void:
	var session := Fixture.create()
	var state: ItemSimulationState = session.state
	var owner: ItemOwnerState = state.get_owners()[0]
	var item_definition := Item.new()
	item_definition.id = &"forecast_copy_item_probe"
	var effect := StatModifierEffect.new()
	item_definition.effects.append(effect)
	item_definition.use_summon = true
	item_definition.max_charges = 2
	item_definition.summon_definition = SummonDefinition.new()
	owner._definitions[item_definition.id] = item_definition
	var id: StringName = item_definition.id
	var copied := ForecastDefinitionCopy.copy_catalog(state)
	check(copied.reason == &"" and copied.definitions.has(id), "valid Item-derived catalogue copied")
	if copied.definitions.has(id):
		var detached: ItemDef = copied.definitions[id]
		check(detached.get_script() == Item, "Item-derived definition remains supported")
		check(detached != item_definition and detached.effects[0] != effect, "definition and nested effect resource detached")
		check(detached.summon_definition != item_definition.summon_definition, "summon resource detached")
		var payload: Array = ["safe", {"value": 7}]
		item_definition.set_meta(&"safe_payload", payload)
		copied = ForecastDefinitionCopy.copy_catalog(state)
		var copied_payload: Array = copied.definitions[id].get_meta(&"safe_payload")
		copied_payload[1]["value"] = 8
		check(payload[1]["value"] == 7, "metadata nested containers detached from source")
		payload[1]["value"] = 9
		check(copied_payload[1]["value"] == 8, "metadata nested containers detached both ways")
		item_definition.remove_meta(&"safe_payload")

	# Все значения с объектной семантикой запрещены прямо и внутри ключей/значений.
	var node := Node.new()
	var bad_values: Array[Variant] = [node, Callable(self, "_run"), session.units[0].vitals.died, RID()]
	var roots: Array[Resource] = [item_definition, effect, item_definition.summon_definition]
	for root: Resource in roots:
		for index: int in range(bad_values.size()):
			set_bad_and_check(state, root, StringName("direct_%d" % index), bad_values[index], "direct unsupported metadata on " + root.get_class() + " kind " + str(index))
			var nested: Dictionary = {"outer": [{bad_values[index]: "key"}]}
			set_bad_and_check(state, root, StringName("nested_key_%d" % index), nested, "nested key metadata on " + root.get_class() + " kind " + str(index))
			set_bad_and_check(state, root, StringName("nested_value_%d" % index), {"outer": [bad_values[index]]}, "nested value metadata on " + root.get_class() + " kind " + str(index))
	check(owner._definitions.has(id), "metadata failures preserve live catalogue entry")
	node.free()

	var cycle: Array = []
	cycle.append(cycle)
	item_definition.set_meta(&"cycle", cycle)
	rejected(state, "cyclic metadata rejected")
	item_definition.remove_meta(&"cycle")
	cycle.clear()
	var deep_value: Variant = "leaf"
	for _level: int in range(ForecastDefinitionCopy.MAX_DEPTH + 1): deep_value = [deep_value]
	set_bad_and_check(state, item_definition, &"too_deep", deep_value, "metadata depth limit enforced")
	var wide: Array = []
	for _entry: int in range(ForecastDefinitionCopy.MAX_VISITS): wide.append(0)
	set_bad_and_check(state, item_definition, &"too_many_visits", wide, "catalogue visit budget enforced")

	# Более позднее безопасное определение с тем же id не должно скрыть ранний отказ.
	var early_owner: ItemOwnerState = state.get_owners()[0]
	var late_owner: ItemOwnerState = state.get_owners().back()
	var unsafe := ItemDef.new()
	unsafe.id = &"repeated_id_probe"
	unsafe.set_meta(&"unsupported", Callable(self, "_run"))
	var safe := ItemDef.new()
	safe.id = unsafe.id
	early_owner._definitions[unsafe.id] = unsafe
	late_owner._definitions[safe.id] = safe
	rejected(state, "earlier repeated-id metadata is validated")
	unsafe.remove_meta(&"unsupported")
	copied = ForecastDefinitionCopy.copy_catalog(state)
	check(copied.reason == &"" and copied.definitions[unsafe.id] != unsafe and copied.definitions[unsafe.id].get_script() == ItemDef, "last repeated id still supplies copied definition")
	early_owner._definitions.erase(unsafe.id)
	late_owner._definitions.erase(safe.id)
	owner._definitions.erase(id)
	session.close()
	print("FORECAST DEFINITION COPY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
