# Chat → Auction Deep-Link Checklist

Manual verification checklist for the flow:
- user clicks a lot link in chat (`auction://lot/{id}`)
- client opens Auction scene
- Lots tab is selected
- requested lot is focused in the list

## Preconditions

- Server is running and reachable by client.
- User is authenticated in client.
- Auction lots exist on backend (`/auctions/lots` returns at least one lot).
- Chat UI is visible and connected to at least one channel.

## Test Data

- Pick an existing lot id, e.g. `123`.
- Build a chat message containing: `[url=auction://lot/123]Lot 123[/url]`.

## Scenario A — Deep-link from chat click

1. Open main menu scene with chat panel.
2. Ensure message with lot link is visible in chat.
3. Click the lot link.

Expected:
- Client navigates to `Auction.tscn`.
- Auction panel switches to **Lots** mode.
- Lots list is loaded.
- Lot with id `123` becomes selected.
- Details panel is populated for selected lot.

## Scenario B — Link click before lots loaded

1. Return to main menu.
2. Simulate slow network (or click link immediately after auction scene opens).
3. Click lot link.

Expected:
- No crash/no script error.
- Selection is deferred until lots response arrives.
- Requested lot is auto-focused after data load.

## Scenario C — Invalid lot id

1. Click message with invalid id, e.g. `auction://lot/99999999`.

Expected:
- Auction scene still opens (if triggered from main menu).
- App does not crash.
- No incorrect lot selection occurs.

## Scenario D — Non-auction links

1. Click a non-matching link in chat metadata.

Expected:
- No auction navigation is triggered.
- Chat remains functional.

## Regression Checks

- Normal auction open via menu button still works.
- Manual switch between Items/Lots still works.
- Bidding flow remains functional in both modes.
- Chat message rendering still works for plain text and BBCode links.

## Troubleshooting Notes

- If auction opens but lot is not selected:
  - verify lot id exists in `/auctions/lots` payload.
  - verify lot object includes `id` field.
- If nothing happens on link click:
  - verify chat log has `bbcode_enabled = true`.
  - verify metadata callback receives `auction://lot/{id}`.
- If scene opens in Items mode:
  - verify `pending_lot_id` is set and mode is switched to `lots` before/after load.
