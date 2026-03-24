extends Node

## Thin centralized HTTP facade over Network autoload.
## Safe migration path: existing scripts can continue using Network directly,
## while new/updated services move to ApiClient incrementally.

const HERO_COLLECTION_PATH := "/heroes/"

func get_hero_collection_path() -> String:
        return HERO_COLLECTION_PATH

func login(email: String, password: String) -> Dictionary:
        var response: Dictionary = await request_post("/auth/login", {
                "login": email,
                "password": password,
        })
        if bool(response.get("ok", false)):
                var payload: Dictionary = _extract_dict(response.get("data", {}))
                var access: String = str(payload.get("access_token", ""))
                var refresh: String = str(payload.get("refresh_token", ""))
                if not access.is_empty():
                        AppState.set_access_token(access)
                if not refresh.is_empty():
                        AppState.refresh_token = refresh
        return response

func register(email: String, username: String, password: String) -> Dictionary:
        return await request_post("/auth/register", {
                "email": email,
                "username": username,
                "password": password,
        })

func get_user() -> Dictionary:
        return await request_get("/auth/me")

func get_heroes() -> Dictionary:
        return await request_get(get_hero_collection_path())

func create_hero(hero_name: String, _investment: int = 0) -> Dictionary:
        return await request_post("/heroes/generate", {
                "locale": _resolve_locale(),
        })

func get_auction_lots(filters: Dictionary = {}) -> Dictionary:
        var normalized: Dictionary = _normalize_auction_filters(filters)
        var query: String = _build_query_string(normalized)
        var path := "/auctions/lots"
        if query.is_empty() == false:
                path = "%s?%s" % [path, query]
        var response: Dictionary = await request_get(path)
        if bool(response.get("ok", false)):
                _sync_auction_to_appstate(response.get("data", {}), normalized)
        return response

func get_chat_messages(channel: String = "global", limit: int = 50, offset: int = 0) -> Dictionary:
        var query := {
                "channel": _legacy_chat_channel(channel),
                "limit": maxi(1, limit),
                "offset": maxi(0, offset),
        }
        var response_variant: Variant = await request_get("/chat/history?%s" % _build_query_string(query))
        if response_variant is Dictionary:
                var response: Dictionary = (response_variant as Dictionary)
                if bool(response.get("ok", false)):
                        _sync_chat_to_appstate(channel, response.get("data", {}))
                return response
        return {
                "ok": false,
                "code": 0,
                "result": HTTPRequest.RESULT_CANT_CONNECT,
                "headers": PackedStringArray(),
                "data": {},
                "message": "Unexpected chat response"
        }


func _legacy_chat_channel(channel: String) -> String:
        var normalized: String = channel.strip_edges().to_lower()
        if normalized == "global":
                return "general"
        return normalized

func get_server_status() -> Dictionary:
        return await request_get("/server/status")

func get_account() -> Dictionary:
        return await get_user()

func get_auctions() -> Dictionary:
        return await request_get("/auctions/")

func place_bid(lot_id: int, amount: int) -> Dictionary:
        return await request_post("/bids/", {
                "lot_id": lot_id,
                "amount": amount,
        })

func buyout(lot_id: int) -> Dictionary:
        return await request_post("/auctions/lots/%d/buyout" % lot_id, {})

# ---------------------------------------------------------------------------
# Healing (no dedicated server endpoint yet — uses hero status)
# ---------------------------------------------------------------------------

func start_healing(hero_id: int) -> Dictionary:
        return await request_post("/heroes/%d/heal" % hero_id)

# ---------------------------------------------------------------------------
# PvP / Arena
# ---------------------------------------------------------------------------

func get_leaderboard() -> Dictionary:
        return await request_get("/pvp/leaderboard")

func pvp_match(player1_id: int, player2_id: int) -> Dictionary:
        return await request_post("/pvp/match", {
                "player1_id": player1_id,
                "player2_id": player2_id,
        })

