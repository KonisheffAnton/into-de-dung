extends Control
class_name D4Expedition

@export var save_path: String = "user://d4-run.save"
var run: D4RunState
var battle: D4BattleSession
var battle_view: D4BattleView
var selected_hero: int = 1
var _panel: Control
var _body: VBoxContainer
var _message: String = ""
var _pending: D4RunState
var _storage_error: String = ""

func _ready() -> void:
	var loaded := D4RunStore.read_run(save_path)
	run = loaded.run
	_storage_error = loaded.error
	_render()

func _process(_delta: float) -> void:
	if battle == null or _pending != null: return
	var outcome := battle.outcome_data()
	if outcome.is_empty(): return
	var candidate := D4RunState.from_dict(run.to_dict())
	if not candidate.apply_battle_result(outcome.victory, outcome.hp, outcome.armor):
		_storage_error = "Результат боя не прошёл проверку. Контрольная точка сохранена."
		_clear_battle()
		_render()
		return
	_commit(candidate)

func _exit_tree() -> void:
	if battle != null: battle.close()

func _commit(candidate: D4RunState) -> void:
	var error := D4RunStore.write_run(save_path, candidate)
	if not error.is_empty():
		_pending = candidate
		_storage_error = error
		if battle_view != null:
			battle_view.set_process(false)
			battle_view.hide()
		_render_panel()
		return
	run = candidate
	_pending = null
	_storage_error = ""
	_clear_battle()
	_render()

func _act(method: StringName, args: Array = []) -> void:
	if run == null or _pending != null or not _storage_error.is_empty(): return
	var candidate := D4RunState.from_dict(run.to_dict())
	var result: Variant = candidate.callv(method, args)
	if (result is bool and not result) or (result is int and result <= 0):
		_message = "Действие недоступно; вещи и материалы сохранены."
		_render_panel()
		return
	_message = "Сохранено."
	_commit(candidate)

func _clear_battle() -> void:
	if battle_view != null:
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	if battle != null: battle.close()
	battle = null

func _render() -> void:
	if run != null and run.phase == D4RunState.BATTLE and _storage_error.is_empty():
		if _panel != null:
			remove_child(_panel)
			_panel.queue_free()
			_panel = null
		battle = D4BattleSession.new()
		if not battle.configure(run):
			_storage_error = "Не удалось собрать бой из сохранённой экипировки."
			_clear_battle()
			_render_panel()
			return
		battle_view = D4BattleView.new()
		battle_view.supplied_session = battle
		battle_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(battle_view)
		return
	_render_panel()

func _render_panel() -> void:
	if _panel != null:
		remove_child(_panel)
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a27")
	for side: String in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 28.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "intoDeDung / Забег"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "RunScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
	if not _storage_error.is_empty():
		_text("Не удалось сохранить или загрузить забег.\n" + _storage_error)
		if _pending != null: _button("Повторить запись", "retry", func() -> void: _commit(_pending))
		_button("К отдельным боям", "menu", _menu)
		return
	_text("Склад и рюкзаки пассивны. Бонусы дают только надетые вещи.\nПри гибели теряется случайная половина неотправленных вещей (округление вверх).")
	_text("Материалы: %d · Забег: %d · Сохранение автоматическое" % [run.materials, run.run_number])
	match run.phase:
		D4RunState.HUB: _hub()
		D4RunState.LOOT: _loot()
		D4RunState.COURIER: _courier()
		D4RunState.RESULT: _result()
	if not _message.is_empty(): _text(_message)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var menu := Button.new()
	menu.text = "К отдельным боям"
	menu.pressed.connect(_menu)
	footer.add_child(menu)
	var notice := Label.new()
	notice.text = "  Загрузка во время боя возвращает к началу этого боя."
	footer.add_child(notice)

