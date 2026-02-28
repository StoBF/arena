# Battle Lobby

## Room UI
- Display available arenas with current player counts (e.g. "Arena 1: 4/5 players"). Use a `VBoxContainer` with custom `RoomEntry` nodes.
- Each entry: labels for arena name and count, plus a "Join" `Button`.
- Example entry and code:
  
      RoomEntry (HBoxContainer):  
      ├─ Label ("Arena 1")  
      ├─ Label ("4 / 5 players")  
      └─ Button ("Join")  

      func _on_join_pressed(arena_id):
          Network.send_websocket(JSON.print({"action":"join_room","arena_id":arena_id}))

## Updating lobby
- On lobby open, request current room data from the server or listen for updates over WebSocket.
- Update the UI when `room_update` messages arrive:
    ```
    func _on_room_update(data):
        # data.rooms is an array of {id, player_count}
        for room in data.rooms:
            update_room_entry(room.id, room.player_count)
    ```

## Starting the battle
- When server sends a `battle_start` message with arena details, switch scenes:
    ```
    if data.action == "battle_start":
        get_tree().change_scene("res://scenes/BattleArena.tscn")
    ```
- Ensure this only happens when teams are full (server should enforce 5 vs 5).

## Prohibited patterns
- Do not start the battle prematurely; rely on server signals to change scenes.
- Do not allow the same player to join multiple teams or send duplicate join requests.
- Avoid polling server for room state; use server-push updates.