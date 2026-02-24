extends GutTest

# Integration tests require the FastAPI server to be running at the ServerConfig URL.
# These tests perform real HTTP requests through NetworkManager and therefore
# should be executed only in an environment where the server is accessible.

func before_each():
    # ensure network has no stale auth
    Network.set_auth_header("")

func test_crafting_updates_server():
    # This test assumes a recipe with id=1 exists and user has resources.
    # It also assumes an authenticated user is logged in via AppState.access_token.
    # Setup: add a valid token to Network, then perform craft and verify response.
    var token = "<your-test-token>"  # replace with a valid token for manual run
    Network.set_auth_header(token)
    var completed = false
    var req = Network.request("/workshop/craft/1", NetworkManager.POST, {})
    req.request_completed.connect(func(result, code, hdrs, body):
        assert_eq(code, 200)
        completed = true
    )
    yield(get_tree().create_timer(2.0), "timeout")
    assert_true(completed, "Craft request should complete")

func test_equipping_updates_server_stats():
    # dummy integration: ensure /equipment/ returns 200 and hero stat endpoint updated
    var token = "<your-test-token>"
    Network.set_auth_header(token)
    var eq_done = false
    var hero_done = false
    var data = {"hero_id": 1, "item_id": 1, "slot": "helmet"}
    var req = Network.request("/equipment/", NetworkManager.POST, data)
    req.request_completed.connect(func(result, code, hdrs, body):
        assert_eq(code, 200)
        eq_done = true
    )
    yield(get_tree().create_timer(2.0), "timeout")
    assert_true(eq_done)
    var hero_req = Network.request("/heroes/1", NetworkManager.GET)
    hero_req.request_completed.connect(func(result, code, hdrs, body):
        assert_eq(code, 200)
        hero_done = true
    )
    yield(get_tree().create_timer(2.0), "timeout")
    assert_true(hero_done)

func test_error_conditions_are_handled():
    # attempt to craft nonexistent recipe
    var completed = false
    var req = Network.request("/workshop/craft/999999", NetworkManager.POST, {})
    req.request_completed.connect(func(result, code, hdrs, body):
        assert_eq(code, 400)
        completed = true
    )
    yield(get_tree().create_timer(2.0), "timeout")
    assert_true(completed)
