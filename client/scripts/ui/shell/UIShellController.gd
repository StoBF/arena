extends Control

@onready var top_bar: Control = $TopBar
@onready var content_host: Control = $ContentHost
@onready var overlay_host: Control = $OverlayHost
@onready var loading_mask: Control = $LoadingMask

var _router: UIModuleRouter = UIModuleRouter.new()

func _ready() -> void:
	_ensure_core_singletons()
	if top_bar.has_signal("navigation_requested"):
		top_bar.navigation_requested.connect(_on_navigation_requested)
	_router.configure(content_host, loading_mask)
	_router.register_default_routes()
	_router.open_module("heroes")

func _on_navigation_requested(module_key: String) -> void:
	_router.open_module(module_key)

func _ensure_core_singletons() -> void:
	var root: Node = get_tree().root
	if root.has_node("AppState") == false:
		var state := UIAppState.new()
		state.name = "AppState"
		root.add_child(state)
	if root.has_node("EventBus") == false:
		var bus := UIEventBus.new()
		bus.name = "EventBus"
		root.add_child(bus)
	if root.has_node("ApiClient") == false:
		var api := UIApiClient.new()
		api.name = "ApiClient"
		root.add_child(api)
