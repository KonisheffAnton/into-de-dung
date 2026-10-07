extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL RAISED SHIELD: " + label)

func raw(numerator: int, denominator: int, type: String = "physical") -> Array[Dictionary]:
	return [{"type": type, "policy": "standard", "numerator": numerator, "denominator": denominator, "source": "raised_test"}]

func _run() -> void:
	_test_codec()
	_test_lifecycle()
	_test_interception()
	print("RAISED SHIELD RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_codec() -> void:
	var legacy := ArmorState.new()
	var v1 := legacy.to_dict()
	check(v1.schema_version == 1 and not v1.has("raised_shield") and ArmorState.from_dict(v1).to_dict() == v1, "schema one encoding and roundtrip unchanged")
	legacy.shield = SpellShield.make(&"mage.shield", 6, 1)
	var v2 := legacy.to_dict()
	check(v2.schema_version == 2 and not v2.has("raised_shield") and ArmorState.from_dict(v2).to_dict() == v2, "schema two encoding and roundtrip unchanged")
	legacy.raised_shield = RaisedShield.make()
	legacy.shield = {}
	var v3 := legacy.to_dict()
	check(v3.schema_version == 3 and not v3.has("shield") and ArmorState.valid(v3), "raised shield emits schema three")
	check(ArmorState.from_dict(v3).to_dict() == v3, "schema three without spell shield roundtrips")
	legacy.shield = SpellShield.make(&"mage.shield", 6, 1)
	v3 = legacy.to_dict()
	check(v3.schema_version == 3 and v3.has("shield") and ArmorState.from_dict(v3).to_dict() == v3, "schema three composes with spell shield")
	var copied := ArmorState.from_dict(v3)
	copied.raised_shield.ready_turn = 8
	copied.shield.hp = 2
	check(legacy.raised_shield.ready_turn == 0 and legacy.shield.hp == 6, "decoded raised and spell shields are isolated copies")
	var removed_spell := legacy.to_dict()
	SpellShield.write_state(removed_spell, {})
	check(removed_spell.schema_version == 3 and removed_spell.raised_shield == legacy.raised_shield, "removing mage shield preserves raised shield schema")
	SpellShield.write_state(removed_spell, SpellShield.make(&"card.shield", 4, 2))
	check(removed_spell.schema_version == 3 and removed_spell.raised_shield == legacy.raised_shield, "adding mage shield preserves raised shield schema")
	var removed_raised := legacy.to_dict()
	RaisedShield.write_state(removed_raised, {})
	check(removed_raised.schema_version == 2 and removed_raised.shield == legacy.shield, "removing raised shield returns schema two")
	var bad := v3.duplicate(true)
	bad.raised_shield.extra = 1
	check(not ArmorState.valid(bad), "armor schema rejects nested unknown keys")
	bad = v3.duplicate(true)
	bad.raised_shield.active = 1
	check(not ArmorState.valid(bad), "armor schema rejects wrong raised flag type")
	bad = v3.duplicate(true)
	bad.raised_shield = RaisedShield.make()
	bad.raised_shield.blocked_root = 2
	check(not ArmorState.valid(bad), "armor schema rejects half-bound attack pair")
	bad = v3.duplicate(true)
	bad.raised_shield.ready_turn = ActionContext.MAX_ID
	check(not ArmorState.valid(bad), "armor schema rejects out of bounds cooldown")
	bad = v3.duplicate(true)
	bad.schema_version = 2
	check(not ArmorState.valid(bad), "old schema rejects raised field")

func _test_lifecycle() -> void:
	var initial := RaisedShield.make()
	check(RaisedShield.valid(initial), "canonical helper state valid")
	var ready := initial.duplicate(true)
	ready.ready_turn = 1
	var active := RaisedShield.activated(ready, 1)
	check(active.active and active.ready_turn == 3 and active.blocked_root == 0 and active.blocked_group == 0, "turn one activation sets cooldown to turn three")
	check(RaisedShield.activated(active, 3).is_empty(), "cannot reactivate while active")
	check(RaisedShield.activated(ready, 0).is_empty(), "activation requires cooldown-ready serial")
	var consumed := {"active": false, "ready_turn": 3, "blocked_root": 4, "blocked_group": 7}
	var expired := RaisedShield.expired(consumed)
	check(not expired.active and expired.ready_turn == 3 and expired.blocked_root == 0 and expired.blocked_group == 0, "expiration clears block and preserves cooldown")
	check(RaisedShield.expired({"bad": true}).is_empty(), "invalid state does not expire")
	for malformed: Variant in [
		{"active": false, "ready_turn": true, "blocked_root": 0, "blocked_group": 0},
		{"active": 1, "ready_turn": 0, "blocked_root": 0, "blocked_group": 0},
		{"active": false, "ready_turn": -1, "blocked_root": 0, "blocked_group": 0},
		{"active": false, "ready_turn": 0, "blocked_root": 0, "blocked_group": ActionContext.MAX_ID},
		{"active": true, "ready_turn": 0, "blocked_root": 3, "blocked_group": 3},
		{"active": false, "ready_turn": 0, "blocked_root": 3, "blocked_group": 0},
		{"active": false, "ready_turn": 0, "blocked_root": 0, "blocked_group": 3},
		{"active": false, "ready_turn": 0, "blocked_root": 0, "blocked_group": 0, "extra": false},
	]:
		check(not RaisedShield.valid(malformed), "strict helper validation rejects malformed shape")

func _test_interception() -> void:
	var before := RaisedShield.activated(RaisedShield.make(), 1)
	var physical := {"type": "physical", "policy": "standard", "numerator": 7, "denominator": 3, "source": "physical_source"}
	var fire := {"type": "fire", "policy": "standard", "numerator": 5, "denominator": 2, "source": "fire_source"}
	var packet: Array[Dictionary] = [physical, fire]
	var first := RaisedShield.intercept(packet, before, 11, 21)
	check(first.reason == &"" and first.blocked and not first.after.active and first.after.blocked_root == 11 and first.after.blocked_group == 21, "active shield binds first direct application")
	check(first.raw[0].numerator == 7 and first.raw[0].denominator == 30 and first.raw[1].numerator == 1 and first.raw[1].denominator == 4, "block 90 percent leaves exact one-tenth of each component")
	check(packet == [physical, fire] and before.active, "interception does not mutate inputs")
	var repeated := RaisedShield.intercept(packet, first.after, 11, 21)
	check(repeated.blocked and repeated.raw == first.raw and repeated.after == first.after, "same attack group keeps scaling after consumption")
	var next_group := RaisedShield.intercept(packet, first.after, 11, 22)
	check(not next_group.blocked and next_group.raw == packet and next_group.after == first.after, "different group is not reduced or consumed")
	var zero: Array[Dictionary] = raw(0, 1)
	var zero_result := RaisedShield.intercept(zero, before, 11, 21)
	check(not zero_result.blocked and zero_result.after == before, "zero nominal hit does not consume")
	var overflow := RaisedShield.intercept(raw(1, ArmorFraction.MAX_INT), before, 11, 21)
	check(overflow.reason == &"armor/overflow" and not overflow.blocked and overflow.after == before, "overflow refuses without mutation")
	var invalid := RaisedShield.intercept([], before, 11, 21)
	check(invalid.reason == &"armor/invalid_hit" and invalid.after == before, "invalid raw packet refuses without mutation")
