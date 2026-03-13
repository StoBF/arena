extends Node
class_name UIModuleRouter

var _content_host: Control = null
var _loading_mask: Control = null
var _loader: UILazySceneLoader = UILazySceneLoader.new()
var _routes: Dictionary = {}
var _current_module: Control = null

func configure(content_host: Control, loading_mask: Control) -> void:
	_content_host = content_host
	_loading_mask = loading_mask

func register_default_routes() -> void:
	_routes = {
		"account": "res://scenes/ui/modules/account/AccountModule.tscn",
		"heroes": "res://scenes/ui/modules/heroes/HeroListModule.tscn",
		"hero_details": "res://scenes/ui/modules/hero_details/HeroDetailsModule.tscn",
		"inventory": "res://scenes/ui/modules/inventory/InventoryModule.tscn",
		"auction": "res://scenes/ui/modules/auction/AuctionModule.tscn",
		"workshop": "res://scenes/ui/modules/workshop/WorkshopModule.tscn",
		"raid": "res://scenes/ui/modules/raid/RaidModule.tscn",
		"chat": "res://scenes/ui/modules/chat/ChatModule.tscn",
	}

func register_route(module_key: String, scene_path: String) -> void:
	_routes[module_key] = scene_path

func open_module(module_key: String) -> void:
	if _content_host == null:
		return
	if _routes.has(module_key) == false:
		return
	if _loading_mask != null:
		_loading_mask.visible = true
	if _current_module != null and _current_module.is_inside_tree():
		_current_module.queue_free()
		_current_module = null
	var next_module: Control = _loader.instantiate(str(_routes[module_key]))
	if next_module != null:
		_content_host.add_child(next_module)
		_current_module = next_module
	if _loading_mask != null:
		_loading_mask.visible = false
