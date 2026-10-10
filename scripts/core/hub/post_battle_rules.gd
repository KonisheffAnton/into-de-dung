extends RefCounted
class_name PostBattleRules

const RECOVERY_PERCENT: int = 10
const REPAIR_AMOUNT: int = 10
const GOLD_PER_ARMOR: int = 2

static func begin(hub: HeroHubState, source: String, node_id: int, serial: int, title: String, victory: bool, completed: bool) -> Dictionary:
	var rows: Array[Dictionary] = []
	var ids: Array = hub.heroes.keys(); ids.sort()
	for id: int in ids:
		var hero: HeroProgression = hub.heroes[id]
		rows.append({"id":id,"name":hero.name,"participated":hub.party.has(id),"alive":true,
			"xp_before":hero.xp_tenths,"xp_after":hero.xp_tenths,"level_before":hero.level(),"level_after":hero.level(),
			"hp_after_battle":float(hero.hp_current),"hp_restored":0.0,"hp_after_recovery":float(hero.hp_current),"hp_max":hero.max_hp()})
	return {"schema":3,"ruleset_id":ExpeditionRulesRegistry.LEGACY,"open":true,"source":source,"run_id":hub.run_serial,"node_id":node_id,"serial":serial,"title":title,
		"victory":victory,"completed":completed,"heroes":rows,"gold_awarded":0,"essence_awarded":0,"gold_lost":0,
		"gold_scope":"run" if source == "expedition" else "hub","items":[],"lost_items":[],"achievements":[],"points_awarded":0,"repairs":[],"artifact_selected":""}

static func finish(hub: HeroHubState, report: Dictionary, hp: Dictionary) -> void:
	var without_losses := true
	for row: Dictionary in report.heroes:
		if row.participated:
			row.hp_after_battle = float(hp[row.id]); row.hp_after_recovery = float(hp[row.id])
			row.alive = float(hp[row.id]) > 0.0
			if not row.alive: without_losses = false
		var hero: HeroProgression = hub.heroes.get(row.id)
		if hero == null: continue
		row.xp_after = hero.xp_tenths; row.level_after = hero.level()
		if report.victory and row.participated and row.alive:
			# Восстановление принадлежит исходу боя; открытие окна не лечит повторно.
			var restored := minf(float(row.hp_max) - hero.hp_current, floorf(float(row.hp_max) * RECOVERY_PERCENT / 100.0))
			hero.hp_current += restored
			row.hp_restored = restored; row.hp_after_recovery = float(hero.hp_current)
	var previous_points := hub.achievements.total_points
	report.achievements = hub.achievements.record(report.victory, without_losses, report.completed)
	report.points_awarded = hub.achievements.total_points - previous_points
	hub.battle_report = report.duplicate(true)

static func repair_quote(hub: HeroHubState, hero_id: int) -> Dictionary:
	var report := hub.battle_report
	if report.get("ruleset_id") == ExpeditionRulesRegistry.DECK and report.get("reward_state") == "pending" and hub.expedition != null and hub.expedition.current_node().kind == "final": return {}
	if report.is_empty() or not report.open or not report.victory or report.repairs.size() >= 256: return {}
	if hub.phase == "battle" or (hub.phase == "expedition" and hub.expedition.phase not in ["reward","route"]): return {}
	var eligible := false
	for row: Dictionary in report.heroes:
		if row.id == hero_id and row.participated and row.alive: eligible = true
	if not eligible or not hub.heroes.has(hero_id): return {}
	var armor := hub.equipped(hero_id,"armor")
	if armor.is_empty(): return {}
	var definition := HeroGearCatalog.definition(armor.definition)
	var amount := mini(REPAIR_AMOUNT, definition.armor_max - int(armor.remaining))
	if amount <= 0: return {}
	var gold := hub.expedition.gold if hub.phase == "expedition" else hub.gold
	return {"hero_id":hero_id,"item_id":int(armor.id),"name":definition.display_name,"before":int(armor.remaining),"after":int(armor.remaining) + amount,
		"amount":amount,"cost":amount * GOLD_PER_ARMOR,"affordable":gold >= amount * GOLD_PER_ARMOR}

static func repair(hub: HeroHubState, hero_id: int) -> bool:
	var quote := repair_quote(hub,hero_id)
	if quote.is_empty() or not quote.affordable: return false
	if hub.phase == "expedition":
		hub.expedition.gold -= int(quote.cost); hub.expedition.repair_spent += int(quote.cost)
	else: hub.gold -= int(quote.cost)
	hub.items[quote.item_id].remaining = int(quote.after)
	hub.battle_report.repairs.append({"hero_id":hero_id,"item_id":int(quote.item_id),"name":String(quote.name),"amount":int(quote.amount),"cost":int(quote.cost)})
	return true

static func valid_report(data: Dictionary, hub: HeroHubState) -> bool:
	if data.get("ruleset_id") == ExpeditionRulesRegistry.DECK: return MageDeckReport.valid(data,hub)
	return _valid_legacy_report(data,hub)

