extends ConfirmationDialog

signal action_confirmed

func _ready() -> void:
	confirmed.connect(_on_confirmed)

func _on_confirmed() -> void:
	action_confirmed.emit()