func team_battle(hero_ids: Array, enemy_ids: Array) -> Dictionary:
        return await request_post("/battle/team", {
                "hero_ids": hero_ids,
                "enemy_ids": enemy_ids,
        })

func queue_arena(mode: String, hero_ids: Array) -> Dictionary:
        # Arena queue is client-side concept; matchmaking finds an opponent then
        # calls pvp_match or team_battle. For now mock the queue step.
        return {
                "ok": true,
                "code": 200,
                "result": HTTPRequest.RESULT_SUCCESS,
                "headers": PackedStringArray(),
                "data": {"mode": mode, "hero_ids": hero_ids, "status": "queued"},
                "message": "Entered %s queue" % mode
        }

func submit_battle_queue(hero_id: int) -> Dictionary:
        if hero_id <= 0:
                return {
                        "ok": false,
                        "code": 400,
                        "result": HTTPRequest.RESULT_SUCCESS,
                        "headers": PackedStringArray(),
                        "data": {},
                        "message": "Invalid hero id"
                }
        return await request_post("/battle/queue/submit", {"hero_id": hero_id})

func get_battle_queue() -> Dictionary:
        return await request_get("/battle/queue")

# ---------------------------------------------------------------------------
# Boss Raids
# ---------------------------------------------------------------------------

func get_bosses() -> Dictionary:
        return await request_get("/raid/bosses")

func start_boss_raid(boss_id: int, hero_ids: Array) -> Dictionary:
        return await request_post("/raid/start", {
                "boss_id": boss_id,
                "hero_ids": hero_ids,
        })

func raid_battle(instance_id: int) -> Dictionary:
        return await request_post("/raid/battle/%d" % instance_id)

func raid_rewards(instance_id: int) -> Dictionary:
        return await request_post("/raid/rewards/%d" % instance_id)

# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------

func get_craft_recipes() -> Dictionary:
        return await request_get("/craft/recipes")

func get_craft_queue() -> Dictionary:
        return await request_get("/craft/queue")

func start_craft(recipe_id: int) -> Dictionary:
        return await request_post("/craft/start", {"recipe_id": recipe_id})

func finish_craft(queue_id: int) -> Dictionary:
        return await request_post("/craft/finish", {"queue_id": queue_id})


  # ---------------------------------------------------------------------------
  # Battle Room
  # ---------------------------------------------------------------------------

  func create_battle_room(hero_ids: Array) -> Dictionary:
        return await request_post("/battle/room/create", {"hero_ids": hero_ids})

  func join_battle_room(room_id: int, hero_ids: Array) -> Dictionary:
        return await request_post("/battle/room/%d/join" % room_id, {"hero_ids": hero_ids})

  func submit_battle_order(room_id: int, order: Dictionary) -> Dictionary:
        return await request_post("/battle/room/%d/order" % room_id, order)

  func set_battle_directive(room_id: int, directive: Dictionary) -> Dictionary:
        return await request_post("/battle/room/%d/directive" % room_id, directive)

  func battle_room_ready(room_id: int) -> Dictionary:
        return await request_post("/battle/room/%d/ready" % room_id)

  func get_battle_room(room_id: int) -> Dictionary:
        return await request_get("/battle/room/%d" % room_id)

  func get_battle_result(room_id: int) -> Dictionary:
        return await request_get("/battle/room/%d/result" % room_id)

  func cancel_battle_room(room_id: int) -> Dictionary:
        return await request_post("/battle/room/%d/cancel" % room_id)

  # ---------------------------------------------------------------------------
  # Resources and Armor
  # ---------------------------------------------------------------------------

  func get_my_resources() -> Dictionary:
        return await request_get("/resources/my")

  func get_resource_catalog() -> Dictionary:
        return await request_get("/resources/catalog")

  func get_armor_catalog(tier: int = 0, set_type: String = "") -> Dictionary:
        var params := ""
        if tier > 0: params += "?tier=%d" % tier
        if set_type != "": params += ("&" if params else "?") + "set_type=" + set_type
        return await request_get("/armor/catalog" + params)

  func get_armor_set_bonuses() -> Dictionary:
        return await request_get("/armor/sets")

  func get_my_armor() -> Dictionary:
        return await request_get("/armor/my")

  func equip_armor(inventory_id: int, hero_id: int) -> Dictionary:
        return await request_post("/armor/equip/%d" % inventory_id, {"hero_id": hero_id})

  func unequip_armor(inventory_id: int) -> Dictionary:
        return await request_post("/armor/unequip/%d" % inventory_id)

  func connect_chat() -> Dictionary:
        return {
                "ok": true,
                "code": 200,
                "result": HTTPRequest.RESULT_SUCCESS,
                "headers": PackedStringArray(),
                "data": {},
                "message": "Chat connection managed by scene websocket flow"
        }

