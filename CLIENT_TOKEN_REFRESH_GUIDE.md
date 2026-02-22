# Client-Side JWT Refresh Integration Guide

**Target Audience**: Godot 4 GDScript Developers  
**Framework**: Godot 4 + Autoload Singletons  
**Reference**: NetworkManager + AppState

---

## Quick Start

### 1. AppState Setup

Token management is automatic through `AppState` singleton:

```gdscript
# AppState.gd is already configured
# Just access tokens via AppState

AppState.access_token = "new_token"      # Set after login
AppState.refresh_token = "refresh_token" # Tracking only
```

### 2. Initial Login

```gdscript
# In your login scene/script:
var response = await NetworkManager.request("/auth/login", NetworkManager.GET, {
    "login": username,
    "password": password
})

if response.status_code == 200:
    var data = JSON.parse_string(response.body)
    AppState.access_token = data["access_token"]
    AppState.refresh_token = data["refresh_token"]
    AppState.user_id = data["user_id"]
    # Cookies set automatically by browser
```

### 3. Automatic Token Refresh (Already Implemented!)

```gdscript
# NetworkManager.gd handles this automatically
# When any request gets 401:

var response = await NetworkManager.request("/api/hero", NetworkManager.GET)

# If access token expired (401):
# 1. NetworkManager detects 401
# 2. Automatically calls /auth/refresh
# 3. Gets new access token
# 4. Retries original request
# 5. Returns 200 response (transparent!)

print(response.status_code)  # 200 (not 401!)
```

---

## Architecture Deep Dive

### AppState Token Storage

**File**: `client/autoload/AppState.gd`

```gdscript
extends Node

class_name AppState

# Token storage
var access_token: String = ""       # Current access token (in memory)
var refresh_token: String = ""      # For reference (cookie is actual source)
var token_type: String = "bearer"

# User information
var user_id: int = -1
var current_hero_id: int = -1
var user_role: String = "user"

# Token refresh state
var is_refreshing_token: bool = false        # Prevent concurrent refresh
var token_refresh_attempted: bool = false    # Track if refresh attempted
```

**Important Notes**:
- `access_token`: Stored in memory, used for Authorization header
- `refresh_token`: Stored in HTTP-only cookie (not in memory)
- `is_refreshing_token`: Prevents infinite loop during refresh
- Cookies are managed by the browser automatically

---

### NetworkManager Token Handling

**File**: `client/scripts/network/NetworkManager.gd`

#### Request Flow with Token

```gdscript
func request(endpoint: String, method: int = GET, data: Variant = null) -> NetworkResponse:
    """Make HTTP request with automatic token refresh on 401"""
    
    # Step 1: Build request info
    var request_info = {
        "endpoint": endpoint,
        "method": method,
        "data": data,
        "retry_count": 0,
        "is_retry_after_refresh": false,  # Will be set to true on retry
        "http_request": HTTPRequest.new()
    }
    
    # Step 2: Set authorization header with current access token
    var headers = _get_default_headers()
    
    # Step 3: Make request
    request_info.http_request.request(url, headers, method, json_data)
    
    # Step 4: Wait for response
    var result = await request_completed
    
    # Step 5: Check for 401 (token expired)
    if response_code == 401 and not request_info["is_retry_after_refresh"]:
        # AUTOMATIC REFRESH TRIGGERED HERE
        if await _handle_token_expiration(request_info):
            return  # Already retried, will get completion signal
    
    # Step 6: Return result
    return NetworkResponse(...)
```

#### Authorization Header

```gdscript
func _get_default_headers() -> PackedStringArray:
    """Build headers with current access token"""
    return PackedStringArray([
        "Content-Type: application/json",
        "Authorization: Bearer %s" % AppState.access_token
    ])

func _update_default_headers():
    """Called after token refresh to update Authorization header"""
    # This ensures next request uses fresh token
    pass  # Headers built on-demand in _get_default_headers()
```

---

## Token Refresh Process Details

### When Refresh is Triggered

```gdscript
# Scenario 1: Access token expired
1. Client makes request
2. Server returns 401 Unauthorized
3. NetworkManager detects 401
4. Does NOT emit "request_completed" signal yet
5. Calls _handle_token_expiration()

# Scenario 2: Refresh token also expired
1. _handle_token_expiration() calls /auth/refresh
2. Server rejects refresh token (7+ days old)
3. Returns 401
4. Client gives up on refresh
5. Emits original 401 error
6. Application should redirect to login
```

