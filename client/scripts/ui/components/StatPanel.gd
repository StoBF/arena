extends VBoxContainer
class_name StatPanel

func set_stats(stats: Dictionary) -> void:
    $Strength.text = "Strength: %d" % stats.get("strength",0)
    $Speed.text = "Speed: %d" % stats.get("speed",0)
    $Agility.text = "Agility: %d" % stats.get("agility",0)
    $Endurance.text = "Endurance: %d" % stats.get("endurance",0)
    $Health.text = "Health: %d" % stats.get("health",0)
    $Defense.text = "Defense: %d" % stats.get("defense",0)
    $Luck.text = "Luck: %d" % stats.get("luck",0)
    $Training.text = "Training: %s" % stats.get("training","none")
    $View.text = "Field of View: %d" % stats.get("field_of_view",0)