func _hub() -> void:
	_text("ПОДГОТОВКА · 2 боя → комната отправки между ними → возвращение", 21)
	_text("В хабе отряд восстанавливает HP. Броня сохраняет износ; 1 материал ремонтирует 1 единицу.")
	var row := HBoxContainer.new()
	_body.add_child(row)
	for hero: Dictionary in run.heroes:
		var button := Button.new()
		button.text = "%s · HP %d/32%s" % [hero.name, hero.hp, "  ✓" if selected_hero == hero.id else ""]
		button.custom_minimum_size = Vector2(220, 42)
		button.name = "hero_%d" % hero.id
		button.pressed.connect(_select_hero.bind(hero.id))
		row.add_child(button)
	_text("НАДЕТО · " + String(run.heroes[selected_hero-1].name), 19)
	for slot: int in 3:
		var found: Dictionary = {}
		for record: Dictionary in run.items:
			if record.place == "equipped" and record.hero == selected_hero and record.slot == slot: found = record
		_text(["Оружие", "Корпус", "Пояс / аксессуар"][slot] + ": " + ("пусто" if found.is_empty() else _item_text(found)))
		if not found.is_empty():
			_button("На склад", "unequip_%d" % found.id, _act.bind(&"unequip", [found.id]))
			if D4Catalog.definition(found.kind).armor_max > found.armor:
				_button("Ремонтировать (до %d материалов)" % (D4Catalog.definition(found.kind).armor_max - int(found.armor)), "repair_%d" % found.id, _act.bind(&"repair", [found.id, 100]))
	_button("Отправиться · бой 1 из 2", "start", _act.bind(&"start_run", []))
	_text("СКЛАД МАГА · не даёт эффектов", 19)
	for record: Dictionary in run.items:
		if record.place != "warehouse": continue
		_button("Надеть: " + _item_text(record), "equip_%d" % record.id, _act.bind(&"equip", [record.id, selected_hero]))

func _loot() -> void:
	_text("ПОБЕДА · Добыча боя %d" % run.encounter, 22)
	for record: Dictionary in run.items:
		if record.place == "loot": _text(_item_text(record))
	_text("Выберите, кто заберёт добычу. В рюкзаке её свойства не действуют.")
	for hero: Dictionary in run.heroes:
		if hero.hp > 0: _button("Забрать в рюкзак: " + hero.name, "collect_%d" % hero.id, _act.bind(&"collect_loot", [hero.id]))

func _courier() -> void:
	_text("КОМНАТА ОТПРАВКИ · бой 1 пройден", 22)
	_text("Отправленные вещи сразу окажутся на складе и переживут поражение.\nМожно отправить и надетое, но во второй бой персонаж пойдёт без него.")
	_button("Продолжить · бой 2 из 2", "continue", _act.bind(&"continue_run", []))
	for hero: Dictionary in run.heroes:
		_text("%s · HP %d/32" % [hero.name, hero.hp], 19)
		for record: Dictionary in run.items:
			if record.hero == hero.id and record.place in ["equipped", "backpack"]:
				_button("Отправить: %s · %s" % [_item_text(record), "надето" if record.place == "equipped" else "рюкзак"], "send_%d" % record.id, _act.bind(&"send_item", [record.id]))

func _result() -> void:
	_text("МАРШРУТ ПРОЙДЕН" if run.last_result == "victory" else "ОТРЯД ПОГИБ", 24)
	_text("Все вещи возвращены на склад. Награда: 60 материалов." if run.last_result == "victory" else "Уцелевшие и ранее отправленные вещи находятся на складе. Потерянные:")
	for record: Dictionary in run.lost_items: _text("Утрачено: " + _item_text(record))
	_button("Вернуться к подготовке", "return", _act.bind(&"return_to_hub", []))

func _select_hero(id: int) -> void:
	selected_hero = id
	_render_panel()

func _item_text(record: Dictionary) -> String:
	var definition := D4Catalog.definition(record.kind)
	var detail := ""
	if definition.armor_max > 0: detail = " · броня %d/%d" % [record.armor, definition.armor_max]
	elif record.kind == "charm": detail = " · +2 силы"
	else: detail = " · +%d урона оружия" % (6 if record.kind == "keen_sword" else 4)
	if record.kind == "piercing_sword": detail += " · пробивание 50%"
	return "%s #%d%s" % [D4Catalog.title(record.kind), record.id, detail]

func _text(value: String, font_size: int = 17) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("dce7f2"))
	_body.add_child(label)

func _button(value: String, key: String, action: Callable) -> void:
	var button := Button.new()
	button.name = key
	button.text = value
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	_body.add_child(button)

func _menu() -> void:
	get_tree().change_scene_to_file("res://scenes/demo/core_combination_battle.tscn")