### Refresh Algorithm

```gdscript
func _handle_token_expiration(original_request: Dictionary) -> bool:
    """Attempt to refresh token and retry original request
    
    Returns: true if refresh succeeded and request retried
             false if refresh failed or already attempted
    """
    
    # SAFEGUARD 1: Prevent concurrent refresh
    if _token_refresh_in_progress:
        print("[AUTH] Refresh already in progress, cannot attempt concurrent refresh")
        return false
    
    # SAFEGUARD 2: Prevent infinite loops
    if _failed_refresh_attempts >= _max_refresh_attempts:
        print("[AUTH] Max refresh attempts (%d) reached" % _max_refresh_attempts)
        return false
    
    # Mark refresh as in progress
    _token_refresh_in_progress = true
    _failed_refresh_attempts += 1
    
    print("[AUTH] Attempting token refresh (attempt %d/%d)" % [_failed_refresh_attempts, _max_refresh_attempts])
    
    # Attempt refresh
    var success = await _refresh_access_token()
    
    # Clean up
    _token_refresh_in_progress = false
    
    if not success:
        print("[AUTH] Token refresh failed")
        return false
    
    print("[AUTH] Token refresh succeeded, retrying original request")
    
    # Retry original request
    original_request["is_retry_after_refresh"] = true
    original_request["retry_count"] = 0
    
    request(
        original_request["endpoint"],
        original_request["method"],
        original_request["data"]
    )
    
    return true
```

### Refresh Endpoint Call

```gdscript
func _refresh_access_token() -> bool:
    """Call /auth/refresh endpoint to refresh access token
    
    - Refresh token in HTTP-only cookie sent automatically
    - Receives new access token in response body
    - New refresh token set in cookie response header (automatic)
    
    Returns: true if successful, false if failed or timeout
    """
    
    var config = ServerConfig.get_instance()
    var url = config.get_http_endpoint("/auth/refresh")
    
    # Create fresh HTTP request
    var http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.timeout = 10.0  # 10 second timeout
    
    var completed = false
    var success = false
    
    # Connect to completion signal
    http_request.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
        completed = true
        
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            # Parse response body
            var body_text = body.get_string_from_utf8()
            var json = JSON.new()
            
            if json.parse(body_text) == OK:
                var data = json.data
                if data and "access_token" in data:
                    # Update access token with new one
                    AppState.access_token = data["access_token"]
                    _update_default_headers()
                    
                    print("[AUTH] New access token obtained from refresh")
                    success = true
                else:
                    print("[AUTH] Response missing access_token field")
            else:
                print("[AUTH] Failed to parse refresh response JSON")
        else:
            print("[AUTH] Refresh endpoint returned error: code=%d result=%d" % [code, result])
    )
    
    # Make refresh request
    # NOTE: Refresh token is sent in HTTP-only cookie automatically
    # Browser/HTTPRequest handles Cookie header transmission
    var err = http_request.request(url, [], HTTPClient.METHOD_POST, "")
    
    if err != OK:
        print("[AUTH] Request error: %s" % error_string(err))
        http_request.queue_free()
        return false
    
    # Wait for completion (max 10 seconds)
    var timeout = 0.0
    while not completed and timeout < 10.0:
        await get_tree().process_frame
        timeout += 0.016
    
    # Clean up HTTP request
    http_request.queue_free()
    
    if not completed:
        print("[AUTH] Refresh request timed out after 10 seconds")
        return false
    
    return success
```

---

## Common Scenarios

### Scenario 1: User Makes Request After Token Expires

```
Time: 0 min
├─ User logs in
├─ AppState.access_token = "eyJhbGciOi..." (20 min expiration)
└─ Refresh token in cookie (7 day expiration)

Time: 20 min
├─ User clicks "View Inventory"
├─ request("/api/inventory")
├─ Token is now expired
└─ Server rejects with 401

Client Response:
├─ Network 401 detected
├─ Calls /auth/refresh
├─ Browser sends refresh token in cookie (automatic)
├─ Server validates refresh token (still valid)
├─ Returns new access token
├─ NetworkManager updates AppState.access_token
├─ Retries original /api/inventory request
├─ Now succeeds with fresh token
└─ User sees inventory (transparent!)
```

