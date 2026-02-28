## Centralized scene navigation controller.
## Autoloaded as "Nav" — use Nav.go("Auction"), Nav.go_main_menu(), etc.
## Provides:
##   - Checked scene transitions with error logging
##   - Fallback to MainMenu on failure
##   - Auth/hero pre-checks before guarded screens
##   - Deduplication (no double-load of same scene)
extends Node

const MAIN_MENU := "res://scenes/MainMenu.tscn"

# Map of short names → scene paths (single source of truth)
const SCENES := {
	"MainMenu":         "res://scenes/MainMenu.tscn",
	"Login":            "res://scenes/login_screen.tscn",
	"Register":         "res://scenes/Register.tscn",
	"GenerateHero":     "res://scenes/GenerateHeroScene.tscn",
	"Auction":          "res://scenes/Auction.tscn",
	"Inventory":        "res://scenes/Inventory.tscn",
	"Battle":           "res://scenes/BattlePrep.tscn",
	"BattleRoom":       "res://scenes/BattlePreparationRoom.tscn",
	"HeroList":         "res://scenes/HeroList.tscn",
	"HeroMenu":         "res://scenes/HeroMenu.tscn",
	"HeroEquipment":    "res://scenes/HeroEquipment.tscn",
	"Settings":         "res://scenes/LocaleMenu.tscn",
	"ChatBox":          "res://scenes/ChatBox.tscn",
}

# Scenes that require an authenticated user
const AUTH_REQUIRED := [
	"MainMenu", "GenerateHero", "Auction", "Inventory",
	"Battle", "BattleRoom", "HeroList", "HeroMenu",
	"HeroEquipment", "Settings",
]

# Scenes that require an active (selected) hero
const HERO_REQUIRED := [
	"Battle", "BattleRoom", "HeroEquipment",
]

# Track current scene to prevent duplicate loads
var _current_scene_path: String = ""

## Navigate to a scene by short name (see SCENES dict).
## Returns true if transition initiated, false on failure.
func go(scene_name: String) -> bool:
	if not SCENES.has(scene_name):
		push_error("[Nav] Unknown scene name: '%s'" % scene_name)
		print("[Nav] ERROR unknown scene: %s" % scene_name)
		return false

	var path: String = SCENES[scene_name]
	return go_path(path, scene_name)

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
			print("[Nav] AUTH REQUIRED for '%s' but no token — redirecting to Login" % tag)
			UIUtils.show_error("Please log in first")
			return _do_change("res://scenes/login_screen.tscn", "Login")

	# Hero guard
	if label in HERO_REQUIRED:
		if AppState.current_hero_id <= 0:
			print("[Nav] HERO REQUIRED for '%s' but no hero selected — showing error" % tag)
			UIUtils.show_error("Select a hero first")
			return false

	# Validate file exists
	if not ResourceLoader.exists(path):
		push_error("[Nav] Scene file not found: %s" % path)
		print("[Nav] ERROR scene not found: '%s' — falling back to MainMenu" % path)
		UIUtils.show_error("Scene '%s' not found" % tag)
		if path != MAIN_MENU:
			return _do_change(MAIN_MENU, "MainMenu")
		return false

	return _do_change(path, tag)

## Go straight to MainMenu (dashboard).
func go_main_menu() -> bool:
	return go("MainMenu")

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
