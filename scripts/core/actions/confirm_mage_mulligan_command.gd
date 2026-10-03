class_name ConfirmMageMulliganCommand
extends MageDeckChangeCommand

func _init(selected: Array[int] = [], rev: int = 0) -> void:
	super(&"mulligan",selected,rev)

func copy_for_queue() -> Command: return ConfirmMageMulliganCommand.new(ids,revision)
