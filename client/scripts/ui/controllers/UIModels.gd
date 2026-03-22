extends RefCounted
class_name UIModels

# ─── Legacy helpers ───────────────────────────────────────────────

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


# ─── Hero v2 parsers ─────────────────────────────────────────────

## Core stats from the backend stats object.
static func hero_stats(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {
			"stamina": 0, "strength": 0, "willpower": 0, "reflex": 0,
			"resilience": 0, "focus": 0, "adaptability": 0, "luck": 0,
		}
	var d: Dictionary = data as Dictionary
	return {
		"stamina":      int(d.get("stamina", 0)),
		"strength":     int(d.get("strength", 0)),
		"willpower":    int(d.get("willpower", 0)),
		"reflex":       int(d.get("reflex", 0)),
		"resilience":   int(d.get("resilience", 0)),
		"focus":        int(d.get("focus", 0)),
		"adaptability": int(d.get("adaptability", 0)),
		"luck":         int(d.get("luck", 0)),
	}


## Derived stats from backend derived_stats object.
static func derived_stats(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {}
	var d: Dictionary = data as Dictionary
	return {
		"max_hp":              int(d.get("max_hp", 0)),
		"initiative":          int(d.get("initiative", 0)),
		"accuracy":            int(d.get("accuracy", 0)),
		"evasion":             int(d.get("evasion", 0)),
		"critical_chance":     snapped(float(d.get("critical_chance", 0.0)), 0.01),
		"critical_resistance": snapped(float(d.get("critical_resistance", 0.0)), 0.01),
		"armor_efficiency":    snapped(float(d.get("armor_efficiency", 0.0)), 0.01),
		"recovery_speed":      snapped(float(d.get("recovery_speed", 0.0)), 0.01),
		"trauma_resistance":   snapped(float(d.get("trauma_resistance", 0.0)), 0.01),
	}


## Parse a single tag from backend tag object.
static func hero_tag(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {}
	var d: Dictionary = data as Dictionary
	return {
		"tag_code":  str(d.get("tag_code", "")),
		"tag_group": str(d.get("tag_group", "")),
		"tag_value": d.get("tag_value", null),
	}


## Parse the catalog block inside a skill.
static func skill_catalog(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {}
	var d: Dictionary = data as Dictionary
	return {
		"skill_code":        str(d.get("skill_code", "")),
		"display_name":      str(d.get("display_name", "")),
		"skill_family":      str(d.get("skill_family", "")),
		"description_short": str(d.get("description_short", "")),
		"description_full":  str(d.get("description_full", "")),
		"target_type":       str(d.get("target_type", "")),
		"target_team":       str(d.get("target_team", "")),
		"cast_type":         str(d.get("cast_type", "")),
		"stamina_cost_base": int(d.get("stamina_cost_base", 0)),
		"cooldown_base":     float(d.get("cooldown_base", 0.0)),
		"duration_base":     float(d.get("duration_base", 0.0)),
		"power_base":        int(d.get("power_base", 0)),
		"radius_base":       float(d.get("radius_base", 0.0)),
		"requires_vision":   bool(d.get("requires_vision", true)),
		"is_redirectable":   bool(d.get("is_redirectable", false)),
		"is_interruptible":  bool(d.get("is_interruptible", true)),
		"is_stealable":      bool(d.get("is_stealable", false)),
		"is_upgradable":     bool(d.get("is_upgradable", true)),
		"has_kill_trigger":   bool(d.get("has_kill_trigger", false)),
		"control_tier":      d.get("control_tier", null),
	}


## Parse a single skill effect.
static func skill_effect(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {}
	var d: Dictionary = data as Dictionary
	return {
		"effect_type":   str(d.get("effect_type", "")),
		"effect_target": str(d.get("effect_target", "")),
		"effect_value":  float(d.get("effect_value", 0.0)),
	}


## Parse a full skill detail from backend SkillDetailOut.
static func skill_detail(data: Variant) -> Dictionary:
	if data == null or not (data is Dictionary):
		return {}
	var d: Dictionary = data as Dictionary
	var catalog_data: Dictionary = skill_catalog(d.get("catalog", null))
	var effects_raw: Variant = d.get("effects", [])
	var effects_list: Array[Dictionary] = []
	if effects_raw is Array:
		for eff_variant: Variant in (effects_raw as Array):
			var eff: Dictionary = skill_effect(eff_variant)
			if not eff.is_empty():
				effects_list.append(eff)
	return {
		"id":                    int(d.get("id", 0)),
		"skill_code":            str(d.get("skill_code", "")),
		"slot_index":            int(d.get("slot_index", 0)),
		"is_signature":          bool(d.get("is_signature", false)),
		"source_type":           str(d.get("source_type", "GENERATION")),
		"generation_level":      int(d.get("generation_level", 1)),
		"power_value":           int(d.get("power_value", 0)),
		"duration_value":        float(d.get("duration_value", 0.0)),
		"cooldown_value":        float(d.get("cooldown_value", 0.0)),
		"stamina_cost_value":    int(d.get("stamina_cost_value", 0)),
		"radius_value":          float(d.get("radius_value", 0.0)),
		"upgrade_count":         int(d.get("upgrade_count", 0)),
		"catalog":               catalog_data,
		"effects":               effects_list,
		# Convenience aliases from catalog so UI can read them directly
		"display_name":          catalog_data.get("display_name", str(d.get("skill_code", ""))),
		"skill_family":          catalog_data.get("skill_family", ""),
		"description_short":     catalog_data.get("description_short", ""),
		"cast_type":             catalog_data.get("cast_type", ""),
		"target_type":           catalog_data.get("target_type", ""),
		"target_team":           catalog_data.get("target_team", ""),
	}


## Parse a full hero from backend HeroRead payload.
## Normalises all nested objects into typed dictionaries.
static func hero_full(data: Dictionary) -> Dictionary:
	# Stats
	var stats: Dictionary = hero_stats(data.get("stats", null))
	var derived: Dictionary = derived_stats(data.get("derived_stats", null))

	# Tags
	var tags_raw: Variant = data.get("tags", [])
	var tags: Array[Dictionary] = []
	if tags_raw is Array:
		for t_variant: Variant in (tags_raw as Array):
			var t: Dictionary = hero_tag(t_variant)
			if not t.is_empty():
				tags.append(t)

	# Skills
	var skills_raw: Variant = data.get("skills", [])
	var skills: Array[Dictionary] = []
	if skills_raw is Array:
		for s_variant: Variant in (skills_raw as Array):
			var s: Dictionary = skill_detail(s_variant)
			if not s.is_empty():
				skills.append(s)

	# Sort skills by slot_index
	skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot_index", 0)) < int(b.get("slot_index", 0))
	)

	return {
		# Identity
		"id":                     int(data.get("id", 0)),
		"name":                   str(data.get("name", "")),
		"hero_generation_level":  int(data.get("hero_generation_level", 1)),
		"generation_version":     int(data.get("generation_version", 2)),
		# Roles
		"primary_role":           str(data.get("primary_role", "")),
		"secondary_role":         str(data.get("secondary_role", "")),
		# Coefficients (only if backend sends them)
		"hero_coherence":         float(data.get("hero_coherence", 1.0)),
		"stability":              float(data.get("stability", 1.0)),
		"control_susceptibility": float(data.get("control_susceptibility", 1.0)),
		"transfer_conductivity":  float(data.get("transfer_conductivity", 1.0)),
		"execution_resonance":    float(data.get("execution_resonance", 1.0)),
		"affinity_bias":          float(data.get("affinity_bias", 0.0)),
		# HP
		"current_hp":             int(data.get("current_hp", 100)),
		"condition":              str(data.get("condition", "healthy")),
		"resurrection_count":     int(data.get("resurrection_count", 0)),
		"is_dead":                bool(data.get("is_dead", false)),
		"is_permadead":           bool(data.get("is_permadead", false)),
		# Combat
		"total_kills":            int(data.get("total_kills", 0)),
		"total_deaths":           int(data.get("total_deaths", 0)),
		"total_absorbed":         int(data.get("total_absorbed", 0)),
		# Status
		"locale":                 str(data.get("locale", "en")),
		"is_on_auction":          bool(data.get("is_on_auction", false)),
		# Nested
		"stats":                  stats,
		"derived_stats":          derived,
		"tags":                   tags,
		"skills":                 skills,
		# Pass-through (body_parts, titles, history stay as raw arrays)
		"body_parts":             data.get("body_parts", []),
		"titles":                 data.get("titles", []),
		"history":                data.get("history", []),
	}


## Build a compact summary string for skill families, e.g. "3 Combat, 1 Buff".
static func skill_family_summary(skills: Array) -> String:
	var counts: Dictionary = {}
	for sk: Variant in skills:
		if sk is Dictionary:
			var family: String = str((sk as Dictionary).get("skill_family", ""))
			if family.is_empty():
				family = "Unknown"
			counts[family] = int(counts.get(family, 0)) + 1
	var parts: PackedStringArray = []
	for family_key: Variant in counts.keys():
		parts.append("%d %s" % [int(counts[family_key]), str(family_key).capitalize()])
	if parts.is_empty():
		return "No skills"
	return ", ".join(parts)


## Extract the first N tags as display strings.
static func top_tags(tags: Array, max_count: int = 4) -> PackedStringArray:
	var result: PackedStringArray = []
	var count: int = 0
	for t_variant: Variant in tags:
		if count >= max_count:
			break
		if t_variant is Dictionary:
			var code: String = str((t_variant as Dictionary).get("tag_code", ""))
			if not code.is_empty():
				result.append(code.capitalize().replace("_", " "))
				count += 1
	return result
