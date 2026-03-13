extends Control

signal navigation_requested(module_key: String)

@onready var account_button: Button = $HBox/AccountButton
@onready var heroes_button: Button = $HBox/HeroesButton
@onready var inventory_button: Button = $HBox/InventoryButton
@onready var auction_button: Button = $HBox/AuctionButton
@onready var workshop_button: Button = $HBox/WorkshopButton
@onready var raid_button: Button = $HBox/RaidButton
@onready var chat_button: Button = $HBox/ChatButton

func _ready() -> void:
	account_button.pressed.connect(func(): navigation_requested.emit("account"))
	heroes_button.pressed.connect(func(): navigation_requested.emit("heroes"))
	inventory_button.pressed.connect(func(): navigation_requested.emit("inventory"))
	auction_button.pressed.connect(func(): navigation_requested.emit("auction"))
	workshop_button.pressed.connect(func(): navigation_requested.emit("workshop"))
	raid_button.pressed.connect(func(): navigation_requested.emit("raid"))
	chat_button.pressed.connect(func(): navigation_requested.emit("chat"))
