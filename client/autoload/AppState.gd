# Autoload AppState.gd
extends Node

# Authentication tokens
var access_token: String = ""
var refresh_token: String = ""

# User data
var user_id: int = -1
var current_hero_id: int = -1
var last_created_hero: Dictionary = {}

# Token refresh state (prevent infinite refresh loops)
var is_refreshing_token: bool = false
var token_refresh_attempted: bool = false
 
