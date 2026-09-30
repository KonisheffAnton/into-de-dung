class_name ExpeditionGenerator
extends RefCounted

const LAYER_SIZES: Array[int] = [2, 3, 2, 1, 3, 2, 1]
const ARTIFACT_IDS: Array[String] = ["spark", "blood", "ember", "ice", "formation", "harvest"]
const NODE_KEYS: Array[String] = ["id", "layer", "kind", "variant", "modifier", "next", "reward", "battle_seed"]
const PLAN_KEYS: Array[String] = ["schema", "seed", "nodes", "start", "content"]

static func generate(seed_value: int) -> Dictionary:
	var graph_rng := RandomNumberGenerator.new()
	graph_rng.seed = _stream_seed(seed_value, 0x13579BDF)
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = _stream_seed(seed_value, 0x2468ACE1)
	var battle_rng := RandomNumberGenerator.new()
	battle_rng.seed = _stream_seed(seed_value, 0x5A17C3E9)
	var nodes: Array[Dictionary] = []
	var layer_ids: Array[Array] = []
	var first_layer_omissions: Array[int] = [0, 1, 2]
	_kshuffle(first_layer_omissions, graph_rng)
	var next_id: int = 1
	for layer_index: int in range(LAYER_SIZES.size()):
		var ids: Array[int] = []
		for unused: int in range(LAYER_SIZES[layer_index]):
			ids.append(next_id)
			next_id += 1
		layer_ids.append(ids)
	for layer_index: int in range(LAYER_SIZES.size()):
		var kinds: Array[String] = _layer_kinds(layer_index)
		_kshuffle(kinds, graph_rng)
		for offset: int in range(LAYER_SIZES[layer_index]):
			var kind: String = kinds[offset]
			var node_id: int = layer_ids[layer_index][offset]
			var omitted_target: int = first_layer_omissions[offset] if layer_index == 0 else -1
			var node_next: Array[int] = _edges_for(layer_index, offset, layer_ids, graph_rng, omitted_target)
			var reward: Array[String] = []
			if kind == "battle" or kind == "elite":
				reward = _pick_rewards(reward_rng)
			nodes.append({
				"id": node_id,
				"layer": layer_index,
				"kind": kind,
				"variant": graph_rng.randi_range(0, 2 if kind == "battle" else 1) if kind == "battle" or kind == "elite" or kind == "final" else 0,
				"modifier": _modifier(kind, graph_rng),
				"next": node_next,
				"reward": reward,
				"battle_seed": battle_rng.randi_range(1, 2147483647)
			})
	return {"schema": 1, "seed": seed_value, "nodes": nodes, "start": [1, 2], "content": ExpeditionCatalog.content_values()}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or not _has_exact_keys(data, PLAN_KEYS):
		return false
	var plan: Dictionary = data
	if not ExpeditionCatalog.matches_content(plan["content"]): return false
	if not _is_plain_int(plan["schema"]) or plan["schema"] != 1 or not _is_plain_int(plan["seed"]):
		return false
	if not plan["nodes"] is Array or not plan["start"] is Array:
		return false
	var nodes: Array = plan["nodes"]
	var starts: Array = plan["start"]
	if nodes.size() != 14 or starts != [1, 2]:
		return false
	var by_id: Dictionary = {}
	var expected_layer: int = 0
	var layer_position: int = 0
	for index: int in range(nodes.size()):
		var raw: Variant = nodes[index]
		if not raw is Dictionary or not _has_exact_keys(raw, NODE_KEYS):
			return false
		var node: Dictionary = raw
		if not _is_plain_int(node["id"]) or node["id"] != index + 1 or by_id.has(node["id"]):
			return false
		if not _is_plain_int(node["layer"]) or node["layer"] != expected_layer:
			return false
		if not _is_plain_int(node["variant"]) or not _is_plain_int(node["battle_seed"]) or node["battle_seed"] < 1:
			return false
		if not node["kind"] is String or not node["modifier"] is String or not node["next"] is Array or not node["reward"] is Array:
			return false
		var kind: String = node["kind"]
		if not _kind_allowed(expected_layer, kind) or not _variant_allowed(kind, node["variant"]):
			return false
		if not _modifier_allowed(kind, node["modifier"]):
			return false
		if kind == "battle" or kind == "elite":
			if node["reward"].size() != 3:
				return false
			var unique_rewards: Dictionary = {}
			for reward: Variant in node["reward"]:
				if not reward is String or not ARTIFACT_IDS.has(reward) or unique_rewards.has(reward):
					return false
				unique_rewards[reward] = true
		elif not node["reward"].is_empty():
			return false
		var next_nodes: Array = node["next"]
		if expected_layer == 6:
			if not next_nodes.is_empty():
				return false
		elif expected_layer == 3:
			if next_nodes.size() != 3:
				return false
		else:
			if next_nodes.size() < 1 or next_nodes.size() > 2:
				return false
		var edge_seen: Dictionary = {}
		for target_id: Variant in next_nodes:
			if not _is_plain_int(target_id) or target_id <= node["id"] or edge_seen.has(target_id):
				return false
			edge_seen[target_id] = true
		by_id[node["id"]] = node
		layer_position += 1
		if layer_position == LAYER_SIZES[expected_layer]:
			layer_position = 0
			expected_layer += 1
	if expected_layer != LAYER_SIZES.size() or layer_position != 0:
		return false
	for id: int in range(1, 15):
		var node: Dictionary = by_id[id]
		for target_id: int in node["next"]:
			if not by_id.has(target_id) or by_id[target_id]["layer"] != node["layer"] + 1:
				return false
	if not _has_all_expected_kinds(by_id):
		return false
	if by_id[1]["next"].size() < 2 or by_id[2]["next"].size() < 2:
		return false
	var camp: Dictionary = by_id[8]
	var camp_targets: Array = camp["next"]
	if camp_targets != [9, 10, 11]:
		return false
	for id: int in [9, 10, 11]:
		if by_id[id]["next"].size() != 2:
			return false
	var reached: Dictionary = {}
	_reachable(1, by_id, reached)
	_reachable(2, by_id, reached)
	if reached.size() != 14:
		return false
	return _all_paths_have_branches(by_id)

