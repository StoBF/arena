extends RefCounted
class_name ConfigManager

# Constants
const CONFIG_PATH = "user://user_config.cfg"
const SECTION = "user"
const SECTION_AUTH = "auth"

# SECURITY: Save only username and token, NEVER passwords
# Tokens are temporary and can be revoked, passwords cannot
static func save_username(username: String) -> void:
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION, "username", username)
	var err = config.save(CONFIG_PATH)
	if err != OK:
		push_error("Failed to save username: %d" % err)

# Save authentication token (JWT)
static func save_token(token: String) -> void:
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION_AUTH, "token", token)
	var err = config.save(CONFIG_PATH)
	if err != OK:
		push_error("Failed to save token: %d" % err)

# Load saved username
static func load_username() -> String:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err != OK:
		return ""
	return config.get_value(SECTION, "username", "")

# Load saved token
static func load_token() -> String:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err != OK:
		return ""
	return config.get_value(SECTION_AUTH, "token", "")

# Check if we should remember user (has username saved)
static func should_remember_user() -> bool:
	return not load_username().is_empty()

# Clear all saved data (logout)
static func clear_all() -> void:
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION, "username", "")
	config.set_value(SECTION_AUTH, "token", "")
	config.save(CONFIG_PATH)

# DEPRECATED: Old methods for backward compatibility
# These should be removed after updating all call sites
static func save_credentials(username: String, password: String) -> void:
	push_warning("ConfigManager.save_credentials() is deprecated. Use save_username() instead.")
	save_username(username)
	# DO NOT save password - security risk

static func load_credentials() -> Dictionary:
	push_warning("ConfigManager.load_credentials() is deprecated. Use load_username() instead.")
	var username = load_username()
	if username.is_empty():
		return {}
	return {
		"username": username,
		"remember_me": true
	}

static func clear_credentials() -> void:
	push_warning("ConfigManager.clear_credentials() is deprecated. Use clear_all() instead.")
	clear_all()

static func has_saved_credentials() -> bool:
	return should_remember_user()