func request_get(path: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
        return await request_json(path, HTTPClient.METHOD_GET, {}, headers)

func request_post(path: String, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
        return await request_json(path, HTTPClient.METHOD_POST, payload, headers)

func request_patch(path: String, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
        return await request_json(path, HTTPClient.METHOD_PATCH, payload, headers)

func request_delete(path: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
        return await request_json(path, HTTPClient.METHOD_DELETE, {}, headers)

func request_json(path: String, method: int, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
        if not has_node("/root/Network"):
                return {
                        "ok": false,
                        "code": 0,
                        "result": HTTPRequest.RESULT_CANT_CONNECT,
                        "headers": PackedStringArray(),
                        "data": {},
                        "message": "Network autoload is not available"
                }

        return await Network.request_json(path, method, payload, headers)

func _extract_dict(data: Variant) -> Dictionary:
        if data is Dictionary:
                return (data as Dictionary).duplicate(true)
        return {}

func _resolve_locale() -> String:
        if has_node("/root/LocalizationManager") and LocalizationManager.has_method("get_current_locale"):
                var locale: String = str(LocalizationManager.get_current_locale()).strip_edges().to_lower()
                if locale in ["en", "pl", "uk"]:
                        return locale
        return "en"

func _build_query_string(params: Dictionary) -> String:
        if params.is_empty():
                return ""
        var parts: PackedStringArray = []
        for key_variant in params.keys():
                var key: String = str(key_variant)
                var value: Variant = params[key_variant]
                if value == null:
                        continue
                parts.append("%s=%s" % [key.uri_encode(), str(value).uri_encode()])
        return "&".join(parts)

func _normalize_auction_filters(filters: Dictionary) -> Dictionary:
        var page: int = maxi(1, int(filters.get("page", 1)))
        var page_size: int = maxi(1, int(filters.get("page_size", filters.get("limit", 20))))
        var offset: int = maxi(0, int(filters.get("offset", (page - 1) * page_size)))
        return {
                "limit": page_size,
                "offset": offset
        }

func _sync_chat_to_appstate(channel: String, parsed: Variant) -> void:
        if has_node("/root/AppState") == false:
                return
        var lines: Array = _extract_chat_lines(parsed)
        if lines.is_empty():
                return
        AppState.set_chat_messages(channel, lines)

func _extract_chat_lines(parsed: Variant) -> Array:
        var items: Array = []
        if parsed is Array:
                items = (parsed as Array).duplicate(true)
        elif parsed is Dictionary:
                var data := parsed as Dictionary
                if data.has("result") and data["result"] is Array:
                        items = (data["result"] as Array).duplicate(true)
                elif data.has("items") and data["items"] is Array:
                        items = (data["items"] as Array).duplicate(true)
        var lines: Array = []
        for message_variant in items:
                if message_variant is Dictionary == false:
                        continue
                var message := message_variant as Dictionary
                var player: String = str(message.get("player", message.get("username", message.get("user", "Player %s" % str(message.get("sender_id", "?"))))))
                var text: String = str(message.get("message", message.get("text", "")))
                if text.is_empty():
                        continue
                lines.append("[%s] %s" % [player, text])
        return lines

func _sync_auction_to_appstate(parsed: Variant, fallback_filters: Dictionary) -> void:
        if has_node("/root/AppState") == false:
                return
        var items: Array = _extract_auction_items(parsed)
        var pagination: Dictionary = _extract_auction_pagination(parsed, fallback_filters, items.size())
        AppState.set_auction_data(items, pagination)

func _extract_auction_items(parsed: Variant) -> Array:
        if parsed is Array:
                return (parsed as Array).duplicate(true)
        if parsed is Dictionary:
                var data := parsed as Dictionary
                if data.has("result") and data["result"] is Array:
                        return (data["result"] as Array).duplicate(true)
                if data.has("items") and data["items"] is Array:
                        return (data["items"] as Array).duplicate(true)
        return []

func _extract_auction_pagination(parsed: Variant, filters: Dictionary, item_count: int) -> Dictionary:
        var page: int = maxi(1, int(filters.get("page", 1)))
        var page_size: int = maxi(1, int(filters.get("page_size", 20)))
        var total: int = item_count
        var has_next: bool = item_count >= page_size
        var has_prev: bool = page > 1
        if parsed is Dictionary:
                var data := parsed as Dictionary
                if data.has("limit") and data.has("offset"):
                        var limit: int = maxi(1, int(data.get("limit", page_size)))
                        var offset: int = maxi(0, int(data.get("offset", 0)))
                        page = int(offset / limit) + 1
                        page_size = limit
                if data.has("total"):
                        total = int(data.get("total", total))
                        has_next = page * page_size < total
                        has_prev = page > 1
                if data.has("has_next"):
                        has_next = bool(data.get("has_next", has_next))
                if data.has("has_prev"):
                        has_prev = bool(data.get("has_prev", has_prev))
        return {
                "page": page,
                "page_size": page_size,
                "total": total,
                "has_next": has_next,
                "has_prev": has_prev,
        }


  # ══════════════════════════════════════════════════════════════════════════════
  # CLAN SYSTEM
  # ══════════════════════════════════════════════════════════════════════════════

  func create_clan(data: Dictionary) -> Dictionary:
      return await _post("/clans", data)

  func search_clans(filters: Dictionary = {}) -> Array:
      var result = await _get("/clans", filters)
      if result is Array:
          return result
      return []

  func get_clan(clan_id: int) -> Dictionary:
      return await _get("/clans/%d" % clan_id)

  func update_clan(clan_id: int, data: Dictionary) -> Dictionary:
      return await _patch("/clans/%d" % clan_id, data)

  func disband_clan(clan_id: int) -> Dictionary:
      return await _delete("/clans/%d" % clan_id)

  # ── Emblem ────────────────────────────────────────────────────────────────────
  func delete_clan_emblem(clan_id: int) -> Dictionary:
      return await _delete("/clans/%d/emblem" % clan_id)

  # ── Members ───────────────────────────────────────────────────────────────────
  func get_clan_members(clan_id: int) -> Array:
      var result = await _get("/clans/%d/members" % clan_id)
      if result is Array:
          return result
      return []

  func kick_clan_member(clan_id: int, target_user_id: int) -> Dictionary:
      return await _delete("/clans/%d/members/%d" % [clan_id, target_user_id])

  func leave_clan(clan_id: int) -> Dictionary:
      return await _post("/clans/%d/members/leave" % clan_id, {})

  func set_member_role(clan_id: int, target_user_id: int, role: String) -> Dictionary:
      return await _patch("/clans/%d/members/%d/role" % [clan_id, target_user_id], {"role": role})

  func set_member_nickname(clan_id: int, target_user_id: int, nickname: String) -> Dictionary:
      return await _patch("/clans/%d/members/%d/nickname" % [clan_id, target_user_id], {"nickname": nickname})

  func set_member_permissions(clan_id: int, target_user_id: int, perms: Dictionary) -> Dictionary:
      return await _patch("/clans/%d/members/%d/permissions" % [clan_id, target_user_id], perms)

  func transfer_leadership(clan_id: int, new_leader_user_id: int) -> Dictionary:
      return await _post("/clans/%d/transfer-leadership" % clan_id, {"new_leader_user_id": new_leader_user_id})

  # ── Applications ──────────────────────────────────────────────────────────────
  func apply_to_clan(clan_id: int, data: Dictionary) -> Dictionary:
      return await _post("/clans/%d/applications" % clan_id, data)

  func get_clan_applications(clan_id: int, status: String = "") -> Array:
      var params := {}
      if status != "":
          params["status"] = status
      var result = await _get("/clans/%d/applications" % clan_id, params)
      if result is Array:
          return result
      return []

  func accept_application(clan_id: int, app_id: int, note: String = "") -> Dictionary:
      return await _post("/clans/%d/applications/%d/accept" % [clan_id, app_id], {"decision_note": note})

  func reject_application(clan_id: int, app_id: int, note: String = "") -> Dictionary:
      return await _post("/clans/%d/applications/%d/reject" % [clan_id, app_id], {"decision_note": note})

  func start_application_interview(clan_id: int, app_id: int, note: String = "") -> Dictionary:
      return await _post("/clans/%d/applications/%d/start-interview" % [clan_id, app_id], {"decision_note": note})

  # ── Storage ───────────────────────────────────────────────────────────────────
  func get_clan_storage(clan_id: int) -> Array:
      var result = await _get("/clans/%d/storage" % clan_id)
      if result is Array:
          return result
      return []

  func deposit_to_clan_storage(clan_id: int, item_type: String, item_id: int, quantity: int, note: String = "") -> Dictionary:
      return await _post("/clans/%d/storage/deposit" % clan_id, {
          "item_type": item_type, "item_id": item_id, "quantity": quantity, "note": note
      })

  func withdraw_from_clan_storage(clan_id: int, item_type: String, item_id: int, quantity: int, note: String = "") -> Dictionary:
      return await _post("/clans/%d/storage/withdraw" % clan_id, {
          "item_type": item_type, "item_id": item_id, "quantity": quantity, "note": note
      })

  func get_clan_storage_logs(clan_id: int, limit: int = 50) -> Array:
      var result = await _get("/clans/%d/storage/logs" % clan_id, {"limit": limit})
      if result is Array:
          return result
      return []

  # ── Activity log ──────────────────────────────────────────────────────────────
  func get_clan_activity(clan_id: int, limit: int = 50) -> Array:
      var result = await _get("/clans/%d/activity" % clan_id, {"limit": limit})
      if result is Array:
          return result
      return []

  # ── Meetup / QR ───────────────────────────────────────────────────────────────
  func create_clan_meetup(clan_id: int, data: Dictionary) -> Dictionary:
      return await _post("/clans/%d/meetups" % clan_id, data)

  func get_clan_meetups(clan_id: int) -> Array:
      var result = await _get("/clans/%d/meetups" % clan_id)
      if result is Array:
          return result
      return []

  func generate_meetup_qr(meetup_id: int) -> Dictionary:
      return await _post("/clans/meetups/%d/generate-qr" % meetup_id, {})

  func meetup_check_in(meetup_id: int, qr_token: String) -> Dictionary:
      return await _post("/clans/meetups/%d/check-in" % meetup_id, {"qr_token": qr_token})

  func close_meetup(meetup_id: int) -> Dictionary:
      return await _post("/clans/meetups/%d/close" % meetup_id, {})

  # ── Raid tickets ──────────────────────────────────────────────────────────────
  func get_my_raid_tickets() -> Array:
      var result = await _get("/clans/raid-tickets/my")
      if result is Array:
          return result
      return []
  

  func get_clan_chat_history(clan_id: int, limit: int = 50, before_id: int = 0) -> Array:
      var params := {"limit": limit}
      if before_id > 0:
          params["before_id"] = before_id
      var result = await _get("/clans/%d/chat/history" % clan_id, params)
      if result is Array:
          return result
      return []

  func get_clan_craft_recipes(clan_id: int) -> Array:
      var result = await _get("/clans/%d/craft/recipes" % clan_id)
      if result is Array:
          return result
      return []

  func start_clan_craft(clan_id: int, recipe_id: int, deliver_to_storage: bool = false) -> Dictionary:
      return await _post("/clans/%d/craft/start" % clan_id, {
          "recipe_id": recipe_id,
          "deliver_to_storage": deliver_to_storage
      })
  

  # ── Live Battle ───────────────────────────────────────────────────────────────

  func create_live_battle(heroes_a: Array, heroes_b: Array, map_id: String = "arena_skirmish") -> Dictionary:
      return await _post("/live-battles/create", {
          "heroes_a": heroes_a,
          "heroes_b": heroes_b,
          "map_id":   map_id,
      })

  func start_live_battle(battle_id: String) -> Dictionary:
      return await _post("/live-battles/%s/start" % battle_id, {})

  func get_live_battle(battle_id: String) -> Dictionary:
      return await _get("/live-battles/%s" % battle_id)

  func stop_live_battle(battle_id: String) -> Dictionary:
      return await _post("/live-battles/%s/stop" % battle_id, {})

  func list_live_battles(status: String = "") -> Array:
      var params := {}
      if status != "":
          params["status"] = status
      var result = await _get("/live-battles/", params)
      if result is Array:
          return result
      return []

  func get_ws_url(path: String) -> String:
      var base: String = base_url.replace("http://", "ws://").replace("https://", "wss://")
      return base + path

  # ── Raid Boss v2 ─────────────────────────────────────────────────────────────

  ## Returns active raid boss spawns (open windows).
  func get_active_raid_spawns() -> Array:
      var result = await _get("/raid-bosses/")
      if result is Array:
          return result
      return []

  ## Returns calendar with all 9 boss templates and their schedules.
  func get_raid_calendar() -> Array:
      var result = await _get("/raid-bosses/calendar")
      if result is Array:
          return result
      return []

  ## Returns full boss detail: template + progress + mutations + phases.
  func get_raid_boss_detail(template_id: int) -> Dictionary:
      return await _get("/raid-bosses/%d" % template_id)

  ## Returns full loot table with adjusted drop chances.
  ## boss_level and no_deaths are optional condition modifiers.
  func get_raid_boss_loot(template_id: int, boss_level: int = 1, no_deaths: bool = false) -> Array:
      var params = {"boss_level": boss_level, "no_deaths": no_deaths}
      var result = await _get("/raid-bosses/%d/loot" % template_id, params)
      if result is Array:
          return result
      return []

  ## Returns last N battle history entries for a boss.
  func get_raid_boss_history(template_id: int, limit: int = 10) -> Array:
      var params = {"limit": limit}
      var result = await _get("/raid-bosses/%d/history" % template_id, params)
      if result is Array:
          return result
      return []

  ## Seeds all 9 boss templates on the server (idempotent).
  func seed_raid_bosses() -> Dictionary:
      return await _post("/raid-bosses/seed", {})

  ## Manually trigger a spawn for a boss template (admin/testing).
  func spawn_raid_boss(template_id: int) -> Dictionary:
      return await _post("/raid-bosses/spawn/%d" % template_id, {})

  # ── Raid Rooms ───────────────────────────────────────────────────────────────

  ## Create a raid room for an open spawn.
  ## loot_rule: "contribution" | "equal" | "clan_share" | "weighted_roll"
  func create_raid_room(spawn_id: int, clan_id: int = -1, loot_rule: String = "contribution") -> Dictionary:
      var body: Dictionary = {"spawn_id": spawn_id, "loot_rule": loot_rule}
      if clan_id > 0:
          body["clan_id"] = clan_id
      return await _post("/raid-rooms/create", body)

  ## Returns room data + participant list.
  func get_raid_room(room_id: int) -> Dictionary:
      return await _get("/raid-rooms/%d" % room_id)

  ## Join a room with a specific hero.
  func join_raid_room(room_id: int, hero_id: int, clan_id: int = -1) -> Dictionary:
      var body: Dictionary = {"user_id": 0, "hero_id": hero_id}
      if clan_id > 0:
          body["clan_id"] = clan_id
      return await _post("/raid-rooms/%d/join" % room_id, body)

  ## Mark a hero as ready in the room.
  func set_raid_hero_ready(room_id: int, hero_id: int, ready: bool = true) -> Dictionary:
      return await _post("/raid-rooms/%d/ready?hero_id=%d&ready=%s" % [room_id, hero_id, str(ready).to_lower()], {})

  ## Lock the roster (no more joins after this).
  func lock_raid_room(room_id: int) -> Dictionary:
      return await _post("/raid-rooms/%d/lock" % room_id, {})

  ## Start the raid simulation. Returns BattleResultOut.
  func start_raid(room_id: int) -> Dictionary:
      return await _post("/raid-rooms/%d/start" % room_id, {})

  ## Get result after battle (contributions + rewards).
  func get_raid_result(room_id: int) -> Dictionary:
      return await _get("/raid-rooms/%d/result" % room_id)

  # ── Coalitions ───────────────────────────────────────────────────────────────

  ## Create a coalition for a specific boss spawn.
  func create_raid_coalition(spawn_id: int, leader_clan_id: int, name: String = "", loot_rule: String = "contribution") -> Dictionary:
      var body: Dictionary = {
          "spawn_id":       spawn_id,
          "leader_clan_id": leader_clan_id,
          "loot_rule":      loot_rule,
      }
      if name != "":
          body["name"] = name
      return await _post("/raid-coalitions/create", body)

  ## Invite a clan to join the coalition.
  func invite_clan_to_coalition(coalition_id: int, clan_id: int, hero_slots: int = 0) -> Dictionary:
      var body: Dictionary = {"clan_id": clan_id}
      if hero_slots > 0:
          body["hero_slots"] = hero_slots
      return await _post("/raid-coalitions/%d/invite" % coalition_id, body)

  ## Accept a coalition invitation (called by the invited clan).
  func accept_coalition_invite(coalition_id: int, clan_id: int) -> Dictionary:
      return await _post("/raid-coalitions/%d/accept?clan_id=%d" % [coalition_id, clan_id], {})

  ## Get coalition details including clan list.
  func get_coalition(coalition_id: int) -> Dictionary:
      return await _get("/raid-coalitions/%d" % coalition_id)

  # ── Access Ranking ───────────────────────────────────────────────────────────

  ## Returns clan access point ranking.
  ## cycle: "weekly" | "monthly"
  func get_raid_access_ranking(cycle: String = "weekly", limit: int = 20) -> Array:
      var params = {"cycle": cycle, "limit": limit}
      var result = await _get("/raid-access/ranking", params)
      if result is Array:
          return result
      return []

  ## Returns this clan's current cycle score and qualification status.
  func get_raid_my_access_score(clan_id: int, cycle: String = "weekly") -> Dictionary:
      var params = {"clan_id": clan_id, "cycle": cycle}
      return await _get("/raid-access/my-score", params)

  ## Add Raid Access Points to a clan (server/admin use).
  func add_raid_access_points(clan_id: int, points: int, cycle: String = "weekly") -> Dictionary:
      return await _post("/raid-access/add?clan_id=%d&points=%d&cycle=%s" % [clan_id, points, cycle], {})
