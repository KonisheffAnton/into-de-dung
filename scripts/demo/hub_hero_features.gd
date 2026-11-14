extends RefCounted
class_name HubHeroFeatures

const ICON_ROOT: String = "res://assets/art_presets/approved/status_icons_silhouette_v1/32/"

static func entries(hero: HeroProgression) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if hero == null:
		return result
	var perk_description: String = HeroCatalog.perk_text(hero.perk)
	var perk_parts: PackedStringArray = perk_description.split(":", false, 1)
	if perk_parts.size() == 2:
		result.append(_entry(StringName("perk_%s" % String(hero.perk)), perk_parts[0].strip_edges(), perk_parts[1].strip_edges(), true, _perk_icon(hero.perk)))
	match hero.class_id:
		&"fighter":
			result.append(_entry(&"fighter_endurance", "Выносливость", "Усиливает получаемое лечение и восстановление брони на 20% в пределах допустимой источником недостачи.", true, "shield.png"))
			result.append(_entry(&"fighter_cleave", "Рассекающий удар", "Обычный физический удар по одной соседней цели, затем 1 стак кровотечения. 1 основное действие, откат 1.", false, "bleeding.png"))
			result.append(_entry(&"fighter_kick", "Пинок ногой", "Физическая база: 2 × max(0, Мощь); воздействие на баланс: max(0, Мощь) / 4. 1 дополнительное действие.", false, "stunned.png"))
		&"shieldbearer":
			result.append(_entry(&"shieldbearer_opportunist", "Оппортунист", "Добровольный выход врага из ближней угрозы вызывает реакционный удар и останавливает его маршрут. Нужен 1 дополнительный ресурс действия.", true, "opportunist.png"))
			result.append(_entry(&"shieldbearer_raise_shields", "Поднять щиты", "Снижает урон первой подходящей прямой атаки на 90% до начала следующего хода команды. 1 основное действие, откат 1.", false, "raised_shield.png"))
		&"rogue":
			result.append(_entry(&"rogue_sneak_attack", "Скрытая атака", "Ближний удар получает +50% физической базы, если цели угрожают две допустимые боковые ближние угрозы, включая атакующего. Дальний выстрел второй угрозой не считается.", true, "counterattack.png"))
		&"archer":
			result.append(_entry(&"archer_entangling_strike", "Опутывающий выстрел", "Накладывает путы при физическом попадании по здоровью.", false, "entangled.png"))
		&"mage":
			result.append(_entry(&"mage_fire_strike", "Огненный удар", "Обычная атака с огненной составляющей. Само огненное попадание не накладывает горение. 1 основное действие.", false, "fire_on_tile.png"))
			result.append(_entry(&"mage_burn", "Поджечь", "Огненная база 4. Если огонь повредил здоровье и цель выжила: сухая цель загорается, мокрая высыхает, замороженная оттаивает и становится мокрой. 1 основное действие.", false, "burning.png"))
			result.append(_entry(&"mage_wet", "Облить", "Мочит цель на 3 хода и гасит горение. 1 основное действие.", false, "wet.png"))
			result.append(_entry(&"mage_freeze", "Заморозить", "Сухую цель сначала мочит. Мокрую замораживает, если брони осталось меньше половины (или брони нет) и нет иммунитета к заморозке. 1 основное действие.", false, "frozen.png"))
			result.append(_entry(&"mage_restore_armor", "Восстановить броню", "Восстанавливает себе до 20 единиц брони. 1 основное действие.", false, "shield.png"))
		&"warrior":
			result.append(_entry(&"warrior_stunning_strike", "Оглушающий удар", "Обычный удар, накладывающий оглушение при физическом уроне по здоровью.", false, "stunned.png"))
			result.append(_entry(&"warrior_opportunity", "Оппортунист", "Реакционная стойка: удар по врагу, добровольно выходящему из ближней угрозы, останавливает его маршрут. Вход: 1 основное действие; реакция: 1 дополнительное.", false, "opportunist.png"))
	return result

static func _entry(id: StringName, title: String, description: String, passive: bool, icon_name: String) -> Dictionary:
	var path: String = ICON_ROOT + icon_name
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return {"id": id, "title": title, "description": description, "passive": passive, "icon": texture}

static func _perk_icon(perk: StringName) -> String:
	match perk:
		&"hardy": return "shield.png"
		&"steady": return "cover.png"
		&"fleet": return "pending.png"
		&"force": return "opportunist.png"
		_: return "shield.png"
