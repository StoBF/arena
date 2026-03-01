extends Window
class_name GenerateDialogPanel

# UI Elements
@onready var generation_field = $GenerationField
@onready var currency_field = $CurrencyField
@onready var generate_button = $GenerateHeroButton

signal generate_requested(generation: int, currency: int)

func _ready():
	generate_button.pressed.connect(Callable(self, "_on_generate_button_pressed"))

func _on_generate_button_pressed():
	var gen = int(generation_field.text)
	var curr = int(currency_field.text)
	emit_signal("generate_requested", gen, curr)
	hide() 
