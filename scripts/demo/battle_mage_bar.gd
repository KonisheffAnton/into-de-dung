extends HBoxContainer
class_name BattleMageBar

signal page_changed(page: int)

const PAGE_SIZE: int = 8

var _buttons: Array[Button] = []
var _all_buttons: Array[Button] = []
var _page: int = 0
var _paging_enabled: bool = true
var _button_row: HBoxContainer
var _previous_button: Button
var _page_label: Label
var _next_button: Button

func _ready() -> void:
	_build()
	_refresh()

func configure(buttons: Array[Button]) -> void:
	_build()
	var prior_page := _page
	_buttons.clear()
	var seen: Dictionary = {}
	for button: Button in buttons:
		if not is_instance_valid(button) or seen.has(button): continue
		seen[button] = true
		_buttons.append(button)
		if not _all_buttons.has(button):
			_all_buttons.append(button)
			if button.get_parent() != _button_row:
				if button.get_parent() != null: button.get_parent().remove_child(button)
				_button_row.add_child(button)
		# Сохраняем порядок выбранного набора, не отсоединяя старые кнопки:
		# родитель панели должен владеть ими до освобождения самой панели.
		var target_index := _buttons.size() - 1
		if button.get_index() != target_index: _button_row.move_child(button, target_index)
	_page = mini(_page, maxi(0, get_page_count() - 1))
	_refresh()
	if _page != prior_page: page_changed.emit(_page)

func set_page(page: int) -> void:
	var next_page := clampi(page, 0, maxi(0, get_page_count() - 1))
	if next_page == _page: return
	_page = next_page
	_refresh()
	page_changed.emit(_page)

func get_page() -> int:
	return _page

func get_page_count() -> int:
	return maxi(1, ceili(float(_buttons.size()) / PAGE_SIZE))

func set_paging_enabled(enabled: bool) -> void:
	_paging_enabled = enabled
	_refresh_controls()

func _build() -> void:
	if _button_row != null: return
	_button_row = HBoxContainer.new()
	_button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_button_row)
	_previous_button = Button.new()
	_previous_button.text = "‹"
	_previous_button.custom_minimum_size = Vector2(34, 36)
	_previous_button.pressed.connect(_previous_page)
	add_child(_previous_button)
	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size.x = 48
	add_child(_page_label)
	_next_button = Button.new()
	_next_button.text = "›"
	_next_button.custom_minimum_size = Vector2(34, 36)
	_next_button.pressed.connect(_next_page)
	add_child(_next_button)

func _refresh() -> void:
	if _button_row == null: return
	# Не переустанавливаем visible у кнопки с тем же состоянием: это сохраняет незавершённое нажатие между кадрами.
	for button: Button in _all_buttons:
		if not is_instance_valid(button): continue
		var index := _buttons.find(button)
		var should_be_visible := index >= _page * PAGE_SIZE and index < (_page + 1) * PAGE_SIZE
		if button.visible != should_be_visible: button.visible = should_be_visible
	_refresh_controls()

func _refresh_controls() -> void:
	if _previous_button == null: return
	var has_pages := _buttons.size() > PAGE_SIZE
	_previous_button.visible = has_pages
	_page_label.visible = has_pages
	_next_button.visible = has_pages
	_page_label.text = "%d/%d" % [_page + 1, get_page_count()]
	_previous_button.disabled = not _paging_enabled or _page <= 0
	_next_button.disabled = not _paging_enabled or _page >= get_page_count() - 1

func _previous_page() -> void:
	if not _paging_enabled or _page <= 0: return
	set_page(_page - 1)

func _next_page() -> void:
	if not _paging_enabled or _page >= get_page_count() - 1: return
	set_page(_page + 1)
