class_name ClassShowcaseRoster
extends RefCounted

static func enemies(run: HeroHubState) -> Array[StringName]:
	var result: Array[StringName] = []
	if run.hero_catalog_version < 4: return result
	var classes := HeroCatalog.class_ids(run.hero_catalog_version)
	var allied: Array[StringName] = []
	for id: int in run.party: allied.append((run.heroes[id] as HeroProgression).class_id)
	# Для обзора классов нужны только отсутствующие виды, без добивки старой встречи.
	for class_id: StringName in classes:
		if not allied.has(class_id): result.append(class_id)
	return result

static func cells(authored: Array[Vector2i], total: int, opening: Dictionary, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(authored.slice(0, total))
	# Дополнительные враги используют свободную правую половину; план/геометрия не переписываются.
	var terrain := BattleBoard.new(size.x, size.y)
	for tile: Dictionary in opening.get("terrain", []):
		terrain.set_terrain(ExpeditionOpening.cell(tile.cell), int(tile.type) as TerrainType.Type)
	if size == BiomeShowcaseLayout.SIZE:
		BiomeShowcaseLayout.apply(terrain, not opening.is_empty())
	for y: int in size.y:
		for x: int in range(size.x - 1, size.x / 2 - 1, -1):
			if result.size() >= total: return result
			var cell := Vector2i(x, y)
			if not result.has(cell) and terrain.get_terrain(cell) == TerrainType.Type.FLOOR: result.append(cell)
	return result

static func apply_class(unit: UnitState, class_id: StringName) -> void:
	unit.combat_perks.definition.tank_reactions = class_id == &"warrior"
	unit.combat_perks.definition.counterattack = class_id == &"warrior"
	unit.combat_perks.definition.stunning_strike = class_id == &"warrior"
	unit.combat_perks.definition.sneak_attack = class_id == &"rogue"
	unit.combat_perks.definition.passive_opportunist = class_id == &"shieldbearer"
	unit.combat_perks.definition.stun_immune = false
	unit.bleeding.immune = false
	if class_id == &"fighter": unit.combat_perks.warrior = WarriorKit.make()
	if class_id == &"shieldbearer": unit.armor.raised_shield = RaisedShield.make()
