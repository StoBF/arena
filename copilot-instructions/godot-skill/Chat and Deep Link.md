# Chat and Deep Link

## Chat channels
- Define channel types (e.g. `enum ChatChannel {GLOBAL, ARENA, TRADE}`) and track `active_channel`.
- Send chat via WebSocket with payload including the channel, e.g. `{"action":"chat","channel":"arena","text":"Hello"}`.
- When receiving messages, display them in the corresponding channel’s UI element.

## Deep linking auction items
- Format auction links as `auction://lot/{id}` and embed in chat BBCode:
  
      var lot_id = 42  
      chat_label.bbcode_enabled = true  
      chat_label.append_bbcode("[%s] %s posted [url=auction://lot/%d]Lot %d[/url]\n" % [time_stamp, player_name, lot_id, lot_id])  

- Connect `RichTextLabel` signal `meta_clicked` to handle link activation.
- Example handler:
  
      func _on_chat_label_meta_clicked(meta):
          if meta.begins_with("auction://lot/"):
              var id = int(meta.split("/").back())
              AppState.open_auction_lot(id)

## Prohibited patterns
- Do not parse arbitrary URLs; only handle the custom `auction://` scheme.
- Do not trigger game actions solely from chat text without validation.