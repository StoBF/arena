## Shared response parsing utility.
## Use: var items = ResponseParser.extract_array(response.get("data", {}))
class_name ResponseParser
extends RefCounted


## Extract an Array from a server response payload.
## Handles: raw Array, {result: []}, {items: []}, {data: []}, {heroes: []}, {lots: []}.
static func extract_array(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		for key in ["result", "items", "data", "heroes", "lots", "inventory"]:
			if data.has(key) and data[key] is Array:
				return (data[key] as Array).duplicate(true)
	return []


## Extract pagination metadata from server response.
static func extract_pagination(parsed: Variant) -> Dictionary:
	var defaults := {
		"page": 1,
		"page_size": 20,
		"total": 0,
		"has_next": false,
		"has_prev": false,
	}
	if parsed is Dictionary == false:
		return defaults
	var data := parsed as Dictionary
	# Check for nested pagination object
	for key in ["pagination", "meta", "paging"]:
		if data.has(key) and data[key] is Dictionary:
			var pg := data[key] as Dictionary
			return {
				"page": int(pg.get("page", pg.get("current_page", 1))),
				"page_size": int(pg.get("page_size", pg.get("per_page", 20))),
				"total": int(pg.get("total", pg.get("total_count", 0))),
				"has_next": bool(pg.get("has_next", pg.get("has_more", false))),
				"has_prev": bool(pg.get("has_prev", pg.get("has_previous", false))),
			}
	# Check for flat pagination fields
	if data.has("total") or data.has("page"):
		return {
			"page": int(data.get("page", data.get("current_page", 1))),
			"page_size": int(data.get("page_size", data.get("per_page", 20))),
			"total": int(data.get("total", data.get("total_count", 0))),
			"has_next": bool(data.get("has_next", data.get("has_more", false))),
			"has_prev": bool(data.get("has_prev", data.get("has_previous", false))),
		}
	return defaults
