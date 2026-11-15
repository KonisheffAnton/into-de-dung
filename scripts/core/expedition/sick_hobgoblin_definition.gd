extends Resource
class_name SickHobgoblinDefinition

@export var id: StringName = &"sick_hobgoblin"
@export var display_name: String = "Нездоровый хоб-гоблин"
@export var attributes: Array[int] = [10, 5, 6, 10, 10]
@export var strength: float = 3.0
@export var weapon_damage: float = 2.0
@export var impact: float = 2.0

func base_stats() -> Dictionary:
	# У противника нет перков: здоровье, ход и равновесие следуют обычным формулам.
	return {
		StatTypes.StatType.HP_MAX: CharacterAttributeRules.max_hp(attributes[2]),
		StatTypes.StatType.ARMOR: 0.0,
		StatTypes.StatType.STRENGTH: strength,
		StatTypes.StatType.WEAPON_DAMAGE: weapon_damage,
		StatTypes.StatType.IMPACT_POWER: impact,
		StatTypes.StatType.BALANCE_MAX: CharacterAttributeRules.balance_max(attributes[2]),
		StatTypes.StatType.MOVE_RANGE: CharacterAttributeRules.move_max(attributes[1]),
		StatTypes.StatType.ATTACK_RANGE: 1.0,
		StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0,
		StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0,
		StatTypes.StatType.POWER: float(attributes[0]),
		StatTypes.StatType.DEXTERITY: float(attributes[1]),
		StatTypes.StatType.ENDURANCE: float(attributes[2]),
		StatTypes.StatType.INTELLECT: float(attributes[3]),
		StatTypes.StatType.MASTERY: float(attributes[4]),
	}
