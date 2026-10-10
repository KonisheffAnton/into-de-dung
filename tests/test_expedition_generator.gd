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
		printerr("FAIL EXPEDITION GENERATOR: " + label)

func _run() -> void:
	var plans: Array[Dictionary] = []
	var serialized: Dictionary = {}
	for seed_value: int in range(256):
		var plan: Dictionary = ExpeditionGenerator.generate(seed_value)
		check(ExpeditionGenerator.valid(plan) and plan.schema == 4 and plan.ruleset_id == ExpeditionRulesRegistry.LEGACY and not plan.opening, "seed %d produces a valid legacy schema4 plan" % seed_value)
		if seed_value == 17:
			serialized = plan
		check(ExpeditionGenerator.generate(seed_value) == plan, "seed %d is reproducible" % seed_value)
		plans.append(plan)
	var unique_plans: Dictionary = {}
	for plan: Dictionary in plans:
		unique_plans[JSON.stringify(plan)] = true
	check(unique_plans.size() > 1, "seeds produce diverse plans")
	_validate_rejections(serialized)
	_copy_isolation()
	for seed_value: int in 32:
		var current := ExpeditionRulesRegistry.generate_plan(seed_value, true)
		var previous := ExpeditionRulesRegistry.generate_plan(seed_value, false)
		check(ExpeditionGenerator.valid(current) and current.schema == 4 and current.ruleset_id == ExpeditionRulesRegistry.DECK and current.opening and current.start == [1] and current.nodes.size() == 13, "single opening graph %d" % seed_value)
		check(current.nodes[0].next == [2,3,4] and current.nodes[0].variant == 0 and current.nodes[0].modifier == "neutral", "fixed opening has all next-layer choices")
		check(ExpeditionGenerator.valid(previous) and previous.schema == 4 and previous.ruleset_id == ExpeditionRulesRegistry.DECK and not previous.opening and previous.start == [1,2], "current two-start deck graph remains loadable")
		check(ExpeditionRulesRegistry.generate_plan(seed_value, true) == current, "opening graph is deterministic")
		for index: int in range(1, current.nodes.size()):
			check(current.nodes[index].battle_seed == previous.nodes[index+1].battle_seed and current.nodes[index].reward == previous.nodes[index+1].reward, "downstream battle/reward streams preserved")
	var damaged := ExpeditionRulesRegistry.generate_plan(17, true)
	damaged.content.opening.hazards[0].effect = "burning"
	check(not ExpeditionGenerator.valid(damaged), "opening manifest cannot silently drift")
	damaged = ExpeditionRulesRegistry.generate_plan(17, true); damaged.nodes[0].next = [2,3]
	check(not ExpeditionGenerator.valid(damaged), "opening cannot strand a next-layer room")
	for kind: String in ["battle","elite","final"]:
		for variant: int in (3 if kind == "battle" else 2):
			var definition := ExpeditionCatalog.encounter(kind,variant)
			check(definition != null and definition.valid(),"encounter template has distinct spawn/hazard cells")
	check(ExpeditionCatalog.encounter("battle",3) == null,"unknown encounter rejected")
	print("EXPEDITION GENERATOR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _validate_rejections(source: Dictionary) -> void:
	var bad: Dictionary = source.duplicate(true)
	bad.schema = 3
	check(not ExpeditionGenerator.valid(bad), "old plan version rejected")
	bad = source.duplicate(true); bad.schema = 5
	check(not ExpeditionGenerator.valid(bad), "future plan version rejected")
	bad = source.duplicate(true); bad.erase("ruleset_id")
	check(not ExpeditionGenerator.valid(bad), "missing ruleset rejected")
	bad = source.duplicate(true); bad.ruleset_id = "unknown"
	check(not ExpeditionGenerator.valid(bad), "unknown ruleset rejected")
	bad = source.duplicate(true); bad.opening = true
	check(not ExpeditionGenerator.valid(bad), "legacy plan cannot claim opening")
	bad = source.duplicate(true); bad.content.version += 1
	check(not ExpeditionGenerator.valid(bad), "unknown content version rejected")
	bad = source.duplicate(true); bad.content.encounters[0].enemy_hp += 1
	check(not ExpeditionGenerator.valid(bad), "saved encounter values cannot silently change")
	bad = source.duplicate(true); bad.content.artifacts[0].max_stacks += 1
	check(not ExpeditionGenerator.valid(bad), "saved artifact values cannot silently change")
	bad = source.duplicate(true); bad.content.rules.spark_damage = true
	check(not ExpeditionGenerator.valid(bad), "content values preserve exact types")
	bad = source.duplicate(true)
	bad.nodes[0].next = [1]
	check(not ExpeditionGenerator.valid(bad), "same-layer edge rejected")
	bad = source.duplicate(true)
	bad.nodes[0].id = 2
	check(not ExpeditionGenerator.valid(bad), "duplicate node id rejected")
	bad = source.duplicate(true)
	bad.nodes[0].modifier = "unknown"
	check(not ExpeditionGenerator.valid(bad), "unknown modifier rejected")
	bad = source.duplicate(true)
	bad.nodes[0].reward[1] = bad.nodes[0].reward[0]
	check(not ExpeditionGenerator.valid(bad), "duplicate reward rejected")
	bad = source.duplicate(true)
	bad.nodes[0].next = [3, 4]
	bad.nodes[1].next = [3, 4]
	check(not ExpeditionGenerator.valid(bad), "inaccessible node rejected")
	bad = source.duplicate(true)
	bad.nodes[8].next = [12]
	check(not ExpeditionGenerator.valid(bad), "missing post-camp branch rejected")
	bad = source.duplicate(true)
	bad.nodes[0].id = true
	check(not ExpeditionGenerator.valid(bad), "bool is not an integer id")
	bad = source.duplicate(true)
	bad.start = [true, 2]
	check(not ExpeditionGenerator.valid(bad), "bool is not a start id")

func _copy_isolation() -> void:
	var first: Dictionary = ExpeditionGenerator.generate(9001)
	var untouched: Dictionary = ExpeditionGenerator.generate(9001)
	first.nodes[0].next.clear()
	first.nodes[0].reward.clear()
	check(ExpeditionGenerator.generate(9001) == untouched and ExpeditionGenerator.valid(untouched), "mutating returned plan cannot change later plan or source")
	var first_definition := ExpeditionCatalog.artifact("spark")
	first_definition.title = "Изменено"
	var second_definition := ExpeditionCatalog.artifact("spark")
	check(second_definition.title == "Искра" and first_definition != second_definition, "catalog definitions are fresh resources")
	var room_a := ExpeditionCatalog.room("battle")
	room_a.gold = 0
	check(ExpeditionCatalog.room("battle").gold == 40, "room definitions are fresh resources")
