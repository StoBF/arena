## Shared datetime parsing and formatting utility.
## Use: var normalized = DateTimeUtils.normalize_datetime(raw_string)
class_name DateTimeUtils
extends RefCounted


## Normalize a datetime string for use with Time.get_unix_time_from_datetime_string().
## Handles ISO 8601 with/without T separator, Z suffix, fractional seconds, timezone offsets.
static func normalize_datetime(value: String) -> String:
	var text: String = value.strip_edges()
	if text.is_empty():
		return text

	# Ensure T separator
	if text.find(" ") != -1 and text.find("T") == -1:
		text = text.replace(" ", "T")

	# Convert Z to +00:00
	if text.ends_with("Z"):
		text = text.substr(0, text.length() - 1) + "+00:00"

	# Find timezone offset position (must be after index 10 to not match date dashes)
	var plus_idx: int = text.rfind("+")
	var minus_idx: int = text.rfind("-")
	var tz_idx: int = maxi(plus_idx, minus_idx)
	if tz_idx <= 10:
		tz_idx = -1

	var main_part: String = text
	var tz_part: String = ""
	if tz_idx != -1:
		main_part = text.substr(0, tz_idx)
		tz_part = text.substr(tz_idx)

	# Strip fractional seconds
	var dot_idx: int = main_part.find(".")
	if dot_idx != -1:
		main_part = main_part.substr(0, dot_idx)

	# Normalize timezone format to HH:MM
	if tz_part.length() == 5 and (tz_part.begins_with("+") or tz_part.begins_with("-")):
		tz_part = tz_part.substr(0, 3) + ":" + tz_part.substr(3, 2)

	if tz_part.is_empty() == false and tz_part.length() > 6:
		tz_part = tz_part.substr(0, 6)

	return main_part + tz_part


## Format seconds into HH:MM:SS or MM:SS countdown string.
static func format_countdown(seconds_left: int) -> String:
	if seconds_left <= 0:
		return "00:00"
	var hours: int = int(seconds_left / 3600)
	var minutes: int = int((seconds_left % 3600) / 60)
	var seconds: int = int(seconds_left % 60)
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]


## Format countdown with urgency prefix indicators.
static func format_countdown_urgent(seconds_left: int) -> String:
	var base: String = format_countdown(seconds_left)
	if seconds_left <= 10:
		return "‼ %s" % base
	if seconds_left <= 60:
		return "⚠ %s" % base
	return base


## Format a price value with 2 decimal places.
static func format_price(value: float) -> String:
	return "%.2f" % value
