extends RefCounted
class_name D4Catalog

const IDS: Array[String] = ["sword", "coat", "bracer", "keen_sword", "charm"]

static func definition(kind: String) -> ItemDef:
	if not IDS.has(kind):
		return null
	var result := ItemDef.new()
	result.id = StringName("d4_" + kind)
	result.display_name = title(kind)
	var effect: StatModifierEffect = null
	match kind:
		"sword":
			effect = StatModifierEffect.new()
			effect.stat_type = StatTypes.StatType.WEAPON_DAMAGE
			effect.value = 4.0
		"keen_sword":
			effect = StatModifierEffect.new()
			effect.stat_type = StatTypes.StatType.WEAPON_DAMAGE
			effect.value = 6.0
		"charm":
			effect = StatModifierEffect.new()
			effect.stat_type = StatTypes.StatType.STRENGTH
			effect.value = 2.0
		"coat":
			result.armor_max = 60
		"bracer":
			result.armor_max = 40
	if effect != null:
		result.effects = [effect]
	return result

static func slot(kind: String) -> int:
	match kind:
		"sword", "keen_sword": return 0
		"coat": return 1
		"bracer", "charm": return 2
	return -1

static func title(kind: String) -> String:
	match kind:
		"sword": return "Меч"
		"coat": return "Кираса"
		"bracer": return "Наручи"
		"keen_sword": return "Острый меч"
		"charm": return "Амулет"
	return ""
