extends RefCounted
class_name PostBattlePanel

static func render(host: HeroHubScreen) -> void:
	var report: Dictionary = host.run.battle_report
	var page: VBoxContainer = host._page("ReportPage")
	var heroes_slot: VBoxContainer = page.get_node("Heroes") as VBoxContainer
	var loot_slot: VBoxContainer = page.get_node("Loot") as VBoxContainer
	var deck_slot: VBoxContainer = page.get_node("DeckReport") as VBoxContainer
	var achievements_slot: VBoxContainer = page.get_node("Achievements") as VBoxContainer
	var repairs_slot: VBoxContainer = page.get_node("Repairs") as VBoxContainer
	var rewards_slot: VBoxContainer = page.get_node("Rewards") as VBoxContainer

	var outcome := "Победа" if bool(report.get("victory", false)) else "Поражение"
	var scope := "походное золото" if String(report.get("gold_scope", "hub")) == "run" else "золото хаба"
	HubUI.text(page, ^"Title", String(report.get("title", "Итоги боя")))
	HubUI.text(page, ^"Outcome", "Поход завершён у безопасной точки" if report.get("return_reason") == "early" else "%s · %s" % [outcome, "поход завершён" if bool(report.get("completed", false)) else "бой завершён"])
	_host_content(host, heroes_slot)

	var heroes: Array = report.get("heroes", [])
	heroes_slot.visible = not heroes.is_empty()
	for value: Variant in heroes:
		if not value is Dictionary: continue
		var hero: Dictionary = value
		var id := int(hero.get("id", 0))
		var participation := "участник" if bool(hero.get("participated", false)) else "резерв"
		var survival := "выжил" if bool(hero.get("alive", false)) else "погиб"
		var xp_before := int(hero.get("xp_before", 0))
		var xp_after := int(hero.get("xp_after", xp_before))
		var hero_view: Control = HubUI.instance("report_hero", heroes_slot)
		HubUI.text(hero_view, ^"Summary", "%s · %s, %s · XP %s → %s (%s) · уровень %d → %d" % [String(hero.get("name", "Герой %d" % id)), participation, survival, _xp(xp_before), _xp(xp_after), _xp_delta(xp_after - xp_before), int(hero.get("level_before", 1)), int(hero.get("level_after", 1))])
		if hero.has("hp_after_battle"):
			HubUI.text(hero_view, ^"Recovery", "После боя %.1f HP · восстановлено %.1f · после восстановления %.1f/%d" % [float(hero.get("hp_after_battle", 0.0)), float(hero.get("hp_restored", 0.0)), float(hero.get("hp_after_recovery", 0.0)), int(hero.get("hp_max", 0))])
			(hero_view.get_node("Recovery") as Label).visible = true
		else:
			(hero_view.get_node("Recovery") as Label).visible = false

	_host_content(host, loot_slot)
	_host_text(host, "Золото: +%d · потери: %d (%s) · эссенция: +%d" % [int(report.get("gold_awarded", 0)), int(report.get("gold_lost", 0)), scope, int(report.get("essence_awarded", 0))], 16)
	_show_names(host, "Предметы", report.get("items", []))
	_show_names(host, "Потеряно", report.get("lost_items", []))
	var selected_artifact := String(report.get("artifact_selected", ""))
	if not selected_artifact.is_empty():
		var definition := ExpeditionCatalog.artifact(selected_artifact)
		_host_text(host, "Выбран артефакт: %s" % (definition.title if definition != null else selected_artifact), 15)

	deck_slot.visible = report.get("schema") == 2
	if deck_slot.visible:
		_host_content(host, deck_slot)
		MageDeckPanel.report(host)

	var achievement_ids: Array = report.get("achievements", [])
	var points_awarded := int(report.get("points_awarded", 0))
	achievements_slot.visible = not achievement_ids.is_empty() or points_awarded > 0
	var achievements_heading: Label = page.get_node("AchievementsHeading") as Label
	HubUI.text(page, ^"AchievementsHeading", "НОВЫЕ ДОСТИЖЕНИЯ · +%d очков" % points_awarded)
	achievements_heading.visible = achievements_slot.visible
	if achievements_slot.visible:
		_host_content(host, achievements_slot)
		for achievement_id: Variant in achievement_ids:
			_host_text(host, _achievement_title(String(achievement_id)), 15)

	_host_content(host, repairs_slot)
	_show_repairs(host, report)
	_host_content(host, rewards_slot)
	_show_reward_choices(host)
	var reward_pending := _reward_pending(host)
	var deck_mode := host.run.expedition != null and host.run.expedition.is_deck()
	(page.get_node("HeroesHeading") as Label).visible = heroes_slot.visible
	(page.get_node("RepairsHeading") as Label).visible = repairs_slot.visible
	var rewards_heading: Label = page.get_node("RewardsHeading") as Label
	HubUI.text(page, ^"RewardsHeading", "ПОБЕДА · выберите один артефакт" if not deck_mode else "НАГРАДА · выберите одну карту или откажитесь")
	rewards_heading.visible = reward_pending and not deck_mode
	var continue_button: Button = HubUI.bind(page, ^"continue_battle_report", host._mutate.bind(&"dismiss_battle_report"))
	continue_button.disabled = reward_pending or host._pending_save != null
	var reward_hint: Label = page.get_node("RewardHint") as Label
	reward_hint.text = "Сначала выберите награду или откажитесь от неё." if report.get("schema") == 2 else "Сначала выберите один артефакт награды."
	reward_hint.visible = reward_pending

