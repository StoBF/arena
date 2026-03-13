extends RefCounted
class_name UILazySceneLoader

var _cache: Dictionary = {}

func load_scene(scene_path: String) -> PackedScene:
	if _cache.has(scene_path):
		return _cache[scene_path] as PackedScene
	var loaded: Resource = ResourceLoader.load(scene_path)
	if loaded is PackedScene:
		_cache[scene_path] = loaded
		return loaded as PackedScene
	return null

func instantiate(scene_path: String) -> Control:
	var packed: PackedScene = load_scene(scene_path)
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	if instance is Control:
		return instance as Control
	instance.queue_free()
	return null

func clear_cache() -> void:
	_cache.clear()