static func _valid_legacy_report(data: Dictionary, hub: HeroHubState, early: bool = false) -> bool:
	if data.is_empty(): return true
	if not ItemSimulationSnapshot._shape(data,{"schema":TYPE_INT,"ruleset_id":TYPE_STRING,"open":TYPE_BOOL,"source":TYPE_STRING,"run_id":TYPE_INT,"node_id":TYPE_INT,"serial":TYPE_INT,"title":TYPE_STRING,"victory":TYPE_BOOL,"completed":TYPE_BOOL,"heroes":TYPE_ARRAY,"gold_awarded":TYPE_INT,"essence_awarded":TYPE_INT,"gold_lost":TYPE_INT,"gold_scope":TYPE_STRING,"items":TYPE_ARRAY,"lost_items":TYPE_ARRAY,"achievements":TYPE_ARRAY,"points_awarded":TYPE_INT,"repairs":TYPE_ARRAY,"artifact_selected":TYPE_STRING}): return false
	if data.schema != 3 or data.ruleset_id != ExpeditionRulesRegistry.LEGACY or data.source not in ["legacy","expedition"] or data.gold_scope not in ["run","hub"]: return false
	if data.run_id < 1 or data.run_id > hub.run_serial or data.serial < 1 or data.serial > ExpeditionRunState.MAX_VALUE or data.node_id < 0 or data.node_id > 14: return false
	if data.source == "legacy" and (data.node_id != 0 or data.serial != data.run_id or data.completed): return false
	if data.source == "expedition" and (data.node_id < 1 or data.serial > 6): return false
	if not data.artifact_selected.is_empty() and ExpeditionCatalog.artifact(data.artifact_selected) == null: return false
	if data.title.length() > 128 or data.artifact_selected.length() > 128 or data.heroes.is_empty() or data.heroes.size() > HeroHubState.MAX_ROSTER or data.repairs.size() > 256: return false
	for key: String in ["gold_awarded","essence_awarded","gold_lost","points_awarded"]:
		if data[key] < 0 or data[key] > ExpeditionRunState.MAX_VALUE: return false
	if data.completed and not data.victory: return false
	for key: String in ["items","lost_items","achievements"]:
		if data[key].size() > 16: return false
		for value: Variant in data[key]:
			if typeof(value) != TYPE_STRING or value.length() > 128: return false
	var ids: Dictionary = {}; var participants: int = 0; var living: int = 0
	for row: Variant in data.heroes:
		if not ItemSimulationSnapshot._shape(row,{"id":TYPE_INT,"name":TYPE_STRING,"participated":TYPE_BOOL,"alive":TYPE_BOOL,"xp_before":TYPE_INT,"xp_after":TYPE_INT,"level_before":TYPE_INT,"level_after":TYPE_INT,"hp_after_battle":TYPE_FLOAT,"hp_restored":TYPE_FLOAT,"hp_after_recovery":TYPE_FLOAT,"hp_max":TYPE_INT}): return false
		if row.id < 1 or row.id >= hub.next_id or ids.has(row.id) or row.name.length() > 128 or row.hp_max < 1 or row.hp_max > ExpeditionRunState.MAX_VALUE: return false
		ids[row.id] = true
		if row.xp_before < 0 or row.xp_after < row.xp_before or row.xp_after > HeroProgression.MAX_XP_TENTHS or row.level_before < 1 or row.level_after < row.level_before or row.level_after > 10: return false
		for key: String in ["hp_after_battle","hp_restored","hp_after_recovery"]:
			if not is_finite(row[key]) or row[key] < 0.0 or row[key] > row.hp_max: return false
		if not is_equal_approx(row.hp_after_battle + row.hp_restored,row.hp_after_recovery): return false
		if row.participated:
			participants += 1
			if row.alive: living += 1
			if row.alive != (row.hp_after_battle > 0.0): return false
		if (not row.alive or not row.participated or not data.victory) and row.hp_restored != 0.0: return false
	if participants < 1 or participants > HeroHubState.MAX_PARTY or data.victory != (living > 0): return false
	var gained: int = 0; var seen: Dictionary = {}
	for id: String in data.achievements:
		if not hub.achievements.unlocked.has(id) or seen.has(id): return false
		seen[id] = true
		for definition: ProfileAchievementDefinition in ProfileAchievements.definitions():
			if definition.id == id: gained += definition.points
	if gained != data.points_awarded: return false
	for row: Variant in data.repairs:
		if not ItemSimulationSnapshot._shape(row,{"hero_id":TYPE_INT,"item_id":TYPE_INT,"name":TYPE_STRING,"amount":TYPE_INT,"cost":TYPE_INT}): return false
		if not ids.has(row.hero_id) or row.item_id < 1 or row.item_id >= hub.next_item_id or row.name.length() > 128 or row.amount < 1 or row.amount > REPAIR_AMOUNT or row.cost != row.amount * GOLD_PER_ARMOR: return false
	if data.open:
		if data.run_id != hub.run_serial or hub.phase == "battle": return false
		if hub.phase == "expedition":
			if data.source != "expedition" or data.gold_scope != "run" or data.serial != hub.expedition.battle_serial or data.node_id != hub.expedition.current_node().id or hub.expedition.phase not in ["reward","route"]: return false
		elif data.gold_scope != "hub" or (data.source == "expedition" and data.victory and not data.completed and not early): return false
	return true
