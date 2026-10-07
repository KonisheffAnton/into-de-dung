extends Resource
class_name HeroGearCatalog

static func definition(key: String) -> ItemDef:
	var parts := key.split(":")
	if parts.size() != 2 or parts[0] not in ["weapon", "armor"]: return null
	var hero_class := HeroCatalog.class_definition(StringName(parts[1]))
	if hero_class == null: return null
	var result := ItemDef.new()
	result.id = StringName(key)
	if parts[0] == "armor":
		result.display_name = "Доспех · " + hero_class.display_name
		result.armor_max = hero_class.armor_max
	else:
		result.display_name = {"warrior":"Меч", "shieldbearer":"Меч", "archer":"Лук", "rogue":"Кинжал", "mage":"Посох"}[parts[1]]
		# Посох усиливает огненный компонент определения атаки, а не физическую базу.
		if parts[1] != "mage":
			var modifier := StatModifierEffect.new()
			modifier.stat_type = StatTypes.StatType.WEAPON_DAMAGE
			modifier.value = hero_class.weapon_damage
			result.effects.append(modifier)
		if parts[1] == "rogue":
			var piercing := StatModifierEffect.new()
			piercing.stat_type = StatTypes.StatType.PHYSICAL_PIERCING_PERCENT
			piercing.value = 35.0
			result.effects.append(piercing)
	return result

static func slot(key: String) -> String:
	return key.get_slice(":", 0)

static func allowed(key: String, class_id: StringName) -> bool:
	return definition(key) != null and (slot(key) == "armor" or key.get_slice(":", 1) == String(class_id))
