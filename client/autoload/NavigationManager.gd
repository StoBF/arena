## Centralized scene navigation controller.
## Autoloaded as "Nav" — use Nav.go("Auction"), Nav.go_main_menu(), etc.
## Provides:
##   - Checked scene transitions with error logging
##   - Fallback to MainMenu on failure
##   - Auth/hero pre-checks before guarded screens
##   - Deduplication (no double-load of same scene)
extends Node

const MAIN_MENU := "res://Main.tscn"

const SCENES := {
	"Main":             "res://Main.tscn",
	"PlayerHub":        "res://scenes/ui/PlayerHub.tscn",
	"HeroCreation":     "res://scenes/ui/HeroCreation.tscn",
	"Storage":          "res://scenes/ui/Storage.tscn",
	"Auction":          "res://scenes/ui/Auction.tscn",
	"BattleRoom":       "res://scenes/ui/BattleRoom.tscn",
	"Settings":         "res://scenes/ui/Settings.tscn",
}

const VIEW_ROUTES := {
	"MainMenu": "PlayerHub",
	"Login": "PlayerHub",
	"Register": "PlayerHub",
	"GenerateHero": "HeroCreation",
	"Inventory": "Storage",
	"HeroList": "Storage",
	"HeroMenu": "Storage",
	"HeroEquipment": "Storage",
	"Battle": "BattleRoom",
	"BattleRoom": "BattleRoom",
	"Auction": "Auction",
	"Settings": "Settings",
	"PlayerHub": "PlayerHub",
	"HeroCreation": "HeroCreation",
	"Storage": "Storage",
}

# Scenes that require an authenticated user
const AUTH_REQUIRED := [
	"PlayerHub", "HeroCreation", "Storage", "Auction", "BattleRoom", "Settings",
	"MainMenu", "GenerateHero", "Inventory", "Battle", "HeroList", "HeroMenu", "HeroEquipment",
]

# Scenes that require an active (selected) hero
const HERO_REQUIRED := [
	"Battle", "BattleRoom",
]

# Track current scene to prevent duplicate loads
var _current_scene_path: String = ""

## Navigate to a scene by short name (see SCENES dict).
## Returns true if transition initiated, false on failure.
func go(scene_name: String) -> bool:
	if VIEW_ROUTES.has(scene_name):
		return go_view(str(VIEW_ROUTES[scene_name]))

	if not SCENES.has(scene_name):
		push_error("[Nav] Unknown scene name: '%s'" % scene_name)
		print("[Nav] ERROR unknown scene: %s" % scene_name)
		return false

	var path: String = SCENES[scene_name]
	return go_path(path, scene_name)

func go_view(view_name: String) -> bool:
	if VIEW_ROUTES.has(view_name):
		view_name = str(VIEW_ROUTES[view_name])
	if SCENES.has(view_name) == false and view_name != "PlayerHub" and view_name != "HeroCreation" and view_name != "Storage" and view_name != "Auction" and view_name != "BattleRoom" and view_name != "Settings":
		push_error("[Nav] Unknown view name: '%s'" % view_name)
		return false

	if has_node("/root/SceneManager"):
		match view_name:
			"PlayerHub":
				SceneManager.open_playerhub()
			"HeroCreation":
				SceneManager.open_hero_creation()
			"Storage":
				SceneManager.open_inventory()
			"Auction":
				SceneManager.open_auction()
			"BattleRoom":
				SceneManager.open_battle_room()
			"Settings":
				SceneManager.open_settings()
			_:
				SceneManager.open_auth()
		return true

	if _current_scene_path != MAIN_MENU:
		if _do_change(MAIN_MENU, "Main") == false:
			return false
		call_deferred("_open_view_on_main", view_name)
		return true

	_open_view_on_main(view_name)
	return true

## Navigate to a scene by full resource path.
func go_path(path: String, label: String = "") -> bool:
	var tag = label if label else path

	# Deduplication
	if path == _current_scene_path:
		print("[Nav] Already on scene '%s', skipping" % tag)
		return true

	# Auth guard
	if label in AUTH_REQUIRED:
		if AppState.access_token.is_empty():
			print("[Nav] AUTH REQUIRED for '%s' but no token — opening PlayerHub" % tag)
			UIUtils.show_error("Please log in first")
			return go_view("PlayerHub")

	# Hero guard
	if label in HERO_REQUIRED:
		if AppState.current_hero_id <= 0:
			print("[Nav] HERO REQUIRED for '%s' but no hero selected — showing error" % tag)
			UIUtils.show_error("Select a hero first")
			return false

	# Validate file exists
	if not ResourceLoader.exists(path):
		push_error("[Nav] Scene file not found: %s" % path)
		print("[Nav] ERROR scene not found: '%s' — falling back to Main" % path)
		UIUtils.show_error("Scene '%s' not found" % tag)
		if path != MAIN_MENU:
			return _do_change(MAIN_MENU, "Main")
		return false

	return _do_change(path, tag)

## Go straight to MainMenu (dashboard).
func go_main_menu() -> bool:
	return go_view("PlayerHub")

func _open_view_on_main(view_name: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.has_method("open_view"):
		scene.call("open_view", view_name)

## Internal: perform the actual scene change with error checking.
func _do_change(path: String, tag: String) -> bool:
	var prev_scene = _current_scene_path if not _current_scene_path.is_empty() else "(none)"
	print("[Nav] Scene change: '%s' → '%s' (%s)" % [prev_scene, tag, path])
	var err = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[Nav] change_scene_to_file failed: err=%d path=%s" % [err, path])
		print("[Nav] ERROR change_scene_to_file returned %d for '%s'" % [err, path])
		if path != MAIN_MENU:
			print("[Nav] Falling back to MainMenu")
			get_tree().change_scene_to_file(MAIN_MENU)
		return false
	_current_scene_path = path
	print("[Nav] Scene change OK → '%s'" % tag)
	return true