static func _layer_kinds(layer_index: int) -> Array[String]:
	match layer_index:
		0: return ["battle", "battle"]
		1, 4: return ["battle", "rest", "cache"]
		2, 5: return ["battle", "elite"]
		3: return ["camp"]
		_: return ["final"]

static func _edges_for(layer_index: int, offset: int, layer_ids: Array[Array], rng: RandomNumberGenerator, omitted_target: int) -> Array[int]:
	if layer_index == 6:
		return []
	var targets: Array[int] = layer_ids[layer_index + 1].duplicate()
	if layer_index == 3:
		return targets
	if layer_index == 0:
		targets.remove_at(omitted_target)
		return targets
	if layer_index == 1:
		if rng.randi_range(0, 1) == 0:
			return [targets[offset % targets.size()]]
		return targets
	if layer_index == 4:
		return targets
	if targets.size() > 1 and rng.randi_range(0, 1) == 0:
		return [targets[rng.randi_range(0, targets.size() - 1)]]
	return targets

static func _pick_rewards(rng: RandomNumberGenerator) -> Array[String]:
	var values: Array[String] = ARTIFACT_IDS.duplicate()
	_kshuffle(values, rng)
	return values.slice(0, 3)

static func _modifier(kind: String, rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	if kind == "battle" or kind == "elite" or kind == "final":
		pool = ["neutral", "spikes", "fire"]
	elif kind == "rest" or kind == "camp":
		pool = ["neutral", "healing", "repair"]
	elif kind == "cache":
		pool = ["neutral", "rich"]
	else:
		return "neutral"
	return pool[rng.randi_range(0, pool.size() - 1)]

static func _kshuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value

static func _stream_seed(seed_value: int, salt: int) -> int:
	var mixed: int = seed_value ^ salt
	mixed = int((mixed ^ (mixed >> 16)) * 0x45D9F3B)
	mixed = int((mixed ^ (mixed >> 16)) * 0x45D9F3B)
	mixed = mixed ^ (mixed >> 16)
	return mixed if mixed != 0 else salt

static func _is_plain_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT

static func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true

static func _kind_allowed(layer: int, kind: String) -> bool:
	match layer:
		0: return kind == "battle"
		1, 4: return ["battle", "rest", "cache"].has(kind)
		2, 5: return ["battle", "elite"].has(kind)
		3: return kind == "camp"
		6: return kind == "final"
	return false

static func _variant_allowed(kind: String, variant: int) -> bool:
	if kind == "battle": return variant >= 0 and variant <= 2
	if kind == "elite" or kind == "final": return variant >= 0 and variant <= 1
	return variant == 0

static func _modifier_allowed(kind: String, modifier: String) -> bool:
	if kind == "battle" or kind == "elite" or kind == "final":
		return ["neutral", "spikes", "fire"].has(modifier)
	if kind == "rest" or kind == "camp":
		return ["neutral", "healing", "repair"].has(modifier)
	if kind == "cache": return ["neutral", "rich"].has(modifier)
	return modifier == "neutral"

static func _has_all_expected_kinds(by_id: Dictionary) -> bool:
	var observed: Array[String] = []
	for id: int in range(1, 15):
		var layer: int = by_id[id]["layer"]
		if not observed.has("%d:%s" % [layer, by_id[id]["kind"]]):
			observed.append("%d:%s" % [layer, by_id[id]["kind"]])
	for layer: int in [1, 4]:
		for kind: String in ["battle", "rest", "cache"]:
			if not observed.has("%d:%s" % [layer, kind]): return false
	for layer: int in [2, 5]:
		for kind: String in ["battle", "elite"]:
			if not observed.has("%d:%s" % [layer, kind]): return false
	return true

static func _reachable(id: int, by_id: Dictionary, reached: Dictionary) -> void:
	if reached.has(id): return
	reached[id] = true
	for target_id: int in by_id[id]["next"]:
		_reachable(target_id, by_id, reached)

static func _all_paths_have_branches(by_id: Dictionary) -> bool:
	return _paths_have_two_branches(1, 0, by_id) and _paths_have_two_branches(2, 0, by_id)

static func _paths_have_two_branches(id: int, branch_count: int, by_id: Dictionary) -> bool:
	var node: Dictionary = by_id[id]
	var count: int = branch_count + (1 if node["next"].size() == 2 else 0)
	if node["layer"] == 6:
		return count >= 2
	for target_id: int in node["next"]:
		if not _paths_have_two_branches(target_id, count, by_id):
			return false
	return true
