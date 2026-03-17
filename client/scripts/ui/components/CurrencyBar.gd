extends PanelContainer

@onready var gold_label: Label = $Margin/Row/GoldLabel
@onready var amount_label: Label = $Margin/Row/AmountLabel

var _amount: float = 0.0

func _ready() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()
	_apply_amount()

func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func set_amount(amount: float) -> void:
	_amount = amount
	_apply_amount()

func _apply_translations() -> void:
	if gold_label != null:
		gold_label.text = CabinetStyle.text("ui.common.currency", "Currency")

func _apply_amount() -> void:
	if amount_label == null:
		push_warning("CurrencyBar: AmountLabel is missing")
		return
	amount_label.text = "%0.2f" % _amount