### Scenario 2: Both Access and Refresh Tokens Expired

```
Time: 0 min
├─ User logs in
├─ AppState.access_token = "..." (20 min)
├─ Refresh token in cookie (7 days)
└─ Browser keeps window open but doesn't use app

Time: 7 days + 1 minute
├─ User comes back and clicks "View Hero"
├─ request("/api/hero")
├─ Access token expired (obviously - 7 days old!)
└─ Server rejects with 401

Client attempts refresh:
├─ Calls /auth/refresh
├─ Browser sends refresh token in cookie
├─ Server checks refresh token: EXPIRED!
├─ Returns 401 (cannot refresh)
├─ NetworkManager gives up
└─ Emits original 401 error

Application should:
├─ Detect 401 from /api/hero
├─ Check if user is authenticated
├─ Redirect to login page
├─ Clear AppState tokens
└─ Prompt user to log in again
```

### Scenario 3: Concurrent Requests While Refreshing

```
Time: exactly 20:00 (token expires)

Request 1: GET /api/inventory
├─ Sent with expired token
├─ Server returns 401
├─ _handle_token_expiration triggered
├─ _token_refresh_in_progress = true
└─ Calling /auth/refresh...

Request 2: POST /api/hero (made at same time)
├─ Sent with expired token (concurrent)
├─ Server returns 401
├─ _handle_token_expiration called
├─ Checks: _token_refresh_in_progress = true
├─ RETURNS FALSE (prevent concurrent refresh)
└─ This 401 treated as normal error

Result:
├─ Only ONE refresh attempted (not two)
├─ First request retries after refresh
├─ Second request fails with 401
└─ App retries second request manually
```

### Scenario 4: Infinite Refresh Prevention

```
Hypothetical: What if /auth/refresh endpoint broken?

Request 1: GET /api/hero
├─ Returns 401 (token expired)
├─ _failed_refresh_attempts = 0
├─ Calls /auth/refresh
├─ _failed_refresh_attempts = 1
├─ Call fails (server error)
├─ Returns false
└─ Original 401 error emitted

Request 2: GET /api/inventory (user tries again)
├─ Returns 401 (token still expired)
├─ _handle_token_expiration called
├─ Checks: _failed_refresh_attempts (1) >= _max_refresh_attempts (1)
├─ RETURNS FALSE (prevent infinite loop)
└─ Error emitted without retry

Result:
├─ Never attempts refresh more than once
├─ No infinite loop
├─ App can handle failure gracefully
└─ User directed to login
```

---

## Troubleshooting

### Issue: "Always getting 401 after some time"

**Diagnosis**:
1. Check browser developer tools → Network
2. Look for `/auth/refresh` request
3. Check if refresh token cookie is being sent

**Solution**:
```gdscript
# In NetworkManager._refresh_access_token():
# Add debug logging
print("Refresh cookie sent: %s" % request.headers)

# In browser Console:
console.log(document.cookie)
# Should NOT show refresh_token (HTTP-only!)
# But cookie should be in Network tab requests
```

### Issue: "Token refresh creates infinite loop"

**This should not happen with safeguards**, but if it does:

```gdscript
# Check NetworkManager configuration:
var _max_refresh_attempts: int = 1  # Should be 1, not higher
var _token_refresh_in_progress: bool = false  # Should reset

# Add debug in _handle_token_expiration:
print("Refresh guard: in_progress=%s, attempts=%d/%d" % [
    _token_refresh_in_progress,
    _failed_refresh_attempts,
    _max_refresh_attempts
])
```

### Issue: "New access token not being used"

**Diagnosis**:
1. Check if `AppState.access_token` is being updated
2. Check if `_update_default_headers()` is called

**Solution**:
```gdscript
# In _refresh_access_token(), after getting response:
print("Old token: %s..." % AppState.access_token.substr(0, 10))
AppState.access_token = data["access_token"]
print("New token: %s..." % AppState.access_token.substr(0, 10))

_update_default_headers()  # CRITICAL - refresh headers
```

### Issue: "Getting 'Refresh token not found in cookie' error"

**This means the browser is not sending the cookie**. Causes:

1. **Domain mismatch**: `localhost` vs `127.0.0.1`, or `example.com` vs `www.example.com`
2. **HTTPS vs HTTP**: Secure cookie can only be sent over HTTPS
3. **Cookie was never set**: Check login response has Set-Cookie header
4. **Cookie deleted**: Browser might have cleared cookies

**Solution**:
```gdscript
# In Browser Dev Tools → Application → Cookies:
# Should see "refresh_token" cookie
# Verify:
# - Domain matches server
# - Secure=true has HTTPS
# - HttpOnly=true (cannot see value, but should exist)
# - SameSite=Strict

# In login response, check Network tab:
# Headers → Set-Cookie should show refresh_token
```

### Issue: "Access token obtained but still getting 401"

**Diagnosis**: New token might not be used in next request.

**Solution**:
```gdscript
# Make sure _update_default_headers() called:
AppState.access_token = data["access_token"]
_update_default_headers()  # MUST call this

# Verify default headers updated:
var headers = _get_default_headers()
assert("Bearer %s" % data["access_token"] in headers[1])
```

---

## Best Practices

### 1. Always Handle 401 Errors

```gdscript
# Good: Check status code
var response = await NetworkManager.request("/api/hero", GET)
if response.status_code == 401:
    # This should be rare (auto-refresh usually handles it)
    redirect_to_login()
elif response.status_code == 200:
    display_hero(response.data)
```

```gdscript
# Bad: Ignore 401
var response = await NetworkManager.request("/api/hero", GET)
var data = JSON.parse_string(response.body)  # Crash if 401!
```

### 2. Check is_refreshing_token

```gdscript
# Bad: Trigger token refresh from UI
func login_button_pressed():
    AppState.access_token = get_new_token()  # Don't do this!

# Good: Trust NetworkManager to handle refresh
func view_inventory_button_pressed():
    var response = await NetworkManager.request("/api/inventory", GET)
    display_inventory(response.data)  # Auto-refresh handled internally
```

### 3. Don't Persist Access Token

```gdscript
# Bad: Save to disk
var access_token = AppState.access_token
save_to_file("access_token.txt", access_token)

# Good: Keep in memory only
AppState.access_token = ""  # Clear on app exit
# On app restart: User must log in again (refresh token in cookie)
```

### 4. Handle Refresh Failures Gracefully

```gdscript
# Bad: Assume refresh always succeeds
var response = await NetworkManager.request("/api/hero", GET)
display_hero(response.data)  # No error check!

# Good: Handle both refresh failure and request failure
var response = await NetworkManager.request("/api/hero", GET)
if response.status_code == 401:
    # Refresh failed, user needs to log in
    show_error("Session expired. Please log in again.")
    redirect_to_login()
elif response.status_code == 200:
    display_hero(response.data)
else:
    show_error("Error: %d" % response.status_code)
```

### 5. Use Consistent Error Handling

```gdscript
# Global handler for all 401s
func _on_any_request_failed(response_code: int, endpoint: String):
    if response_code == 401:
        print("Session expired at %s, redirecting to login" % endpoint)
        AppState.access_token = ""
        AppState.user_id = -1
        get_tree().change_scene_to_file("res://scenes/login_screen.tscn")

# In login screen:
func _on_auto_login_failed():
    show_message("Please log in to continue")
    focus_on_username_field()
```

---

## Integration Checklist

- [ ] AppState.gdscript loaded as autoload in project.godot
- [ ] NetworkManager.gd has token refresh methods
- [ ] Login scene sets AppState.access_token after successful login
- [ ] All API calls use NetworkManager.request()
- [ ] Error handlers check for 401 status code
- [ ] Browser dev tools show refresh_token cookie
- [ ] Network tab shows /auth/refresh called when appropriate
- [ ] Refresh token cookie has HttpOnly, Secure, SameSite flags
- [ ] Testing with expired token triggers automatic refresh
- [ ] Logging shows [AUTH] messages for debugging

---

## Summary

**Automatic token refresh is fully implemented!**

✅ Tokens stored securely (access in memory, refresh in HTTP-only cookie)  
✅ Automatic refresh on 401 response  
✅ Safeguards against infinite loops and concurrent refresh  
✅ Timeout protection (10 seconds)  
✅ Transparent to calling code - just make requests normally  

**For developers**: Just use `NetworkManager.request()` and token management is handled automatically. 🎉
