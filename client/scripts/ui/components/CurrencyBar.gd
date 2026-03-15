extends PanelContainer

@onready var amount_label: Label = $Margin/Row/AmountLabel

func set_amount(amount: float) -> void:
	amount_label.text = "%0.2f" % amount
