extends Control
class_name ExpeditionMapView

signal room_chosen(id: int)
var run: ExpeditionRunState
var _positions: Dictionary = {}

func _ready() -> void:
	resized.connect(_layout)
	if run == null: return
	for node: Dictionary in run.plan.nodes:
		var button := preload("res://scenes/demo/hub/map_room.tscn").instantiate() as Button
		button.name = "room_%d" % node.id
		var accessible := run.available_nodes().has(node.id)
		var prefix := "✓ " if run.resolved.has(node.id) else "→ " if accessible else ""
		button.text = "%s%d · %s" % [prefix,node.id,ExpeditionCatalog.room_name(node.kind)]
		if accessible:
			if node.kind in ["battle","elite","final"]:
				var encounter := ExpeditionCatalog.encounter(node.kind,node.variant)
				button.text += "\n%d дозорных · %s" % [encounter.enemy_cells.size(), ["колонна","уступ","широко"][node.variant]]
				button.tooltip_text = encounter_details(encounter,node.modifier)
			button.text += "\n" + modifier_name(node.modifier)
		button.disabled = not accessible
		button.pressed.connect(func() -> void: room_chosen.emit(node.id))
		add_child(button)
	_layout()

func _layout() -> void:
	if run == null: return
	_positions.clear()
	for layer: int in 7:
		var nodes: Array[Dictionary] = []
		for node: Dictionary in run.plan.nodes:
			if node.layer == layer: nodes.append(node)
		for index: int in nodes.size():
			var node: Dictionary = nodes[index]
			var center := Vector2(size.x * (index + 0.5) / nodes.size(), layer * 92 + 35)
			_positions[node.id] = center
			var button := get_node("room_%d" % node.id) as Button
			button.position = center - Vector2(116, 31)
			button.size = Vector2(232, 62)
	queue_redraw()

func _draw() -> void:
	if run == null: return
	for node: Dictionary in run.plan.nodes:
		for target: int in node.next:
			if not _positions.has(node.id) or not _positions.has(target): continue
			var chosen: bool = run.route.has(node.id) and run.route.has(target)
			draw_line(_positions[node.id] + Vector2(0,31),_positions[target] - Vector2(0,31),Color("e3b66f") if chosen else Color("516077"),3 if chosen else 1.5)

static func modifier_name(value: String) -> String:
	return {"neutral":"Без модификатора","spikes":"Шипы","fire":"Горящая земля","healing":"Лечение 50%","repair":"Ремонт 50%","rich":"Богатый тайник"}.get(value, "")

static func encounter_details(value: ExpeditionEncounterDefinition, modifier: String) -> String:
	var cells: PackedStringArray = []
	for cell: Vector2i in value.enemy_cells: cells.append("%s%d" % [String.chr(65 + cell.x),cell.y + 1])
	var result := "Дозорные: %d; HP %d; броня 0; сила %d; оружие %d; дальность %d; ход %d; баланс %d; импакт %d.\nКлетки: %s." % [value.enemy_cells.size(),value.enemy_hp,value.enemy_strength,value.enemy_weapon_damage,value.enemy_range,value.enemy_move,value.enemy_balance,value.enemy_impact,", ".join(cells)]
	if modifier in ["spikes","fire"]:
		cells.clear()
		for cell: Vector2i in value.hazard_cells: cells.append("%s%d" % [String.chr(65 + cell.x),cell.y + 1])
		result += "\n%s: %s." % [modifier_name(modifier),", ".join(cells)]
	return result
