extends Control
class_name AccountUI

const HERO_ENDPOINT: String = "/heroes/my"
const HERO_CARD_MIN_SIZE: Vector2 = Vector2(170, 240)
const HERO_AVATAR_SIZE: Vector2 = Vector2(128, 128)
const DETAILS_AVATAR_SIZE: Vector2 = Vector2(128, 128)
const HTTP_TIMEOUT_SECONDS: float = 10.0

@onready var hero_grid: GridContainer = $VBoxContainer/HeroScroll/HeroGrid
@onready var hero_details_dialog: AcceptDialog = $HeroDetailsDialog
@onready var details_avatar: TextureRect = $HeroDetailsDialog/VBoxContainer/Avatar
@onready var details_name: Label = $HeroDetailsDialog/VBoxContainer/Name
@onready var details_level: Label = $HeroDetailsDialog/VBoxContainer/Level
@onready var details_class: Label = $HeroDetailsDialog/VBoxContainer/Class
@onready var details_power: Label = $HeroDetailsDialog/VBoxContainer/Power

func _ready() -> void:
	fetch_heroes()

func fetch_heroes() -> void:
	_clear_hero_grid()
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(request)
	if not request.request_completed.is_connected(_on_fetch_heroes_completed):
		request.request_completed.connect(_on_fetch_heroes_completed.bind(request))

	var headers: PackedStringArray = PackedStringArray()
	if not AppState.access_token.is_empty():
		headers.append("Authorization: Bearer %s" % AppState.access_token)

	var config = ServerConfig.get_instance()
	var url: String = config.get_http_endpoint(HERO_ENDPOINT)
	var err: Error = request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		_show_message("Failed to start hero request")

func _on_fetch_heroes_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	if is_instance_valid(request):
		request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_show_message("Failed to fetch heroes")
		return

	if code != 200:
		_show_message("Unable to load heroes (HTTP %d)" % code)
		return

	var body_text: String = body.get_string_from_utf8()
	var parsed = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_ARRAY:
		_show_message("Invalid heroes response")
		return

	populate_heroes(parsed)

func populate_heroes(data: Array) -> void:
	_clear_hero_grid()
	if data.is_empty():
		_show_message("No heroes found")
		return

	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var hero_data: Dictionary = entry
		var hero_button: Button = Button.new()
		hero_button.flat = true
		hero_button.custom_minimum_size = HERO_CARD_MIN_SIZE

		var card_box: VBoxContainer = VBoxContainer.new()
		card_box.alignment = BoxContainer.ALIGNMENT_CENTER
		card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var avatar_rect: TextureRect = TextureRect.new()
		avatar_rect.custom_minimum_size = HERO_AVATAR_SIZE
		avatar_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_set_texture_from_source(avatar_rect, str(hero_data.get("avatar_url", "")))

		var name_label: Label = Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text = str(hero_data.get("name", "Unknown"))

		var level_label: Label = Label.new()
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_label.text = "Level %d" % int(hero_data.get("level", 0))

		card_box.add_child(avatar_rect)
		card_box.add_child(name_label)
		card_box.add_child(level_label)
		hero_button.add_child(card_box)

		var press_callable: Callable = _on_hero_pressed.bind(hero_data)
		if not hero_button.pressed.is_connected(press_callable):
			hero_button.pressed.connect(press_callable)

		hero_grid.add_child(hero_button)

func _on_hero_pressed(hero_data: Dictionary) -> void:
	show_hero_details(hero_data)

func show_hero_details(hero_data: Dictionary) -> void:
	details_name.text = "Name: %s" % str(hero_data.get("name", "-"))
	details_level.text = "Level: %d" % int(hero_data.get("level", 0))
	details_class.text = "Class: %s" % str(hero_data.get("class", "-"))
	details_power.text = "Power: %d" % int(hero_data.get("power", 0))
	details_avatar.custom_minimum_size = DETAILS_AVATAR_SIZE
	_set_texture_from_source(details_avatar, str(hero_data.get("avatar_url", "")))
	hero_details_dialog.popup_centered()

func _set_texture_from_source(target: TextureRect, source: String) -> void:
	if source.is_empty():
		target.texture = null
		return

	var loaded_res: Resource = load(source)
	if loaded_res is Texture2D:
		target.texture = loaded_res
		return

	if source.begins_with("http://") or source.begins_with("https://"):
		_load_remote_avatar(target, source)
		return

	target.texture = null

func _load_remote_avatar(target: TextureRect, url: String) -> void:
	var avatar_request: HTTPRequest = HTTPRequest.new()
	avatar_request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(avatar_request)
	if not avatar_request.request_completed.is_connected(_on_remote_avatar_completed):
		avatar_request.request_completed.connect(_on_remote_avatar_completed.bind(target, avatar_request))
	var err: Error = avatar_request.request(url)
	if err != OK:
		avatar_request.queue_free()

func _on_remote_avatar_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, target: TextureRect, avatar_request: HTTPRequest) -> void:
	if is_instance_valid(avatar_request):
		avatar_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return

	var image: Image = Image.new()
	var load_err: Error = image.load_png_from_buffer(body)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		return

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	target.texture = texture

func _clear_hero_grid() -> void:
	for child: Node in hero_grid.get_children():
		child.queue_free()

func _show_message(text: String) -> void:
	_clear_hero_grid()
	var message_label: Label = Label.new()
	message_label.text = text
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero_grid.add_child(message_label)
