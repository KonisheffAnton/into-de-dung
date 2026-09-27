extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		printerr("FAIL ABILITY CATALOG: " + label)

func _run() -> void:
	var defaults := AbilityCatalog.defaults()
	var ids: Dictionary = {}
	for descriptor: AbilityDefinition in defaults: ids[descriptor.ability_id] = descriptor
	for id: StringName in [&"move", &"safe_retreat", &"guard:default", &"guard:opportunist", &"guard:cover", &"guard:counterattack", &"restore_armor", &"raise_corpse", &"elemental:burning", &"elemental:wet", &"elemental:freeze", &"team.end_turn"]:
		check(ids.has(id), "default descriptor " + String(id))
	check(ids.has(&"perk:sneak_attack") and ids.has(&"perk:burning_bypass_hp_gate") and ids.has(&"immunity:freeze"), "perk and immunity coverage")
	var fire: AbilityDefinition = ids[&"mage.fire"]
	var heal: AbilityDefinition = ids[&"mage.heal"]
	check(fire.effect == &"fire" and fire.amount == 4 and fire.mana_cost == 2 and fire.cooldown_turns == 2, "mage.fire values")
	check(heal.effect == &"heal" and heal.amount == 4 and heal.mana_cost == 3 and heal.cooldown_turns == 2, "mage.heal values")
	for cooldown: int in [0, 1, 2, 3, 9223372036854775807]:
		var mage_variant := fire.copy(); mage_variant.cooldown_turns = cooldown
		check(mage_variant.validate() == &"", "mage cooldown supported: %d" % cooldown)
	var mage_without_effect := fire.copy(); mage_without_effect.effect = &""; mage_without_effect.mana_cost = 0; mage_without_effect.amount = 0
	check(mage_without_effect.validate() != &"", "mage ID requires fixed effect and price")
	var attack := AttackDefinition.new(); attack.id = &"sample"; attack.profile = AttackRules.PROFILE
	var attack_rules := AttackRules.new([1, 2], [{"actor_unit_id": 1, "target_unit_id": 2}], [attack])
	var item := ItemDef.new(); item.id = &"potion"; item.use_heal_amount = 2.0; item.max_charges = 1
	item.effects = [StatModifierEffect.new(), HealOnDamageEffect.new()]
	var catalog := AbilityCatalog.build(attack_rules, {&"potion": item})
	var built: Dictionary = {}
	for descriptor: AbilityDefinition in catalog: built[descriptor.ability_id] = descriptor
	check(built.has(&"attack:sample") and built.has(&"item_use:potion:heal_self"), "dynamic attack and item use IDs")
	check(built.has(&"item_effect:potion:0") and built.has(&"item_effect:potion:1"), "indexed item effect IDs")
	var copy := fire.copy()
	copy.amount = 99
	check(fire.amount == 4 and copy != fire, "copy isolation")
	var encoded := fire.to_dict()
	check(AbilityDefinition.from_dict(encoded) != null, "strict scalar roundtrip")
	for malformed: Dictionary in [
		{"ability_id": "x", "mana_cost": 0, "effect": "", "amount": 0},
		{"ability_id": "x", "cooldown_turns": true, "mana_cost": 0, "effect": "", "amount": 0},
		{"ability_id": "x", "cooldown_turns": 0, "mana_cost": 0.0, "effect": "", "amount": 0},
		{"ability_id": "x", "cooldown_turns": 0, "mana_cost": 0, "effect": "", "amount": 0, "extra": 1}
	]: check(AbilityDefinition.from_dict(malformed) == null, "reject malformed descriptor")
	var unsupported_attack := AttackDefinition.new(); unsupported_attack.id = &"unsupported"; unsupported_attack.profile = AttackRules.PROFILE; unsupported_attack.cooldown_turns = 1
	check(AttackRules.new([1, 2], [{"actor_unit_id": 1, "target_unit_id": 2}], [unsupported_attack]).validate() != &"", "reject unsupported positive attack cooldown")
	var legacy_positive := AbilityDefinition.new(); legacy_positive.ability_id = &"legacy"; legacy_positive.cooldown_turns = 1
	check(legacy_positive.validate() != &"", "reject positive legacy descriptor cooldown")
	item.cooldown_turns = 1
	check(ItemUseAction.from_definition(item) == null, "reject unsupported positive item cooldown")
	print("ABILITY CATALOG RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
