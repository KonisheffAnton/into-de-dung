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
		check(ExpeditionGenerator.valid(plan), "seed %d produces a valid full plan" % seed_value)
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
	for kind: String in ["battle","elite","final"]:
		for variant: int in (3 if kind == "battle" else 2):
			var definition := ExpeditionCatalog.encounter(kind,variant)
			check(definition != null and definition.valid(),"encounter template has distinct spawn/hazard cells")
	check(ExpeditionCatalog.encounter("battle",3) == null,"unknown encounter rejected")
	print("EXPEDITION GENERATOR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _validate_rejections(source: Dictionary) -> void:
	var bad: Dictionary = source.duplicate(true)
	bad.schema = 2
	check(not ExpeditionGenerator.valid(bad), "unknown schema rejected")
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
	check(ExpeditionGenerator.generate(9001) == untouched, "mutating returned plan cannot change a later plan")
	var first_definition := ExpeditionCatalog.artifact("spark")
	first_definition.title = "Изменено"
	var second_definition := ExpeditionCatalog.artifact("spark")
	check(second_definition.title == "Искра" and first_definition != second_definition, "catalog definitions are fresh resources")
	var room_a := ExpeditionCatalog.room("battle")
	room_a.gold = 0
	check(ExpeditionCatalog.room("battle").gold == 40, "room definitions are fresh resources")
