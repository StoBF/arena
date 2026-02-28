# Networking

## Communication protocols
- Use **WebSocketClient** for real-time events (battle updates, chat). Connect signals `connection_established`, `connection_closed`, and `data_received`. Call `ws.poll()` in `_process()` to pump network events.
- Use **HTTPRequest** (or HTTPClient) for RESTful calls (inventory update, login, etc). Send JSON payloads and await the `request_completed` signal (use `yield` or `await`).
- Store base URLs and endpoints in constants; avoid hard-coding them in multiple places.

## Message format
- Send and receive JSON: structure messages with an `"action"` field and associated data. Example: `{"action":"join_room","room_id":5}`.
- Always `JSON.parse(...)` incoming messages before use; check for errors.
- Example WebSocket handler:
  
    var ws = WebSocketClient.new()  
    ws.connect_to_url(ws_url)  
    ws.connect("data_received", self, "_on_ws_data")  
    func _on_ws_data():  
        var pkt = ws.get_packet().get_string_from_utf8()  
        var msg = JSON.parse(pkt).result  
        match msg.action:  
            "battle_start":  
                AppState.battle_frames = msg.frames  

- Example HTTPRequest usage:
  
    var http = HTTPRequest.new()  
    add_child(http)  
    var payload = {"item_id": item_id, "hero_id": hero_id}  
    http.request(api_url + "/inventory/update", [], false, HTTPClient.METHOD_POST, JSON.print(payload))  
    yield(http, "request_completed")  
    var resp = JSON.parse(http.get_response_body_as_string()).result  
    AppState.inventory = resp.items  

## Error handling & best practices
- Check `ws.get_ready_state()` to ensure it's `STATE_OPEN` before sending. Reconnect or handle errors on failures.
- For HTTP, check the HTTP response code (e.g. 200 OK) after completion.
- Use asynchronous calls (signals/await) to avoid blocking. Do not freeze the main loop with blocking waits.
- Dispatch received data to game logic via `AppState` or signals, not directly manipulate UI or scenes in the network code.

## Prohibited patterns
- Do not use busy-wait loops or fixed-interval polling for server updates; rely on WebSocket push.
- Avoid modifying global state or UI directly from network callbacks; always route through `AppState` or command handlers.