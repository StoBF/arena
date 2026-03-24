# DEPRECATED — this router is NOT registered in main.py and is dead code.
#
# Reason: duplicates /raid/* endpoints already in routers/raid.py with a
# broken boss_id=user.get("boss_id", 0) default that always passes 0.
#
# All PvE raid functionality is served via:
#   GET  /raid/bosses
#   POST /raid/start        (body: RaidStartIn { boss_id, hero_ids })
#   POST /raid/battle/{id}
#   POST /raid/rewards/{id}
#
# Do not re-register this module.