static func _show_names(host: HeroHubScreen, heading: String, values: Variant) -> void:
	if not values is Array or (values as Array).is_empty(): return
	var names: PackedStringArray = []
	for value: Variant in values:
		names.append(String(value))
	_host_text(host, "%s: %s" % [heading, " · ".join(names)], 15)

static func _show_repairs(host: HeroHubScreen, report: Dictionary) -> void:
	var repairs: Array = report.get("repairs", [])
	var repairs_slot: VBoxContainer = host._content as VBoxContainer
	repairs_slot.visible = not repairs.is_empty()
	if not repairs.is_empty():
		for value: Variant in repairs:
			if not value is Dictionary: continue
			var repair: Dictionary = value
			var hero_name := "Герой"
			for hero_value: Variant in report.get("heroes", []):
				if hero_value is Dictionary and int((hero_value as Dictionary).get("id", 0)) == int(repair.get("hero_id", 0)):
					hero_name = String((hero_value as Dictionary).get("name", hero_name))
					break
			_host_text(host, "%s · %s: восстановлено %d брони за %d золота" % [hero_name, String(repair.get("name", "Доспех")), int(repair.get("amount", 0)), int(repair.get("cost", 0))], 14)
	if not bool(report.get("victory", false)): return
	for value: Variant in report.get("heroes", []):
		if not value is Dictionary: continue
		var hero: Dictionary = value
		var hero_id := int(hero.get("id", 0))
		if not bool(hero.get("alive", false)) or hero_id <= 0: continue
		var quote := PostBattleRules.repair_quote(host.run, hero_id)
		if quote.is_empty(): continue
		repairs_slot.visible = true
		var button_text := "Починить %s · %s: %d→%d (+%d) · %d золота" % [String(quote.get("name", "доспех")), String(hero.get("name", "герой")), int(quote.get("before", 0)), int(quote.get("after", 0)), int(quote.get("amount", 0)), int(quote.get("cost", 0))]
		var button := host._button_for(host._content, button_text, "repair_%d" % hero_id, host._mutate.bind(&"repair_after_battle", [hero_id]))
		button.disabled = not bool(quote.get("affordable", false)) or host._pending_save != null

static func _show_reward_choices(host: HeroHubScreen) -> void:
	var rewards_slot: VBoxContainer = host._content as VBoxContainer
	if not _reward_pending(host):
		rewards_slot.visible = false
		return
	rewards_slot.visible = true
	if host.run.expedition.is_deck(): MageDeckPanel.rewards(host); return
	var rewards: Array = host.run.expedition.current_node().reward
	for index: int in rewards.size():
		var definition := ExpeditionCatalog.artifact(rewards[index])
		var button := host._button_for(host._content, definition.title, "reward_%d" % index, host._expedition_action.bind("reward", {"index": index}))
		button.disabled = host._pending_save != null
		_host_text(host, definition.description, 15)

static func _reward_pending(host: HeroHubScreen) -> bool:
	return host.run.phase == "expedition" and host.run.expedition != null and host.run.expedition.phase == "reward"

static func _host_content(host: HeroHubScreen, content: VBoxContainer) -> void:
	host._content = content

static func _host_text(host: HeroHubScreen, value: String, font_size: int) -> void:
	host._text(value, font_size)

static func _achievement_title(id: String) -> String:
	for definition: ProfileAchievementDefinition in ProfileAchievements.definitions():
		if String(definition.id) == id: return definition.title
	return id

static func _xp(value: int) -> String:
	return "%d.%d" % [int(value / 10), absi(value % 10)]

static func _xp_delta(value: int) -> String:
	return ("+" if value >= 0 else "−") + _xp(absi(value))
