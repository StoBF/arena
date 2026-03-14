extends Control

@onready var status_label: Label = $VBox/Status

func _ready() -> void:
	var response: Dictionary = await ApiClient.get_account()
	status_label.text = "Account loaded" if bool(response.get("ok", false)) else "Account unavailable"
