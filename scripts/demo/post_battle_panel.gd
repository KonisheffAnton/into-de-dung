extends RefCounted
class_name PostBattlePanel

static func render(host: HeroHubScreen) -> void:
	var report: Dictionary = host.run.battle_report
	host._text(String(report.get("title", "Итоги боя")), 25)
	var outcome := "Победа" if bool(report.get("victory", false)) else "Поражение"
	var scope := "походное золото" if String(report.get("gold_scope", "hub")) == "run" else "золото хаба"
	host._text("Поход завершён у безопасной точки" if report.get("return_reason") == "early" else "%s · %s" % [outcome, "поход завершён" if bool(report.get("completed", false)) else "бой завершён"], 20)

	host._text("ГЕРОИ", 20)
	var heroes: Array = report.get("heroes", [])
	for value: Variant in heroes:
		if not value is Dictionary: continue
		var hero: Dictionary = value
		var id := int(hero.get("id", 0))
		var participation := "участник" if bool(hero.get("participated", false)) else "резерв"
		var survival := "выжил" if bool(hero.get("alive", false)) else "погиб"
		var xp_before := int(hero.get("xp_before", 0))
		var xp_after := int(hero.get("xp_after", xp_before))
		host._text("%s · %s, %s · XP %s → %s (%s) · уровень %d → %d" % [String(hero.get("name", "Герой %d" % id)), participation, survival, _xp(xp_before), _xp(xp_after), _xp_delta(xp_after - xp_before), int(hero.get("level_before", 1)), int(hero.get("level_after", 1))], 16)
		if hero.has("hp_after_battle"):
			host._text("После боя %.1f HP · восстановлено %.1f · после восстановления %.1f/%d" % [float(hero.get("hp_after_battle", 0.0)), float(hero.get("hp_restored", 0.0)), float(hero.get("hp_after_recovery", 0.0)), int(hero.get("hp_max", 0))], 14)

	host._text("НАГРАДА И ПОТЕРИ", 20)
	host._text("Золото: +%d · потери: %d (%s) · эссенция: +%d" % [int(report.get("gold_awarded", 0)), int(report.get("gold_lost", 0)), scope, int(report.get("essence_awarded", 0))], 16)
	_show_names(host, "Предметы", report.get("items", []))
	_show_names(host, "Потеряно", report.get("lost_items", []))
	if report.get("schema") == 2: MageDeckPanel.report(host)
	var selected_artifact := String(report.get("artifact_selected", ""))
	if not selected_artifact.is_empty():
		var definition := ExpeditionCatalog.artifact(selected_artifact)
		host._text("Выбран артефакт: %s" % (definition.title if definition != null else selected_artifact), 15)

	var achievement_ids: Array = report.get("achievements", [])
	if not achievement_ids.is_empty() or int(report.get("points_awarded", 0)) > 0:
		host._text("НОВЫЕ ДОСТИЖЕНИЯ · +%d очков" % int(report.get("points_awarded", 0)), 20)
		for achievement_id: Variant in achievement_ids:
			host._text(_achievement_title(String(achievement_id)), 15)

	_show_repairs(host, report)
	_show_reward_choices(host)
	var reward_pending := _reward_pending(host)
	var continue_button := host._button_for(host._content, "Продолжить", "continue_battle_report", host._mutate.bind(&"dismiss_battle_report"))
	continue_button.disabled = reward_pending or host._pending_save != null
	if reward_pending:
		host._text("Сначала выберите награду или откажитесь от неё." if report.get("schema") == 2 else "Сначала выберите один артефакт награды.", 14)

static func _show_names(host: HeroHubScreen, heading: String, values: Variant) -> void:
	if not values is Array or (values as Array).is_empty(): return
	var names: PackedStringArray = []
	for value: Variant in values:
		names.append(String(value))
	host._text("%s: %s" % [heading, " · ".join(names)], 15)

static func _show_repairs(host: HeroHubScreen, report: Dictionary) -> void:
	var repairs: Array = report.get("repairs", [])
	if not repairs.is_empty():
		host._text("ПОЧИНКА ПОСЛЕ БОЯ", 19)
		for value: Variant in repairs:
			if not value is Dictionary: continue
			var repair: Dictionary = value
			var hero_name := "Герой"
			for hero_value: Variant in report.get("heroes", []):
				if hero_value is Dictionary and int((hero_value as Dictionary).get("id", 0)) == int(repair.get("hero_id", 0)):
					hero_name = String((hero_value as Dictionary).get("name", hero_name))
					break
			host._text("%s · %s: восстановлено %d брони за %d золота" % [hero_name, String(repair.get("name", "Доспех")), int(repair.get("amount", 0)), int(repair.get("cost", 0))], 14)
	if not bool(report.get("victory", false)): return
	for value: Variant in report.get("heroes", []):
		if not value is Dictionary: continue
		var hero: Dictionary = value
		var hero_id := int(hero.get("id", 0))
		if not bool(hero.get("alive", false)) or hero_id <= 0: continue
		var quote := PostBattleRules.repair_quote(host.run, hero_id)
		if quote.is_empty(): continue
		var button_text := "Починить %s · %s: %d→%d (+%d) · %d золота" % [String(quote.get("name", "доспех")), String(hero.get("name", "герой")), int(quote.get("before", 0)), int(quote.get("after", 0)), int(quote.get("amount", 0)), int(quote.get("cost", 0))]
		var button := host._button_for(host._content, button_text, "repair_%d" % hero_id, host._mutate.bind(&"repair_after_battle", [hero_id]))
		button.disabled = not bool(quote.get("affordable", false)) or host._pending_save != null

static func _show_reward_choices(host: HeroHubScreen) -> void:
	if not _reward_pending(host): return
	if host.run.expedition.is_deck(): MageDeckPanel.rewards(host); return
	host._text("ПОБЕДА · выберите один артефакт", 20)
	var rewards: Array = host.run.expedition.current_node().reward
	for index: int in rewards.size():
		var definition := ExpeditionCatalog.artifact(rewards[index])
		var button := host._button_for(host._content, definition.title, "reward_%d" % index, host._expedition_action.bind("reward", {"index": index}))
		button.disabled = host._pending_save != null
		host._text(definition.description, 15)

static func _reward_pending(host: HeroHubScreen) -> bool:
	return host.run.phase == "expedition" and host.run.expedition != null and host.run.expedition.phase == "reward"

static func _achievement_title(id: String) -> String:
	for definition: ProfileAchievementDefinition in ProfileAchievements.definitions():
		if String(definition.id) == id: return definition.title
	return id

static func _xp(value: int) -> String:
	return "%d.%d" % [int(value / 10), absi(value % 10)]

static func _xp_delta(value: int) -> String:
	return ("+" if value >= 0 else "−") + _xp(absi(value))
