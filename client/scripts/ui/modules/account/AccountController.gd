extends Control

@onready var status_label: Label = $VBox/Status

func _ready() -> void:
	if has_node("/root/ApiClient"):
		var response: Dictionary = await (get_node("/root/ApiClient") as UIApiClient).get_account()
		status_label.text = "Account loaded" if bool(response.get("ok", false)) else "Account unavailable"
