extends RefCounted
class_name UIModels

static func hero(data: Dictionary) -> Dictionary:
	return {
		"id": str(data.get("id", "")),
		"name": str(data.get("name", "")),
	}

static func is_empty_hero(data: Dictionary) -> bool:
	return str(data.get("id", "")).is_empty()

static func resource_map(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in data.keys():
		result[str(key)] = maxi(0, int(data[key]))
	return result

static func item(data: Dictionary) -> Dictionary:
	return {
		"id": str(data.get("id", "")),
		"name": str(data.get("name", "")),
		"quantity": maxi(0, int(data.get("quantity", 0))),
		"category": str(data.get("category", "")),
		"icon": str(data.get("icon", "")),
	}

static func recipe(data: Dictionary) -> Dictionary:
	var requirements := data.get("requirements", {}) as Dictionary
	return {
		"id": str(data.get("id", "")),
		"name": str(data.get("name", "Recipe")),
		"output_item": str(data.get("output_item", "")),
		"output_quantity": maxi(1, int(data.get("output_quantity", 1))),
		"requirements": resource_map(requirements),
	}

static func equipment(data: Dictionary) -> Dictionary:
	return {
		"shirt": item(data.get("shirt", {}) as Dictionary),
		"pants": item(data.get("pants", {}) as Dictionary),
		"shoes": item(data.get("shoes", {}) as Dictionary),
	}
