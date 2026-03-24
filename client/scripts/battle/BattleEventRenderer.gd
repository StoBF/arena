extends Node
## BattleEventRenderer.gd
## Translates server combat events into 3D visual feedback and HUD messages.
## Attach as child of LiveBattleDirector.

@onready var hud: Node = get_parent().find_child("SpectatorHUD")

const EVENT_COLORS := {
	"hero_dead":        Color(0.9, 0.1, 0.1),
	"hero_unconscious": Color(0.9, 0.6, 0.1),
	"kill_trigger":     Color(1.0, 0.9, 0.0),
	"absorb_trigger":   Color(0.5, 0.0, 1.0),
	"cast_interrupted": Color(0.2, 0.8, 1.0),
	"cast_redirected":  Color(0.8, 0.4, 1.0),
	"skill_hit":        Color(1.0, 1.0, 1.0),
	"damage_applied":   Color(1.0, 0.4, 0.2),
	"control_applied":  Color(0.3, 1.0, 0.5),
}

const EVENT_LABELS := {
	"hero_dead":        "[KILL]",
	"hero_unconscious": "[KO]",
	"kill_trigger":     "[TRIGGER]",
	"absorb_trigger":   "[ABSORB]",
	"cast_interrupted": "[INTERRUPT]",
	"cast_redirected":  "[REDIRECT]",
	"skill_hit":        "[HIT]",
	"damage_applied":   "[DMG]",
	"control_applied":  "[CC]",
}

func play_event(ev: Dictionary) -> void:
	var etype: String = ev.get("type", "")
	if hud == null:
		return

	var prefix: String = EVENT_LABELS.get(etype, "[EVENT]")
	var color:  Color  = EVENT_COLORS.get(etype, Color.WHITE)
	var payload: Dictionary = ev.get("payload", {})

	var msg: String = prefix

	match etype:
		"hero_dead":
			var vid: int = ev.get("target_id", 0)
			var kid: int = ev.get("source_id", 0)
			msg = "[KILL] Hero #%d → Hero #%d" % [kid, vid]
		"hero_unconscious":
			var tid: int = ev.get("target_id", 0)
			msg = "[KO] Hero #%d is unconscious (HP %.0f%%)" % [
				tid, payload.get("hp_pct", 0.0) * 100]
		"kill_trigger":
			var at: String = payload.get("absorb_type", "?")
			if at == "stat_shard":
				msg = "[TRIGGER] Stat absorbed: %s +%.2f" % [
					payload.get("stat", "?"), payload.get("boost", 0.0)]
			else:
				msg = "[TRIGGER] Cooldown reset!"
		"absorb_trigger":
			msg = "[ABSORB] Hero #%d absorbed from #%d" % [
				ev.get("source_id", 0), ev.get("target_id", 0)]
		"cast_interrupted":
			msg = "[INTERRUPT] %s interrupted!" % payload.get("skill", "Skill")
		"cast_redirected":
			msg = "[REDIRECT] %s → new target #%d" % [
				payload.get("skill", "Skill"), ev.get("target_id", 0)]
		"skill_hit":
			msg = "[HIT] %s (%s)" % [payload.get("skill", "?"), payload.get("family", "?")]
		"control_applied":
			msg = "[CC] %s for %.1fs on #%d" % [
				payload.get("control", "?"),
				payload.get("duration", 0.0),
				ev.get("target_id", 0)]

	if hud.has_method("push_event_message"):
		hud.push_event_message(msg, color)
