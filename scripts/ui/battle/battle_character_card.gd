class_name BattleCharacterCard
extends PanelContainer

signal close_requested

@onready var portrait_rect: TextureRect = %Portrait
@onready var name_label: Label = %Name
@onready var class_label_node: Label = %ClassFaction
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_value: Label = %HpValue
@onready var armor_bar: ProgressBar = %ArmorBar
@onready var armor_value: Label = %ArmorValue
@onready var balance_bar: ProgressBar = %BalanceBar
@onready var balance_value: Label = %BalanceValue
@onready var actions_label: Label = %Actions
@onready var attributes_label: Label = %Attributes
@onready var status_label: RichTextLabel = %Statuses
@onready var scroll_container: ScrollContainer = $Layout/Scroll
@onready var details_button: Button = %DetailsButton
@onready var details_label: Label = %Details
@onready var close_button: Button = %CloseButton

var _displayed_id: int = -1
var _details_expanded: bool = false


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	details_button.pressed.connect(_on_details_pressed)
	visible = false


func show_data(data: Dictionary) -> void:
	if data.is_empty():
		visible = false
		return
	var unit_id: int = int(data.get("id", -1))
	if unit_id != _displayed_id:
		_details_expanded = false
		_displayed_id = unit_id
		# Новый боец должен открываться с начала списка, чтобы не скрыть основные показатели.
		scroll_container.scroll_vertical = 0
	_apply_details_visibility()
	name_label.text = str(data.get("name", ""))
	class_label_node.text = "%s · %s" % [str(data.get("class_label", "")), str(data.get("faction_label", ""))]
	portrait_rect.texture = data.get("portrait") as Texture2D
	_set_bar(hp_bar, hp_value, float(data.get("hp_ratio", 0.0)), str(data.get("hp_text", "")))
	_set_bar(armor_bar, armor_value, float(data.get("armor_ratio", 0.0)), str(data.get("armor_text", "")))
	_set_bar(balance_bar, balance_value, float(data.get("balance_ratio", 0.0)), str(data.get("balance_text", "")))
	actions_label.text = str(data.get("actions_text", ""))
	attributes_label.text = str(data.get("attributes_text", ""))
	var status_bbcode := String(data.get("status_bbcode", ""))
	if status_bbcode.is_empty():
		status_bbcode = BattleStatusPresentation.escape_bbcode(String(data.get("status_text", "")))
	status_label.text = status_bbcode
	details_label.text = str(data.get("details_text", ""))
	visible = true


func _set_bar(bar: ProgressBar, value_label: Label, ratio: float, value_text: String) -> void:
	bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	value_label.text = value_text


func _apply_details_visibility() -> void:
	details_label.visible = _details_expanded
	details_button.text = "Снаряжение и свойства  ▾" if _details_expanded else "Снаряжение и свойства  ▸"


func _on_close_pressed() -> void:
	visible = false
	close_requested.emit()


func _on_details_pressed() -> void:
	_details_expanded = not _details_expanded
	_apply_details_visibility()
